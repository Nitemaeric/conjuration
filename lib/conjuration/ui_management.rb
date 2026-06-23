module Conjuration
  module UIManagement
    attr_reader :ui

    def initialize(...)
      super(...)
      @ui = UI.build
    end

    private

    def perform_setup
      ui.calculate_layout
      gtk.set_cursor(*UI.default_cursor) if UI.default_cursor

      super
    end

    def perform_input
      super

      # DR tracks the last device used; let the mouse drive focus only while it's
      # active, so keyboard/controller focus isn't stolen back by a resting cursor.
      if inputs.last_active == :mouse
        update_focus_from_mouse
      else
        update_focus_by_navigation
      end

      trigger_focused_node if UI.focused_node && confirm_pressed?
    end

    def perform_update
      super

      ui.calculate_layout if events.orientation_changed
    end

    # Mouse drives focus: hover to focus (swapping the cursor), click to trigger.
    def update_focus_from_mouse
      hovered = ui.find_interactive_intersect(inputs.mouse)

      if hovered != UI.focused_node
        UI.focused_node = hovered

        if UI.focused_node
          gtk.set_cursor(*UI.hover_cursor) if UI.hover_cursor
        else
          gtk.set_cursor(*UI.default_cursor) if UI.default_cursor
        end
      end

      focused = UI.focused_node
      trigger_focused_node if inputs.mouse.click && focused && focused.intersect_rect?(inputs.mouse)
    end

    # Keyboard / controller moves focus spatially. The cursor is left as-is — it's
    # a mouse affordance, irrelevant while navigating by key or d-pad.
    def update_focus_by_navigation
      direction = navigation_direction
      return unless direction

      target = ui.navigate(UI.focused_node, direction)
      UI.focused_node = target if target
    end

    def navigation_direction
      keyboard = inputs.keyboard.key_down
      controller = inputs.controller_one.key_down

      return :up if keyboard.up || controller.up
      return :down if keyboard.down || controller.down
      return :left if keyboard.left || controller.left
      return :right if keyboard.right || controller.right

      nil
    end

    # Enter or controller A. Space is intentionally excluded — games commonly bind
    # it (the hit-stop demo swings with it), so confirming on it would double-fire.
    def confirm_pressed?
      inputs.keyboard.key_down.enter || inputs.controller_one.key_down.a
    end

    # Run the focused node's action, but only if it belongs to THIS ui: focus is a
    # shared global, so a scene and its cameras all reach here each tick.
    def trigger_focused_node
      return unless ui.interactive_nodes.include?(UI.focused_node)

      instance_exec(&UI.focused_node.object.action)
    end
  end
end
