module Conjuration
  module Projection
    class Isometric
      attr_reader :tile_w, :tile_h

      def initialize(tile_w:, tile_h:)
        @tile_w = tile_w
        @tile_h = tile_h

        # / 2.0 forces float: DR's mruby has 1/2 == 0.5, CRuby has 1/2 == 0.
        @half_w = tile_w / 2.0
        @half_h = tile_h / 2.0
      end

      # y negated so a greater (col + row) sits lower on screen, nearer the viewer.
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

        # (v + 0.5).floor rounds half up and stays defined for negatives, unlike round.
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
