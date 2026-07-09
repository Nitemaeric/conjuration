require "app/views/prompt_view.rb"
require "app/views/button_view.rb"

class ZoomScene < Conjuration::Scene
  TILE_SIZE = 40

  def setup
    self.virtual_w = self.virtual_h = 16000

    add_camera(:main, speed: 30, zoom_speed: 0.05)
    cameras[:main].ui.group = :hud # the whole HUD is one navigable pane
    activate_navigation(:hud)

    @tiles = Conjuration::TileLayer.new(name: :grid, chunk_size: 400)

    (virtual_w / TILE_SIZE).to_i.times do |row|
      (virtual_h / TILE_SIZE).to_i.times do |column|
        cell = { x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE }

        @tiles.add({ **cell, path: :pixel, r: (row + column) % 2 == 0 ? 192 : 64, g: (row + column) % 2 == 0 ? 192 : 64, b: (row + column) % 2 == 0 ? 192 : 64, a: 192 })
        @tiles.add({ **cell, primitive_marker: :border, r: 255, g: 255, b: 255, a: 192 })
      end
    end

    camera = cameras[:main]
    camera.ui.view { hud(camera) }
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
