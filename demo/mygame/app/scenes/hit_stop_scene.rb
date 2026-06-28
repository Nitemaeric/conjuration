# A knight swings at a row of crates. On contact everything fires at once for an
# "impact frame": the game freezes (Game#hit_stop), the camera shakes along the
# blow, the crate flashes white and pops, debris bursts, an impact starburst
# snaps out, and the screen flickers — then it all thaws into motion.
#
# Because the effects are triggered on strike but animated in update, the freeze
# HOLDS the flash/pop/debris on screen, which is what sells the hit.
#
# Sprites: Kenney "Tiny Dungeon" (CC0) — see sprites/kenney-tiny-dungeon-license.txt
class HitStopScene < Conjuration::Scene
  KNIGHT = { x: 480, y: 360, size: 96 }.freeze

  CRATE_SIZE = 64
  CRATE_COUNT = 4
  CRATE_START_X = 720
  CRATE_SPACING = 92
  CRATE_Y = 360

  SWING_INTERVAL = 70 # idle frames between automatic swings
  SWING_DURATION = 22 # frames per swing
  CONTACT_FRAME = 15  # frame within the swing when the blade connects
  GRAVITY = 0.9

  HIT_STOP = 12        # frames frozen on contact
  FLASH_DURATION = 10  # crate white-flash frames
  SCREEN_FLASH = 6     # screen-flash frames
  PARTICLE_LIFE = 28   # debris lifetime
  BURST_LIFE = 12      # starburst lifetime
  POP_SCALE = 1.45     # crate scale punch on impact

  def setup
    add_camera(:main)
    cameras[:main].ui.group = :hud # the whole HUD is one navigable pane
    activate_navigation(:hud)

    reset_crates
    state.particles = []
    state.bursts = []
    state.flash = 0
    state.swinging = false
    state.swing_frame = 0
    state.swing_timer = 0

    cameras[:main].ui.node({ x: 20, y: cameras[:main].from_top(20), anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    cameras[:main].ui.node({ x: grid.w / 2, y: cameras[:main].from_top(30), w: 700, anchor_x: 0.5, anchor_y: 1 }, align: :center) do
      node({ text: "Knight auto-swings — SPACE to swing now", r: 255, g: 255, b: 255 })
    end
  end

  def input
    start_swing if inputs.keyboard.key_down.space
  end

  def update
    state.crates.each do |crate|
      if crate.launched
        crate.x += crate.vx
        crate.y += crate.vy
        crate.vy -= GRAVITY
        crate.angle += crate.spin
      end

      crate.scale += (1.0 - crate.scale) * 0.25 # ease the pop back to normal
      crate.flash -= 1 if crate.flash > 0
    end

    state.particles.each do |p|
      p.x += p.vx
      p.y += p.vy
      p.vy -= GRAVITY
      p.life -= 1
    end
    state.particles.reject! { |p| p.life <= 0 }

    state.bursts.each { |burst| burst.life -= 1 }
    state.bursts.reject! { |burst| burst.life <= 0 }

    state.flash -= 1 if state.flash > 0

    if state.swinging
      state.swing_frame += 1
      strike if state.swing_frame == CONTACT_FRAME
      state.swinging = false if state.swing_frame >= SWING_DURATION
    else
      state.swing_timer += 1
      start_swing if state.swing_timer >= SWING_INTERVAL
    end

    reset_crates if state.crates.all? { |crate| crate.launched && offscreen?(crate) }
  end

  # Screen-space flash, drawn over the camera view.
  def render
    return unless state.flash > 0

    outputs.primitives << {
      x: grid.allscreen_x, y: grid.allscreen_y, w: grid.allscreen_w, h: grid.allscreen_h,
      path: :pixel, r: 255, g: 255, b: 255, a: 60 * state.flash / SCREEN_FLASH
    }
  end

  def draw_world(camera)
    state.crates.each do |crate|
      w = crate.w * crate.scale
      h = crate.h * crate.scale

      camera.draw({ x: crate.x, y: crate.y, w: w, h: h, path: "sprites/crate.png", angle: crate.angle, anchor_x: 0.5, anchor_y: 0.5 })

      next unless crate.flash > 0

      camera.draw({ x: crate.x, y: crate.y, w: w, h: h, path: :pixel, r: 255, g: 255, b: 255, a: 255 * crate.flash / FLASH_DURATION, angle: crate.angle, anchor_x: 0.5, anchor_y: 0.5 })
    end

    state.particles.each do |p|
      camera.draw({ x: p.x, y: p.y, w: p.size, h: p.size, path: :pixel, r: 235, g: 205, b: 150, a: 255 * p.life / p.max_life, anchor_x: 0.5, anchor_y: 0.5 })
    end

    state.bursts.each { |burst| draw_burst(camera, burst) }

    # The knight lunges into the swing.
    lunge = state.swinging ? Math.sin(state.swing_frame.to_f / SWING_DURATION * Math::PI) * 28 : 0
    knight_x = KNIGHT[:x] + lunge

    camera.draw({ x: knight_x, y: KNIGHT[:y], w: KNIGHT[:size], h: KNIGHT[:size], path: "sprites/knight.png", anchor_x: 0.5, anchor_y: 0.5 })

    hand_x = knight_x + 30
    hand_y = KNIGHT[:y] - 32

    # The blade is a sprite pivoted at the grip (anchor + rotation anchor at the
    # bottom-centre), swung through the arc. weapon_angle is the blade's heading
    # (90deg = straight up); the art already points up, so the draw angle is that
    # heading minus 90.
    camera.draw({
      x: hand_x, y: hand_y,
      w: 72, h: 72,
      path: "sprites/sword.png",
      angle: weapon_angle - 90,
      anchor_x: 0.5, anchor_y: 0.1,
      angle_anchor_x: 0.5, angle_anchor_y: 0.1
    })
  end

  private

  def reset_crates
    state.crates = CRATE_COUNT.times.map do |i|
      { x: CRATE_START_X + i * CRATE_SPACING, y: CRATE_Y, w: CRATE_SIZE, h: CRATE_SIZE, vx: 0, vy: 0, angle: 0, spin: 0, scale: 1.0, flash: 0, launched: false }
    end
  end

  def start_swing
    return if state.swinging || stationary_crates.empty?

    state.swinging = true
    state.swing_frame = 0
    state.swing_timer = 0
  end

  # The hit lands: launch the nearest crate and fire every juice effect at once.
  def strike
    crate = stationary_crates.min_by { |c| c.x }
    return unless crate

    crate.launched = true
    crate.vx = 17
    crate.vy = 13
    crate.spin = 11
    crate.scale = POP_SCALE
    crate.flash = FLASH_DURATION

    spawn_particles(crate.x, crate.y)
    state.bursts << { x: crate.x, y: crate.y, life: BURST_LIFE, max_life: BURST_LIFE }
    state.flash = SCREEN_FLASH

    game.hit_stop(HIT_STOP)
    cameras[:main].shake(0.7, direction: { x: 1, y: 0.4 })
  end

  def spawn_particles(x, y)
    14.times do
      angle = rand * 2 * Math::PI
      speed = rand * 9 + 4

      state.particles << {
        x: x, y: y,
        vx: Math.cos(angle) * speed + 5, # radial burst, biased along the impact
        vy: Math.sin(angle) * speed,
        size: rand * 7 + 5,
        life: PARTICLE_LIFE,
        max_life: PARTICLE_LIFE
      }
    end
  end

  # A starburst of lines snapping outward from the impact point.
  def draw_burst(camera, burst)
    progress = 1 - burst.life.to_f / burst.max_life
    alpha = 255 * burst.life / burst.max_life
    inner = 12 + progress * 26
    outer = inner + 24

    8.times do |i|
      angle = i * Math::PI / 4

      camera.draw({
        x: burst.x + Math.cos(angle) * inner,
        y: burst.y + Math.sin(angle) * inner,
        x2: burst.x + Math.cos(angle) * outer,
        y2: burst.y + Math.sin(angle) * outer,
        primitive_marker: :line, r: 255, g: 240, b: 190, a: alpha
      })
    end
  end

  def stationary_crates
    state.crates.reject { |crate| crate.launched }
  end

  def offscreen?(crate)
    crate.x > 1500 || crate.y < -300
  end

  # Sweeps from raised (90deg, straight up) down past horizontal, connecting with
  # the crates around 0deg at CONTACT_FRAME.
  def weapon_angle
    return 90 unless state.swinging

    90 - 135 * (state.swing_frame.to_f / SWING_DURATION)
  end
end
