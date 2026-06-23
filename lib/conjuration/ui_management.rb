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

      if UI.focused_node
        if UI.focused_node.intersect_rect?(inputs.mouse)
          if inputs.mouse.click
            instance_exec(&UI.focused_node.object.action) if ui.interactive_nodes.include?(UI.focused_node)
          end
        else
          UI.focused_node = nil
          gtk.set_cursor(*UI.default_cursor) if UI.default_cursor
        end
      else
        UI.focused_node = ui.find_interactive_intersect(inputs.mouse)

        gtk.set_cursor(*UI.hover_cursor) if UI.focused_node && UI.hover_cursor
      end
    end

    def perform_update
      super

      ui.calculate_layout if events.orientation_changed
    end
  end
end
