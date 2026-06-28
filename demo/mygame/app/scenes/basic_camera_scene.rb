class BasicCameraScene < Conjuration::Scene
  TILE_SIZE = 40

  def setup
    self.virtual_w = self.virtual_h = 2000

    add_camera(:main, speed: 30)
    cameras[:main].ui.group = :hud # the whole HUD is one navigable pane
    activate_navigation(:hud)

    @tiles = Conjuration::TileLayer.new(name: :grid, chunk_size: 400)

    (virtual_w / TILE_SIZE).to_i.times do |row|
      (virtual_h / TILE_SIZE).to_i.times do |column|
        cell = { x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE }

        @tiles.add({ **cell, path: :pixel, r: 192, g: 192, b: 192, a: 192 })
        @tiles.add({ **cell, primitive_marker: :border, r: 255, g: 255, b: 255, a: 192 })
      end
    end

    # A target that orbits the world for the camera to follow.
    state.target = { x: 1000, y: 1000, w: 80, h: 80 }

    cameras[:main].ui.node({ x: 20, y: cameras[:main].from_top(20), anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: 0, y: grid.h / 2, w: 256, h: 400, anchor_y: 0.5, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, align: :stretch, padding: 20, gap: 20) do
      node(h: 50, gap: 5, align: :center) do
        node({ text: "WASD to pan" })
        node({ text: "SPACE to shake" })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { scene.cameras[:main].look_at(x: 1200, y: 1600) }}, justify: :center, align: :center) do
        node({ text: "Point A", r: 255, g: 255, b: 255 })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { scene.cameras[:main].look_at(x: 640, y: 600) }}, justify: :center, align: :center) do
        node({ text: "Point B", r: 255, g: 255, b: 255 })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { scene.cameras[:main].look_at(x: 1200, y: 400) }}, justify: :center, align: :center) do
        node({ text: "Point C", r: 255, g: 255, b: 255 })
      end

      node({ h: 50, path: "sprites/button.png", action: -> { camera = scene.cameras[:main]; camera.following ? camera.unfollow : camera.follow(scene.state.target) }}, justify: :center, align: :center) do
        node({ text: "Follow", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: cameras[:main].from_right(20), y: 20, anchor_x: 1, anchor_y: 0 }, justify: :end, align: :end) do
      node({ text: "Camera" }, id: :camera_label)
    end
  end

  def input
    if focused_camera && (!inputs.up_down.zero? || !inputs.left_right.zero?)
      focused_camera.look_at(x: focused_camera.current.x + inputs.left_right * 10, y: focused_camera.current.y + inputs.up_down * 10)
    end

    if focused_camera && inputs.keyboard.key_down.space
      # Shake along the target's orbital velocity, for a directional impact.
      angle = Kernel.tick_count * 0.02
      focused_camera.shake(0.8, direction: { x: -Math.sin(angle), y: Math.cos(angle) })
    end
  end

  def update
    angle = Kernel.tick_count * 0.02
    state.target.x = 1000 + Math.cos(angle) * 400
    state.target.y = 1000 + Math.sin(angle) * 400

    camera = cameras[:main]
    label = camera.following ? "Following target" : "Camera: #{camera.current.x.round}, #{camera.current.y.round}"
    camera.ui.find(:camera_label).object.text = label
  end

  def draw_world(camera)
    # Static grid: drawn from cached chunk textures, so the 2000x2000 world stays
    # cheap even fully zoomed out and across multiple cameras.
    @tiles.draw(camera)

    # The follow target (orange square).
    camera.draw({ **state.target, path: :pixel, r: 255, g: 140, b: 0 })

    # Dynamic hover highlight, drawn immediately on top of the cached tiles.
    return unless camera == focused_camera

    point = camera.to_world(**inputs.mouse.rect)
    column = (point.x / TILE_SIZE).floor
    row = (point.y / TILE_SIZE).floor

    return unless column.between?(0, (virtual_w / TILE_SIZE).to_i - 1)
    return unless row.between?(0, (virtual_h / TILE_SIZE).to_i - 1)

    camera.draw({ x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE, path: :pixel, r: 255, g: 0, b: 0, a: 128 })
  end
end
