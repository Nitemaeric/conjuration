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

    private

    def perform_setup
      setup if respond_to?(:setup)
      super
    end

    def perform_input
      input if respond_to?(:input)
      super
    end

    def perform_update
      update if respond_to?(:update)
      super
    end

    def perform_render
      render if respond_to?(:render)
      super
      # outputs.debug << gtk.framerate_diagnostics_primitives
    end
  end
end
