module Conjuration
  # A scheduler applying easing over a scene's clock — NOT an easing library. It
  # holds timers (after/every) and tweens keyed to elapsed = clock - started_at,
  # so a frozen clock (hit stop, pause, stacked scene) freezes every schedule for
  # free and resumes without double-firing.
  #
  # Lifecycle: schedules are transient — they live on the scene INSTANCE, not in
  # save state, and die when the scene is torn down. Re-entering a scene starts
  # with an empty scheduler.
  #
  # Zero-cost when unused: the backing array is nil until the first schedule, and
  # the scene skips #tick entirely while no scheduler exists.
  class Scheduler
    # DR's Easing module isn't in the mruby test harness, so we carry the four
    # classic power curves inline and resolve a Symbol against this table lazily.
    # Any callable is accepted as-is, so a game can pass its own curve (or a real
    # DR easing lambda) without this table knowing about it.
    EASING = {
      identity: ->(t) { t },
      smooth_start: ->(t) { t * t },
      smooth_stop: ->(t) { 1.0 - (1.0 - t) * (1.0 - t) },
      smooth_step: ->(t) { t * t * (3.0 - 2.0 * t) }
    }.freeze

    def after(started_at, ticks, block)
      add(After.new(started_at, ticks, block))
    end

    def every(started_at, ticks, block)
      add(Every.new(started_at, ticks, block))
    end

    def tween(started_at, target, attrs, over, ease)
      add(Tween.new(started_at, target, attrs, over, resolve_ease(ease)))
    end

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
  module Scheduling
    def after(ticks, &block)
      scheduler.after(clock, ticks, block)
    end

    def every(ticks, &block)
      scheduler.every(clock, ticks, block)
    end

    def tween(target, attr = nil, to: nil, over:, ease: :identity, **attrs)
      attrs = { attr => to } if attr
      scheduler.tween(clock, target, attrs, over, ease)
    end

    def scheduler
      @scheduler ||= Scheduler.new
    end

    private

    def tick_schedules
      @scheduler.tick(clock) if @scheduler
    end
  end
end
