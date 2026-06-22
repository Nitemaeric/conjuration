class ZoomScene < Conjuration::Scene
  TILE_SIZE = 80

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    self.virtual_w = self.virtual_h = 2000

    add_camera(:main, speed: 30, zoom_speed: 0.05)

    state.cells = []

    (virtual_w / TILE_SIZE).to_i.times do |row|
      (virtual_h / TILE_SIZE).to_i.times do |column|
        state.cells << {
          x: column * TILE_SIZE,
          y: row * TILE_SIZE,
          w: TILE_SIZE,
          h: TILE_SIZE,
        }
      end
    end

    cameras[:main].ui.node({ x: 20, y: 20.from_top, anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: 0, y: grid.h / 2, w: 256, h: cameras[:main].h / 2, anchor_y: 0.5, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, align: :stretch, padding: 20, gap: 20) do
      node(h: 50, gap: 5, align: :center) do
        node({ text: "WASD / arrows to pan" })
        node({ text: "Scroll wheel to zoom" })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { camera = scene.cameras[:main]; camera.look_at(zoom: camera.target.zoom + 0.5) }}, justify: :center, align: :center) do
        node({ text: "Zoom In", r: 255, g: 255, b: 255 })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { camera = scene.cameras[:main]; camera.look_at(zoom: camera.target.zoom - 0.5) }}, justify: :center, align: :center) do
        node({ text: "Zoom Out", r: 255, g: 255, b: 255 })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { scene.cameras[:main].look_at(zoom: 1) }}, justify: :center, align: :center) do
        node({ text: "Reset", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: 20.from_right, y: 20, anchor_x: 1, anchor_y: 0 }, justify: :end, align: :end) do
      node({ text: "Zoom" }, id: :zoom_label)
    end
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

  def update
    cameras[:main].ui.find(:zoom_label).object.text = "Zoom: #{cameras[:main].current.zoom.round(2)}"
  end

  def draw_world(camera)
    hover = camera == focused_camera ? camera.to_world(**inputs.mouse.rect) : nil

    state.cells.each do |cell|
      focused = hover&.inside_rect?(cell)

      camera.draw({
        **cell,
        path: :pixel,
        r: 192,
        g: focused ? 0 : 192,
        b: focused ? 0 : 192,
        a: focused ? 255 : 192
      })

      camera.draw({
        **cell,
        primitive_marker: :border,
        r: 255,
        g: 255,
        b: 255,
        a: 192
      })
    end
  end
end
