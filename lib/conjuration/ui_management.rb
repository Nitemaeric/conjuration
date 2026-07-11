module Conjuration
  # Scene/camera integration for the UI tree: builds the tree, drives input
  # (hover, focus, shortcuts, scroll), and renders primitives each frame.
  #
  # Mixed into {Conjuration::Scene} and cameras that host HUD trees.
  #
  # @note Navigation is inert until a group is activated; nil
  #   +UI.active_navigation_group+ means gameplay owns input and menus stay dormant.
  # @note Hover never writes focus; hover tracks mouse, focus tracks keyboard/pad.
  # @note Focus is retained but the indicator is hidden while the mouse is the
  #   active device (+inputs.last_active == :mouse+).
  # @note Shortcuts fire without focus; they are global accelerators that run
  #   when the declared shortcut edge-presses, regardless of focus.
  module UIManagement
    # node() emits into the descriptor build context, so a scene's `view` (or a
    # camera's `camera.ui.view { ... }`) can declare its tree with `self` intact.
    include UI::Builder

    # The built UI tree root for this scene/camera.
    #
    # @return [Conjuration::UI::Node]
    attr_reader :ui

    def initialize(...)
      super(...)
      @ui = UI.build
    end

    # Turn UI navigation on for the named pane `group`. The game owns this — call
    # it when a menu opens, and reassign UI.active_navigation_group yourself to
    # move between panes.
    #
    # @param group [Symbol, Object] navigation group id (matches +group:+ on nodes)
    # @return [void]
    # @note Navigation is inert until a group is activated; nil
    #   +UI.active_navigation_group+ means gameplay owns input.
    # @example Activate and cycle groups (from UIScene)
    #   NAV_GROUPS = [:hud, :party, :skills, :list].freeze
    #
    #   def input
    #     if Conjuration::UI.active_navigation_group.nil? && inputs.last_active != :mouse
    #       activate_navigation(:skills)
    #     elsif Conjuration::UI.active_navigation_group && inputs.keyboard.key_down.tab
    #       current = NAV_GROUPS.index(Conjuration::UI.active_navigation_group) || -1
    #       activate_navigation(NAV_GROUPS[(current + 1) % NAV_GROUPS.length])
    #     end
    #   end
    def activate_navigation(group)
      UI.active_navigation_group = group
    end

    # Turn UI navigation off and drop the highlight; gameplay owns the input
    # again until something reactivates it.
    #
    # @return [void]
    # @note Navigation is inert until a group is activated; nil
    #   +UI.active_navigation_group+ means gameplay owns input and menus stay dormant.
    def deactivate_navigation
      UI.active_navigation_group = nil
      UI.focused_node = nil
    end

    private

    def perform_setup
      # A scene that defines `view` opts into the reactive path; the block keeps
      # self = the scene, so `view` and its helpers resolve normally. Build the
      # tree once here so it exists before the first render/input pass.
      ui.view { view } if respond_to?(:view) && !ui.view?
      ui.render_view
      ui.calculate_layout
      gtk.set_cursor(*UI.default_cursor) if UI.default_cursor

      super
    end

    def perform_input
      super

      scroll_under_mouse

      # The mouse is pointing, not navigating: it drives hovered_node (styling +
      # click targeting) and never touches focused_node, so keyboard/pad focus
      # survives a mouse interlude and resumes where it left off. Navigation only
      # runs once the game has set an active group; nil means nav is off, so
      # gameplay can own the stick while menus stay dormant.
      if inputs.last_active == :mouse
        update_hover_from_mouse
      else
        UI.hovered_node = nil
        if UI.active_navigation_group
          ensure_focus_in_active_group
          update_focus_by_navigation
          trigger_node(UI.focused_node) if UI.focused_node && confirm_pressed?
        end
      end

      UI.pressed_node = pressed_target

      trigger_shortcuts

      scroll_focused
    end

    # Fire any interactive node whose declared shortcut edge-pressed this frame,
    # regardless of focus or whether a navigation group is active — a global
    # accelerator. Bound by the cached shortcut list (rebuilt only with the
    # structure caches), so a ui with no shortcuts costs one array read.
    def trigger_shortcuts
      nodes = ui.shortcut_nodes
      return if nodes.empty?

      source = game.input_source
      pad = game.ui_pad
      nodes.each do |node|
        next unless source.shortcut_just_pressed?(pad, node.shortcut_action_name, node.shortcut)

        action = node.object.action
        instance_exec(&action) if action
      end
    end

    # Mouse wheel scrolls the overflow: :scroll container under the cursor.
    def scroll_under_mouse
      return unless inputs.mouse.wheel

      container = ui.nodes.find { |node| node.scroll? && node.intersect_rect?(inputs.mouse) }
      return unless container

      container.scroll_offset = (container.scroll_offset - inputs.mouse.wheel.y * 20).clamp(0, container.max_scroll)
    end

    # The right thumbstick scrolls the focused scroll container (when this ui owns
    # it), so a navigated-to scroll pane scrolls by default.
    def scroll_focused
      focused = UI.focused_node
      return unless focused&.scroll? && ui.interactive_nodes.include?(focused)

      delta = inputs.controller_one.right_analog_y_perc
      return if delta.abs < 0.15

      focused.scroll_offset = (focused.scroll_offset - delta * 14).clamp(0, focused.max_scroll)
    end

    def perform_update
      super

      # Orientation flips every grid-relative value; mark the whole tree dirty so
      # the per-frame relayout (perform_render) rebuilds it.
      ui.invalidate_subtree! if events.orientation_changed
    end

    def update_hover_from_mouse
      hovered = ui.find_interactive_intersect(inputs.mouse)

      # Scene + cameras share UI.hovered_node and each runs this; the scene's
      # input supers into the cameras', so it runs last. Only manage hover for
      # this ui's own nodes, or an empty scene ui would clear hover owned by a
      # camera (and reset its cursor).
      owns_hover = UI.hovered_node && ui.interactive_nodes.include?(UI.hovered_node)
      return if hovered.nil? && !owns_hover

      if hovered != UI.hovered_node
        UI.hovered_node = hovered

        if hovered
          gtk.set_cursor(*UI.hover_cursor) if UI.hover_cursor
        else
          gtk.set_cursor(*UI.default_cursor) if UI.default_cursor
        end
      end

      hovered = UI.hovered_node
      trigger_node(hovered) if inputs.mouse.click && hovered && hovered.intersect_rect?(inputs.mouse)
    end

    # The cursor is left as-is here — a mouse affordance, irrelevant when
    # navigating by key/pad.
    def update_focus_by_navigation
      direction = navigation_vector
      return if direction.nil?

      # Spatial nav stays within the active pane.
      candidates = ui.navigation_groups[UI.active_navigation_group] || []
      target = ui.spatial_navigate(UI.focused_node, direction, candidates: candidates)
      UI.focused_node = target if target
    end

    # Left unnormalized (a diagonal fires both axes); spatial_navigate reads only
    # the signs. The digital arrows drive it directly; when they're neutral, the
    # right stick contributes one flick step (sources that don't implement it —
    # e.g. a raw keyboard-only source — simply don't).
    def navigation_vector
      source = game.input_source
      pad = game.ui_pad

      x = (source.just_pressed?(pad, :ui_right) ? 1 : 0) - (source.just_pressed?(pad, :ui_left) ? 1 : 0)
      y = (source.just_pressed?(pad, :ui_up) ? 1 : 0) - (source.just_pressed?(pad, :ui_down) ? 1 : 0)

      if x == 0 && y == 0 && source.respond_to?(:navigation_flick)
        return source.navigation_flick(pad)
      end

      return nil if x == 0 && y == 0

      { x: x, y: y }
    end

    # Seed focus into the active group when it isn't already there (e.g. right
    # after the game activates navigation), so there's always a visible selection.
    # A focus retained in the group is left alone — a mouse interlude never
    # reseeds the selection.
    def ensure_focus_in_active_group
      members = ui.navigation_groups[UI.active_navigation_group]
      return if members.nil? || members.empty?
      return if members.any? { |member| member.equal?(UI.focused_node) }

      UI.focused_node = members.first
    end

    def confirm_pressed?
      game.input_source.just_pressed?(game.ui_pad, :ui_confirm)
    end

    # A mouse press acts on the hovered node; a held confirm on the focused one.
    def pressed_target
      hovered = UI.hovered_node
      return hovered if hovered && inputs.mouse.held && hovered.intersect_rect?(inputs.mouse)

      focused = UI.focused_node
      return focused if focused && game.input_source.pressed?(game.ui_pad, :ui_confirm)

      nil
    end

    # Only triggers if the node belongs to THIS ui: hover/focus are shared
    # globals, so a scene and its cameras all reach here each tick.
    def trigger_node(node)
      return unless ui.interactive_nodes.include?(node)

      # A focusable node may have no action (e.g. a scroll container); confirm is
      # a no-op on it.
      action = node.object.action
      instance_exec(&action) if action
    end

    # Re-derive this ui's tree from state (no-op unless a `view` is registered),
    # relayout once per frame, then emit its primitives, focus indicator, and — in
    # debug — its interactive/container bounds into `outputs`. Reconcile writes
    # only changed props and clean subtrees early-out of layout, so this is
    # near-free when nothing changed. Scene and camera share it, each passing its
    # own outputs (screen HUD vs. viewport target).
    #
    # @param outputs [Object] DragonRuby outputs target (e.g. +args.outputs+ or a
    #   camera render target)
    # @return [void]
    def render_ui(outputs)
      ui.render_view
      ui.calculate_layout
      ui.render_scroll_targets

      outputs.primitives << ui.primitives

      indicator = focus_indicator
      outputs.primitives << indicator if indicator

      return unless debug?

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

    # The built-in focus highlight, so keyboard/pad focus is visible without any
    # game styling. Hidden (but retained) while the mouse is the active device;
    # nil unless THIS ui owns the focused node (focus is a shared global, reached
    # by every scene + camera each tick).
    #
    # Override per scene/camera to opt in or out of the built-in ring.
    #
    # @return [Boolean] whether the built-in focus indicator may draw
    # @note Focus is retained but the indicator is hidden while
    #   +inputs.last_active == :mouse+.
    # @example Opt in (from UIScene)
    #   def focus_indicator_enabled?
    #     true
    #   end
    def focus_indicator_enabled?
      UI.focus_indicator_default
    end

    def focus_indicator
      return unless focus_indicator_enabled?
      return if inputs.last_active == :mouse

      focused = UI.focused_node
      return unless focused && ui.interactive_nodes.include?(focused)

      rect = focused.rect
      x = rect.x - (rect.anchor_x || 0) * rect.w
      y = rect.y - (rect.anchor_y || 0) * rect.h

      cursor = UI.focus_cursor
      if cursor[:w] == 0 # uninitialised / reset on scene change: snap, don't slide
        cursor[:x], cursor[:y], cursor[:w], cursor[:h] = x, y, rect.w, rect.h
      else
        cursor[:x] = cursor[:x].lerp(x, 0.3)
        cursor[:y] = cursor[:y].lerp(y, 0.3)
        cursor[:w] = cursor[:w].lerp(rect.w, 0.3)
        cursor[:h] = cursor[:h].lerp(rect.h, 0.3)
      end

      # Two nested borders — a dark outline under a light one — so the ring reads
      # on any background without shouting.
      [
        { x: cursor[:x] - 4, y: cursor[:y] - 4, w: cursor[:w] + 8, h: cursor[:h] + 8, r: 20, g: 16, b: 8, a: 160 }.border!,
        { x: cursor[:x] - 3, y: cursor[:y] - 3, w: cursor[:w] + 6, h: cursor[:h] + 6, r: 255, g: 250, b: 235, a: 220 }.border!
      ]
    end
  end
end