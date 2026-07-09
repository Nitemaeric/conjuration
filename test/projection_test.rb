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
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  near = iso.to_world(3, 3)
  far  = iso.to_world(1, 1)
  assert.true!(near[:y] < far[:y], "greater (col + row) => smaller y => drawn/sorted in front")
end

def test_iso_round_trips_a_spread_of_tiles(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  [[0, 0], [1, 0], [0, 1], [3, 2], [5, 5], [-1, 0], [0, -1], [-3, -4], [7, -2]].each do |(col, row)|
    world = iso.to_world(col, row)
    back = iso.to_grid(world[:x], world[:y])
    assert.equal!([back[:col], back[:row]], [col, row], "tile (#{col},#{row}) centre round-trips")
  end
end

def test_iso_round_trips_with_odd_tile_dimensions(args, assert)
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

  a = iso.to_world(0, 0)
  b = iso.to_world(1, 0)
  midpoint = iso.to_grid((a[:x] + b[:x]) / 2.0, (a[:y] + b[:y]) / 2.0)
  assert.equal!([midpoint[:col], midpoint[:row]], [1, 0], "the shared edge resolves to a single, deterministic owner")
end

def test_iso_shared_corner_resolves_to_one_owner(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  centres = [[0, 0], [1, 0], [0, 1], [1, 1]].map { |(c, r)| iso.to_world(c, r) }
  cx = (centres[0][:x] + centres[1][:x] + centres[2][:x] + centres[3][:x]) / 4.0
  cy = (centres[0][:y] + centres[1][:y] + centres[2][:y] + centres[3][:y]) / 4.0
  pick = iso.to_grid(cx, cy)

  assert.equal!([pick[:col], pick[:row]], [1, 1], "the shared corner resolves to a single owner")
end

def test_iso_height_zero_is_identical_to_the_no_height_projection(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  [[0, 0], [3, 2], [-1, 4]].each do |(col, row)|
    flat = iso.to_world(col, row)
    zero = iso.to_world(col, row, 0)
    assert.equal!([zero[:x], zero[:y]], [flat[:x], flat[:y]], "height 0 returns exactly the ground projection for (#{col},#{row})")
  end
end

def test_iso_elevation_step_defaults_to_half_tile_h_as_a_float(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  assert.equal!(iso.elevation_step, 16.0, "elevation_step defaults to tile_h / 2.0")
  assert.true!(iso.elevation_step.is_a?(Float), "elevation_step is a float")

  custom = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32, elevation_step: 24)
  assert.equal!(custom.elevation_step, 24.0, "elevation_step honours the constructor override as a float")
end

def test_iso_height_offsets_y_upward_by_height_times_elevation_step(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32, elevation_step: 20)

  ground = iso.to_world(2, 3)
  [1, 2, 5].each do |h|
    raised = iso.to_world(2, 3, h)
    assert.close!(raised[:x], ground[:x], "height leaves x unchanged (h=#{h})")
    assert.close!(raised[:y], ground[:y] + h * 20, "height raises y by height * elevation_step (h=#{h})")
  end
end

def test_iso_round_trips_a_raised_tile_at_its_own_height(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

  [[0, 0, 1], [3, 2, 2], [5, 5, 3], [-2, 4, 1]].each do |(col, row, h)|
    world = iso.to_world(col, row, h)
    back = iso.to_grid(world[:x], world[:y], h)
    assert.equal!([back[:col], back[:row]], [col, row], "raised tile (#{col},#{row}) at height #{h} round-trips")
  end
end

def probe_height(iso, heightmap, x, y, max_height)
  # Highest-first: a tall tile's top face occludes the lower cells drawn behind
  # it, so the first candidate height whose cell actually stands that tall is the
  # one under the cursor.
  h = max_height
  while h >= 0
    cell = iso.to_grid(x, y, h)
    stack = heightmap[[cell[:col], cell[:row]]]
    return cell if stack && stack == h
    h -= 1
  end
  nil
end

def test_iso_probe_finds_the_top_of_a_stack(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  heightmap = {
    [0, 0] => 0,
    [1, 0] => 2,
    [0, 1] => 0,
    [1, 1] => 1
  }

  top = iso.to_world(1, 0, 2)
  pick = probe_height(iso, heightmap, top[:x], top[:y], 2)
  assert.equal!([pick[:col], pick[:row]], [1, 0], "probe picks the raised tile at its elevated top face")

  ground = iso.to_world(0, 1, 0)
  flat = probe_height(iso, heightmap, ground[:x], ground[:y], 2)
  assert.equal!([flat[:col], flat[:row]], [0, 1], "probe falls through to a ground tile when nothing taller occludes it")
end

def test_topdown_to_world_ignores_height(args, assert)
  td = Conjuration::Projection::TopDown.new(tile_w: 40, tile_h: 40)
  flat = td.to_world(2, 3)
  raised = td.to_world(2, 3, 5)
  assert.equal!([raised[:x], raised[:y]], [flat[:x], flat[:y]], "TopDown height is a no-op")
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
