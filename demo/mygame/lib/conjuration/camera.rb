module Conjuration
  class Camera < Node
    attr_accessor :scene, :name
    attr_accessor :x, :y, :w, :h
    attr_accessor :source_w, :source_h
    attr_accessor :focus_x, :focus_y, :zoom
    attr_accessor :target_x, :target_y, :target_zoom
    attr_accessor :speed, :zoom_speed

    delegate :outputs, :grid, to: :game

    # camera = Camera.new(outputs[:scene])
    def initialize(scene, name: "", x: 0, y: 0, w: grid.w, h: grid.h, zoom: 1, speed: 1_000_000, zoom_speed: 0.1, source_w: nil, source_h: nil)
      super(scene: scene, name: name, x: x, y: y, w: w, h: h, zoom: zoom, speed: speed, zoom_speed: zoom_speed, source_w: source_w || w, source_h: source_h || h)

      @target_x = @focus_x = grid.w / 2
      @target_y = @focus_y = grid.h / 2
      @target_zoom = @zoom
    end

    def look_at(object)
      self.target_x = self.focus_x = object.x.clamp(w / 2, scene.w - w / 2)
      self.target_y = self.focus_y = object.y.clamp(h / 2, scene.h - h / 2)
    end

    def to_world(x:, y:, w: nil, h: nil)
      {
        x: (x + focus_x - self.w / 2 - self.x) * zoom,
        y: (y + focus_y - self.h / 2 - self.y) * zoom,
        w: w ? w * zoom : nil,
        h: h ? h * zoom : nil
      }
    end

    def to_screen(x:, y:, w:, h:)
      {
        x: (focus_x + self.x) / zoom,
        y: (focus_y + self.y) / zoom,
        w: w / zoom,
        h: h / zoom
      }
    end

    def outputs
      game.outputs["camera_#{name}"]
    end

    private

    def perform_render
      # Render scene to camera viewport
      outputs.primitives << {
        x: 0,
        y: 0,
        w: grid.w,
        h: grid.h,
        source_x: (focus_x - (w / 2) / zoom).clamp(0, outputs[:scene].w - w),
        source_y: (focus_y - (h / 2) / zoom).clamp(0, outputs[:scene].h - h),
        source_w: source_w / zoom,
        source_h: source_h / zoom,
        path: :scene
      }

      # Render camera viewport to screen
      game.outputs.primitives << [
        {
          x: x,
          y: y,
          w: w,
          h: h,
          path: "camera_#{name}"
        },
        {
          x: x,
          y: y,
          w: w,
          h: h,
        }.border!
      ]
    end

    def perform_update
      # return if target_x == focus_x && target_y == focus_y && target_zoom == zoom

      # normalized_direction = Geometry.vec2_normalize(x: (target_x - focus_x), y: (target_y - focus_y))

      # puts "normalized_direction: #{normalized_direction}"

      # self.focus_x += normalized_direction.x * speed
      # self.focus_y += normalized_direction.y * speed
    end

    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} name: #{name}, x: #{x}, y: #{y}, w: #{w}, h: #{h}, focus_x: #{focus_x}, focus_y: #{focus_y}, zoom: #{zoom}, speed: #{speed}, zoom_speed: #{zoom_speed}>"
    end
  end
end
