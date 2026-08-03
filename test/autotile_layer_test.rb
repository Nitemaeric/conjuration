# AutotileLayer bridges an auto-tiling grid into a chunk-cached TileLayer. The
# grid double implements dragon_autotile's Grid contract (each_dual_cell,
# dual_mask, draw_cell, dirty?, drain_dirty) — the adapter is duck-typed and
# Conjuration carries no dependency on the library itself.

class AutotileGridDouble
  attr_reader :removed

  def initialize(cells)
    @cells = cells      # { [dcol, drow] => mask }
    @dirty = []
  end

  def each_dual_cell
    @cells.each { |key, mask| yield key[0], key[1], mask }
  end

  def dual_mask(dcol, drow)
    @cells[[dcol, drow]] || 0
  end

  def draw_cell(dcol, drow, tileset)
    {
      path: "walls.png", source_x: dual_mask(dcol, drow) * 8, source_y: 0, source_w: 8, source_h: 8,
      x: dcol * 8 - 4, y: drow * 8 - 4, w: 8, h: 8
    }
  end

  def edit(dcol, drow, mask)
    @cells[[dcol, drow]] = mask
    @dirty << [dcol, drow]
  end

  def dirty?
    !@dirty.empty?
  end

  def drain_dirty
    dirty = @dirty
    @dirty = []
    dirty
  end
end

def autotile_camera
  make_camera(current: { x: 640, y: 360, zoom: 1 })
end

def test_autotile_layer_builds_from_the_grid(args, assert)
  grid = AutotileGridDouble.new({ [1, 1] => 15, [2, 1] => 3, [3, 1] => 0 })
  layer = Conjuration::AutotileLayer.new(name: :at_build, grid: grid, tileset: :unused_by_double)

  layer.draw(autotile_camera)

  target = $game.outputs["tile_layer_at_build_0_0"]
  assert.equal!(target.primitives.length, 2, "solid dual cells are added, mask 0 skipped")
end

def test_autotile_layer_construction_leaves_nothing_dirty(args, assert)
  grid = AutotileGridDouble.new({ [1, 1] => 15 })
  grid.edit(1, 1, 15)
  Conjuration::AutotileLayer.new(name: :at_clean, grid: grid, tileset: :unused_by_double)

  assert.equal!(grid.dirty?, false, "construction drains any pending dirty cells")
end

def test_autotile_layer_syncs_edits_locally(args, assert)
  grid = AutotileGridDouble.new({ [1, 1] => 15 })
  layer = Conjuration::AutotileLayer.new(name: :at_sync, grid: grid, tileset: :unused_by_double)
  layer.draw(autotile_camera)

  grid.edit(1, 1, 7)
  layer.draw(autotile_camera)

  target = $game.outputs["tile_layer_at_sync_0_0"]
  assert.equal!(target.primitives.length, 1, "the dual cell was evicted and re-added once")
  assert.equal!(target.primitives.first[:source_x], 56, "the re-added cell resolves the new mask")
end

def test_autotile_layer_edit_to_empty_removes(args, assert)
  grid = AutotileGridDouble.new({ [1, 1] => 15 })
  layer = Conjuration::AutotileLayer.new(name: :at_empty, grid: grid, tileset: :unused_by_double)
  layer.draw(autotile_camera)

  grid.edit(1, 1, 0)
  cam = autotile_camera
  layer.draw(cam)

  emitted = cam.outputs.primitives.select { |p| p[:path].to_s.start_with?("tile_layer_at_empty_") }
  assert.equal!(emitted.length, 0, "a cell resolving to mask 0 is evicted; the emptied chunk stops being emitted")
end

def test_autotile_layer_decorates_draws(args, assert)
  grid = AutotileGridDouble.new({ [1, 1] => 15 })
  layer = Conjuration::AutotileLayer.new(name: :at_tint, grid: grid, tileset: :unused_by_double) do |draw, dcol, drow|
    draw.merge(r: 200, g: 100, b: 50, dcol: dcol, drow: drow)
  end

  layer.draw(autotile_camera)

  primitive = $game.outputs["tile_layer_at_tint_0_0"].primitives.first
  assert.equal!(primitive[:r], 200, "the decorate block shapes the stored draw")
  assert.equal!(primitive[:dcol], 1, "the block receives the dual position")
end
