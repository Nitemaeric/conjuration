# Hash geometry helpers (lib/conjuration/extensions/hash.rb): anchored edges,
# centre, deanchor — and their behaviour on rects with missing or nil parts.

def test_hash_edges_without_anchors_are_finite(args, assert)
  rect = { x: 10, y: 20, w: 100, h: 40 }
  assert.equal!(rect.left, 10, "left is x when unanchored")
  assert.equal!(rect.right, 110, "right is x + w when unanchored")
  assert.equal!(rect.bottom, 20, "bottom is y when unanchored")
  assert.equal!(rect.top, 60, "top is y + h when unanchored")
  assert.equal!(rect.center.x, 60, "centre x")
  assert.equal!(rect.center.y, 40, "centre y")
end

def test_hash_edges_treat_nil_anchors_as_zero(args, assert)
  rect = { x: 10, y: 20, w: 100, h: 40, anchor_x: nil, anchor_y: nil }
  assert.equal!(rect.left, 10, "nil anchor_x behaves as anchor 0")
  assert.equal!(rect.right, 110, "nil anchor_x still spans w")
  assert.equal!(rect.bottom, 20, "nil anchor_y behaves as anchor 0")
  assert.equal!(rect.top, 60, "nil anchor_y still spans h")
  assert.equal!(rect.center.x, 60, "centre survives nil anchors")
end

def test_hash_center_handles_zero_edges(args, assert)
  rect = { x: 0, y: 0, w: 50, h: 50, anchor_x: 0, anchor_y: 0 }
  assert.equal!(rect.center.x, 25, "a zero left edge is a value, not an absence")
  assert.equal!(rect.center.y, 25, "a zero bottom edge is a value, not an absence")
end

def test_hash_edges_degrade_when_the_dimension_is_missing(args, assert)
  nil_w = { x: 10, y: 20, w: nil, h: 40, anchor_x: 0.5, anchor_y: 0.5 }
  assert.equal!(nil_w.left, 10, "nil w falls back to the raw coordinate")
  assert.equal!(nil_w.right, nil, "right needs a width")
  assert.equal!(nil_w.center.x, nil, "centre x is nil without a width")

  no_w = { x: 10, y: 20, h: 40, anchor_x: 0.5, anchor_y: 0.5 }
  assert.equal!(no_w.left, 10, "missing w falls back to the raw coordinate")
  assert.equal!(no_w.center.x, nil, "centre x is nil without a width")
  assert.equal!(no_w.center.y, 20, "the resolved axis still computes")
end

def test_hash_edges_are_nil_without_a_coordinate(args, assert)
  rect = { w: 100, h: 40, anchor_x: 0.5 }
  assert.equal!(rect.left, nil, "no x, no left")
  assert.equal!(rect.top, nil, "no y, no top")
  assert.equal!(rect.center.x, nil, "no x, no centre x")
end

# DR's native Geometry.rect_navigate builds intermediate hashes carrying literal
# :left/:center keys and reads them back through these very methods.
def test_hash_geometry_defers_to_literal_keys(args, assert)
  assert.equal!({ left: 7, x: 100, w: 10 }.left, 7, ":left wins over computed")
  assert.equal!({ right: 7, x: 100, w: 10 }.right, 7, ":right wins over computed")
  assert.equal!({ bottom: 7, y: 100, h: 10 }.bottom, 7, ":bottom wins over computed")
  assert.equal!({ top: 7, y: 100, h: 10 }.top, 7, ":top wins over computed")

  stashed = { item: :node, center: { x: 3, y: 4 } }
  assert.equal!(stashed.center.x, 3, ":center wins over computed")
end

def test_hash_deanchor_tolerates_nil_anchors_and_dimensions(args, assert)
  anchored = { x: 100, y: 100, w: 40, h: 20, anchor_x: 0.5, anchor_y: 1 }.deanchor
  assert.equal!(anchored.x, 80, "deanchored x")
  assert.equal!(anchored.y, 80, "deanchored y")
  assert.equal!(anchored.key?(:anchor_x), false, "anchor keys are dropped")

  loose = { x: 100, y: 100, w: nil, h: 20, anchor_x: nil, anchor_y: 0.5 }.deanchor
  assert.equal!(loose.x, 100, "nil anchor/width leaves x untouched")
  assert.equal!(loose.y, 90, "the resolved axis still deanchors")
end
