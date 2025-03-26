module Conjuration
  module CameraManagement
    attr_accessor :cameras, :focused_camera

    def initialize(...)
      super(...)
      @cameras = {}
    end

    def add_camera(name, x:, y:, w: $game.grid.w, h: $game.grid.h, zoom: 1, speed: 1_000_000, zoom_speed: 0.1, source_w: nil, source_h: nil)
      camera = Camera.new(self, name: name, x: x, y: y, w: w, h: h, zoom: zoom, speed: speed, zoom_speed: zoom_speed, source_w: source_w, source_h: source_h)
      cameras[name] = camera
      camera
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
