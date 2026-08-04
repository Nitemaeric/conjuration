# AutotileLayer bridges an auto-tiling grid into a chunk-cached TileLayer. The
# grid double implements dragon_autotile's Grid contract (each_dual_cell,
# dual_mask, draw_cell, dirty?, drain_dirty) — the adapter is duck-typed and
# Conjuration carries no dependency on the library itself.

class AutotileGridDouble
  attr_reader :seen_solids

  def initialize(cells)
    @cells = cells      # { [dcol, drow] => mask }
    @dirty = []
    @seen_solids = []
  end

  def each_dual_cell(solid: nil)
    @seen_solids << solid
    @cells.each { |key, mask| yield key[0], key[1], apply(mask, solid) }
  end

  def dual_mask(dcol, drow, solid: nil)
    apply(@cells[[dcol, drow]] || 0, solid)
  end

  def draw_cell(dcol, drow, tileset, solid: nil)
    {
      path: "walls.png", source_x: dual_mask(dcol, drow, solid: solid) * 8, source_y: 0, source_w: 8, source_h: 8,
      x: dcol * 8 - 4, y: drow * 8 - 4, w: 8, h: 8
    }
  end

  def edit(dcol, drow, mask)
    @cells[[dcol, drow]] = mask
    @dirty << [dcol, drow]
    if @feeds
      @feeds.each { |feed| feed.push([dcol, drow]) }
    end
  end

  def dirty?
    !@dirty.empty?
  end

  def drain_dirty
    dirty = @dirty
    @dirty = []
    dirty
  end

  private

  # The double's "predicate" filters by mask parity — enough to prove the
  # layer threads solid: through without modelling terrain values.
  def apply(mask, solid)
    return mask if solid.nil?

    solid.call(mask) ? mask : 0
  end
end

class FeedingGridDouble < AutotileGridDouble
  class Feed
    def initialize; @cells = []; end
    def push(cell); @cells << cell; end
    def dirty?; !@cells.empty?; end

    def drain_dirty
      cells = @cells
      @cells = []
      cells
    end
  end

  def dirty_feed
    feed = Feed.new
    (@feeds ||= []) << feed
    feed
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

def test_autotile_layer_forwards_the_solid_predicate(args, assert)
  grid = AutotileGridDouble.new({ [1, 1] => 15, [2, 1] => 4 })
  odd_only = ->(mask) { mask % 2 == 1 }
  layer = Conjuration::AutotileLayer.new(name: :at_solid, grid: grid, tileset: :unused, solid: odd_only)

  layer.draw(autotile_camera)

  assert.equal!(grid.seen_solids.first, odd_only, "the layer's predicate reaches the grid walk")
  target = $game.outputs["tile_layer_at_solid_0_0"]
  assert.equal!(target.primitives.length, 1, "cells the predicate rejects resolve to mask 0 and are skipped")
end

def test_two_layers_share_one_grid_via_feeds(args, assert)
  grid = FeedingGridDouble.new({ [1, 1] => 15 })
  low = Conjuration::AutotileLayer.new(name: :at_low, grid: grid, tileset: :unused)
  high = Conjuration::AutotileLayer.new(name: :at_high, grid: grid, tileset: :unused)
  low.draw(autotile_camera)
  high.draw(autotile_camera)

  grid.edit(1, 1, 7)
  low.draw(autotile_camera)
  high.draw(autotile_camera)

  low_target = $game.outputs["tile_layer_at_low_0_0"]
  high_target = $game.outputs["tile_layer_at_high_0_0"]
  assert.equal!(low_target.primitives.first[:source_x], 56, "the first layer synced the edit")
  assert.equal!(high_target.primitives.first[:source_x], 56, "the second layer synced the SAME edit from its own feed")
end
