module Conjuration
  module CameraManagement
    attr_accessor :cameras, :focused_camera

    def initialize(...)
      super(...)
      @cameras = {}
    end

    def add_camera(name, **attributes)
      camera = Camera.new(self, name: name, **attributes)
      cameras[name] = camera
      camera
    end

    private

    def perform_setup
      cameras.each do |name, camera|
        camera.perform_setup
      end
    end

    def perform_input
      cameras.each do |name, camera|
        camera.perform_input
      end
    end

    def perform_update
      # Reset each tick so focus clears once the pointer leaves every camera.
      @focused_camera = nil

      cameras.each do |name, camera|
        camera.perform_update

        # Viewports are scene-space rects, so the pointer test uses the
        # scene-space (canvas) mouse.
        @focused_camera = camera if game.mouse.inside_rect?(camera.rect)
      end
    end

    def perform_render
      cameras.each do |name, camera|
        camera.perform_render
      end
    end
  end
end
