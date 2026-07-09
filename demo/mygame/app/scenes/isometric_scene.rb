class IsometricScene < Conjuration::Scene
  GRID_COLS = 10
  GRID_ROWS = 10

  KNIGHT_ROW = 5
  MAX_HEIGHT = 2

  # Kenney "Sketch Desert" (CC0) cube art — see sprites/isometric/CREDITS.md.
  # Measured from the PNGs: the top-face diamond footprint, one block level's
  # side-face height, and the top-face centre within the 256x352 canvas. The
  # projection is set to MATCH the art, not the other way round.
  SPRITE_W = 256
  SPRITE_H = 352
  DIAMOND_W = 231
  DIAMOND_H = 122
  STEP_PX = 97
  TOP_FACE_PY = 190
  SCALE = 0.5

  TILE_W = DIAMOND_W * SCALE
  TILE_H = DIAMOND_H * SCALE
  ELEVATION_STEP = STEP_PX * SCALE
  DRAW_W = SPRITE_W * SCALE
  DRAW_H = SPRITE_H * SCALE
  TILE_ANCHOR_X = 0.5
  TILE_ANCHOR_Y = (SPRITE_H - TOP_FACE_PY) / SPRITE_H.to_f

  # FFTA unit convention: feet plant at the top face's NEAR corner — the point
  # shared with the front neighbour's far corner — so a same-elevation neighbour
  # can never rise above the feet line. Anchored at the diamond centre instead,
  # the neighbour's art legitimately covers everything below the centre line
  # (half the diamond + the old 0.15 feet sink ≈ 60% of the sprite: the
  # waist-deep clip). Constant offset, so the walking lerp is untouched.
  KNIGHT_FEET_OFFSET = TILE_H / 2.0
  KNIGHT_H = TILE_H * 1.5
  KNIGHT_W = KNIGHT_H * 48 / 68.0

  DIRT = "sprites/isometric/dirt_center.png".freeze
  GRASS = "sprites/isometric/grass_center.png".freeze

  # Ground props (col, row, sprite, anchor_x, anchor_y) — anchors are each
  # sprite's base centre, so it plants on the tile's top face. Placed off the
  # knight's row so he z-interleaves with them as he walks past.
  PROPS = [
    [8, 4, "sprites/isometric/tree.png".freeze, 0.501, 0.139],
    [2, 6, "sprites/isometric/rocks.png".freeze, 0.458, 0.071]
  ].freeze

  # Hand-authored terrain: a height-2 plateau with a height-1 apron. Row 5 (the
  # knight's path) reads 0 0 0 1 2 2 2 1 0 0 — a ramp up, a plateau, a ramp down.
  HEIGHTMAP = [
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 1, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 1, 2, 2, 2, 1, 0, 0],
    [0, 0, 0, 1, 2, 2, 2, 1, 0, 0],
    [0, 0, 0, 1, 2, 2, 2, 1, 0, 0],
    [0, 0, 0, 1, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  ].freeze

  def setup
    @iso = Conjuration::Projection::Isometric.new(tile_w: TILE_W, tile_h: TILE_H, elevation_step: ELEVATION_STEP)

    build_highlight_texture

    add_camera(:main, speed: 30)
    cameras[:main].ui.group = :hud
    activate_navigation(:hud)

    centre = @iso.to_world(GRID_COLS / 2, GRID_ROWS / 2)
    camera = cameras[:main]
    camera.current.x = camera.target.x = centre[:x]
    camera.current.y = camera.target.y = centre[:y]

    state.knight_col = 0.0
    state.knight_height = 0.0

    build_hud
  end

  def input
    if focused_camera && (!inputs.up_down.zero? || !inputs.left_right.zero?)
      focused_camera.look_at(
        x: focused_camera.current.x + inputs.left_right * 8,
        y: focused_camera.current.y + inputs.up_down * 8
      )
    end
  end

  def update
    phase = (clock * 0.01) % 2.0
    state.knight_col = (phase <= 1.0 ? phase : 2.0 - phase) * (GRID_COLS - 1)

    # Round, not floor: the occupied cell is the one under his feet centre, not
    # the one his sprite's back edge overhangs — flooring buries him a block deep
    # on every ascent.
    target = height_at(state.knight_col.round, KNIGHT_ROW)
    state.knight_height += (target - state.knight_height) * 0.2

    label = cameras[:main].ui.find(:hover_label)
    label.object.text = hovered_label
    label.invalidate!
  end

  def draw_world(camera)
    draw_terrain(camera)
    draw_props(camera)

    if camera == focused_camera
      pick = picked_cell(camera)
      if pick
        c = @iso.to_world(pick[:col], pick[:row], pick[:height])
        camera.draw({
          x: c[:x], y: c[:y], w: TILE_W, h: TILE_H,
          path: :iso_highlight, anchor_x: 0.5, anchor_y: 0.5,
          r: 255, g: 232, b: 120, a: 150
        }, z: pick[:col] + pick[:row])
      end
    end

    draw_knight(camera)
  end

  private

  # Each cell is a stack of cube sprites, one per level 0..height, drawn deferred
  # at z: col + row (height never touches z). Emitting bottom-up means each cube's
  # base covers the top of the one below, so the art's own side faces terrace like
  # FFTA; grass caps the top of a raised cell. The knight is emitted after all of
  # his cell's cubes, so equal-z stable ordering lands him on top of his own tile.
  def draw_terrain(camera)
    GRID_ROWS.times do |row|
      GRID_COLS.times do |col|
        h = HEIGHTMAP[row][col]
        z = col + row

        (0..h).each do |level|
          c = @iso.to_world(col, row, level)
          path = (h > 0 && level == h) ? GRASS : DIRT
          camera.draw({
            x: c[:x], y: c[:y], w: DRAW_W, h: DRAW_H,
            path: path, anchor_x: TILE_ANCHOR_X, anchor_y: TILE_ANCHOR_Y
          }, z: z)
        end
      end
    end
  end

  def draw_props(camera)
    PROPS.each do |(col, row, path, anchor_x, anchor_y)|
      c = @iso.to_world(col, row, height_at(col, row))
      camera.draw({
        x: c[:x], y: c[:y], w: DRAW_W, h: DRAW_H,
        path: path, anchor_x: anchor_x, anchor_y: anchor_y
      }, z: col + row)
    end
  end

  def draw_knight(camera)
    pos = @iso.to_world(state.knight_col, KNIGHT_ROW, state.knight_height)
    camera.draw({
      x: pos[:x], y: pos[:y] - KNIGHT_FEET_OFFSET, w: KNIGHT_W, h: KNIGHT_H,
      path: "sprites/knight.png", anchor_x: 0.5, anchor_y: 0
    }, z: state.knight_col.round + KNIGHT_ROW)
  end

  # Probe from the tallest possible stack down: the first candidate height whose
  # cell actually stands that tall is the top face under the cursor, because a
  # raised tile occludes the lower cells drawn behind it.
  def picked_cell(camera)
    point = camera.to_world(**inputs.mouse.rect)

    h = MAX_HEIGHT
    while h >= 0
      cell = @iso.to_grid(point[:x], point[:y], h)
      if in_bounds?(cell[:col], cell[:row]) && height_at(cell[:col], cell[:row]) == h
        return { col: cell[:col], row: cell[:row], height: h }
      end
      h -= 1
    end
    nil
  end

  def height_at(col, row)
    return 0 unless in_bounds?(col, row)

    HEIGHTMAP[row][col]
  end

  def in_bounds?(col, row)
    col.between?(0, GRID_COLS - 1) && row.between?(0, GRID_ROWS - 1)
  end

  def hovered_label
    return "Tile: -" unless focused_camera

    pick = picked_cell(focused_camera)
    pick ? "Tile: #{pick[:col]}, #{pick[:row]} (h#{pick[:height]})" : "Tile: -"
  end

  # A flat diamond matching the cube's top-face footprint, so the pick highlight
  # hugs the lit top of whatever the cursor is over.
  def build_highlight_texture
    return if @highlight_built

    target = outputs[:iso_highlight]
    target.width = DIAMOND_W
    target.height = DIAMOND_H

    half_h = DIAMOND_H / 2.0
    DIAMOND_H.times do |yy|
      frac = 1.0 - ((yy + 0.5) - half_h).abs / half_h
      half = DIAMOND_W * frac / 2.0
      target.primitives << { x: DIAMOND_W / 2.0 - half, y: yy, w: half * 2, h: 1, path: :pixel, r: 255, g: 255, b: 255 }
    end

    @highlight_built = true
  end

  def build_hud
    camera = cameras[:main]

    camera.ui.node({ x: 20, y: camera.from_top(20), anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) } }, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    camera.ui.node({ x: 0, y: grid.h / 2, w: 256, h: 220, anchor_y: 0.5, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, align: :stretch, padding: 20, gap: 16) do
      node(h: 70, gap: 5, align: :center) do
        node({ text: "Isometric" })
        node({ text: "WASD to pan" })
        node({ text: "Move mouse to pick" })
      end

      node({ h: 30, gap: 5, align: :center }) do
        node({ text: "Tile: -", r: 255, g: 232, b: 120 }, id: :hover_label)
      end
    end
  end
end
