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

      self.current_at_target_change = current.dup
    end

    def to_world(x:, y:, w: nil, h: nil)
      {
        x: current.x + (x - self.x - self.w / 2) / current.zoom,
        y: current.y + (y - self.y - self.h / 2) / current.zoom,
        w: w ? w / current.zoom : nil,
        h: h ? h / current.zoom : nil
      }
    end

    def to_screen(x:, y:, w: nil, h: nil)
      {
        x: self.x + self.w / 2 + (x - current.x) * current.zoom,
        y: self.y + self.h / 2 + (y - current.y) * current.zoom,
        w: w ? w * current.zoom : nil,
        h: h ? h * current.zoom : nil
      }
    end

    # World-space rectangle this camera currently sees (pan + zoom applied).
    def view_rect
      @view_rect ||= {
        x: current.x - (w / current.zoom) / 2,
        y: current.y - (h / current.zoom) / 2,
        w: w / current.zoom,
        h: h / current.zoom
      }
    end

    # Whether a world-space rect overlaps the current view at all. Hand-rolled
    # AABB test with bracket access: this runs per object per camera per frame,
    # so it avoids method_missing and Geometry-call overhead.
    def visible?(world_rect)
      view = view_rect
      rw = world_rect[:w] || 0
      rh = world_rect[:h] || 0

      world_rect[:x]      < view[:x] + view[:w] &&
        world_rect[:x] + rw > view[:x] &&
        world_rect[:y]      < view[:y] + view[:h] &&
        world_rect[:y] + rh > view[:y]
    end

    # World space -> this camera's viewport-local space, (0, 0)..(w, h). Bracket
    # access keeps this allocation- and method_missing-light on the hot path.
    def to_viewport(world_rect)
      view = view_rect
      zoom = current.zoom

      result = world_rect.dup
      result[:x] = (world_rect[:x] - view[:x]) * zoom
      result[:y] = (world_rect[:y] - view[:y]) * zoom
      result[:w] = world_rect[:w] * zoom if world_rect[:w]
      result[:h] = world_rect[:h] * zoom if world_rect[:h]
      result
    end

    # Cull + transform + emit a world-space primitive into this camera's
    # viewport. A no-op when the rect is outside the view, so a scene can hand
    # every object to every camera and only the visible ones are drawn.
    def draw(world_rect)
      outputs.primitives << to_viewport(world_rect) if visible?(world_rect)
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

      if target.zoom != current.zoom
        zoom_step = target.zoom > current.zoom ? zoom_speed : -zoom_speed

        self.current.zoom += zoom_step.clamp(-(target.zoom - current.zoom).abs, (target.zoom - current.zoom).abs)
      end
    end

    def perform_render
      @view_rect = nil
      # The camera's render target is viewport-sized, never world-sized, so the
      # world can be arbitrarily large without exceeding the GPU texture limit.
      outputs.width, outputs.height = w, h

      # The scene draws its world through us; only on-screen content is emitted.
      scene.draw_world(self)

      # Camera HUD, positioned in viewport-local space.
      outputs.primitives << ui.primitives

      if debug?
        outputs.debug << ui.interactive_nodes.map do |node|
          {
            **node.rect,
            r: 0,
            g: 255,
            b: 0
          }.border!
        end
      end

      # Blit the camera's viewport onto its rect on the screen.
      game.outputs.primitives << {
        x: x,
        y: y,
        w: w,
        h: h,
        path: "camera_#{name}"
      }
    end

    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} name: #{name}, x: #{x}, y: #{y}, w: #{w}, h: #{h}, current-x: #{current&.x}, current-y: #{current&.y}, current-zoom: #{current&.zoom}, speed: #{speed}, zoom_speed: #{zoom_speed}>"
    end

    class FocalPoint < Node
      attr_accessor :x, :y, :zoom, :camera

      def initialize(camera, **attributes)
        super(camera: camera, **attributes)
      end

      # Clamp the focal point so the view stays within the scene's virtual
      # bounds. When the scene is unbounded (virtual_w is nil), pan freely.
      def x=(value)
        bound = camera && camera.scene && camera.scene.virtual_w

        if bound
          half = camera.w / 2 / (zoom || 1)
          @x = half <= bound - half ? value.clamp(half, bound - half) : bound / 2
        else
          @x = value
        end
      end

      def y=(value)
        bound = camera && camera.scene && camera.scene.virtual_h

        if bound
          half = camera.h / 2 / (zoom || 1)
          @y = half <= bound - half ? value.clamp(half, bound - half) : bound / 2
        else
          @y = value
        end
      end

      def zoom=(value)
        @zoom = value.clamp(0.1, 10)
      end
    end
  end
end
