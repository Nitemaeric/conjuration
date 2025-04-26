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

      super
    end

    def perform_input
      super

      if UI.focused_node
        if UI.focused_node.intersect_rect?(inputs.mouse)
          if inputs.mouse.click
            instance_exec(&UI.focused_node.object.action) if ui.interactive_nodes.include?(UI.focused_node)
          end
        else
          UI.focused_node = nil
          gtk.set_cursor "sprites/cursor-none.png", 9, 4
        end
      else
        UI.focused_node = ui.find_interactive_intersect(inputs.mouse)

        gtk.set_cursor "sprites/hand-point.png", 6, 4 if UI.focused_node
      end
    end

    def perform_update
      super

      ui.calculate_layout if events.orientation_changed
    end
  end
end
