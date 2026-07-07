class ParallaxScene < Conjuration::Scene
  # Parallax scales both focal axes, but the camera is pinned vertically (a
  # full-height view in a single-screen-tall world), so the y-scaling reads as a
  # *constant* lift, not a scroll — it just seats each layer at its own height on
  # the horizon. The layer positions below are authored with that in mind; the
  # horizontal axis is the one that actually parallaxes as you walk.
  WORLD_W = 6000
  GROUND_H = 120

  SKY    = { parallax: 0.1, z: -400 }.freeze
  HILLS  = { parallax: 0.3, z: -300 }.freeze
  CLOUDS = { parallax: 0.5, z: -200 }.freeze
  TREES  = { parallax: 0.75, z: -100 }.freeze

  def setup
    self.virtual_w = WORLD_W
    self.virtual_h = grid.h

    add_camera(:main, speed: 12)
    cameras[:main].ui.group = :hud
    activate_navigation(:hud)

    @hills  = build_hills
    @clouds = build_clouds
    @trees  = build_trees

    cameras[:main].ui.node({ x: 20, y: cameras[:main].from_top(20), anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: 20, y: 20, anchor_y: 0, w: 220, h: 90, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, align: :center, justify: :center, padding: 16, gap: 6) do
      node({ text: "A / D to walk" })
      node({ text: "layers parallax" }, id: :layer_label)
    end

    state.hero = { x: grid.w / 2, y: GROUND_H, w: 44, h: 72, facing: 1 }
    cameras[:main].follow(state.hero)
  end

  def input
    hero = state.hero
    dx = inputs.left_right * 6
    return if dx.zero?

    hero.x = (hero.x + dx).clamp(hero.w / 2, WORLD_W - hero.w / 2)
    hero.facing = dx.positive? ? 1 : -1
  end

  def update
    cameras[:main].ui.find(:layer_label).object.text = "camera x: #{cameras[:main].current.x.round}"
  end

  def draw_world(camera)
    # Drawn well past the view edges so the vertical lift and any zoom never
    # expose a seam.
    camera.draw({ x: 0, y: -400, w: WORLD_W, h: 1600, path: :pixel, r: 132, g: 196, b: 236 }, **SKY)

    @hills.each  { |hill|  camera.draw(hill,  **HILLS) }
    @clouds.each { |cloud| camera.draw(cloud, **CLOUDS) }
    @trees.each  { |tree|  camera.draw(tree,  **TREES) }

    camera.draw({ x: 0, y: 0, w: WORLD_W, h: GROUND_H, path: :pixel, r: 74, g: 120, b: 84 })

    hero = state.hero
    camera.draw({ **hero.slice(:x, :y, :w, :h), path: :pixel, r: 40, g: 40, b: 56, anchor_x: 0.5 }, z: -hero.y)
  end

  private

  def build_hills
    (0...WORLD_W).step(340).map do |x|
      { x: x, y: 0, w: 460, h: 210 + (x % 3) * 40, path: :pixel, r: 96, g: 150, b: 112, anchor_x: 0.5 }
    end
  end

  def build_clouds
    (0...WORLD_W).step(520).map.with_index do |x, i|
      { x: x + (i % 2) * 160, y: 360 + (i % 3) * 70, w: 240, h: 70, path: :pixel, r: 245, g: 248, b: 252, a: 235 }
    end
  end

  def build_trees
    (0...WORLD_W).step(230).map do |x|
      { x: x, y: -30, w: 50, h: 190 + (x % 2) * 50, path: :pixel, r: 52, g: 84, b: 60, anchor_x: 0.5 }
    end
  end
end
