module Conjuration
  class Scene < Node
    include BaseLifecycleMethods
    include CameraManagement
    include UIManagement

    attr_accessor :config, :w, :h

    # Logical world bounds. Cameras clamp panning to these; leave them nil for
    # an unbounded (infinitely large) world.
    attr_accessor :virtual_w, :virtual_h

    attr_reader :name

    delegate :layout, :geometry, :gtk, :audio, :change_scene, to: :game

    def initialize(name, **config)
      @name = name

      super(
        config: config,
        w: grid.w,
        h: grid.h
      )
    end

    def state
      game.state["scene_#{name}"]
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
    end

    def perform_render
      super

      render if respond_to?(:render)

      # Relayout once per frame, after input/update have mutated + invalidated.
      # Clean subtrees early-out, so this is near-free when nothing changed.
      ui.calculate_layout

      outputs.primitives << ui.primitives

      indicator = focus_indicator
      outputs.primitives << indicator if indicator

      if debug?
        outputs.debug << ui.interactive_nodes.map do |node|
          {
            **node.rect,
            r: 0,
            g: 255,
            b: 0
          }.border!
        end

        # Invisible layout containers, in magenta — only where they resolve to
        # real bounds (the root has none).
        container_bounds = ui.nodes.reject(&:renderable?).map(&:rect).select { |rect| rect[:w] && rect[:h] }
        outputs.debug << container_bounds.map { |rect| { **rect, r: 255, g: 0, b: 255 }.border! }
      end
    end
  end
end
