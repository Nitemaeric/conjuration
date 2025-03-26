module Conjuration
  class Scene < Node
    include CameraManagement

    attr_accessor :key, :config, :w, :h

    delegate :inputs, :grid, :layout, :geometry, :gtk, :audio, to: :game

    def initialize(key, **config)
      super(
        key: key,
        config: config,
        w: grid.w,
        h: grid.h
      )
    end

    def state
      game.state[key.to_sym]
    end

    def outputs
      game.outputs[:scene]
    end

    def debug_inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} size: #{w}x#{h}>"
    end

    private

    def perform_setup
      setup if respond_to?(:setup)
      outputs.width = w
      outputs.height = h
    end

    def perform_input
      input if respond_to?(:input)
    end

    def perform_update
      super
      update if respond_to?(:update)
    end

    def perform_render
      super
      render if respond_to?(:render)
    end
  end
end
