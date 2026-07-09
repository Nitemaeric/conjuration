class MultipleCamerasScene < Conjuration::Scene
  TILE_SIZE = 40

  def setup
    self.virtual_w = self.virtual_h = 2000

    left_camera = add_camera(:left, x: 0, y: 0, w: grid.w / 2)
    # No activate_navigation: the arrows pan the focused camera; activating
    # would let ensure_focus_in_active_group steal them for the HUD.
    left_camera.ui.group = :hud
    add_camera(:left_minimap, x: left_camera.rect.right - 220, y: left_camera.rect.top - 120, w: 200, h: 100)

    right_camera = add_camera(:right, x: grid.w / 2, y: 0, w: grid.w / 2)
    add_camera(:right_minimap, x: grid.w - 220, y: grid.h - 120, w: 200, h: 100)

    @tiles = Conjuration::TileLayer.new(name: :grid, chunk_size: 400)

    (virtual_w / TILE_SIZE).to_i.times do |row|
      (virtual_h / TILE_SIZE).to_i.times do |column|
        cell = { x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE }

        @tiles.add({ **cell, path: :pixel, r: 192, g: 192, b: 192, a: 192 })
        @tiles.add({ **cell, primitive_marker: :border, r: 255, g: 255, b: 255, a: 192 })
      end
    end

    left_camera.ui.node({ x: 20, y: left_camera.from_top(20), anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end
  end

  def input
    if focused_camera && (!inputs.up_down.zero? || !inputs.left_right.zero?)
      focused_camera.look_at(x: focused_camera.current.x + inputs.left_right * 10, y: focused_camera.current.y + inputs.up_down * 10)
    end
  end

  def draw_world(camera)
    # Static grid: cached chunk textures. The minimaps see the whole world, so
    # this is a handful of textured quads per camera instead of ~2500 cells.
    @tiles.draw(camera)

    # Dynamic hover highlight on the focused camera, on top of the cached tiles.
    return unless camera == focused_camera

    point = camera.to_world(**inputs.mouse.rect)
    column = (point.x / TILE_SIZE).floor
    row = (point.y / TILE_SIZE).floor

    return unless column.between?(0, (virtual_w / TILE_SIZE).to_i - 1)
    return unless row.between?(0, (virtual_h / TILE_SIZE).to_i - 1)

    camera.draw({ x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE, path: :pixel, r: 255, g: 0, b: 0, a: 128 })
  end

  def render
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
