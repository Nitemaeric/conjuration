module Conjuration
  module UIManagement
    # node() emits into the descriptor build context, so a scene's `view` (or a
    # camera's `camera.ui.view { ... }`) can declare its tree with `self` intact.
    include UI::Builder

    attr_reader :ui

    def initialize(...)
      super(...)
      @ui = UI.build
    end

    # Turn UI navigation on for the named pane `group`. The game owns this — call
    # it when a menu opens, and reassign UI.active_navigation_group yourself to
    # move between panes.
    def activate_navigation(group)
      UI.active_navigation_group = group
    end

    # Turn UI navigation off and drop the highlight; gameplay owns the input
    # again until something reactivates it.
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

      # The mouse drives focus directly and always — it's pointing, not
      # "navigating". Keyboard/controller navigation only runs once the game has
      # set an active group; nil means nav is off, so gameplay can own the stick
      # while menus stay dormant until the game activates one.
      if inputs.last_active == :mouse
        update_focus_from_mouse
      elsif UI.active_navigation_group
        ensure_focus_in_active_group
        update_focus_by_navigation
        trigger_focused_node if UI.focused_node && confirm_pressed?
      end

      UI.pressed_node = pressing? ? UI.focused_node : nil

      scroll_focused
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

    def update_focus_from_mouse
      hovered = ui.find_interactive_intersect(inputs.mouse)

      # Scene + cameras share UI.focused_node and each runs this; the scene's input
      # supers into the cameras', so it runs last. Only manage focus for this ui's
      # own nodes, or an empty scene ui would clear focus owned by a camera (and
      # reset its cursor) — which is why the Back button never showed the hand.
      owns_focus = UI.focused_node && ui.interactive_nodes.include?(UI.focused_node)
      return if hovered.nil? && !owns_focus

      if hovered != UI.focused_node
        UI.focused_node = hovered

        if UI.focused_node
          # Moving the mouse into another pane makes it the active group, so mouse
          # and game-driven navigation agree on where focus lives.
          group = ui.group_of(UI.focused_node)
          UI.active_navigation_group = group if group
          gtk.set_cursor(*UI.hover_cursor) if UI.hover_cursor
        else
          gtk.set_cursor(*UI.default_cursor) if UI.default_cursor
        end
      end

      focused = UI.focused_node
      trigger_focused_node if inputs.mouse.click && focused && focused.intersect_rect?(inputs.mouse)
    end

    # The cursor is left as-is here — a mouse affordance, irrelevant when
    # navigating by key/pad.
    def update_focus_by_navigation
      direction = game.control_scheme.navigation_vector
      return if direction.nil? || (direction.x == 0 && direction.y == 0)

      # Spatial nav stays within the active pane.
      candidates = ui.navigation_groups[UI.active_navigation_group] || []
      target = ui.spatial_navigate(UI.focused_node, direction, candidates: candidates)
      UI.focused_node = target if target
    end

    # Seed focus into the active group when it isn't already there (e.g. right
    # after the game activates navigation), so there's always a visible selection.
    def ensure_focus_in_active_group
      members = ui.navigation_groups[UI.active_navigation_group]
      return if members.nil? || members.empty?
      return if members.any? { |member| member.equal?(UI.focused_node) }

      UI.focused_node = members.first
    end

    def confirm_pressed?
      game.control_scheme.confirm_down?
    end

    def pressing?
      focused = UI.focused_node
      return false unless focused

      (inputs.mouse.held && focused.intersect_rect?(inputs.mouse)) ||
        game.control_scheme.confirm_held?
    end

    # Only triggers if the focused node belongs to THIS ui: focus is a shared
    # global, so a scene and its cameras all reach here each tick.
    def trigger_focused_node
      return unless ui.interactive_nodes.include?(UI.focused_node)

      # A focusable node may have no action (e.g. a scroll container); confirm is
      # a no-op on it.
      action = UI.focused_node.object.action
      instance_exec(&action) if action
    end

    # The built-in focus highlight, so keyboard/pad focus is always visible. nil
    # unless THIS ui owns the focused node (focus is a shared global, reached by
    # every scene + camera each tick).
    def focus_indicator
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

      { x: cursor[:x] - 4, y: cursor[:y] - 4, w: cursor[:w] + 8, h: cursor[:h] + 8, r: 255, g: 220, b: 0 }.border!
    end
  end
end
