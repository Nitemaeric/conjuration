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
      cameras.each do |name, camera|
        camera.perform_update

        if inputs.mouse.inside_rect?(camera.rect)
          @focused_camera = camera
        end
      end
    end

    def perform_render
      cameras.each do |name, camera|
        camera.perform_render
      end
    end
  end
end
