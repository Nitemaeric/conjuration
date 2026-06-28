module Conjuration
  module UIManagement
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
      ui.calculate_layout
      gtk.set_cursor(*UI.default_cursor) if UI.default_cursor

      super
    end

    def perform_input
      super

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
      direction = inputs.key_down.directional_vector
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

    # Space is intentionally excluded — games commonly bind it (the hit-stop demo
    # swings with it), so confirming on it would double-fire.
    def confirm_pressed?
      inputs.keyboard.key_down.enter || inputs.controller_one.key_down.a
    end

    # Drives the :pressed state: the focused node held down (mouse over it with the
    # button down, or a held confirm key).
    def pressing?
      focused = UI.focused_node
      return false unless focused

      (inputs.mouse.held && focused.intersect_rect?(inputs.mouse)) ||
        inputs.keyboard.key_held.enter ||
        inputs.controller_one.key_held.a
    end

    # Only triggers if the focused node belongs to THIS ui: focus is a shared
    # global, so a scene and its cameras all reach here each tick.
    def trigger_focused_node
      return unless ui.interactive_nodes.include?(UI.focused_node)

      instance_exec(&UI.focused_node.object.action)
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
