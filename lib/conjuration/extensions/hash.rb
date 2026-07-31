class Hash
  def left
    return self[:left] if key?(:left)
    return nil if x.nil?

    ax = anchor_x
    return x if ax.nil? || ax == 0 || w.nil?

    x - ax * w
  end

  def right
    return self[:right] if key?(:right)
    return nil if x.nil?

    ax = anchor_x
    return x if ax == 1
    return nil if w.nil?

    x + (1 - (ax || 0)) * w
  end

  def bottom
    return self[:bottom] if key?(:bottom)
    return nil if y.nil?

    ay = anchor_y
    return y if ay.nil? || ay == 0 || h.nil?

    y - ay * h
  end

  def top
    return self[:top] if key?(:top)
    return nil if y.nil?

    ay = anchor_y
    return y if ay == 1
    return nil if h.nil?

    y + (1 - (ay || 0)) * h
  end

  def center
    # Defer to an explicit :center, exactly as left/right/top/bottom defer to
    # their own keys above. DR's Geometry.rect_navigate stashes a computed center
    # on intermediate { item:, center: } hashes and reads it back as `.center`;
    # without this fallback our override recomputes from absent x/y/w/h, returns
    # { x: nil, y: nil }, and the nav comparisons blow up on nil.
    return self[:center] if key?(:center)

    l = left
    r = right
    t = top
    b = bottom

    {
      x: l.nil? || r.nil? ? nil : (l + r) / 2,
      y: t.nil? || b.nil? ? nil : (t + b) / 2
    }
  end

  def deanchor
    ax = anchor_x
    ay = anchor_y

    {
      **except(:anchor_x, :anchor_y),
      x: ax.nil? || x.nil? || w.nil? ? x : x - ax * w,
      y: ay.nil? || y.nil? || h.nil? ? y : y - ay * h,
    }
  end
end
