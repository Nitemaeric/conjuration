module Conjuration
  class Scene < Node
    include BaseLifecycleMethods
    include CameraManagement
    include UIManagement
    include Scheduling
    include Sequencing

    attr_accessor :config, :w, :h

    # Logical world bounds. Cameras clamp panning to these; leave them nil for
    # an unbounded (infinitely large) world.
    attr_accessor :virtual_w, :virtual_h

    attr_reader :name

    # Advances one per active-top update (frozen while paused or during a hit
    # stop). Key scene animations to this, not Kernel.tick_count.
    attr_reader :clock

    # Where push/pop stashes this scene's focus/navigation globals while it is
    # paused underneath an overlay (see SceneManagement).
    attr_accessor :saved_focus

    delegate :layout, :geometry, :gtk, :audio, :change_scene, :push_scene, :pop_scene, to: :game

    def initialize(name, **config)
      @name = name

      @state_key = "scene_#{name}"
      @clock = 0

      super(
        config: config,
        w: grid.w,
        h: grid.h
      )
    end

    # Per-instance token so stacked scenes that both add a `:main` camera get
    # distinct render targets (camera.rb keys targets by scene.uid). object_id is
    # unique and never reused, so no two live scenes ever collide.
    def uid
      object_id
    end

    def state
      game.state[@state_key] ||= {}
    end

    # Screen-space output for HUD/backgrounds. World content is drawn through
    # cameras via #draw_world, not into a scene-sized render target. Routed
    # through render_output so a transition can capture a frame into a snapshot
    # target (normally this is just game.outputs).
    def outputs
      game.render_output
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
      # Audio is no longer cleared here — that policy moved to the change_scene
      # path (SceneManagement) so a pushed overlay never silences the scene it
      # pauses. See docs/design/scene-lifecycle.md §7.
      @clock = 0
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
      @clock += 1 # advances only while this scene is the active top

      super

      update if respond_to?(:update)

      tick_sequence # first, so a step's freshly-kicked tween ticks the same frame
      tick_schedules # keyed to the scene clock, which holds during a hit stop
    end

    def perform_render
      super

      render if respond_to?(:render)

      render_ui(outputs)
    end
  end
end
