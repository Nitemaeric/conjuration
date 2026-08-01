module Conjuration
  class Game < Node
    include AttrGTK
    include SceneManagement
    include CanvasHost

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

    DEBUG_PANEL_ANCHORS = [:top_left, :top_right, :bottom_right, :bottom_left].freeze

    # Screen corner for the state panel, so it can be moved off information it
    # covers. Guarded here as well as at the call site: builds nothing when debug
    # is off. The scene stack and transition/loading phase (unmerged PR #19) are
    # a per-line addition to #game_debug_panel_lines.
    def render_game_debug_panel
      return unless debug?

      lines = game_debug_panel_lines
      widest = lines.map { |text| gtk.calcstringbox(text)[0] }.max
      panel_w = widest + 8
      panel_h = lines.length * 18 + 6

      update_debug_panel_drag
      left, panel_top = debug_panel_origin(panel_w, panel_h)

      @debug_panel_rect = { x: left, y: panel_top - panel_h, w: panel_w, h: panel_h }
      outputs.debug << { x: left, y: panel_top - panel_h, w: panel_w, h: panel_h, path: :pixel, r: 0, g: 0, b: 0, a: 190 }
      lines.each_with_index do |text, index|
        outputs.debug << { x: left + 4, y: panel_top - 4 - index * 18, text: text, size_px: 14, r: 255, g: 255, b: 255, anchor_y: 1 }
      end
    end

    def debug_panel_origin(panel_w, panel_h)
      position = @debug_panel_position
      if position
        [position[:x].clamp(0, grid.w - panel_w), position[:y].clamp(panel_h, grid.h)]
      else
        anchor = debug_panel_anchor
        left = anchor == :top_left || anchor == :bottom_left ? 4 : grid.w - 4 - panel_w
        top = anchor == :top_left || anchor == :top_right ? grid.h - 4 : 4 + panel_h
        [left, top]
      end
    end

    # Grab anywhere on the panel and drag; releasing drops it, cycling the
    # anchor snaps it back to a corner. The grab test uses last frame's rect —
    # one frame of lag, invisible at 60fps. Runs in render so dragging still
    # works during a hit stop, when input/update are skipped.
    def update_debug_panel_drag
      source = inputs
      mouse = source && source.mouse
      return unless mouse

      drag = @debug_panel_drag
      if drag
        if mouse.held
          @debug_panel_position = { x: mouse.x - drag[:dx], y: mouse.y - drag[:dy] }
        else
          @debug_panel_drag = nil
        end
        return
      end

      rect = @debug_panel_rect
      return unless rect && mouse.click
      return unless mouse.x >= rect[:x] && mouse.x <= rect[:x] + rect[:w] &&
                    mouse.y >= rect[:y] && mouse.y <= rect[:y] + rect[:h]

      @debug_panel_drag = { dx: mouse.x - rect[:x], dy: mouse.y - (rect[:y] + rect[:h]) }
    end

    def debug_panel_anchor
      @debug_panel_anchor ||= :top_left
    end

    def debug_panel_anchor=(anchor)
      raise ArgumentError, "unknown anchor #{anchor.inspect} (#{DEBUG_PANEL_ANCHORS.join(", ")})" unless DEBUG_PANEL_ANCHORS.include?(anchor)

      @debug_panel_anchor = anchor
      @debug_panel_position = nil
      @debug_panel_drag = nil
    end

    def cycle_debug_panel_anchor
      index = DEBUG_PANEL_ANCHORS.index(debug_panel_anchor)
      self.debug_panel_anchor = DEBUG_PANEL_ANCHORS[(index + 1) % DEBUG_PANEL_ANCHORS.length]
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
