module Conjuration
  class Game < Node
    include AttrGTK
    include SceneManagement

    attr_accessor :debug

    # Frames elapsed in game time: +1 per un-frozen update, so it holds still
    # during a hit stop (and, later, while a scene is paused). Key easings and
    # timers to this, not Kernel.tick_count — Kernel.tick_count keeps advancing
    # through a freeze, so an easing keyed to it skips instead of holding.
    attr_reader :clock

    def initialize(args)
      self.args = args
      self.debug = false
      @clock = 0
    end

    # Freeze the game for `frames` ticks: input and update are skipped while
    # rendering continues (a hit stop / impact freeze). Pair with camera shake
    # for impact effects.
    def hit_stop(frames)
      @hit_stop = frames
    end

    def tick
      if @hit_stop && @hit_stop > 0
        @hit_stop -= 1
      else
        perform_input
        perform_update
      end

      perform_render
    end

    def debug?
      debug
    end

    # The object framework UI reads input through: it answers
    # just_pressed?(pad, action) / pressed?(pad, action) for the reserved
    # UI_ACTIONS names. Defaults implicitly — DragonInput when it's loaded,
    # otherwise the raw-inputs fallback. Assigning one (see input_source=) opts
    # out of all implicit behaviour.
    def input_source
      return @input_source if @input_source_assigned

      @input_source ||= detect_input_source
    end

    def input_source=(source)
      @input_source_assigned = true
      @input_source = source
    end

    # The logical pad framework UI listens to.
    def ui_pad
      @ui_pad ||= :one
    end

    attr_writer :ui_pad

    private

    def detect_input_source
      # const_defined?, not defined? — DragonRuby's mruby has no `defined?`.
      if Object.const_defined?(:DragonInput)
        DragonInputSource.new
      else
        FallbackInputSource.new(inputs)
      end
    end

    def perform_setup
      setup if respond_to?(:setup)
      super
    end

    def perform_input
      super
      input if respond_to?(:input)
    end

    def perform_update
      # Only runs on un-frozen ticks (tick skips input+update during a hit stop),
      # so advancing the clock here is what freezes game time with the freeze.
      @clock += 1
      super
      update if respond_to?(:update)
    end

    def perform_render
      super
      render if respond_to?(:render)

      if debug?
        gtk.framerate_diagnostics_primitives
          .select { |primitive| primitive[:primitive_marker] == :label && !primitive[:text].start_with?("FPS") }
          .map { |primitive| primitive[:text] }
          .each do |primitive|
            outputs.debug << primitive
          end
      end
    end
  end
end
