# Vector arithmetic. x/y are public attr_accessors, so magnitude must not be
# memoized — the regression below guards against a stale cached value.

def test_magnitude_of_3_4_5_triangle(args, assert)
  assert.equal!(Conjuration::Vector.new(x: 3, y: 4).magnitude, 5, "3-4-5 magnitude")
end

def test_magnitude_tracks_mutated_components(args, assert)
  v = Conjuration::Vector.new(x: 3, y: 4)
  assert.equal!(v.magnitude, 5, "initial magnitude")

  v.x = 6
  v.y = 8
  assert.equal!(v.magnitude, 10, "magnitude follows reassigned x/y (no stale memo)")
end
