# Integer-vs-float division is a live hazard here (MEMORY: DR's mruby
# `1/2 == 0.5`), so tile sizes with odd halves are used on purpose.

def test_iso_to_world_places_origin_tile_at_the_origin(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  w = iso.to_world(0, 0)
  assert.close!(w[:x], 0, "tile (0,0) centre x")
  assert.close!(w[:y], 0, "tile (0,0) centre y")
end

def test_iso_columns_go_right_and_down_rows_left_and_down(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  col = iso.to_world(1, 0)
  assert.close!(col[:x], 32, "one column shifts +half_w in x")
  assert.close!(col[:y], -16, "one column shifts -half_h in y (toward the viewer)")

  row = iso.to_world(0, 1)
  assert.close!(row[:x], -32, "one row shifts -half_w in x")
  assert.close!(row[:y], -16, "one row shifts -half_h in y")
end

def test_iso_depth_key_increases_toward_the_viewer(args, assert)
  # Guards `z: col + row`: only correct if a higher (col + row) sits lower on
  # screen. Pins the convention so it can't drift out of sync with the maths.
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  near = iso.to_world(3, 3)
  far  = iso.to_world(1, 1)
  assert.true!(near[:y] < far[:y], "greater (col + row) => smaller y => drawn/sorted in front")
end

def test_iso_round_trips_a_spread_of_tiles(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  # Negatives included: floor-based rounding must hold on both sides of zero.
  [[0, 0], [1, 0], [0, 1], [3, 2], [5, 5], [-1, 0], [0, -1], [-3, -4], [7, -2]].each do |(col, row)|
    world = iso.to_world(col, row)
    back = iso.to_grid(world[:x], world[:y])
    assert.equal!([back[:col], back[:row]], [col, row], "tile (#{col},#{row}) centre round-trips")
  end
end

def test_iso_round_trips_with_odd_tile_dimensions(args, assert)
  # Odd width/height give half-extents of x.5 — exactly where integer division
  # would corrupt the maths if a `/ 2` slipped in for a `/ 2.0`.
  iso = Conjuration::Projection::Isometric.new(tile_w: 65, tile_h: 33)

  [[2, 3], [4, 1], [-2, 5]].each do |(col, row)|
    world = iso.to_world(col, row)
    back = iso.to_grid(world[:x], world[:y])
    assert.equal!([back[:col], back[:row]], [col, row], "odd-sized tile (#{col},#{row}) round-trips")
  end
end

def test_iso_picks_interior_points_of_a_tile(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  centre = iso.to_world(2, 1)

  [[3, 0], [-3, 0], [0, 3], [0, -3], [4, 4]].each do |(dx, dy)|
    back = iso.to_grid(centre[:x] + dx, centre[:y] + dy)
    assert.equal!([back[:col], back[:row]], [2, 1], "point offset (#{dx},#{dy}) stays in tile (2,1)")
  end
end

def test_iso_shared_edge_resolves_to_one_owner(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  # The midpoint of (0,0) and (1,0)'s centres lies on their shared edge;
  # round-half-up must resolve it deterministically to the higher neighbour (1,0).
  a = iso.to_world(0, 0)
  b = iso.to_world(1, 0)
  midpoint = iso.to_grid((a[:x] + b[:x]) / 2.0, (a[:y] + b[:y]) / 2.0)
  assert.equal!([midpoint[:col], midpoint[:row]], [1, 0], "the shared edge resolves to a single, deterministic owner")
end

def test_iso_shared_corner_resolves_to_one_owner(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  # Averaging all four tiles' centres lands on their shared corner (a vertex of
  # four diamonds); round-half-up must still resolve it to one owner, (1,1).
  centres = [[0, 0], [1, 0], [0, 1], [1, 1]].map { |(c, r)| iso.to_world(c, r) }
  cx = (centres[0][:x] + centres[1][:x] + centres[2][:x] + centres[3][:x]) / 4.0
  cy = (centres[0][:y] + centres[1][:y] + centres[2][:y] + centres[3][:y]) / 4.0
  pick = iso.to_grid(cx, cy)

  assert.equal!([pick[:col], pick[:row]], [1, 1], "the shared corner resolves to a single owner")
end

def test_topdown_is_the_identity_projection(args, assert)
  td = Conjuration::Projection::TopDown.new(tile_w: 40, tile_h: 40)

  centre = td.to_world(3, 2)
  assert.close!(centre[:x], 3 * 40 + 20, "tile centre x is col*tile_w + half")
  assert.close!(centre[:y], 2 * 40 + 20, "tile centre y is row*tile_h + half")

  assert.equal!(td.to_grid(0, 0).values_at(:col, :row), [0, 0], "origin picks tile (0,0)")
  assert.equal!(td.to_grid(39, 39).values_at(:col, :row), [0, 0], "interior picks its tile")
  assert.equal!(td.to_grid(40, 40).values_at(:col, :row), [1, 1], "the far edge belongs to the next tile")
  assert.equal!(td.to_grid(-1, -1).values_at(:col, :row), [-1, -1], "negative world coords floor correctly")
end

def test_topdown_round_trips(args, assert)
  td = Conjuration::Projection::TopDown.new(tile_w: 40, tile_h: 40)

  [[0, 0], [5, 3], [-2, 4], [-6, -6]].each do |(col, row)|
    world = td.to_world(col, row)
    back = td.to_grid(world[:x], world[:y])
    assert.equal!([back[:col], back[:row]], [col, row], "top-down tile (#{col},#{row}) round-trips")
  end
end

# Pins the premise that an iso tile sprite is an axis-aligned world rect (the
# diamond's bounding box) so it chunks like any other sprite — iso's use of the
# cached TileLayer depends on it.

def test_iso_tile_bounding_box_is_axis_aligned_and_chunks(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  layer = Conjuration::TileLayer.new(name: :iso_chunk, chunk_size: 256)

  half_w = 32
  half_h = 16
  tiles = [[0, 0], [4, 0], [0, 4], [4, 4], [8, 8]]
  tiles.each do |(col, row)|
    c = iso.to_world(col, row)
    layer.add({ x: c[:x] - half_w, y: c[:y] - half_h, w: 64, h: 32, path: :pixel })
  end

  c44 = iso.to_world(4, 4)
  assert.close!(c44[:x], 0, "tile (4,4) centre x")
  assert.close!(c44[:y], -128, "tile (4,4) centre y")

  cam = make_camera(current: { x: 0, y: -128, zoom: 1 })
  layer.draw(cam)

  chunk_sprites = cam.outputs.primitives.select { |p| p[:path].to_s.start_with?("tile_layer_iso_chunk_") }
  assert.true!(chunk_sprites.any?, "iso tiles chunk and emit as ordinary sprites")
  chunk_sprites.each do |sprite|
    assert.true!(!sprite[:w].nil? && !sprite[:h].nil?, "each emitted chunk is an axis-aligned w/h rect")
  end
end
