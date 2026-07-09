class IsometricScene < Conjuration::Scene
  TILE_W = 64
  TILE_H = 32

  GRID_COLS = 10
  GRID_ROWS = 10

  RAISE_COL = 5
  RAISE_ROW = 5

  def setup
    @iso = Conjuration::Projection::Isometric.new(tile_w: TILE_W, tile_h: TILE_H)

    build_tile_texture

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

    label = cameras[:main].ui.find(:hover_label)
    label.object.text = hovered_label
    label.invalidate!
  end

  def draw_world(camera)
    @tiles.draw(camera)

    if camera == focused_camera
      point = camera.to_world(**inputs.mouse.rect)
      cell = @iso.to_grid(point[:x], point[:y])

      if in_bounds?(cell[:col], cell[:row])
        c = @iso.to_world(cell[:col], cell[:row])
        camera.draw({
          x: c[:x], y: c[:y], w: TILE_W, h: TILE_H,
          path: :iso_tile, anchor_x: 0.5, anchor_y: 0.5,
          r: 255, g: 232, b: 120, a: 200
        })
      end
    end

    draw_raised_block(camera)
    draw_knight(camera)
  end

  private

  def draw_raised_block(camera)
    base = @iso.to_world(RAISE_COL, RAISE_ROW)
    z = RAISE_COL + RAISE_ROW

    camera.draw({
      x: base[:x], y: base[:y], w: TILE_W, h: TILE_H,
      path: :iso_tile, anchor_x: 0.5, anchor_y: 0.5, r: 96, g: 78, b: 150
    }, z: z)

    3.times do |i|
      camera.draw({
        x: base[:x], y: base[:y] + 6 + i * 26, w: 44, h: 44,
        path: "sprites/crate.png", anchor_x: 0.5, anchor_y: 0.3
      }, z: z)
    end
  end

  def draw_knight(camera)
    pos = @iso.to_world(state.knight_col, RAISE_ROW)
    camera.draw({
      x: pos[:x], y: pos[:y], w: 30, h: 42,
      path: "sprites/knight.png", anchor_x: 0.5, anchor_y: 0.2
    }, z: state.knight_col + RAISE_ROW)
  end

  def in_bounds?(col, row)
    col.between?(0, GRID_COLS - 1) && row.between?(0, GRID_ROWS - 1)
  end

  def hovered_label
    return "Hover: -" unless focused_camera

    point = focused_camera.to_world(**inputs.mouse.rect)
    cell = @iso.to_grid(point[:x], point[:y])
    in_bounds?(cell[:col], cell[:row]) ? "Tile: #{cell[:col]}, #{cell[:row]}" : "Tile: -"
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
