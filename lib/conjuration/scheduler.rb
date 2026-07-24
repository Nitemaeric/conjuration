module Conjuration
  # Applies easing and time over a scene's clock — NOT an easing library.
  # Holds timers (after/every) and tweens keyed to elapsed = clock - started_at,
  # so a frozen clock (hit stop, pause, stacked scene) freezes every schedule for
  # free and resumes without double-firing.
  #
  # Lifecycle: schedules are transient — they live on the scene INSTANCE, not in
  # save state, and die when the scene is torn down. Re-entering a scene starts
  # with an empty scheduler.
  #
  # Zero-cost when unused: the backing array is nil until the first schedule, and
  # the scene skips #tick entirely while no scheduler exists.
  #
  # @note Schedules key to the scene clock, so frozen clocks (hit-stop, pause,
  #   stacked scene) freeze all schedules for free.
  # @note Schedules are transient (live on scene instance, not in save state;
  #   die when scene tears down).
  # @see Conjuration::Scheduling
  class Scheduler
    # DR's Easing module isn't in the mruby test harness, so we carry the four
    # classic power curves inline and resolve a Symbol against this table lazily.
    # Any callable is accepted as-is, so a game can pass its own curve (or a real
    # DR easing lambda) without this table knowing about it.
    #
    # @return [Hash{Symbol => Proc}] symbol names to easing functions
    EASING = {
      identity: ->(t) { t },
      smooth_start: ->(t) { t * t },
      smooth_stop: ->(t) { 1.0 - (1.0 - t) * (1.0 - t) },
      smooth_step: ->(t) { t * t * (3.0 - 2.0 * t) }
    }.freeze

    # Schedule a callback to fire once, on the first tick where the elapsed span has passed.
    #
    # @param started_at [Numeric] clock value at schedule creation (typically scene.clock)
    # @param ticks [Numeric] frame count until the callback fires
    # @param block [Proc] callback invoked when ticks have elapsed
    # @return [After] handle for cancellation (respond_to?(:cancel))
    def after(started_at, ticks, block)
      add(After.new(started_at, ticks, block))
    end

    # Schedule a callback to fire repeatedly, every N ticks.
    #
    # @param started_at [Numeric] clock value at schedule creation (typically scene.clock)
    # @param ticks [Numeric] frame count between firings (must be >= 1)
    # @param block [Proc] callback invoked at each interval
    # @return [Every] handle for cancellation (respond_to?(:cancel))
    # @note Tick count must be >= 1.
    def every(started_at, ticks, block)
      add(Every.new(started_at, ticks, block))
    end

    # Schedule a tween of one or more attributes toward target values over a time span.
    #
    # Reads/writes via bracket-access on Hash or via attr_accessor methods on objects,
    # so it works with both plain state hashes and model objects with accessors.
    #
    # @param started_at [Numeric] clock value at tween creation (typically scene.clock)
    # @param target [Hash, Object] the object holding attributes to tween
    # @param attrs [Hash{Symbol => Numeric}] attribute names and target values
    # @param over [Numeric] total frame count for the tween
    # @param ease [Symbol, Proc] easing function—symbol key from {EASING} or callable
    # @return [Tween] handle for cancellation (respond_to?(:cancel))
    # @note Works with Hash (bracket access) or objects with attr_accessor (method calls).
    # @note Easing can be a Symbol ({EASING} key) or any callable taking t in [0.0, 1.0].
    # @example Tween a scale from 1.0 to 1.45 over 12 frames (demo hit_stop_scene)
    #   tween(crate, :scale, to: 1.45, over: POP_DURATION, ease: :smooth_stop)
    # @example Tween a screen-flash alpha to 0 over 6 frames
    #   tween(state, :screen_flash, to: 0, over: SCREEN_FLASH)
    def tween(started_at, target, attrs, over, ease)
      add(Tween.new(started_at, target, attrs, over, resolve_ease(ease)))
    end

    # Advance all active schedules to the given clock value.
    #
    # Typically called by Scene#tick_schedules once per frame. Allocates nothing
    # if no schedules exist (backing array is nil).
    #
    # @param clock [Numeric] current scene clock value
    # @return [void]
    def tick(clock)
      return if @schedules.nil? || @schedules.empty?

      # Snapshot the count so a schedule created inside a callback waits until the
      # next tick — appending mid-iteration is safe and deterministic.
      count = @schedules.length
      i = 0
      while i < count
        @schedules[i].tick(clock)
        i += 1
      end

      @schedules.reject!(&:done?)
    end

    # Whether any schedules are currently active.
    #
    # @return [Boolean] true if one or more schedules exist
    def active?
      !(@schedules.nil? || @schedules.empty?)
    end

    private

    def add(schedule)
      (@schedules ||= []) << schedule
      schedule
    end

    def resolve_ease(ease)
      return ease if ease.respond_to?(:call)

      EASING[ease] || raise(ArgumentError, "unknown easing #{ease.inspect}; use #{EASING.keys.inspect} or a callable")
    end

    # Fires its block once, on the first tick where the elapsed span has passed.
    class After
      def initialize(started_at, ticks, block)
        @started_at = started_at
        @ticks = ticks
        @block = block
        @done = false
        @cancelled = false
      end

      def tick(clock)
        return if done?
        return if clock - @started_at < @ticks

        @done = true # set before the callback so a re-entrant schedule is safe
        @block.call
      end

      def cancel
        @cancelled = true
      end

      def done?
        @done || @cancelled
      end
    end

    # Fires every `ticks` from creation until cancelled. next_at is absolute, so a
    # held clock simply doesn't reach it — no catch-up burst on resume.
    class Every
      def initialize(started_at, ticks, block)
        raise ArgumentError, "every(ticks) needs ticks >= 1, got #{ticks.inspect}" if ticks < 1

        @next_at = started_at + ticks
        @ticks = ticks
        @block = block
        @cancelled = false
      end

      def tick(clock)
        while !@cancelled && clock >= @next_at
          @next_at += @ticks
          @block.call
        end
      end

      def cancel
        @cancelled = true
      end

      def done?
        @cancelled
      end
    end

    # Interpolates one or more numeric attributes toward their targets over `over`
    # ticks. Reads/writes bracket-access on a Hash and accessor methods otherwise,
    # so it drives both plain state hashes and attr_accessor objects.
    class Tween
      def initialize(started_at, target, attrs, over, ease)
        @started_at = started_at
        @target = target
        @over = over
        @ease = ease
        @to = attrs
        @from = {}
        attrs.each { |key, _| @from[key] = read(key) }
        @done = false
        @cancelled = false
      end

      def tick(clock)
        return if done?

        elapsed = clock - @started_at
        if elapsed >= @over
          apply(1.0) # exact endpoint, then retire — no drift from float easing
          @done = true
        elsif elapsed <= 0
          apply(0.0)
        else
          apply(@ease.call(elapsed.to_f / @over))
        end
      end

      def cancel
        @cancelled = true
      end

      def done?
        @done || @cancelled
      end

      private

      def apply(eased)
        @to.each do |key, target_value|
          from = @from[key]
          write(key, from + (target_value - from) * eased)
        end
      end

      def read(key)
        @target.is_a?(Hash) ? @target[key] : @target.send(key)
      end

      def write(key, value)
        if @target.is_a?(Hash)
          @target[key] = value
        else
          @target.send("#{key}=", value)
        end
      end
    end
  end

  # The scene-facing surface. Included into Scene; every method keys to the host's
  # own #clock, and #scheduler is allocated lazily on first use.
  #
  # @note All schedules key to the scene's clock, so frozen clocks (hit-stop,
  #   pause, stacked scene) freeze all schedules for free.
  # @example Fire a callback after 30 frames (demo hit_stop_scene)
  #   after(30) { trigger_effect }
  # @example Fire a callback every 10 frames until cancelled (demo hit_stop_scene)
  #   handle = every(10) { update_animation }
  # @example Tween an attribute over 12 frames with easing
  #   tween(entity, :scale, to: 1.45, over: 12, ease: :smooth_stop)
  # @see Conjuration::Scheduler
  module Scheduling
    # Schedule a callback to fire once after N frames on this scene's clock.
    #
    # @param ticks [Numeric] frame count until the callback fires
    # @yield callback invoked after ticks have elapsed
    # @return [Scheduler::After] handle (respond_to?(:cancel) for cancellation)
    def after(ticks, &block)
      scheduler.after(clock, ticks, block)
    end

    # Schedule a callback to fire repeatedly every N frames on this scene's clock.
    #
    # @param ticks [Numeric] frame count between firings (must be >= 1)
    # @yield callback invoked at each interval
    # @return [Scheduler::Every] handle (respond_to?(:cancel) for cancellation)
    def every(ticks, &block)
      scheduler.every(clock, ticks, block)
    end

    # Schedule a tween of one or more attributes toward targets over a time span.
    #
    # Accepts either positional (target, attr, to:) or keyword (**attrs) form.
    # Reads/writes via bracket-access on Hash or via accessor methods on objects.
    #
    # @param target [Hash, Object] the object holding attributes to tween
    # @param attr [Symbol, nil] single attribute name (positional form)
    # @param to [Numeric, nil] single target value (keyword, paired with attr)
    # @param over [Numeric] total frame count for the tween
    # @param ease [Symbol, Proc] easing function—symbol from Scheduler::EASING or callable
    # @param attrs [Hash{Symbol => Numeric}] attribute names and targets (keyword form)
    # @return [Scheduler::Tween] handle (respond_to?(:cancel) for cancellation)
    # @example Single attribute
    #   tween(crate, :scale, to: 1.45, over: 12)
    # @example Multiple attributes
    #   tween(entity, scale: 1.0, alpha: 255, over: 20, ease: :smooth_step)
    def tween(target, attr = nil, to: nil, over:, ease: :identity, **attrs)
      attrs = { attr => to } if attr
      scheduler.tween(clock, target, attrs, over, ease)
    end

    # Access the underlying scheduler for this scene.
    #
    # @return [Scheduler] the scene's scheduler (lazy-allocated)
    def scheduler
      @scheduler ||= Scheduler.new
    end

    private

    def tick_schedules
      @scheduler.tick(clock) if @scheduler
    end
  end
end
