class IsometricScene < Conjuration::Scene
  TILE_W = 64
  TILE_H = 32

  GRID_COLS = 10
  GRID_ROWS = 10

  KNIGHT_ROW = 5
  MAX_HEIGHT = 2

  # Chunky, clearly-stepped columns (the lib default of tile_h/2 reads thin here).
  ELEVATION_STEP = 24

  # One hue; the baked block textures carry three grey shades that this tint
  # multiplies into three shades of the same colour (lit top, mid + dark faces).
  BLOCK_TINT = [120, 165, 120].freeze

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

    build_tile_texture
    build_block_textures

    add_camera(:main, speed: 30)
    cameras[:main].ui.group = :hud
    activate_navigation(:hud)

    centre = @iso.to_world(GRID_COLS / 2, GRID_ROWS / 2)
    camera = cameras[:main]
    camera.current.x = camera.target.x = centre[:x]
    camera.current.y = camera.target.y = centre[:y]

    @tiles = Conjuration::TileLayer.new(name: :iso_floor, chunk_size: 512)
    GRID_ROWS.times do |row|
      GRID_COLS.times do |col|
        c = @iso.to_world(col, row)
        tint = (col + row).even? ? [70, 120, 90] : [92, 150, 112]
        @tiles.add({
          x: c[:x] - TILE_W / 2, y: c[:y] - TILE_H / 2, w: TILE_W, h: TILE_H,
          path: :iso_tile, r: tint[0], g: tint[1], b: tint[2]
        })
      end
    end

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
    @tiles.draw(camera)

    draw_terrain(camera)

    if camera == focused_camera
      pick = picked_cell(camera)
      if pick
        c = @iso.to_world(pick[:col], pick[:row], pick[:height])
        camera.draw({
          x: c[:x], y: c[:y], w: TILE_W, h: TILE_H,
          path: :iso_tile, anchor_x: 0.5, anchor_y: 0.5,
          r: 255, g: 232, b: 120, a: 200
        }, z: pick[:col] + pick[:row])
      end
    end

    draw_knight(camera)
  end

  private

  # One baked block-column sprite per raised cell: lit top diamond + two side
  # faces. Deferred (z: col + row, height never touches z), not baked into the
  # static floor TileLayer, so the moving knight z-interleaves with the terrain.
  def draw_terrain(camera)
    half_h = TILE_H / 2.0

    GRID_ROWS.times do |row|
      GRID_COLS.times do |col|
        h = HEIGHTMAP[row][col]
        next if h.zero?

        top = @iso.to_world(col, row, h)
        depth = h * @iso.elevation_step
        tex_h = TILE_H + depth

        camera.draw({
          x: top[:x], y: top[:y], w: TILE_W, h: tex_h,
          path: :"iso_block_#{h}", anchor_x: 0.5, anchor_y: (depth + half_h) / tex_h,
          r: BLOCK_TINT[0], g: BLOCK_TINT[1], b: BLOCK_TINT[2]
        }, z: col + row)
      end
    end
  end

  def draw_knight(camera)
    pos = @iso.to_world(state.knight_col, KNIGHT_ROW, state.knight_height)
    camera.draw({
      x: pos[:x], y: pos[:y], w: 30, h: 42,
      path: "sprites/knight.png", anchor_x: 0.5, anchor_y: 0.2
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

  def build_tile_texture
    return if @tile_texture_built

    target = outputs[:iso_tile]
    target.width = TILE_W
    target.height = TILE_H

    half_h = TILE_H / 2.0
    TILE_H.times do |yy|
      frac = 1.0 - ((yy + 0.5) - half_h).abs / half_h
      half = TILE_W * frac / 2.0
      target.primitives << { x: TILE_W / 2.0 - half, y: yy, w: half * 2, h: 1, path: :pixel, r: 255, g: 255, b: 255 }
    end

    @tile_texture_built = true
  end

  # Rasterise one block-column texture per distinct height, column by column: a
  # lit top diamond over two side faces (SW dark, SE mid). Baked in greyscale so
  # the per-cell BLOCK_TINT multiplies into three shades of a single colour.
  def build_block_textures
    return if @block_textures_built

    half_w = TILE_W / 2.0
    half_h = TILE_H / 2.0

    (1..MAX_HEIGHT).each do |h|
      depth = h * @iso.elevation_step
      tex_h = TILE_H + depth

      target = outputs[:"iso_block_#{h}"]
      target.width = TILE_W
      target.height = tex_h

      TILE_W.times do |xx|
        col_frac = 1.0 - ((xx + 0.5) - half_w).abs / half_w
        dh = half_h * col_frac
        y_centre = depth + half_h
        shade = xx < half_w ? 105 : 175

        target.primitives << { x: xx, y: y_centre - dh, w: 1, h: dh * 2, path: :pixel, r: 255, g: 255, b: 255 }
        target.primitives << { x: xx, y: y_centre - dh - depth, w: 1, h: depth, path: :pixel, r: shade, g: shade, b: shade }
      end
    end

    @block_textures_built = true
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
