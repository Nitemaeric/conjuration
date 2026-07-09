module Conjuration
  module SceneManagement
    attr_accessor :current_scene

    def change_scene(to:)
      # Focus state is module-global, so the outgoing scene's focus/navigation
      # would otherwise leak into the incoming one. Reset before setup so the
      # new scene's own activate_navigation (e.g. MenuScene's) still sticks.
      UI.focused_node = nil
      UI.pressed_node = nil
      UI.active_navigation_group = nil

      @current_scene = to
      @current_scene.perform_setup
    end

    private

    def perform_setup
      current_scene.perform_setup
    end

    def perform_input
      current_scene.perform_input
    end

    def perform_update
      current_scene.perform_update
    end

    def perform_render
      current_scene.perform_render
    end
  end
end
