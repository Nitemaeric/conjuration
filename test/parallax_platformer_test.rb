# Gameplay tests for the parallax demo's platformer layer: the jump arc, one-way
# platform landings, and the deadzone camera from docs/cameras.md.
#
# These drive the scene's own #input / #update rather than the full lifecycle, in
# the order Scene#perform_update uses (cameras ease first, then the scene writes
# the next target), so the camera assertions see exactly the frame the engine
# would.

def parallax_scene
  DragonInput.setup do |c|
    c.action_set :gameplay do |s|
      s.digital :move_left, controller: :dpad_left, keyboard: :a
      s.digital :move_right, controller: :dpad_right, keyboard: :d
      s.digital :jump, controller: :a, keyboard: :space
    end
  end

  $game.state.delete("scene_platformer")
  scene = ParallaxScene.new(:platformer)
  $game.current_scene = scene
  scene.setup
  scene
end

def parallax_tick(scene, left_right: 0, pressed: [], held: [])
  $game.inputs = { left_right: left_right }
  $game.input_source = FakeInputSource.new(pressed: pressed, held: held)

  scene.input
  scene.cameras.each_value { |camera| camera.send(:perform_update) }
  scene.update

  # Camera#perform_render is what drops the per-frame view memo; these ticks never
  # render, so without this every parallax layer rect stays frozen at frame one.
  scene.cameras.each_value do |camera|
    camera.instance_variable_set(:@view_rect, nil)
    camera.instance_variable_set(:@parallax_view_rects, nil)
  end
end

def parallax_reset!
  $game.inputs = nil
  $game.input_source = nil
  $game.current_scene = nil
  $game.state.delete("scene_platformer")
  DragonInput.reset!
end

def drop_onto(scene, platform)
  hero = scene.state.hero
  hero[:x] = platform[:x] + platform[:w] / 2
  hero[:y] = platform[:y] + 60
  hero[:vy] = 0
  hero[:grounded] = false

  40.times do
    parallax_tick(scene)
    break if hero[:grounded]
  end
  hero
end

def layer_x(camera, layer)
  camera.view_rect(parallax: layer[:parallax])[:x]
end

# --- jump and gravity ---

def test_parallax_jump_rises_to_an_apex_and_lands_back_on_the_ground(args, assert)
  scene = parallax_scene
  hero = scene.state.hero

  parallax_tick(scene, pressed: [:jump], held: [:jump])
  assert.equal!(hero[:grounded], false, "the impulse leaves the ground on the frame :jump goes down")
  assert.equal!(hero[:y], ParallaxScene::GROUND_H + ParallaxScene::JUMP_SPEED - ParallaxScene::GRAVITY,
                "the first airborne step is the impulse less one tick of gravity")

  apex = hero[:y]
  ticks = 1
  while !hero[:grounded] && ticks < 200
    parallax_tick(scene, held: [:jump])
    apex = hero[:y] if hero[:y] > apex
    ticks += 1
  end

  assert.equal!(apex, ParallaxScene::GROUND_H + 136, "a held jump peaks 136 above the take-off surface")
  assert.equal!(hero[:y], ParallaxScene::GROUND_H, "and comes down flush on the ground line")
  assert.equal!(hero[:vy], 0, "landing zeroes the vertical velocity")
  assert.equal!(hero[:support_y], ParallaxScene::GROUND_H, "the ground is the surface underfoot again")
  assert.true!(ticks > 20 && ticks < 50, "the arc lasts a playable number of frames (#{ticks})")
ensure
  parallax_reset!
end

def test_parallax_releasing_jump_early_cuts_the_arc(args, assert)
  scene = parallax_scene
  hero = scene.state.hero

  parallax_tick(scene, pressed: [:jump], held: [:jump])
  apex = hero[:y]
  ticks = 1
  while !hero[:grounded] && ticks < 200
    parallax_tick(scene) # released from the second frame on
    apex = hero[:y] if hero[:y] > apex
    ticks += 1
  end

  assert.equal!(apex, ParallaxScene::GROUND_H + 37, "the release clamps the rise to JUMP_CUT_SPEED")
  assert.true!(apex < ParallaxScene::GROUND_H + 136, "a cut jump is markedly shorter than a held one")
  assert.equal!(hero[:y], ParallaxScene::GROUND_H, "and still lands on the ground line")
ensure
  parallax_reset!
end

def test_parallax_jump_is_ignored_while_airborne(args, assert)
  scene = parallax_scene
  hero = scene.state.hero

  parallax_tick(scene, pressed: [:jump], held: [:jump])
  airborne_vy = hero[:vy]
  parallax_tick(scene, pressed: [:jump], held: [:jump])

  assert.true!(hero[:vy] < airborne_vy, "a second press mid-air does not re-impulse")
ensure
  parallax_reset!
end

# --- platforms ---

def test_parallax_hero_lands_on_a_platform_top_and_drops_when_he_walks_off(args, assert)
  scene = parallax_scene
  platform = ParallaxScene::PLATFORMS[0]
  hero = drop_onto(scene, platform)

  assert.equal!(hero[:grounded], true, "he caught the platform on the way down")
  assert.equal!(hero[:y], platform[:y], "feet settle exactly on the top face")
  assert.equal!(hero[:support_y], platform[:y], "and it becomes the surface the camera tracks")

  ledge = platform[:x] + platform[:w] + ParallaxScene::FOOT_HALF
  steps = 0
  while hero[:grounded] && steps < 120
    parallax_tick(scene, left_right: 1)
    steps += 1
  end

  assert.equal!(hero[:x], ledge, "he keeps his footing until the foot box clears the ledge")
  assert.equal!(hero[:grounded], false, "then there is nothing under him")

  fall = 0
  while !hero[:grounded] && fall < 200
    parallax_tick(scene)
    fall += 1
  end

  assert.equal!(hero[:y], ParallaxScene::GROUND_H, "and he falls to the ground below")
  assert.equal!(hero[:support_y], ParallaxScene::GROUND_H, "the ground takes over as the support surface")
ensure
  parallax_reset!
end

def test_parallax_platforms_are_one_way(args, assert)
  scene = parallax_scene
  platform = ParallaxScene::PLATFORMS[0]
  hero = scene.state.hero
  hero[:x] = platform[:x] + platform[:w] / 2

  parallax_tick(scene, pressed: [:jump], held: [:jump])
  crossed_rising = false
  ticks = 1
  while !hero[:grounded] && ticks < 200
    crossed_rising = true if hero[:vy] > 0 && hero[:y] > platform[:y]
    parallax_tick(scene, held: [:jump])
    ticks += 1
  end

  assert.true!(crossed_rising, "the jump passes up through the slab")
  assert.equal!(hero[:y], platform[:y], "and lands on top of it on the way back down")
ensure
  parallax_reset!
end

# The art and the collision surface are derived from the same PLATFORMS entry;
# this is the assertion that keeps them from drifting apart.
def test_parallax_platform_art_lands_where_its_collision_surface_is(args, assert)
  scene = parallax_scene
  camera = scene.cameras[:main]
  platform = ParallaxScene::PLATFORMS[0]
  hero = drop_onto(scene, platform)

  scene.draw_world(camera)
  slab = camera.to_viewport({ x: platform[:x], y: hero[:y] - ParallaxScene::PLATFORM_H, w: platform[:w], h: ParallaxScene::PLATFORM_H })
  buffered = camera.instance_variable_get(:@draw_buffer)

  assert.true!(buffered.any? { |entry| entry[2][:x] == slab[:x] && entry[2][:y] == slab[:y] && entry[2][:w] == slab[:w] },
               "the slab is drawn with its top face exactly where the feet stopped")
ensure
  parallax_reset!
end

# --- deadzone camera ---

def test_parallax_camera_holds_while_the_hero_moves_inside_the_deadzone(args, assert)
  scene = parallax_scene
  camera = scene.cameras[:main]
  hero = scene.state.hero

  start_x = camera.target.x
  sky_before = layer_x(camera, ParallaxScene::SKY)
  trees_before = layer_x(camera, ParallaxScene::TREES)

  20.times { parallax_tick(scene, left_right: 1) }

  assert.equal!(hero[:x] - start_x, 100, "the hero walked 100px, inside the 120px half-extent")
  assert.equal!(camera.target.x, start_x, "the camera target never budged")
  assert.equal!(camera.current.x, start_x, "and neither did the eased focal point")
  assert.equal!(layer_x(camera, ParallaxScene::SKY), sky_before, "so the sky layer's derived view holds")
  assert.equal!(layer_x(camera, ParallaxScene::TREES), trees_before, "and so does the tree layer's")
ensure
  parallax_reset!
end

def test_parallax_camera_pushes_by_the_excess_once_the_deadzone_edge_is_crossed(args, assert)
  scene = parallax_scene
  camera = scene.cameras[:main]
  hero = scene.state.hero

  start_x = camera.target.x
  sky_before = layer_x(camera, ParallaxScene::SKY)
  trees_before = layer_x(camera, ParallaxScene::TREES)

  40.times { parallax_tick(scene, left_right: 1) }

  assert.equal!(hero[:x], start_x + 200, "the hero walked 200px, past the half-extent")
  assert.equal!(camera.target.x, hero[:x] - ParallaxScene::DEADZONE_HALF_W,
                "the target sits exactly on the deadzone's trailing edge — it moved only by the excess")
  assert.true!(camera.current.x > start_x, "the eased focal point followed it")
  assert.true!(camera.current.x <= camera.target.x, "and never overshoots the target")

  panned = camera.current.x - start_x
  assert.close!(layer_x(camera, ParallaxScene::SKY) - sky_before, panned * ParallaxScene::SKY[:parallax],
                "the sky layer's derived view moved at its own factor")
  assert.close!(layer_x(camera, ParallaxScene::TREES) - trees_before, panned * ParallaxScene::TREES[:parallax],
                "and the tree layer at its faster one")
ensure
  parallax_reset!
end

def test_parallax_an_ordinary_jump_does_not_scroll_the_camera_vertically(args, assert)
  scene = parallax_scene
  camera = scene.cameras[:main]
  hero = scene.state.hero
  y_before = camera.target.y

  parallax_tick(scene, pressed: [:jump], held: [:jump])
  peak = hero[:y]
  ticks = 1
  while !hero[:grounded] && ticks < 200
    parallax_tick(scene, held: [:jump])
    peak = hero[:y] if hero[:y] > peak
    assert.equal!(camera.target.y, y_before, "frame #{ticks}: the camera holds while he is off the ground")
    ticks += 1
  end

  assert.true!(peak - ParallaxScene::GROUND_H > 100, "he really did leave the ground")
  assert.equal!(camera.target.y, y_before, "and the view ends exactly where it started")
  assert.equal!(camera.current.y, y_before, "with nothing eased in between")
ensure
  parallax_reset!
end

# The half-extent alone already covers a jump off flat ground (the arc is shorter
# than it is). This is the case that isolates the support-surface rule: from the
# high ledge the apex clears the box outright, so only tracking the surface
# underfoot keeps the view still.
def test_parallax_a_jump_from_a_high_ledge_still_does_not_scroll_the_camera(args, assert)
  scene = parallax_scene
  camera = scene.cameras[:main]
  high = ParallaxScene::PLATFORMS[1]

  hero = drop_onto(scene, high)
  settled_y = camera.target.y
  assert.true!(settled_y > 360, "the ledge pushed the camera up first")

  parallax_tick(scene, pressed: [:jump], held: [:jump])
  peak = hero[:y]
  ticks = 1
  while !hero[:grounded] && ticks < 200
    parallax_tick(scene, held: [:jump])
    peak = hero[:y] if hero[:y] > peak
    assert.equal!(camera.target.y, settled_y, "frame #{ticks}: airborne frames leave the target alone")
    ticks += 1
  end

  assert.true!(peak + ParallaxScene::CAMERA_RISE - settled_y > ParallaxScene::DEADZONE_HALF_H,
               "the apex would have left the deadzone had the camera tracked his live y")
  assert.equal!(hero[:support_y], high[:y], "he came back down on the same ledge")
  assert.equal!(camera.target.y, settled_y, "and the camera never moved")
ensure
  parallax_reset!
end

def test_parallax_landing_on_a_high_ledge_pushes_the_camera_up(args, assert)
  scene = parallax_scene
  camera = scene.cameras[:main]
  low = ParallaxScene::PLATFORMS[0]
  high = ParallaxScene::PLATFORMS[1]
  rest_y = camera.target.y

  hero = drop_onto(scene, low)
  assert.equal!(hero[:support_y], low[:y], "standing on the low ledge")
  assert.equal!(camera.target.y, rest_y, "which stays inside the taller vertical half-extent")

  drop_onto(scene, high)
  assert.equal!(camera.target.y, high[:y] + ParallaxScene::CAMERA_RISE - ParallaxScene::DEADZONE_HALF_H,
                "the high ledge pushes the target up by the excess only")
  assert.true!(camera.target.y < scene.virtual_h - camera.h / 2, "and stays inside the world's vertical bounds")
ensure
  parallax_reset!
end

# --- the documented recipe itself ---

# Mirrors docs/cameras.md §"Camera feel" — the deadzone block plus the platformer
# variant's vertical focus — verbatim. Running it beside the scene's own camera,
# frame for frame, is what stops the demo and the documented recipe from drifting.
def documented_deadzone(camera, hero, half_w, half_h, rise)
  x = camera.target.x
  y = camera.target.y

  dx = hero[:x] - x
  x += dx - half_w if dx >  half_w
  x += dx + half_w if dx < -half_w

  dy = hero[:support_y] + rise - y
  y += dy - half_h if dy >  half_h
  y += dy + half_h if dy < -half_h

  camera.look_at(x: x, y: y)
end

def test_parallax_camera_matches_the_documented_deadzone_recipe(args, assert)
  scene = parallax_scene
  main = scene.cameras[:main]
  hero = scene.state.hero

  mirror = scene.add_camera(:recipe, speed: 12)
  mirror.current.x = mirror.target.x = main.target.x
  mirror.current.y = mirror.target.y = main.target.y

  supports = []
  60.times do |tick|
    parallax_tick(scene,
                  left_right: 1,
                  pressed: tick == 10 ? [:jump] : [],
                  held: tick >= 10 && tick <= 20 ? [:jump] : [])
    documented_deadzone(mirror, hero,
                        ParallaxScene::DEADZONE_HALF_W,
                        ParallaxScene::DEADZONE_HALF_H,
                        ParallaxScene::CAMERA_RISE)
    supports << hero[:support_y]

    assert.equal!(main.target.x, mirror.target.x, "frame #{tick}: the scene tracks the documented x")
    assert.equal!(main.target.y, mirror.target.y, "frame #{tick}: the scene tracks the documented y")
    assert.equal!(main.current.x, mirror.current.x, "frame #{tick}: and eases identically")
  end

  assert.true!(main.target.x > 640, "the run exercised the horizontal push, not just the hold")
  assert.true!(supports.uniq.length > 1, "and a landing changed the support surface along the way")
ensure
  parallax_reset!
end
