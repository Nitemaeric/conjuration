class Camera < Node
  attr_accessor :scene
  attr_accessor :x, :y, :w, :h
  attr_accessor :focus_x, :focus_y, :zoom
  attr_accessor :target_x, :target_y, :target_zoom
  attr_accessor :speed, :zoom_speed

  delegate :outputs, to: :game

  # camera = Camera.new(outputs[:scene])
  def initialize(scene, x: 0, y: 0, w: $game.grid.w, h: $game.grid.h, zoom: 1, speed: 1_000_000, zoom_speed: 0.1)
    super(scene: scene, x: x, y: y, w: w, h: h, zoom: zoom, speed: speed, zoom_speed: zoom_speed)

    @target_x = @focus_x = x + w / 2
    @target_y = @focus_y = y + h / 2
    @target_zoom = @zoom
  end

  def look_at(object)
    self.target_x = self.focus_x = object.x
    self.target_y = self.focus_y = object.y
  end

  def to_world(x:, y:, w:, h:)
    {
      x: (x - self.x) * zoom,
      y: (y - self.y) * zoom,
      w: w * zoom,
      h: h * zoom
    }
  end

  def to_screen(x:, y:, w:, h:)
    {
      x: (x + self.x) / zoom,
      y: (y + self.y) / zoom,
      w: w / zoom,
      h: h / zoom
    }
  end

  private

  def perform_render
    outputs.primitives << {
      x: x,
      y: y,
      w: w,
      h: h,
      source_x: (focus_x - (w / 2) / zoom).clamp(0, outputs[:scene].w - w),
      source_y: (focus_y - (h / 2) / zoom).clamp(0, outputs[:scene].h - h),
      source_w: w / zoom,
      source_h: h / zoom,
      path: :scene
    }
  end

  def perform_update
    # return if target_x == focus_x && target_y == focus_y && target_zoom == zoom

    # normalized_direction = Geometry.vec2_normalize(x: (target_x - focus_x), y: (target_y - focus_y))

    # puts "normalized_direction: #{normalized_direction}"

    # self.focus_x += normalized_direction.x * speed
    # self.focus_y += normalized_direction.y * speed
  end

  def game
    $game
  end

  def inspect
    "#<#{self.class.name}:0x#{object_id.to_s(16)} x: #{x}, y: #{y}, w: #{w}, h: #{h}, zoom: #{zoom}, speed: #{speed}, zoom_speed: #{zoom_speed}>"
  end
end
