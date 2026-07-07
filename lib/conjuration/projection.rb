module Conjuration
  # Both projections anchor on the tile CENTRE, so to_grid is a clean inverse (a
  # centre always picks back to its own tile; a shared corner would be ambiguous)
  # and tile sprites are drawn with anchor_x/anchor_y 0.5 (a TileLayer rect is
  # x - tile_w/2, y - tile_h/2, tile_w, tile_h).
  module Projection
    class Isometric
      attr_reader :tile_w, :tile_h

      def initialize(tile_w:, tile_h:)
        @tile_w = tile_w
        @tile_h = tile_h

        # Forced to float so the math is unaffected by the host's integer-division
        # rule (CRuby's `1/2 == 0`; DR's patched mruby `== 0.5`).
        @half_w = tile_w / 2.0
        @half_h = tile_h / 2.0
      end

      # y is negated so a higher (col + row) sits lower on screen and reads as
      # nearer the viewer — the same ordering that makes `z: col + row` the
      # correct depth key for the camera.
      def to_world(col, row)
        {
          x: (col - row) * @half_w,
          y: -(col + row) * @half_h
        }
      end

      def to_grid(x, y)
        diff = x / @half_w
        sum  = -y / @half_h

        col = (sum + diff) / 2.0
        row = (sum - diff) / 2.0

        # Round to the nearest lattice point via `(v + 0.5).floor` rather than
        # round: it stays well defined for negatives and resolves points on a
        # shared edge/corner to a single deterministic owner (half-values up).
        {
          col: (col + 0.5).floor,
          row: (row + 0.5).floor
        }
      end
    end

    class TopDown
      attr_reader :tile_w, :tile_h

      def initialize(tile_w:, tile_h:)
        @tile_w = tile_w
        @tile_h = tile_h
        @half_w = tile_w / 2.0
        @half_h = tile_h / 2.0
      end

      def to_world(col, row)
        {
          x: col * @tile_w + @half_w,
          y: row * @tile_h + @half_h
        }
      end

      def to_grid(x, y)
        {
          col: (x / @tile_w.to_f).floor,
          row: (y / @tile_h.to_f).floor
        }
      end
    end
  end
end
