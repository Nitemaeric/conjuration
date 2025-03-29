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

    @back_button = Conjuration::UI.build({ x: 20, y: 20.from_top, anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end
  end

  def input
    if focused_camera
      focused_camera.look_at(x: focused_camera.focus_x + inputs.left_right * 10, y: focused_camera.focus_y + inputs.up_down * 10)
    end

    focused_button = @back_button.find_interactive_intersect(inputs.mouse)

    if focused_button
      gtk.set_cursor "sprites/hand-point.png", 6, 4

      instance_exec(&focused_button.action) if inputs.mouse.click
    else
      gtk.set_cursor "sprites/cursor-none.png", 9, 4
    end
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
    outputs.primitives << @back_button.primitives

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
