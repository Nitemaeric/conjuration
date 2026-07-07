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
      # Recompute focus from scratch each tick so it clears when the mouse leaves
      # every camera (a retained value would keep the last camera focused with
      # the pointer outside it). Cameras are visited in insertion order and the
      # last hit wins, so where viewports overlap the topmost — the most recently
      # added camera, which is also drawn last — takes focus.
      @focused_camera = nil

      cameras.each do |name, camera|
        camera.perform_update

        @focused_camera = camera if inputs.mouse.inside_rect?(camera.rect)
      end
    end

    def perform_render
      cameras.each do |name, camera|
        camera.perform_render
      end
    end
  end
end
