class BasicCameraScene < Conjuration::Scene
  TILE_SIZE = 40

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    self.w = self.h = 2000

    add_camera(:main, x: 0, y: 0)

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
  end

  def input
    if focused_camera
      # if inputs.mouse.click
      #   focused_camera.look_at(inputs.mouse.rect)
      # end

      focused_camera.look_at(x: focused_camera.focus_x + inputs.left_right * 10, y: focused_camera.focus_y + inputs.up_down * 10)
    end
  end

  def render
    outputs.primitives << state.cells.map do |cell|
      focused = focused_camera&.to_world(**inputs.mouse.rect).inside_rect?(cell)

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

    cameras[:main].outputs.primitives << [
      {
        x: 0,
        y: grid.h / 2,
        w: 256,
        h: cameras[:main].h / 2,
        path: "sprites/menu-container-background.png",
        anchor_y: 0.5,
        tile_x: 32,
        tile_w: 480 - 32,
      }
    ]
  end
end
