require "app/entities/critter.rb"
require "app/systems/movement_system.rb"
require "app/systems/bounce_system.rb"

class CritterWorld < Draco::World
  systems MovementSystem, BounceSystem
end

class ECSScene < Conjuration::Scene
  SPAWN_BATCH = 50
  PALETTE = [
    [255, 120, 90], [120, 200, 255], [255, 210, 90],
    [160, 255, 150], [220, 150, 255]
  ].freeze

  def setup
    self.virtual_w = self.virtual_h = 1280

    add_camera(:main, speed: 30)
    cameras[:main].ui.group = :hud
    activate_navigation(:hud)

    @world = CritterWorld.new
    spawn(120)

    refresh_renderables

    cameras[:main].ui.node({ x: 20, y: cameras[:main].from_top(20), anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) } }, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: cameras[:main].from_right(20), y: 20, anchor_x: 1, anchor_y: 0 }, direction: :column, justify: :end, align: :end, gap: 6) do
      node({ text: "SPACE to spawn 50", r: 255, g: 255, b: 255 })
      node({ text: "Critters: 0", r: 255, g: 255, b: 255 }, id: :count_label)
    end
  end

  def input
    spawn(SPAWN_BATCH) if inputs.keyboard.key_down.space
  end

  def update
    # Tick from #update, not #draw_world, so a hit stop freezes the sim too.
    @world.tick(self)

    refresh_renderables

    cameras[:main].ui.find(:count_label).object.text = "Critters: #{@renderables.length}"
  end

  def draw_world(camera)
    @renderables.each do |entity|
      position = entity.position
      primitive = entity.sprite.primitive
      primitive[:x] = position.x
      primitive[:y] = position.y

      camera.draw(primitive, z: -position.y)
    end
  end

  private

  def refresh_renderables
    @renderables = @world.filter(Position, Sprite).to_a
  end

  def spawn(count)
    count.times do
      colour = PALETTE[rand(PALETTE.length)]
      size = 16 + rand(20)

      @world.entities << Critter.new(
        position: { x: rand(virtual_w - size), y: rand(virtual_h - size) },
        velocity: { dx: rand_speed, dy: rand_speed },
        sprite: { w: size, h: size, r: colour[0], g: colour[1], b: colour[2] }
      )
    end
  end

  def rand_speed
    magnitude = 1 + rand(3)
    rand(2).zero? ? magnitude : -magnitude
  end
end
