module Conjuration
  class Scene < Node
    include CameraManagement
    include UIManagement

    attr_accessor :config, :w, :h

    attr_reader :name

    delegate :layout, :geometry, :gtk, :audio, :change_scene, to: :game

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
      UI.focused_node = nil
      setup if respond_to?(:setup)
      outputs.width, outputs.height = w, h
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
      outputs.primitives << ui.primitives

      if debug?
        outputs.debug << ui.interactive_nodes.map do |node|
          {
            **node.object,
            r: 0,
            g: 255,
            b: 0
          }.border!
        end
      end
    end
  end
end
