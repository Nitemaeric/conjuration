class Rect
  attr_accessor :x, :y, :w, :h, :anchor_x, :anchor_y

  def initialize(x:, y:, w:, h:, anchor_x: 0, anchor_y: 0)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.anchor_x = anchor_x
    self.anchor_y = anchor_y
  end

  def left
    x - anchor_x * w
  end

  def right
    x + (1 - anchor_x) * w
  end

  def top
    y + anchor_y * h
  end

  def bottom
    y - (1 - anchor_y) * h
  end

  def center
    {
      x: x + anchor_x * w,
      y: y + anchor_y * h
    }
  end

  def to_h
    {
      x: x,
      y: y,
      w: w,
      h: h,
      anchor_x: anchor_x,
      anchor_y: anchor_y
    }
  end
end
