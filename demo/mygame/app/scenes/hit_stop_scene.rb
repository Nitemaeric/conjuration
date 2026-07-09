# A knight swings at a row of crates. On contact everything fires at once for an
# "impact frame": the game freezes (Game#hit_stop), the camera shakes along the
# blow, the crate flashes white and pops, debris bursts, an impact starburst
# snaps out, and the screen flickers — then it all thaws into motion.
#
# The freeze HOLDS the flash/pop/debris on screen — that hold is what sells the
# hit. It comes for free two ways: the timed effects (flashes, burst, swing) are
# keyed to game.clock, which stops advancing during a hit stop; the physics sims
# (debris, crate flight) integrate in update, which doesn't run during one. Both
# resume exactly where they froze — see the note in #update.
#
# Sprites: Kenney "Tiny Dungeon" (CC0) — see sprites/kenney-tiny-dungeon-license.txt
require "app/views/prompt_view.rb"

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
    state.flash_at = nil         # clock tick of the last screen flash (nil = none)
    state.swing_started_at = nil # clock tick the current swing began (nil = idle)
    state.idle_since = clock      # clock tick we've been idle since (drives auto-swing)

    cameras[:main].ui.view do
      node({ x: 20, y: cameras[:main].from_top(20), anchor_y: 1 }) do
        node({ w: 100, h: 50, path: "sprites/button.png", action: -> { scene.change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
          node({ text: "Back", r: 255, g: 255, b: 255 })
        end
      end

      node({ x: grid.w / 2, y: cameras[:main].from_top(30), anchor_x: 0.5, anchor_y: 1 }, direction: :row, justify: :center, align: :center, gap: 12) do
        node({ text: "Knight auto-swings —", r: 255, g: 255, b: 255 })
        PromptView(id: :swing, keys: [:space], controller: :b, label: "swing now", pad: game.ui_pad, color: { r: 255, g: 255, b: 255 })
      end
    end
  end

  def input
    start_swing if inputs.keyboard.key_down.space
  end

  def update
    # Physics sims (crate flight, debris) integrate per update, so they freeze on
    # their own during a hit stop — update simply doesn't run. Time-keyed effects
    # (flashes, burst, swing) instead read elapsed = clock - started_at; clock
    # holds through the freeze, so they hold identically, no manual counters.
    state.crates.each do |crate|
      if crate.launched
        crate.x += crate.vx
        crate.y += crate.vy
        crate.vy -= GRAVITY
        crate.angle += crate.spin
      end

      crate.scale += (1.0 - crate.scale) * 0.25 # ease the pop back to normal
    end

    state.particles.each do |p|
      p.x += p.vx
      p.y += p.vy
      p.vy -= GRAVITY
      p.life -= 1
    end
    state.particles.reject! { |p| p.life <= 0 }

    state.bursts.reject! { |burst| clock - burst.born >= BURST_LIFE }

    if state.swing_started_at
      elapsed = clock - state.swing_started_at
      strike if elapsed == CONTACT_FRAME

      if elapsed >= SWING_DURATION
        state.swing_started_at = nil
        state.idle_since = clock
      end
    elsif clock - state.idle_since >= SWING_INTERVAL
      start_swing
    end

    reset_crates if state.crates.all? { |crate| crate.launched && offscreen?(crate) }
  end

  # Screen-space flash, drawn over the camera view.
  def render
    alpha = screen_flash_alpha
    return unless alpha > 0

    outputs.primitives << {
      x: grid.allscreen_x, y: grid.allscreen_y, w: grid.allscreen_w, h: grid.allscreen_h,
      path: :pixel, r: 255, g: 255, b: 255, a: alpha
    }
  end

  def draw_world(camera)
    state.crates.each do |crate|
      w = crate.w * crate.scale
      h = crate.h * crate.scale

      camera.draw({ x: crate.x, y: crate.y, w: w, h: h, path: "sprites/crate.png", angle: crate.angle, anchor_x: 0.5, anchor_y: 0.5 })

      flash = crate_flash_alpha(crate)
      next unless flash > 0

      camera.draw({ x: crate.x, y: crate.y, w: w, h: h, path: :pixel, r: 255, g: 255, b: 255, a: flash, angle: crate.angle, anchor_x: 0.5, anchor_y: 0.5 })
    end

    state.particles.each do |p|
      camera.draw({ x: p.x, y: p.y, w: p.size, h: p.size, path: :pixel, r: 235, g: 205, b: 150, a: 255 * p.life / p.max_life, anchor_x: 0.5, anchor_y: 0.5 })
    end

    state.bursts.each { |burst| draw_burst(camera, burst) }

    # The knight lunges into the swing.
    lunge = swinging? ? Math.sin(swing_elapsed.to_f / SWING_DURATION * Math::PI) * 28 : 0
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
      { x: CRATE_START_X + i * CRATE_SPACING, y: CRATE_Y, w: CRATE_SIZE, h: CRATE_SIZE, vx: 0, vy: 0, angle: 0, spin: 0, scale: 1.0, flash_at: nil, launched: false }
    end
  end

  def start_swing
    return if swinging? || stationary_crates.empty?

    state.swing_started_at = clock
  end

  # Swing timing keyed to game.clock, so a mid-swing hit stop holds the blade in
  # place (clock frozen) instead of the counter marching on.
  def swinging?
    state.swing_started_at && clock - state.swing_started_at < SWING_DURATION
  end

  def swing_elapsed
    clock - state.swing_started_at
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
    crate.flash_at = clock

    spawn_particles(crate.x, crate.y)
    state.bursts << { x: crate.x, y: crate.y, born: clock }
    state.flash_at = clock

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
    elapsed = clock - burst.born
    progress = elapsed.to_f / BURST_LIFE
    alpha = 255 * (BURST_LIFE - elapsed) / BURST_LIFE
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

  # Fade alphas for the two flashes, keyed to elapsed clock ticks since the hit.
  # remaining counts down from the full duration, so both hold at peak through a
  # hit stop (clock frozen) then fade once it thaws — same curve as before.
  def crate_flash_alpha(crate)
    return 0 unless crate.flash_at

    remaining = FLASH_DURATION - (clock - crate.flash_at)
    remaining > 0 ? 255 * remaining / FLASH_DURATION : 0
  end

  def screen_flash_alpha
    return 0 unless state.flash_at

    remaining = SCREEN_FLASH - (clock - state.flash_at)
    remaining > 0 ? 60 * remaining / SCREEN_FLASH : 0
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
    return 90 unless swinging?

    90 - 135 * (swing_elapsed.to_f / SWING_DURATION)
  end
end
