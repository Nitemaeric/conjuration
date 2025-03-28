module Conjuration
  class Game < Node
    include AttrGTK
    include SceneManagement

    attr_accessor :debug

    def initialize(args)
      self.args = args
      self.debug = false
    end

    def tick
      perform_input
      perform_update
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
