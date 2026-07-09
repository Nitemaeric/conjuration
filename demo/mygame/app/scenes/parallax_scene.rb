require "app/views/prompt_view.rb"

class ParallaxScene < Conjuration::Scene
  WORLD_W = 6000
  GROUND_H = 120

  # A factor-f layer's derived view sweeps f * camera.x +- half a screen, which
  # goes negative near the world's left edge — layers must extend past x: 0.
  LAYER_MARGIN = 1280

  SKY    = { parallax: 0.1, z: -400 }.freeze
  HILLS  = { parallax: 0.3, z: -300 }.freeze
  CLOUDS = { parallax: 0.5, z: -200 }.freeze
  TREES  = { parallax: 0.75, z: -100 }.freeze

  SKY_COLOR    = { r: 207, g: 239, b: 252 }.freeze
  GROUND_COLOR = { r: 35, g: 191, b: 118 }.freeze

  HILL_W = 1024
  HILL_H = 400
  HILL_SPRITES = [
    "sprites/parallax/hills.png",
    "sprites/parallax/hillsLarge.png",
    "sprites/parallax/mountains.png"
  ].freeze

  CLOUD_SPRITES = [
    { path: "sprites/parallax/cloud1.png", w: 203, h: 121 },
    { path: "sprites/parallax/cloud2.png", w: 196, h: 156 },
    { path: "sprites/parallax/cloud3.png", w: 216, h: 139 },
    { path: "sprites/parallax/cloud4.png", w: 250, h: 146 }
  ].freeze

  TREE_SPRITES = [
    { path: "sprites/parallax/tree.png",     w: 94,  h: 204 },
    { path: "sprites/parallax/treePine.png", w: 106, h: 254 },
    { path: "sprites/parallax/treeLong.png", w: 82,  h: 249 }
  ].freeze

  GROUND_TILE_W = 600

  # Kenney Toon Characters frames are 96x128; feet sit flush on the frame's
  # bottom edge, so the default bottom anchor puts them on the ground line.
  HERO_W = 90
  HERO_H = 120
  WALK_SPEED = 5
  WALK_FRAMES = 8
  WALK_FRAME_DIV = 5
  HERO_IDLE = "sprites/parallax/hero/idle.png"

  def setup
    self.virtual_w = WORLD_W
    self.virtual_h = grid.h

    add_camera(:main, speed: 12)
    # No activate_navigation: A/D and the arrows belong to walking; activating
    # would let ensure_focus_in_active_group steal them for the HUD.
    cameras[:main].ui.group = :hud

    @hills  = build_hills
    @clouds = build_clouds
    @trees  = build_trees
    @ground = build_ground
    @hero_walk = Array.new(WALK_FRAMES) { |i| "sprites/parallax/hero/walk#{i}.png" }

    cameras[:main].ui.view do
      node({ x: 20, y: cameras[:main].from_top(20), anchor_y: 1 }) do
        node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
          node({ text: "Back", r: 255, g: 255, b: 255 })
        end
      end

      node({ x: 20, y: 20, anchor_y: 0, w: 220, h: 90, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, align: :center, justify: :center, padding: 16, gap: 6) do
        PromptView(id: :walk, keys: [:a, :d], controller: :left_analog, label: "walk", pad: game.ui_pad)
        node({ text: "camera x: #{cameras[:main].current.x.round}" }, id: :layer_label)
      end
    end

    state.hero = { x: grid.w / 2, y: GROUND_H, w: HERO_W, h: HERO_H, facing: 1, moving: false }
    cameras[:main].follow(state.hero)
  end

  def input
    hero = state.hero
    dx = inputs.left_right * WALK_SPEED
    hero.moving = !dx.zero?
    return if dx.zero?

    hero.x = (hero.x + dx).clamp(hero.w / 2, WORLD_W - hero.w / 2)
    hero.facing = dx.positive? ? 1 : -1
  end

  def draw_world(camera)
    camera.draw({ x: -LAYER_MARGIN, y: -400, w: WORLD_W + LAYER_MARGIN * 2, h: 1600, path: :pixel, **SKY_COLOR }, **SKY)

    @hills.each  { |hill|  camera.draw(hill,  **HILLS) }
    @clouds.each { |cloud| camera.draw(cloud, **CLOUDS) }
    @trees.each  { |tree|  camera.draw(tree,  **TREES) }

    @ground.each { |tile| camera.draw(tile, z: 0) }

    hero = state.hero
    path = hero.moving ? @hero_walk[clock.idiv(WALK_FRAME_DIV) % WALK_FRAMES] : HERO_IDLE
    camera.draw({ x: hero.x, y: hero.y, w: hero.w, h: hero.h, path: path, anchor_x: 0.5, flip_horizontally: hero.facing.negative? }, z: 0)
  end

  private

  # DR's mruby has no Range#step; index-based construction instead. i % n picks a
  # sprite variant so silhouettes vary deterministically across hotloads.
  def build_hills
    Array.new(((WORLD_W + LAYER_MARGIN) / HILL_W.to_f).ceil) do |i|
      { x: i * HILL_W - LAYER_MARGIN, y: 0, w: HILL_W, h: HILL_H, path: HILL_SPRITES[i % HILL_SPRITES.length] }
    end
  end

  def build_clouds
    spacing = 520
    Array.new(((WORLD_W + LAYER_MARGIN) / spacing.to_f).ceil) do |i|
      sprite = CLOUD_SPRITES[i % CLOUD_SPRITES.length]
      { x: i * spacing - LAYER_MARGIN + (i % 2) * 170, y: 380 + (i % 3) * 90, w: sprite[:w], h: sprite[:h], path: sprite[:path], anchor_x: 0.5 }
    end
  end

  def build_trees
    spacing = 230
    Array.new(((WORLD_W + LAYER_MARGIN) / spacing.to_f).ceil) do |i|
      sprite = TREE_SPRITES[i % TREE_SPRITES.length]
      scale = 1.0 + (i % 4) * 0.12
      { x: i * spacing - LAYER_MARGIN, y: -18, w: sprite[:w] * scale, h: sprite[:h] * scale, path: sprite[:path], anchor_x: 0.5 }
    end
  end

  def build_ground
    Array.new((WORLD_W / GROUND_TILE_W.to_f).ceil) do |i|
      { x: i * GROUND_TILE_W, y: 0, w: GROUND_TILE_W, h: GROUND_H, path: :pixel, **GROUND_COLOR }
    end
  end
end
