# Roadmap PR 5 (D1): proves draco (an external ECS) integrates with Conjuration.
#
# The shape of the integration — the thing this scene exists to demonstrate:
#   * simulation lives in a draco World, ticked ONCE per frame from #update;
#   * rendering stays in #draw_world, which runs once PER CAMERA and reads
#     components straight into camera.draw(..., z:).
#
# Keeping the World tick in #update (not #draw_world) is what makes the ECS
# inherit Conjuration's game clock for free: #update is skipped during a hit
# stop, so the whole simulation freezes with the game — see docs/ecs.md.
#
# draco is vendored via drenv (see drenv.toml / app/drenv_bundle.rb).

# --- Components: plain data (see docs/ecs.md "components vs primitives") -------

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

  # The glue between an ECS component (an object) and camera.draw (a hash
  # primitive). Built once here and mutated in place each frame in #draw_world,
  # so the per-entity render path allocates nothing. It is NOT a draco
  # `attribute`: attribute defaults are evaluated once and shared, so a `{}`
  # default would hand every entity the SAME hash.
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

# --- Systems: behaviour, mutating components. Run in declared order. ----------

# Integrate position by velocity. `context` is whatever #update passes to
# world.tick — here, the Scene, so systems can read world bounds off it.
class MovementSystem < Draco::System
  filter Position, Velocity

  def tick(_context)
    entities.each do |entity|
      entity.position.x += entity.velocity.dx
      entity.position.y += entity.velocity.dy
    end
  end
end

# Reflect velocity at the world edges. A three-component filter (needs Sprite
# for the body size) — demonstrates draco's set-intersection filtering.
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

    # The World is held in an instance variable, NOT in scene `state`: it is a
    # live object graph (Sets, subscriptions, class refs) that Conjuration's
    # serializable scene state should not try to round-trip. See docs/ecs.md.
    @world = CritterWorld.new
    spawn(120)

    # Cache the renderable set once here so #draw_world doesn't re-filter; it is
    # rebuilt every #update (see below), so spawns are picked up next frame.
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
    # Tick the ECS once per frame. Because this runs in #update (not #render), it
    # is skipped during a hit stop — the simulation freezes with the game.
    @world.tick(self)

    # Re-cache the renderable list ONCE per frame. #draw_world then iterates this
    # cache for every camera instead of calling world.filter per camera, which
    # would re-run draco's set intersection (and allocate a fresh Set) each time.
    # See docs/ecs.md for the measured cost of skipping this.
    refresh_renderables

    cameras[:main].ui.find(:count_label).object.text = "Critters: #{@renderables.length}"
  end

  def draw_world(camera)
    # Runs once per camera. Reads components straight into the reusable primitive
    # hash and hands it to camera.draw with a y-sorted z, so nothing allocates
    # per critter and depth falls out of the z buffer.
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

  # A non-zero speed in [-3, -1] u [1, 3]. Avoids Enumerable#sum / float traps.
  def rand_speed
    magnitude = 1 + rand(3)
    rand(2).zero? ? magnitude : -magnitude
  end
end
