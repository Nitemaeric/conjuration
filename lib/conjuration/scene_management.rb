module Conjuration
  module SceneManagement
    attr_accessor :current_scene

    def change_scene(to:)
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
