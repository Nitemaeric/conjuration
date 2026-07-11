module Conjuration
  # Mixin for Scene that manages multiple cameras.
  #
  # Cameras are composited from back to front in the order they were added.
  # The focused_camera attribute tracks which camera (if any) the mouse pointer
  # is currently over.
  #
  # @example Adding and accessing cameras
  #   add_camera(:main, speed: 12)
  #   add_camera(:minimap, x: grid.w - 200, y: grid.h - 150, w: 200, h: 150)
  #   cameras[:main].follow(player)
  module CameraManagement
    attr_accessor :cameras, :focused_camera

    def initialize(...)
      super(...)
      @cameras = {}
    end

    # Create and register a new camera in the scene.
    #
    # @param name [Symbol, String] unique identifier for this camera
    # @param attributes [Hash] camera attributes
    # @option attributes [Numeric] :x screen position (default: 0)
    # @option attributes [Numeric] :y screen position (default: 0)
    # @option attributes [Numeric] :w viewport width (default: grid.w)
    # @option attributes [Numeric] :h viewport height (default: grid.h)
    # @option attributes [Hash] :current focal point {x:, y:, zoom:}
    # @option attributes [Numeric] :speed pan speed per tick (default: SNAP)
    # @option attributes [Numeric] :zoom_speed zoom per tick (default: 0.1)
    # @return [Camera] the created camera
    # @example Creating a split-screen setup
    #   left  = add_camera(:left,  x: 0,          y: 0, w: grid.w / 2, h: grid.h)
    #   right = add_camera(:right, x: grid.w / 2, y: 0, w: grid.w / 2, h: grid.h)
    # @example Creating a minimap
    #   minimap = add_camera(:minimap, x: grid.w - 200, y: grid.h - 150, w: 200, h: 150)
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
