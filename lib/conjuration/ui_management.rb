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
      super rescue nil
    end

    def perform_input
      super rescue nil

      if UI.focused_node
        if UI.focused_node.intersect_rect?(inputs.mouse)
          instance_exec(&UI.focused_node.action) if inputs.mouse.click
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
      super rescue nil

      ui.calculate_layout if events.orientation_changed
    end
  end
end
