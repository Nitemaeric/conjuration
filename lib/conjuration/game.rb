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
      # config is nil until the game (or framework UI) calls setup; gating on it
      # skips the pump for games that never use input.
      DragonInput.tick(args) if DragonInput.config

      if transitioning?
        # A transition/loading handover owns the tick: input and update (and thus
        # every clock, game and scene) are suspended until the incoming scene is
        # ready and revealed.
        advance_handover
      elsif @hit_stop && @hit_stop > 0
        @hit_stop -= 1
      else
        perform_input
        # A transition begun from input (e.g. walking into a doorway) suspends the
        # rest of the tick, so update never lands on the freshly-swapped scene.
        perform_update unless transitioning?
      end

      perform_render
    end

    def debug?
      debug
    end

    def input_source
      return @input_source if @input_source_assigned

      @input_source ||= DragonInputSource.new
    end

    def input_source=(source)
      @input_source_assigned = true
      @input_source = source
    end

    def ui_pad
      @ui_pad ||= :one
    end

    attr_writer :ui_pad

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
        render_game_debug_panel

        gtk.framerate_diagnostics_primitives
          .select { |primitive| primitive[:primitive_marker] == :label && !primitive[:text].start_with?("FPS") }
          .map { |primitive| primitive[:text] }
          .each do |primitive|
            outputs.debug << primitive
          end
      end
    end

    # Screen-space state panel, anchored top-left so it clears the demo's
    # top-right FPS readout. Guarded here as well as at the call site: builds
    # nothing when debug is off. The scene stack and transition/loading phase
    # (unmerged PR #19) are a per-line addition to #game_debug_panel_lines.
    def render_game_debug_panel
      return unless debug?

      top = grid.h - 8
      game_debug_panel_lines.each_with_index do |text, index|
        outputs.debug << { x: 8, y: top - index * 18, text: text, size_px: 14, r: 255, g: 255, b: 255, anchor_y: 1 }
      end
    end

    def game_debug_panel_lines
      scene = current_scene
      camera = scene.respond_to?(:focused_camera) ? scene.focused_camera : nil

      [
        "scene: #{scene_debug_label(scene)}",
        "clock: #{clock}  hit-stop: #{@hit_stop || 0}",
        "camera: #{camera ? camera.name : "-"}",
        "ui: focus=#{node_debug_id(UI.focused_node)} hover=#{node_debug_id(UI.hovered_node)} nav=#{UI.active_navigation_group || "-"}"
      ]
    end

    def scene_debug_label(scene)
      return "-" unless scene

      name = scene.respond_to?(:name) ? scene.name : nil
      name ? "#{scene.class.name} (#{name})" : scene.class.name
    end

    def node_debug_id(node)
      node ? node.id : "-"
    end
  end
end
