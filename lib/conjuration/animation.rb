module Conjuration
  # Named-clip frame animation keyed to a scene/game clock. The current frame is
  # derived from `clock - started_at` rather than incremented per tick, so a hit
  # stop or pause — which freezes the clock — freezes the frame and resumes mid
  # clip for free. Players are plain objects owned by game code; there is no
  # registry, and querying #path allocates nothing.
  class Animation
    # An ordered set of frames with per-frame hold durations and a playback mode.
    #
    #   :loop      — 0..n-1, repeat.
    #   :once      — 0..n-1, then hold the last frame (see #finished?).
    #   :ping_pong — 0..n-1 then n-2..1, repeat. The turnaround frames (0 and
    #                n-1) are held once per cycle, not double-held; interior
    #                frames are entered twice per cycle (once each direction), so
    #                their frame events fire twice per cycle.
    class Clip
      attr_reader :frames, :mode, :durations, :total, :cycle

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

      def frame_at(elapsed)
        @frames[frame_index_at(elapsed)]
      end

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

    attr_reader :current, :clock

    def initialize(clips)
      @clips = {}
      clips.each { |name, spec| @clips[name] = to_clip(spec) }
      @events = {}
      @current = nil
      @started_at = nil
      @last_elapsed = -1
      @clock = 0
    end

    # Register a callback fired once each time the clip enters `frame`.
    def on(clip_name, frame:, &block)
      raise ArgumentError, "unknown clip #{clip_name.inspect}" unless @clips.key?(clip_name)

      ((@events[clip_name] ||= {})[frame] ||= []) << block
      self
    end

    # Idempotent while already playing `name`; switching clips re-anchors so the
    # new clip starts from frame 0 on the next #update.
    def play(name)
      raise ArgumentError, "unknown clip #{name.inspect}" unless @clips.key?(name)
      return self if name == @current

      @current = name
      @started_at = nil
      self
    end

    # Poll step: advances the derived frame to `clock` and fires the frame events
    # crossed since the last poll. Must be called once per frame for events; a
    # frozen clock leaves elapsed unchanged, so no event refires.
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

    def path
      return nil if @current.nil?

      clip = @clips[@current]
      return clip.frames.first if @started_at.nil?

      clip.frame_at(@clock - @started_at)
    end

    def frame_index
      return nil if @current.nil?

      @clips[@current].frame_index_at(@clock - (@started_at || @clock))
    end

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
