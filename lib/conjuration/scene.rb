module Conjuration
  class Scene < Node
    include BaseLifecycleMethods
    include CameraManagement
    include UIManagement
    include Scheduling

    attr_accessor :config, :w, :h

    # Logical world bounds. Cameras clamp panning to these; leave them nil for
    # an unbounded (infinitely large) world.
    attr_accessor :virtual_w, :virtual_h

    attr_reader :name

    delegate :layout, :geometry, :gtk, :audio, :change_scene, :clock, to: :game

    def initialize(name, **config)
      @name = name

      @state_key = "scene_#{name}"

      super(
        config: config,
        w: grid.w,
        h: grid.h
      )
    end

    def state
      game.state[@state_key] ||= {}
    end

    # Screen-space output for HUD/backgrounds. World content is drawn through
    # cameras via #draw_world, not into a scene-sized render target.
    def outputs
      game.outputs
    end

    def debug_inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} size: #{w}x#{h}>"
    end

    # Emit world-space content for the given camera. Override in subclasses and
    # use camera.draw(rect) (or camera.visible? / camera.to_viewport) so only
    # on-screen objects are rendered. Called once per camera, per frame.
    def draw_world(camera); end

    private

    def perform_setup
      audio.clear
      UI.focused_node = nil
      UI.hovered_node = nil
      UI.pressed_node = nil
      UI.active_navigation_group = nil # every scene starts inert; opt in via setup
      UI.focus_cursor[:w] = 0 # re-snap the highlight in the new scene
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

      tick_schedules # keyed to the (game) clock, which holds during a hit stop
    end

    def perform_render
      super

      render if respond_to?(:render)

      render_ui(outputs)
    end
  end
end
