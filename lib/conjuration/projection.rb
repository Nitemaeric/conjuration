module Conjuration
  module Projection
    class Isometric
      attr_reader :tile_w, :tile_h, :elevation_step

      def initialize(tile_w:, tile_h:, elevation_step: nil)
        @tile_w = tile_w
        @tile_h = tile_h

        # / 2.0 forces float: DR's mruby has 1/2 == 0.5, CRuby has 1/2 == 0.
        @half_w = tile_w / 2.0
        @half_h = tile_h / 2.0
        @elevation_step = elevation_step ? elevation_step * 1.0 : tile_h / 2.0
      end

      # y negated so a greater (col + row) sits lower on screen, nearer the viewer;
      # height raises the tile centre by whole elevation_step blocks (0 == ground).
      # height is positional (not a kwarg) to stay allocation-free on the per-frame
      # draw/pick paths.
      def to_world(col, row, height = 0)
        {
          x: (col - row) * @half_w,
          y: -(col + row) * @half_h + height * @elevation_step
        }
      end

      # Ground-plane pick; pass height to un-offset a point known to sit that many
      # blocks up before the diamond test (the probe technique — see README).
      def to_grid(x, y, height = 0)
        y -= height * @elevation_step

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

      # height is a no-op here: the identity projection has no elevation axis. It
      # keeps the signature uniform across the projection family.
      def to_world(col, row, height = 0)
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
