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

    # The active input binding for framework UI (confirm/navigation). Framework
    # code reads input only through here — never off `inputs` directly — so an
    # input library replaces this object instead of being retrofitted across
    # UIManagement. Memoized (one instance, not one per frame); assign your own
    # scheme to rebind. Scenes/games may still read raw `inputs` freely.
    def control_scheme
      @control_scheme ||= ControlScheme.new(inputs)
    end

    attr_writer :control_scheme

    private

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
