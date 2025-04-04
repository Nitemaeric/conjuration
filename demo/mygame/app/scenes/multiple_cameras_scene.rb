class MultipleCamerasScene < Conjuration::Scene
  TILE_SIZE = 40

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    self.w = self.h = 2000

    left_camera = add_camera(:left, x: 0, y: 0, w: grid.w / 2)
    add_camera(:left_minimap, x: left_camera.rect.right - 220, y: left_camera.rect.top - 120, w: 200, h: 100)

    right_camera = add_camera(:right, x: grid.w / 2, y: 0, w: grid.w / 2)
    add_camera(:right_minimap, x: grid.w - 220, y: grid.h - 120, w: 200, h: 100)

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

    left_camera.ui.node({ x: 20, y: 20.from_top, anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end
  end

  def input
    if focused_camera && (!inputs.up_down.zero? || !inputs.left_right.zero?)
      focused_camera.look_at(x: focused_camera.current.x + inputs.left_right * 10, y: focused_camera.current.y + inputs.up_down * 10)
    end
  end

  def update
    # cameras.each do |name, camera|
    #   if inputs.mouse.inside_rect?(x: camera.x, y: camera.y, w: camera.w, h: camera.h)
    #     state.cells.each do |cell|
    #       if camera.to_world(**inputs.mouse.rect).inside_rect?(cell)
    #         cell[:r] = 255
    #         cell[:g] = 0
    #         cell[:b] = 0
    #       else
    #         cell[:r] = 192
    #         cell[:g] = 192
    #         cell[:b] = 192
    #       end
    #     end
    #   end
    # end
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

    cameras.each do |name, camera|
      game.outputs.primitives << {
        x: camera.x,
        y: camera.y,
        w: camera.w,
        h: camera.h,
        primitive_marker: :border
      }
    end
  end
end
