module Conjuration
  class Scene < Node
    include CameraManagement

    attr_accessor :name, :config, :w, :h

    delegate :inputs, :layout, :geometry, :gtk, :audio, :change_scene, to: :game

    def initialize(name, **config)
      super(
        name: name,
        config: config,
        w: grid.w,
        h: grid.h
      )
    end

    def state
      game.state["scene_#{name}"]
    end

    def outputs
      game.outputs["scene_#{name}"]
    end

    def debug_inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} size: #{w}x#{h}>"
    end

    private

    def perform_setup
      audio.clear
      setup if respond_to?(:setup)
      outputs.width, outputs.height = w, h
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
