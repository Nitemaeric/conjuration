module Conjuration
  class Game < Node
    include AttrGTK
    include SceneManagement

    attr_accessor :debug

    def initialize(args)
      self.args = args
      self.debug = false
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
