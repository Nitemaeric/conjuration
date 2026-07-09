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

  # Tactics-style unit rule: a unit belongs to the one cell under its feet
  # centre, shares that cell's depth band (z = col + row, emitted after the
  # cell's cubes), and its FEET SIT AT THE TOP-FACE CENTRE. At the centre, a
  # same-height front neighbour's top face peaks half a diamond BELOW the feet
  # line, so it can never clip the unit; at the near corner (the previous
  # anchor) those neighbours rise above the feet and wedge over the shins.
  KNIGHT_H = TILE_H * 1.5
  KNIGHT_W = KNIGHT_H * 48 / 68.0

  # Elevation while walking must track the occupied cell, not lag it: the old
  # eased lerp trailed by nearly a whole tile, so right after a terrace-edge z
  # flip the knight was drawn a step too low and the front cell's cubes covered
  # his legs. Instead the height ramps deterministically across a narrow window
  # centred on the cell boundary (an FFTA stair-step), reaching the new surface
  # while the sprite is still between columns where no neighbour art can reach.
  STEP_RAMP = 0.15

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
    # Draw-order forensics: K freezes the walk so a clipping pose can be held,
    # P dumps that frame's entire deferred draw buffer to iso_draw_dump.txt
    # (analyse with demo/tools/analyze_iso_dump.rb).
    state.walk_paused = !state.walk_paused if inputs.keyboard.key_down.k
    @dump_requested = true if inputs.keyboard.key_down.p

    unless state.walk_paused
      phase = (clock * 0.01) % 2.0
      state.knight_col = (phase <= 1.0 ? phase : 2.0 - phase) * (GRID_COLS - 1)
    end

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
        prim = {
          x: c[:x], y: c[:y], w: TILE_W, h: TILE_H,
          path: :iso_highlight, anchor_x: 0.5, anchor_y: 0.5,
          r: 255, g: 232, b: 120, a: 150
        }
        prim[:dbg] = "highlight_#{pick[:col]}_#{pick[:row]}" if @dump_requested
        camera.draw(prim, z: pick[:col] + pick[:row])
      end
    end

    draw_knight(camera)

    if @dump_requested && camera == cameras[:main]
      dump_draw_buffer(camera)
      @dump_requested = false
    end
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
          prim = {
            x: c[:x], y: c[:y], w: DRAW_W, h: DRAW_H,
            path: path, anchor_x: TILE_ANCHOR_X, anchor_y: TILE_ANCHOR_Y
          }
          prim[:dbg] = "cube_#{col}_#{row}_L#{level}" if @dump_requested
          camera.draw(prim, z: z)
        end
      end
    end
  end

  def draw_props(camera)
    PROPS.each do |(col, row, path, anchor_x, anchor_y)|
      c = @iso.to_world(col, row, height_at(col, row))
      prim = {
        x: c[:x], y: c[:y], w: DRAW_W, h: DRAW_H,
        path: path, anchor_x: anchor_x, anchor_y: anchor_y
      }
      prim[:dbg] = "prop_#{col}_#{row}" if @dump_requested
      camera.draw(prim, z: col + row)
    end
  end

  def draw_knight(camera)
    pos = @iso.to_world(state.knight_col, KNIGHT_ROW, walk_height(state.knight_col, KNIGHT_ROW))
    prim = {
      x: pos[:x], y: pos[:y], w: KNIGHT_W, h: KNIGHT_H,
      path: "sprites/knight.png", anchor_x: 0.5, anchor_y: 0
    }
    prim[:dbg] = "knight" if @dump_requested
    # ceil, not round: mid-stride the sprite straddles two columns, and the
    # deeper one (z+1) would otherwise flush after him and paint over his
    # leading half — engine dump at col 5.49 showed cube (6,5) 15px over his feet.
    camera.draw(prim, z: state.knight_col.ceil + KNIGHT_ROW)
  end

  # Ground truth for the clip investigation: the camera's deferred buffer, in
  # post-sort flush order, exactly as DR will composite it — plus every runtime
  # constant the offline model needs. Taps @draw_buffer before the camera's own
  # flush so the lib stays untouched; the sort here mirrors flush_ordered_draws.
  def dump_draw_buffer(camera)
    buffer = camera.instance_variable_get(:@draw_buffer)
    flushed = buffer.sort { |a, b| a[0] == b[0] ? a[1] <=> b[1] : a[0] <=> b[0] }
    view = camera.view_rect

    lines = []
    lines << "# iso draw dump v1 (viewport space, y-up; rect = [x - ax*w, y - ay*h, w, h])"
    lines << "const TILE_W=#{TILE_W} TILE_H=#{TILE_H} ELEVATION_STEP=#{ELEVATION_STEP} DRAW_W=#{DRAW_W} DRAW_H=#{DRAW_H} TILE_ANCHOR_X=#{TILE_ANCHOR_X} TILE_ANCHOR_Y=#{TILE_ANCHOR_Y} KNIGHT_W=#{KNIGHT_W} KNIGHT_H=#{KNIGHT_H} STEP_RAMP=#{STEP_RAMP}"
    lines << "camera x=#{camera.current.x} y=#{camera.current.y} zoom=#{camera.current.zoom} w=#{camera.w} h=#{camera.h}"
    lines << "view x=#{view[:x]} y=#{view[:y]} w=#{view[:w]} h=#{view[:h]}"
    lines << "knight col=#{state.knight_col} row=#{KNIGHT_ROW} z=#{state.knight_col.ceil + KNIGHT_ROW} walk_height=#{walk_height(state.knight_col, KNIGHT_ROW)}"

    flushed.each_with_index do |(z, em, prim), idx|
      lines << "prim idx=#{idx} z=#{z} em=#{em} x=#{prim[:x]} y=#{prim[:y]} w=#{prim[:w]} h=#{prim[:h]} ax=#{prim[:anchor_x]} ay=#{prim[:anchor_y]} path=#{prim[:path]} dbg=#{prim[:dbg]}"
    end

    gtk.write_file("iso_draw_dump.txt", lines.join("\n") + "\n")
    gtk.notify!("wrote iso_draw_dump.txt (#{flushed.length} prims)")
  end

  # Surface height under a fractional column: the occupied cell's height, except
  # within STEP_RAMP of a cell boundary, where it blends linearly toward the
  # neighbour so the crossing reads as a stair step. Halfway at the boundary
  # itself — continuous from both sides, exactly when the depth key flips.
  def walk_height(col_exact, row)
    col = col_exact.round
    here = height_at(col, row)

    frac = col_exact - col
    edge = 0.5 - frac.abs
    return here * 1.0 if edge >= STEP_RAMP

    there = height_at(col + (frac > 0 ? 1 : -1), row)
    t = 0.5 + 0.5 * (edge / STEP_RAMP)
    there + (here - there) * t
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
