module Conjuration
  # Coordinate transformation between grid/tile space and world space.
  #
  # Projections define how a grid cell (col, row, height) maps to world
  # coordinates (x, y) for rendering and picking.
  module Projection
    # Isometric projection (dimetric pseudo-3D).
    #
    # Tiles are arranged in a diamond grid; a tile's screen position combines
    # column and row into (col - row) * half_w, -(col + row) * half_h. Height
    # is a separate axis: each level raises the sprite by elevation_step pixels.
    #
    # @example Creating an isometric projection
    #   iso = Projection::Isometric.new(tile_w: 116, tile_h: 61, elevation_step: 50)
    #   world_pos = iso.to_world(5, 3, height: 2)  # {x: 348, y: -427}
    #   grid_pos = iso.to_grid(348, -427, height: 2)  # {col: 5, row: 3}
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

    # Top-down orthographic projection (no depth effect).
    #
    # Tiles are arranged in a rectangular grid; a tile at (col, row) renders at
    # (col * tile_w + half_w, row * tile_h + half_h). The height parameter is
    # accepted for signature uniformity but is a no-op.
    #
    # @example Creating a top-down projection
    #   td = Projection::TopDown.new(tile_w: 32, tile_h: 32)
    #   world_pos = td.to_world(5, 3)  # {x: 176, y: 112}
    #   grid_pos = td.to_grid(176, 112)  # {col: 5, row: 3}
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
