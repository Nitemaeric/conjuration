module Conjuration
  # Named-clip frame animation keyed to a scene/game clock. The current frame is
  # derived from `clock - started_at` rather than incremented per tick, so a hit
  # stop or pause — which freezes the clock — freezes the frame and resumes mid
  # clip for free. Players are plain objects owned by game code; there is no
  # registry, and querying #path allocates nothing.
  #
  # @note Frames are keyed to scene/game clock, so a frozen clock (hit-stop, pause,
  #   stacked scene) freezes the current frame for free and resumes without re-firing events.
  # @note Players are plain objects; animation is keyed by attribute, not by registry.
  # @example Create and use an animation (demo parallax_scene)
  #   @hero_anim = Conjuration::Animation.new(
  #     walk: { frames: Array.new(WALK_FRAMES) { |i| "sprites/hero/walk#{i}.png" }, hold: 5 },
  #     idle: { frames: [HERO_IDLE] }
  #   )
  #   @hero_anim.play(:idle)
  #   # In update:
  #   @hero_anim.play(state.hero.moving ? :walk : :idle)
  #   @hero_anim.update(clock)
  #   # In render:
  #   camera.draw({ x: hero.x, y: hero.y, path: @hero_anim.path, ... })
  # @see Conjuration::Animation::Clip
  class Animation
    # An ordered set of frames with per-frame hold durations and a playback mode.
    #
    # Frames are indexed in playback order determined by mode. Clips do not
    # directly track elapsed time; the parent Animation does.
    #
    # @note Modes:
    #   - +:loop+: Frames 0..n-1 repeat infinitely.
    #   - +:once+: Frames 0..n-1 then hold the last frame (see Animation#finished?).
    #   - +:ping_pong+: Frames 0..n-1 then n-2..1, repeat. Turnaround frames (0, n-1)
    #     are held once per cycle; interior frames are entered twice per cycle (once each
    #     direction), so their frame events fire twice per cycle.
    # @see Conjuration::Animation
    class Clip
      # @return [Array] frame references (typically sprite paths as strings)
      attr_reader :frames
      # @return [Symbol] playback mode (:loop, :once, :ping_pong)
      attr_reader :mode
      # @return [Array<Numeric>] per-frame durations (in frames)
      attr_reader :durations
      # @return [Numeric] total duration of one complete cycle in :loop/:ping_pong,
      #   or full sequence in :once
      attr_reader :total
      # @return [Numeric] duration of one full cycle for repeating modes (:loop, :ping_pong)
      attr_reader :cycle

      # Create a clip from a frame list and hold duration(s).
      #
      # @param frames [Array] frame references (typically sprite paths)
      # @param hold [Numeric] default duration per frame in frames (default 1)
      # @param durations [Array<Numeric>, nil] per-frame durations (overrides hold for specific frames)
      # @param mode [Symbol] playback mode: :loop, :once, :ping_pong (default :loop)
      # @raise [ArgumentError] if frames is empty
      def initialize(frames, hold: 1, durations: nil, mode: :loop)
        raise ArgumentError, "a clip needs at least one frame" if frames.nil? || frames.empty?

        @frames = frames
        @mode = mode
        @durations = build_durations(frames.length, hold, durations)
        @total = sum(@durations)

        @order = build_order(frames.length, mode)
        @order_durations = @order.map { |i| @durations[i] }
        @offsets = build_offsets(@order_durations)
        @cycle = @offsets.last + @order_durations.last
      end

      # Look up the frame at a given elapsed time within the clip.
      #
      # @param elapsed [Numeric] elapsed time since clip start (in frames)
      # @return [Object] the frame reference at that time
      def frame_at(elapsed)
        @frames[frame_index_at(elapsed)]
      end

      # Look up the frame index at a given elapsed time within the clip.
      #
      # @param elapsed [Numeric] elapsed time since clip start (in frames)
      # @return [Integer] the index in @frames at that time
      def frame_index_at(elapsed)
        elapsed = 0 if elapsed < 0

        if @mode == :once
          return @frames.length - 1 if elapsed >= @total

          @order[slot_at(elapsed)]
        else
          @order[slot_at(elapsed % @cycle)]
        end
      end

      # Yields the frame index of every frame-entry boundary in the open-closed
      # window (lo, hi], in playback order — so a slow game frame that skips over
      # several boundaries fires each in sequence. lo starts at -1 on (re)start,
      # which is why an event on frame 0 fires when the clip begins.
      #
      # @param lo [Numeric] lower bound (exclusive)
      # @param hi [Numeric] upper bound (inclusive)
      # @yield [Integer] frame indices crossed in the window, in order
      # @return [void]
      def each_boundary(lo, hi)
        if @mode == :once
          j = 0
          while j < @order.length
            t = @offsets[j]
            break if t > hi

            yield @order[j] if t > lo
            j += 1
          end
        else
          k = lo < 0 ? 0 : floor_div(lo, @cycle)
          loop do
            base = k * @cycle
            break if base > hi

            j = 0
            while j < @order.length
              t = base + @offsets[j]
              return if t > hi

              yield @order[j] if t > lo
              j += 1
            end
            k += 1
          end
        end
      end

      private

      def slot_at(position)
        j = 0
        while j < @order.length
          return j if position < @offsets[j] + @order_durations[j]

          j += 1
        end
        @order.length - 1
      end

      def build_durations(count, hold, durations)
        result = Array.new(count) { |i| durations ? (durations[i] || hold) : hold }
        raise ArgumentError, "frame durations must be >= 1" if result.any? { |d| d < 1 }

        result
      end

      def build_order(count, mode)
        forward = (0...count).to_a
        return forward unless mode == :ping_pong

        backward = count > 2 ? (1...(count - 1)).to_a.reverse : []
        forward + backward
      end

      def build_offsets(durations)
        offsets = []
        accumulator = 0
        durations.each do |duration|
          offsets << accumulator
          accumulator += duration
        end
        offsets
      end

      def sum(values)
        values.inject(0) { |accumulator, value| accumulator + value }
      end

      # Floor division that survives DragonRuby patching Integer#/ to return a
      # Float (plain mruby returns an Integer); both floor for the non-negative
      # arguments this is ever called with.
      def floor_div(numerator, denominator)
        (numerator / denominator).to_i
      end
    end

    # @return [Symbol, nil] name of the currently playing clip, or nil if stopped
    attr_reader :current
    # @return [Numeric] the last clock value passed to #update
    attr_reader :clock

    # Create an animation with one or more named clips.
    #
    # Each clip can be specified as a Clip object, an Array (used as frames),
    # or a Hash with :frames and optional :hold, :durations, :mode keys.
    #
    # @param clips [Hash{Symbol => Clip, Array, Hash}] clip definitions
    # @example Simple clips from arrays
    #   Animation.new(
    #     idle: ["sprite_idle.png"],
    #     walk: ["sprite_walk0.png", "sprite_walk1.png", "sprite_walk2.png"]
    #   )
    # @example Clips with hold durations and modes (demo parallax_scene)
    #   Animation.new(
    #     walk: { frames: Array.new(WALK_FRAMES) { |i| "sprites/hero/walk#{i}.png" }, hold: 5 },
    #     idle: { frames: [HERO_IDLE] }
    #   )
    def initialize(clips)
      @clips = {}
      clips.each { |name, spec| @clips[name] = to_clip(spec) }
      @events = {}
      @current = nil
      @started_at = nil
      @last_elapsed = -1
      @clock = 0
    end

    # Register a callback fired once each time the clip enters a specific frame.
    #
    # @param clip_name [Symbol] name of the clip
    # @param frame [Integer] frame index to watch
    # @yield callback invoked when entering the frame
    # @return [Animation] self (allows chaining)
    # @raise [ArgumentError] if clip_name does not exist
    def on(clip_name, frame:, &block)
      raise ArgumentError, "unknown clip #{clip_name.inspect}" unless @clips.key?(clip_name)

      ((@events[clip_name] ||= {})[frame] ||= []) << block
      self
    end

    # Switch to a clip, starting from frame 0 on the next update.
    #
    # Idempotent: calling with the already-playing clip name has no effect.
    #
    # @param name [Symbol] clip name
    # @return [Animation] self (allows chaining)
    # @raise [ArgumentError] if clip name does not exist
    def play(name)
      raise ArgumentError, "unknown clip #{name.inspect}" unless @clips.key?(name)
      return self if name == @current

      @current = name
      @started_at = nil
      self
    end

    # Poll step: advances the frame to match the given clock, firing frame events
    # crossed since the last update.
    #
    # Must be called once per frame for frame events to fire. When clock is frozen
    # (hit-stop, pause, stacked scene), elapsed stays the same, so no events re-fire.
    #
    # @param clock [Numeric] current scene clock value
    # @return [Animation] self (allows chaining)
    def update(clock)
      return self if @current.nil?

      if @started_at.nil?
        @started_at = clock
        @last_elapsed = -1
      end

      elapsed = clock - @started_at
      fire_events(@last_elapsed, elapsed)
      @last_elapsed = elapsed
      @clock = clock
      self
    end

    # The current frame reference, or nil if no clip is playing.
    #
    # Allocates nothing — no closure or temporary objects created.
    #
    # @return [Object, nil] frame reference from the active clip, or nil
    def path
      return nil if @current.nil?

      clip = @clips[@current]
      return clip.frames.first if @started_at.nil?

      clip.frame_at(@clock - @started_at)
    end

    # The current frame index, or nil if no clip is playing.
    #
    # @return [Integer, nil] frame index in the clip's frame array
    def frame_index
      return nil if @current.nil?

      @clips[@current].frame_index_at(@clock - (@started_at || @clock))
    end

    # Whether playback has reached the final frame in a :once clip.
    #
    # @return [Boolean] true only in :once mode when elapsed >= clip.total
    def finished?
      return false if @current.nil? || @started_at.nil?

      clip = @clips[@current]
      clip.mode == :once && (@clock - @started_at) >= clip.total
    end

    private

    def fire_events(lo, hi)
      return if hi <= lo

      clip_events = @events[@current]
      return if clip_events.nil? || clip_events.empty?

      @clips[@current].each_boundary(lo, hi) do |frame|
        callbacks = clip_events[frame]
        callbacks.each { |callback| callback.call } if callbacks
      end
    end

    def to_clip(spec)
      return spec if spec.is_a?(Clip)
      return Clip.new(spec) if spec.is_a?(Array)

      Clip.new(spec[:frames], hold: spec[:hold] || 1, durations: spec[:durations], mode: spec[:mode] || :loop)
    end
  end
end
