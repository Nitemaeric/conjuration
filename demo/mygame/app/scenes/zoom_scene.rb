require "app/views/prompt_view.rb"
require "app/views/button_view.rb"

class ZoomScene < Conjuration::Scene
  TILE_SIZE = 40
  WORLD = 16000
  # Rows of the grid baked per load_tick. The whole 400x400 grid (320k tiles) is
  # the same total work as the old synchronous build in setup — spread across
  # frames so a fade transition + progress bar cover the wait instead of a stall.
  ROWS_PER_TICK = 6

  # Bake one grid row into the layer. A class method so a test can build a
  # reference layer synchronously and compare it against the sliced build.
  def self.paint_row(tiles, row, dim, tile_size)
    dim.times do |column|
      cell = { x: column * tile_size, y: row * tile_size, w: tile_size, h: tile_size }
      shade = (row + column) % 2 == 0 ? 192 : 64
      tiles.add({ **cell, path: :pixel, r: shade, g: shade, b: shade, a: 192 })
      tiles.add({ **cell, primitive_marker: :border, r: 255, g: 255, b: 255, a: 192 })
    end
  end

  def setup
    self.virtual_w = self.virtual_h = WORLD

    add_camera(:main, speed: 30, zoom_speed: 0.05)
    # No activate_navigation: the arrows pan the camera; activating would let
    # ensure_focus_in_active_group steal them for the HUD.
    cameras[:main].ui.group = :hud

    @tiles = Conjuration::TileLayer.new(name: :grid, chunk_size: 400)
    @dim = (WORLD / TILE_SIZE).to_i
    @build_row = 0

    camera = cameras[:main]
    camera.ui.view { hud(camera) }
  end

  # Time-slice the map build: a handful of rows per frame, reporting 0..1
  # progress, then :done. Absent this hook a scene is instantly ready, so the
  # protocol is zero-cost for the other demos.
  def load_tick
    return :done if @build_row >= @dim

    target = @build_row + ROWS_PER_TICK
    target = @dim if target > @dim

    while @build_row < target
      self.class.paint_row(@tiles, @build_row, @dim, TILE_SIZE)
      @build_row += 1
    end

    @build_row >= @dim ? :done : @build_row.to_f / @dim
  end

  # A view method: builds nodes inside the framework's render-only loading root
  # (under a transition's hold, or on a bare black screen without one), re-derived
  # each loading frame as progress advances. A labelled progress bar.
  def loading_view(progress)
    bar_w = 480
    bar_x = grid.w / 2 - bar_w / 2
    bar_y = grid.h / 2 - 16

    node({ x: grid.w / 2, y: bar_y + 60, text: "Building world  #{(progress * 100).to_i}%", size_enum: 2, anchor_x: 0.5, anchor_y: 0.5, r: 235, g: 235, b: 240 }, id: :loading_label)
    node({ x: bar_x, y: bar_y, w: bar_w, h: 24, path: :pixel, r: 40, g: 40, b: 48 }, id: :loading_track)
    node({ x: bar_x, y: bar_y, w: bar_w * progress, h: 24, path: :pixel, r: 120, g: 200, b: 130 }, id: :loading_fill)
  end

  def hud(camera)
    node({ x: 20, y: camera.from_top(20), anchor_y: 1 }) do
      ButtonView(id: :back, label: "Back", action: -> { scene.change_scene(to: MenuScene.new(:main)) }, height: 50, shortcut: { keyboard: :escape, controller: :b }, pad: game.ui_pad)
    end

    node({ x: 0, y: grid.h / 2, w: 256, h: camera.h / 2, anchor_y: 0.5, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, id: :panel, align: :stretch, padding: 20, gap: 20) do
      node({ h: 56 }, gap: 6, align: :center) do
        PromptView(id: :pan, action: :pan, label: "pan", pad: game.ui_pad)
        node({ text: "Scroll wheel to zoom" })
      end

      ButtonView(id: :zoom_in, label: "Zoom In", action: -> { camera = scene.cameras[:main]; camera.look_at(zoom: camera.target.zoom + 0.1) }, width: nil, height: 50)

      ButtonView(id: :zoom_out, label: "Zoom Out", action: -> { camera = scene.cameras[:main]; camera.look_at(zoom: camera.target.zoom - 0.1) }, width: nil, height: 50)

      ButtonView(id: :reset_zoom, label: "Reset", action: -> { scene.cameras[:main].look_at(zoom: 1) }, width: nil, height: 50)
    end

    # format, not Float#round(2): the harness's mruby round takes no digits arg.
    node({ x: camera.from_right(20), y: 20, anchor_x: 1, anchor_y: 0, text: "Zoom: #{format('%.2f', camera.current.zoom)}" }, id: :zoom_label)
  end

  def input
    return unless focused_camera

    if !inputs.up_down.zero? || !inputs.left_right.zero?
      focused_camera.look_at(
        x: focused_camera.current.x + inputs.left_right * 10,
        y: focused_camera.current.y + inputs.up_down * 10
      )
    end

    if inputs.mouse.wheel
      focused_camera.look_at(zoom: focused_camera.target.zoom + inputs.mouse.wheel.y * 0.1)
    end
  end

  def draw_world(camera)
    # Static grid: drawn from cached chunk textures, so the whole 2000x2000
    # world stays cheap even fully zoomed out.
    @tiles.draw(camera)

    # Dynamic hover highlight: drawn immediately, on top of the cached tiles.
    return unless camera == focused_camera

    point = camera.to_world(**inputs.mouse.rect)
    column = (point.x / TILE_SIZE).floor
    row = (point.y / TILE_SIZE).floor

    return unless column.between?(0, (virtual_w / TILE_SIZE).to_i - 1)
    return unless row.between?(0, (virtual_h / TILE_SIZE).to_i - 1)

    camera.draw({
      x: column * TILE_SIZE,
      y: row * TILE_SIZE,
      w: TILE_SIZE,
      h: TILE_SIZE,
      path: :pixel,
      r: 255,
      g: 0,
      b: 0,
      a: 128
    })
  end
end
