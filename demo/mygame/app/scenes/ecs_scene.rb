class Position < Draco::Component
  attribute :x, default: 0
  attribute :y, default: 0
end

class Velocity < Draco::Component
  attribute :dx, default: 0
  attribute :dy, default: 0
end

class Sprite < Draco::Component
  attribute :w, default: 24
  attribute :h, default: 24
  attribute :r, default: 255
  attribute :g, default: 255
  attribute :b, default: 255

  # attr_reader, not a draco attribute: a `{}` default is shared across all entities.
  attr_reader :primitive

  def after_initialize
    @primitive = { w: w, h: h, path: :pixel, r: r, g: g, b: b }
  end
end

class Critter < Draco::Entity
  component Position
  component Velocity
  component Sprite
end

class MovementSystem < Draco::System
  filter Position, Velocity

  def tick(_context)
    entities.each do |entity|
      entity.position.x += entity.velocity.dx
      entity.position.y += entity.velocity.dy
    end
  end
end

class BounceSystem < Draco::System
  filter Position, Velocity, Sprite

  def tick(context)
    max_x = context.virtual_w
    max_y = context.virtual_h

    entities.each do |entity|
      position = entity.position
      velocity = entity.velocity
      sprite = entity.sprite

      if position.x < 0
        position.x = 0
        velocity.dx = velocity.dx.abs
      elsif position.x + sprite.w > max_x
        position.x = max_x - sprite.w
        velocity.dx = -velocity.dx.abs
      end

      if position.y < 0
        position.y = 0
        velocity.dy = velocity.dy.abs
      elsif position.y + sprite.h > max_y
        position.y = max_y - sprite.h
        velocity.dy = -velocity.dy.abs
      end
    end
  end
end

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
