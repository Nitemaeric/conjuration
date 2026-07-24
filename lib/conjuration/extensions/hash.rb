# Extensions to Ruby's Hash for rectangle geometry operations.
#
# These methods compute or retrieve coordinate values for axis-aligned rectangles.
# Used internally by DragonRuby's Geometry for UI navigation and hit testing.
#
# @note Override contract: geometry extensions check for an explicit +:key+
#   in the hash first (e.g., +self[:left]+) and return it before any computed
#   fallback. This is required for DragonRuby's Geometry.rect_navigate, which
#   caches computed centers on intermediate hashes. Failing to return +self[:key]+
#   first breaks DR's navigation APIs.
# @see Hash#left
# @see Hash#right
# @see Hash#top
# @see Hash#bottom
# @see Hash#center
class Hash
  # Look up or compute the left x-coordinate of a rectangle.
  #
  # Returns in priority order:
  # 1. Explicit +:left+ key in the hash
  # 2. Computed from +x+, +anchor_x+, and +w+ (for anchor-based rectangles)
  # 3. +x+ value (treated as the left edge by default)
  #
  # @return [Numeric, nil] left x coordinate, or nil if insufficient data
  # @note Override contract: MUST return +self[:left]+ first if it exists,
  #   or DR's Geometry.rect_navigate breaks when it caches intermediate centers.
  def left
    return self[:left]            if key?(:left)
    return x - anchor_x * w       if key?(:x) && key?(:anchor_x) && key?(:w)
    return x                      if key?(:x) && anchor_x == 0
    return x                      if key?(:x)
  end

  # Look up or compute the right x-coordinate of a rectangle.
  #
  # Returns in priority order:
  # 1. Explicit +:right+ key in the hash
  # 2. Computed from +x+, +anchor_x+, and +w+ (for anchor-based rectangles)
  # 3. +x + w+ (right edge of unanchored rectangle)
  #
  # @return [Numeric, nil] right x coordinate, or nil if insufficient data
  # @note Override contract: MUST return +self[:right]+ first if it exists.
  def right
    return self[:right]           if key?(:right)
    return x + (1 - anchor_x) * w if key?(:x) && key?(:anchor_x) && key?(:w)
    return x                      if key?(:x) && anchor_x == 1
    return x + w                  if key?(:x) && key?(:w)
  end

  # Look up or compute the bottom y-coordinate of a rectangle.
  #
  # Returns in priority order:
  # 1. Explicit +:bottom+ key in the hash
  # 2. Computed from +y+, +anchor_y+, and +h+ (for anchor-based rectangles)
  # 3. +y+ value (treated as the bottom edge by default)
  #
  # @return [Numeric, nil] bottom y coordinate, or nil if insufficient data
  # @note Override contract: MUST return +self[:bottom]+ first if it exists.
  def bottom
    return self[:bottom]          if key?(:bottom)
    return y - anchor_y * h       if key?(:y) && key?(:anchor_y) && key?(:h)
    return y                      if key?(:y) && anchor_y == 0
    return y                      if key?(:y)
  end

  # Look up or compute the top y-coordinate of a rectangle.
  #
  # Returns in priority order:
  # 1. Explicit +:top+ key in the hash
  # 2. Computed from +y+, +anchor_y+, and +h+ (for anchor-based rectangles)
  # 3. +y + h+ (top edge of unanchored rectangle)
  #
  # @return [Numeric, nil] top y coordinate, or nil if insufficient data
  # @note Override contract: MUST return +self[:top]+ first if it exists.
  def top
    return self[:top]             if key?(:top)
    return y + (1 - anchor_y) * h if key?(:y) && key?(:anchor_y) && key?(:h)
    return y                      if key?(:y) && anchor_y == 1
    return y + h                  if key?(:y) && key?(:h)
  end

  # Look up or compute the center point of a rectangle.
  #
  # Returns in priority order:
  # 1. Explicit +:center+ key in the hash (checked first for DR compatibility)
  # 2. Computed center +{x: (left + right) / 2, y: (top + bottom) / 2}+
  #
  # @return [Hash{Symbol => Numeric}, nil] +{x:, y:}+ hash, or nil if insufficient data
  # @note Override contract: MUST return +self[:center]+ first if it exists.
  #   DragonRuby's Geometry.rect_navigate caches computed centers on intermediate
  #   hashes and reads them back as +.center+. Without this check, our override
  #   recomputes from absent x/y/w/h, returns +{x: nil, y: nil}+, and breaks
  #   the navigation comparisons.
  def center
    # Defer to an explicit :center, exactly as left/right/top/bottom defer to
    # their own keys above. DR's Geometry.rect_navigate stashes a computed center
    # on intermediate { item:, center: } hashes and reads it back as `.center`;
    # without this fallback our override recomputes from absent x/y/w/h, returns
    # { x: nil, y: nil }, and the nav comparisons blow up on nil.
    return self[:center] if key?(:center)

    {
      x: left && right  ? (left + right) / 2 : nil,
      y: top  && bottom ? (top + bottom) / 2 : nil
    }
  end

  # Create a copy with anchor values removed and x/y adjusted by the anchored offset.
  #
  # Useful for converting from an anchored coordinate (e.g., +anchor_x: 0.5+)
  # to an unanchored one where x/y represent the top-left corner.
  #
  # @return [Hash] new hash with anchor_x/anchor_y removed and x/y adjusted
  # @example Convert an anchored rect to unanchored
  #   anchored = { x: 100, y: 50, w: 20, h: 20, anchor_x: 0.5, anchor_y: 0.5 }
  #   unanchored = anchored.deanchor  # => { x: 90, y: 40, w: 20, h: 20 }
  def deanchor
    {
      **except(:anchor_x, :anchor_y),
      x: x - anchor_x * w,
      y: y - anchor_y * h,
    }
  end
end
