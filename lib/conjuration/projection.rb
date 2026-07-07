module Conjuration
  # Grid <-> world coordinate mappings, as pure, stateless math.
  #
  # A projection answers two questions and nothing else:
  #
  #   to_world(col, row) # => { x:, y: }   where tile (col, row) sits in world space
  #   to_grid(x, y)      # => { col:, row: } which tile a world point falls in
  #
  # This is deliberately NOT a camera concern. The camera already works in
  # continuous world space (pan, zoom, shake, culling) and is projection-blind;
  # so is TileLayer. What makes a view "isometric" is only (a) this grid->world
  # mapping and (b) draw order — and draw order is already handled by the
  # camera's `z:` buffer. So iso needs no engine changes: place tiles with
  # #to_world, pick with #to_grid (feeding it camera.to_world(mouse)), and depth
  # is the documented convention `camera.draw(tile, z: col + row)`.
  #
  # Both projections return the tile's CENTRE in world space, so:
  #   - #to_grid is a clean inverse: a tile's own centre always picks back to it
  #     (a corner would be shared by adjacent tiles — ambiguous), and
  #   - a tile sprite is drawn anchored at that centre: `anchor_x: 0.5,
  #     anchor_y: 0.5`. For a rect/TileLayer entry, the bounding box is
  #     (x - tile_w/2, y - tile_h/2, tile_w, tile_h).
  module Projection
    # Diamond (2:1-style) isometric mapping. `tile_w`/`tile_h` are the full
    # diamond footprint in world units (e.g. 64x32); the tile is twice as wide as
    # it is tall in the classic iso look, but any ratio works.
    #
    # World axes match the camera's: +y is up. Tiles further from the origin along
    # (col + row) are placed LOWER on screen (smaller y) so they read as nearer the
    # viewer — which is exactly why `z: col + row` is the correct depth key: a
    # higher (col + row) tile is both drawn later (on top) and sits in front.
    class Isometric
      attr_reader :tile_w, :tile_h

      def initialize(tile_w:, tile_h:)
        @tile_w = tile_w
        @tile_h = tile_h

        # Half-extents, forced to float so the math is unaffected by the host's
        # integer-division rule (CRuby's `1/2 == 0`; DR's patched mruby `== 0.5`).
        # These are the per-step deltas: moving one column shifts the tile centre
        # by (+half_w, -half_h) in world space, one row by (-half_w, -half_h).
        @half_w = tile_w / 2.0
        @half_h = tile_h / 2.0
      end

      # Tile (col, row) centre in world space. Draw the tile sprite here with
      # anchor_x: 0.5, anchor_y: 0.5.
      def to_world(col, row)
        {
          x: (col - row) * @half_w,
          y: -(col + row) * @half_h
        }
      end

      # World point -> the tile whose diamond contains it (true diamond
      # hit-testing, not the sprite's bounding box). Feed it a world point from
      # camera.to_world(mouse) to pick under the cursor.
      #
      # The forward map sends tile centres to integer lattice points in a rotated,
      # non-uniformly-scaled frame; inverting recovers continuous (col, row), and
      # a tile owns the unit cell centred on its lattice point. So we round to the
      # nearest lattice point, done as `(v + 0.5).floor` — a floor-based round that
      # stays well defined for negative coordinates (half-values resolve up, giving
      # a deterministic, non-overlapping owner for points on a shared edge/corner).
      def to_grid(x, y)
        # (col - row) and (col + row) recovered from the two world axes.
        diff = x / @half_w        # col - row
        sum  = -y / @half_h       # col + row

        col = (sum + diff) / 2.0
        row = (sum - diff) / 2.0

        {
          col: (col + 0.5).floor,
          row: (row + 0.5).floor
        }
      end
    end

    # Straight top-down (axis-aligned) mapping. The identity of the family: same
    # to_world/to_grid contract, no diamond skew. Included so isometric reads as
    # one option among projections rather than a bespoke special case — swap the
    # projection object and the same tile/pick code drives either view.
    class TopDown
      attr_reader :tile_w, :tile_h

      def initialize(tile_w:, tile_h:)
        @tile_w = tile_w
        @tile_h = tile_h
        @half_w = tile_w / 2.0
        @half_h = tile_h / 2.0
      end

      # Tile centre in world space (anchor_x: 0.5, anchor_y: 0.5), matching the
      # isometric contract so callers can treat the two interchangeably.
      def to_world(col, row)
        {
          x: col * @tile_w + @half_w,
          y: row * @tile_h + @half_h
        }
      end

      # World point -> containing tile. A plain floor of the grid coordinate; the
      # cell [col*tile_w, (col+1)*tile_w) owns its right/top edge's neighbour,
      # matching the usual `(x / tile_w).floor` picking.
      def to_grid(x, y)
        {
          col: (x / @tile_w.to_f).floor,
          row: (y / @tile_h.to_f).floor
        }
      end
    end
  end
end
