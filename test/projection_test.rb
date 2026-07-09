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

# The surface-height lookup a character stands on: round the fractional column
# to the cell under his feet centre, then index [row][col]. Mirrors the demo's
# height lookup — the reference that would have caught the buried-knight bug.
def surface_height(heightmap, col_exact, row)
  return 0 if row < 0 || row >= heightmap.length

  col = col_exact.round
  cells = heightmap[row]
  return 0 if col < 0 || col >= cells.length

  cells[col]
end

def test_iso_surface_height_rounds_to_the_feet_centre_cell(args, assert)
  # Non-square and non-symmetric on purpose: a [row][col] vs [col][row] swap
  # changes the answers, and floor-vs-round at a boundary changes which cell the
  # feet occupy — so both flavours of the bug fail this test.
  heightmap = [
    [0, 1, 2],
    [3, 0, 0]
  ]

  assert.equal!(surface_height(heightmap, 1.0, 0), 1, "cell (1,0) reads its own height")
  assert.equal!(surface_height(heightmap, 2.0, 0), 2, "cell (2,0) reads its own height")
  assert.equal!(surface_height(heightmap, 0.0, 1), 3, "indexed [row][col], not swapped: (col 0,row 1) is 3, not 1")

  # Feet centre past the half-way line belongs to the NEXT cell; floor would
  # report the lower cell and bury the knight a block deep (the regression).
  assert.equal!(surface_height(heightmap, 1.6, 0), 2, "col 1.6 rounds up to cell 2 (feet centre), not floored to 1")
  assert.equal!(surface_height(heightmap, 0.4, 0), 0, "col 0.4 rounds down to cell 0")
end

# Tactics unit rule: feet sit at the top-face CENTRE. A same-height front
# neighbour's top face peaks exactly at the unit's centre line but only at the
# neighbour's own apex (half a tile away in x) — along the shared edge it climbs
# from half a diamond BELOW the feet, so within any unit narrower than the tile
# it stays under the feet line. Corner-anchored feet (the previous convention)
# put the boot pixels ON that edge and same-height neighbours wedged over them.
def test_iso_feet_sit_at_the_top_face_centre_clear_of_neighbours(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32, elevation_step: 24)
  half_w = 32.0
  half_h = 16.0

  [[4, 5, 2], [3, 5, 1], [7, 2, 3]].each do |(col, row, h)|
    ground = iso.to_world(col, row, 0)
    feet   = iso.to_world(col, row, h)

    assert.close!(feet[:y], ground[:y] + h * 24, "feet ride the top face, h*step above the ground plane (h=#{h})")
    assert.close!(feet[:x], ground[:x], "elevation leaves x unchanged (h=#{h})")

    # Front-right neighbour at the SAME height: its top face's upper-left edge
    # runs from the shared corner toward its apex. Sampled at a body half-width
    # (under the full half-tile) it stays strictly below the feet line.
    body_half = half_w * 0.6
    neighbour = iso.to_world(col + 1, row, h)
    edge_y = (neighbour[:y] + half_h) - half_h * (1.0 - body_half / half_w)
    assert.true!(edge_y < feet[:y], "same-height front neighbour's art stays below centre-anchored feet (h=#{h})")

    # One block HIGHER in front: its top face rises above the feet line — the
    # legitimate occlusion (unit hidden behind a taller terrace).
    higher = iso.to_world(col + 1, row, h + 1)
    assert.true!(higher[:y] + half_h > feet[:y], "a higher front neighbour rises above the feet line (h=#{h})")
  end
end

# The demo's walk elevation: the occupied cell's surface, blended toward the
# neighbour only inside a narrow ramp around the cell boundary, exactly halfway
# AT the boundary — where the depth key flips cell. Mirrors walk_height in
# isometric_scene.rb; a lagging eased height here is the mid-stride clip bug.
def walk_height_ref(heightmap, col_exact, row, ramp = 0.15)
  col = col_exact.round
  here = heightmap[row][col]

  frac = col_exact - col
  edge = 0.5 - frac.abs
  return here * 1.0 if edge >= ramp

  neighbour_col = (col + (frac > 0 ? 1 : -1)).clamp(0, heightmap[row].length - 1)
  there = heightmap[row][neighbour_col]
  t = 0.5 + 0.5 * (edge / ramp)
  there + (here - there) * t
end

def test_iso_walk_height_steps_across_the_boundary_not_after_it(args, assert)
  row = [0, 1, 2, 1, 0]
  map = [row]

  assert.close!(walk_height_ref(map, 1.0, 0), 1.0, "cell centre reads its own height")
  assert.close!(walk_height_ref(map, 1.3, 0), 1.0, "outside the ramp the height holds steady")
  assert.close!(walk_height_ref(map, 1.5, 0), 1.5, "at the boundary the height is exactly halfway")
  assert.close!(walk_height_ref(map, 2.5, 0), 1.5, "descending boundary is halfway too")
  assert.close!(walk_height_ref(map, 1.65, 0), 2.0, "the ramp completes just past the boundary")

  before = walk_height_ref(map, 1.49, 0)
  after  = walk_height_ref(map, 1.51, 0)
  assert.true!((after - before).abs < 0.1, "height is continuous through the depth-key flip")
end

def test_iso_walking_knight_sorts_with_his_occupied_cell_at_every_step(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32, elevation_step: 16)
  cam = make_camera(current: { x: 0, y: 0, zoom: 1 })
  heights = [0, 1, 2, 1, 0]
  map = [heights]

  # The full terrace walk, including every mid-transition quarter-step. Mid-
  # stride the knight takes the deeper straddled band (ceil) only once his feet
  # reach that cell's surface; ascending, he stays in the shallower band so the
  # taller entered column occludes him (both cases proven by engine dumps).
  Array.new(17) { |i| i * 0.25 }.each do |col|
    cam.outputs.primitives.clear

    heights.each_with_index do |h, c|
      (0..h).each do |level|
        centre = iso.to_world(c, 0, level)
        cam.draw({ x: centre[:x], y: centre[:y], w: 64, h: 48, path: :"cube_#{c}_#{level}", anchor_x: 0.5, anchor_y: 0.5 }, z: c)
      end
    end

    height = walk_height_ref(map, col, 0)
    band = height >= heights[col.ceil] ? col.ceil : col.floor
    k = iso.to_world(col, 0, height)
    cam.draw({ x: k[:x], y: k[:y], w: 30, h: 42, path: :knight, anchor_x: 0.5, anchor_y: 0 }, z: band)

    cam.send(:flush_ordered_draws)
    order = cam.outputs.primitives.map { |p| p[:path] }
    knight_at = order.index(:knight)
    occupied = band

    heights.each_with_index do |h, c|
      (0..h).each do |level|
        cube_at = order.index(:"cube_#{c}_#{level}")
        next unless cube_at

        if c <= occupied
          assert.true!(cube_at < knight_at, "col #{col}: cube (#{c},#{level}) of straddled band <= #{occupied} draws before the knight")
        else
          assert.true!(cube_at > knight_at, "col #{col}: cube (#{c},#{level}) of nearer cell #{c} draws after the knight")
        end
      end
    end
  end
end

def test_iso_knight_sorts_between_its_cell_and_the_nearer_cell(args, assert)
  iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
  cam = make_camera(current: { x: 0, y: -32, zoom: 1 })
  cam.outputs.primitives.clear

  # A diagonal of raised cells: z = col + row = 0, 2, 4.
  paths = { [0, 0] => :block_far, [1, 1] => :block_mid, [2, 2] => :block_near }
  paths.each do |(col, row), path|
    c = iso.to_world(col, row, 1)
    cam.draw({ x: c[:x], y: c[:y], w: 64, h: 48, path: path, anchor_x: 0.5, anchor_y: 0.5 }, z: col + row)
  end

  # The knight stands on the middle cell (1,1), emitted AFTER its block at the
  # same z: equal-z ties break on emission order.
  k = iso.to_world(1.0, 1, 1)
  cam.draw({ x: k[:x], y: k[:y], w: 30, h: 42, path: :knight, anchor_x: 0.5, anchor_y: 0.2 }, z: 1.0.ceil + 1)

  cam.send(:flush_ordered_draws)
  order = cam.outputs.primitives.map { |p| p[:path] }

  assert.true!(order.index(:block_mid) < order.index(:knight), "knight sorts after his own cell's block (same z, later emission)")
  assert.true!(order.index(:knight) < order.index(:block_near), "knight sorts before the strictly-nearer cell's block")
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
