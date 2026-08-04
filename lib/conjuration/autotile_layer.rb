module Conjuration
  # Bridges an auto-tiling grid (dragon_autotile's Grid, or anything with the
  # same contract: each_dual_cell, dual_mask, draw_cell, dirty?, drain_dirty)
  # into a chunk-cached TileLayer.
  #
  #   tiles = DragonAutotile::Tileset.new(path: :walls, tile_size: 8)
  #   @walls = Conjuration::AutotileLayer.new(name: :walls, grid: map, tileset: tiles)
  #
  #   def render
  #     @walls.draw(camera)          # syncs pending edits, then chunk-draws
  #   end
  #
  # Edits go to the grid (`map.set(col, row, :wall)`); on the next draw the
  # dirtied dual cells — exactly four per edited structure cell — are evicted
  # and re-resolved, invalidating only the chunks they touch. The optional
  # block decorates each draw hash (per-region tint, blendmodes):
  #
  #   AutotileLayer.new(name: :walls, grid: map, tileset: tiles) do |draw, dcol, drow|
  #     draw.merge(region_tint(dcol, drow))
  #   end
  #
  # Duck-typed on purpose: Conjuration does not depend on dragon_autotile.
  # Nothing here references its constants, so the framework loads without it
  # and this class works the moment a game vendors it.
  class AutotileLayer
    attr_reader :grid, :tileset, :layer

    # solid: overrides the grid's predicate for this layer — the multi-terrain
    # pattern: several layers over ONE grid of terrain ids, one per terrain in
    # priority order, each with its own predicate (lower terrains count higher
    # ones as solid so their edges tuck beneath). When the grid provides
    # dirty_feed (dragon_autotile >= 0.1 with feeds), each layer takes its own
    # edit stream; the single-consumer drain_dirty remains the fallback, where
    # only one layer per grid can live-sync.
    def initialize(name:, grid:, tileset:, chunk_size: 512, solid: nil, &decorate)
      @grid = grid
      @tileset = tileset
      @solid = solid
      @decorate = decorate
      @feed = grid.respond_to?(:dirty_feed) ? grid.dirty_feed : grid
      @layer = TileLayer.new(name: name, chunk_size: chunk_size)

      @grid.each_dual_cell(solid: @solid) do |dcol, drow, mask|
        add_cell(dcol, drow, mask)
      end
      @feed.drain_dirty
    end

    def sync
      return unless @feed.dirty?

      @feed.drain_dirty.each do |cell|
        dcol = cell[0]
        drow = cell[1]
        rect = @grid.draw_cell(dcol, drow, @tileset, solid: @solid)
        @layer.remove(x: rect[:x], y: rect[:y], w: rect[:w], h: rect[:h])
        add_cell(dcol, drow, @grid.dual_mask(dcol, drow, solid: @solid))
      end
    end

    def draw(camera)
      sync
      @layer.draw(camera)
    end

    private

    def add_cell(dcol, drow, mask)
      return if mask == 0

      draw = @grid.draw_cell(dcol, drow, @tileset, solid: @solid)
      draw = @decorate.call(draw, dcol, drow) || draw if @decorate
      @layer.add(draw)
    end
  end
end
