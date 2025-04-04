class BasicCameraScene < Conjuration::Scene
  TILE_SIZE = 40

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    self.w = self.h = 2000

    add_camera(:main, speed: 30)

    state.cells = []

    (w / TILE_SIZE).to_i.times do |row|
      (h / TILE_SIZE).to_i.times do |column|
        state.cells << {
          x: column * TILE_SIZE,
          y: row * TILE_SIZE,
          w: TILE_SIZE,
          h: TILE_SIZE,
        }
      end
    end

    cameras[:main].ui.node({ x: 20, y: 20.from_top, anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: 0, y: grid.h / 2, w: 256, h: cameras[:main].h / 2, anchor_y: 0.5, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, align: :stretch, padding: 20, gap: 20) do
      node(h: 50, gap: 5, align: :center) do
        node({ text: "Use WASD to move the" })
        node({ text: "camera around" })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { cameras[:main].look_at(x: 1200, y: 1600) }}, justify: :center, align: :center) do
        node({ text: "Point A", r: 255, g: 255, b: 255 })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { cameras[:main].look_at(x: 640, y: 600) }}, justify: :center, align: :center) do
        node({ text: "Point B", r: 255, g: 255, b: 255 })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { cameras[:main].look_at(x: 1200, y: 400) }}, justify: :center, align: :center) do
        node({ text: "Point C", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: 20.from_right, y: 20, anchor_x: 1, anchor_y: 0 }, justify: :end, align: :end) do
      node({ text: "Camera" }, id: :camera_label)
    end
  end

  def input
    if focused_camera && (!inputs.up_down.zero? || !inputs.left_right.zero?)
      focused_camera.look_at(x: focused_camera.current.x + inputs.left_right * 10, y: focused_camera.current.y + inputs.up_down * 10)
    end
  end

  def update
    cameras[:main].ui.find(:camera_label).object.text = "Camera: #{cameras[:main].current.x.round}, #{cameras[:main].current.y.round}"
  end

  def render
    outputs.primitives << state.cells.map do |cell|
      focused = focused_camera&.to_world(**inputs.mouse.rect)&.inside_rect?(cell)

      [
        {
          **cell,
          path: :pixel,
          r: 192,
          g: focused ? 0 : 192,
          b: focused ? 0 : 192,
          a: focused ? 255 : 192
        },
        {
          **cell,
          primitive_marker: :border,
          r: 255,
          g: 255,
          b: 255,
          a: 192
        }
      ]
    end
  end
end
