class Hash
  def left
    return self[:left]            if key?(:left)
    return x - anchor_x * w       if key?(:x) && key?(:anchor_x) && key?(:w)
    return x                      if key?(:x) && anchor_x == 0
    return x                      if key?(:x)
  end

  def right
    return self[:right]           if key?(:right)
    return x + (1 - anchor_x) * w if key?(:x) && key?(:anchor_x) && key?(:w)
    return x                      if key?(:x) && anchor_x == 1
    return x + w                  if key?(:x) && key?(:w)
  end

  def bottom
    return self[:bottom]          if key?(:bottom)
    return y - anchor_y * h       if key?(:y) && key?(:anchor_y) && key?(:h)
    return y                      if key?(:y) && anchor_y == 0
    return y                      if key?(:y)
  end

  def top
    return self[:top]             if key?(:top)
    return y + (1 - anchor_y) * h if key?(:y) && key?(:anchor_y) && key?(:h)
    return y                      if key?(:y) && anchor_y == 1
    return y + h                  if key?(:y) && key?(:h)
  end

  def center
    {
      x: left && right  ? (left + right) / 2 : nil,
      y: top  && bottom ? (top + bottom) / 2 : nil
    }
  end

  def deanchor
    {
      **except(:anchor_x, :anchor_y),
      x: x - anchor_x * w,
      y: y - anchor_y * h,
    }
  end
end
