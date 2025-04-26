module Conjuration
  class Camera < Node
    include BaseLifecycleMethods
    include UIManagement

    attr_accessor :scene, :name

    # Camera's viewport on the screen
    attr_accessor :x, :y, :w, :h

    attr_accessor :current, :target, :current_at_target_change
    attr_accessor :speed, :zoom_speed

    def initialize(scene, name:, x: 0, y: 0, w: grid.w, h: grid.h, current: { x: grid.w / 2, y: grid.h / 2, zoom: 1 }, speed: 1_000_000, zoom_speed: 0.1)
      super(scene: scene, name: name, x: x, y: y, w: w, h: h, speed: speed, zoom_speed: zoom_speed)

      @current = FocalPoint.new(self, **current)
      @target = FocalPoint.new(self, **current)
    end

    def look_at(object)
      self.target.x    = object.x    if object.x
      self.target.y    = object.y    if object.y
      self.target.zoom = object.zoom if object.zoom

      current_at_target_change = current.dup
    end

    def to_world(x:, y:, w: nil, h: nil)
      {
        x: (x + current.x - self.w / 2 - self.x) * current.zoom,
        y: (y + current.y - self.h / 2 - self.y) * current.zoom,
        w: w ? w * current.zoom : nil,
        h: h ? h * current.zoom : nil
      }
    end

    def to_screen(x:, y:, w:, h:)
      {
        x: (current.x + self.x) / current.zoom,
        y: (current.y + self.y) / current.zoom,
        w: w / current.zoom,
        h: h / current.zoom
      }
    end

    def outputs
      game.outputs["camera_#{name}"]
    end

    private

    def perform_update
      super

      if target.x != current.x || target.y != current.y
        normalized_direction = Geometry.vec2_normalize(x: (target.x - current.x), y: (target.y - current.y))

        self.current.x += (normalized_direction.x * speed).clamp(-(target.x - current.x).abs, (target.x - current.x).abs)
        self.current.y += (normalized_direction.y * speed).clamp(-(target.y - current.y).abs, (target.y - current.y).abs)
      end
    end

    def perform_render
      # Render scene to camera viewport
      outputs.primitives << {
        x: 0,
        y: 0,
        w: grid.w,
        h: grid.h,
        source_x: (current.x - (w / 2) / current.zoom).clamp(0, scene.outputs.w - w),
        source_y: (current.y - (h / 2) / current.zoom).clamp(0, scene.outputs.h - h),
        source_w: w / current.zoom,
        source_h: h / current.zoom,
        path: "scene_#{scene.name}"
      }

      # Render UI components to camera viewport
      outputs.primitives << ui.primitives

      if debug?
        outputs.debug << ui.interactive_nodes.map do |node|
          {
            **node.object,
            r: 0,
            g: 255,
            b: 0
          }.border!
        end
      end

      # Render camera viewport to screen viewport
      game.outputs.primitives << [
        {
          x: x,
          y: y,
          w: w,
          h: h,
          path: "camera_#{name}"
        }
      ]
    end

    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} name: #{name}, x: #{x}, y: #{y}, w: #{w}, h: #{h}, current-x: #{current&.x}, current-y: #{current&.y}, current-zoom: #{current&.zoom}, speed: #{speed}, zoom_speed: #{zoom_speed}>"
    end

    class FocalPoint < Node
      attr_accessor :x, :y, :zoom, :camera

      def initialize(camera, **attributes)
        super(camera: camera, **attributes)
      end

      def x=(value)
        @x = camera && camera.scene ? value.clamp(camera.w / 2, camera.scene.outputs.w - camera.w / 2) : value
      end

      def y=(value)
        @y = camera && camera.scene ? value.clamp(camera.h / 2, camera.scene.outputs.h - camera.h / 2) : value
      end

      def zoom=(value)
        @zoom = value.clamp(0.1, 10)
      end
    end
  end
end
