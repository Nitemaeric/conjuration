# Layout smoke tests for the demo's converted HUD views: build each scene's hud
# against the real UI machinery (as the navigation tests do) and lay it out.
# The justify-fallback warning is asserted away because it is the post-#28
# trace of the class that hard-crashed the hit-stop scene: a centered/justified
# node whose main-axis size never resolves.

def demo_hud_ui(scene_class, style: nil)
  DragonInput.setup do |c|
    c.action_set :gameplay do |s|
      s.digital :attack, controller: :b, keyboard: :space
      s.analog :pan, controller: :left_analog, keyboard: :wasd
      s.digital :move_left, controller: :dpad_left, keyboard: :a
      s.digital :move_right, controller: :dpad_right, keyboard: :d
    end
  end
  DragonInput.glyph_style = style

  scene = scene_class.new(:smoke)
  camera = make_camera
  Conjuration::UI.warnings.clear
  camera.ui.view { scene.hud(camera) }
  camera.ui.render_view
  camera.ui.calculate_layout
  camera.ui
end

def assert_no_justify_fallbacks!(assert, scene_name)
  fallbacks = Conjuration::UI.warnings.select { |warning| warning.include?("falling back to :start") }
  assert.equal!(fallbacks, [], "#{scene_name}: a justified node is missing its main-axis size")
end

def test_hit_stop_hud_layout(args, assert)
  ui = demo_hud_ui(HitStopScene)
  assert_no_justify_fallbacks!(assert, "hit_stop")

  row = ui.find(:prompt_row)
  swing = ui.find(:swing)

  assert.equal!(ui.find(:swing_g0).object.w, 41, "space keycap renders wide (24 * 1.7)")
  assert.true!(swing.object.w > 0, "the prompt row carries its own width")
  assert.true!(swing.object.right <= row.object.right, "prompt stays inside the centered row")
  assert.true!(swing.object.left >= row.object.left, "prompt starts inside the centered row")
ensure
  DragonInput.reset!
end

def test_basic_camera_hud_layout(args, assert)
  ui = demo_hud_ui(BasicCameraScene)
  assert_no_justify_fallbacks!(assert, "basic_camera")

  panel = ui.find(:panel)
  inner_left = panel.object.left + 20
  inner_right = panel.object.right - 20

  assert.equal!(ui.find(:pan_g0).object.w, 36, "wasd prompt uses the arrows cluster cap (24 * 1.5)")
  assert.equal!(ui.find(:shake_g0).object.w, 41, "space keycap renders wide (24 * 1.7)")

  [ui.find(:pan), ui.find(:shake)].each do |prompt|
    assert.true!(prompt.object.left >= inner_left, "#{prompt.id}: starts inside the panel padding")
    assert.true!(prompt.object.right <= inner_right, "#{prompt.id}: no overflow past the panel's right edge")
  end
ensure
  DragonInput.reset!
end

def test_zoom_hud_layout(args, assert)
  ui = demo_hud_ui(ZoomScene)
  assert_no_justify_fallbacks!(assert, "zoom")

  panel = ui.find(:panel)
  pan = ui.find(:pan)

  assert.true!(pan.object.left >= panel.object.left + 20, "prompt starts inside the panel padding")
  assert.true!(pan.object.right <= panel.object.right - 20, "no overflow past the panel's right edge")
ensure
  DragonInput.reset!
end

def test_ecs_hud_layout(args, assert)
  ui = demo_hud_ui(ECSScene)
  assert_no_justify_fallbacks!(assert, "ecs")

  readout = ui.find(:readout)
  spawn = ui.find(:spawn)

  assert.true!(spawn.object.right <= readout.object.right, "prompt hugs the readout's right edge, on screen")
  assert.true!(spawn.object.left >= readout.object.left, "prompt fits inside the readout box")
  assert.true!(spawn.object.top <= readout.object.top, "prompt stays inside the readout box vertically")
  assert.true!(spawn.object.bottom >= readout.object.bottom, "prompt sits above the bottom margin")
ensure
  DragonInput.reset!
end

def test_parallax_hud_layout(args, assert)
  ui = demo_hud_ui(ParallaxScene)
  assert_no_justify_fallbacks!(assert, "parallax")

  panel = ui.find(:panel)
  walk = ui.find(:walk)

  assert.true!(!ui.find(:walk_g0).nil?, "keyboard style: a cap for :move_left")
  assert.true!(!ui.find(:walk_g1).nil?, "keyboard style: a cap for :move_right")
  assert.true!(walk.object.left >= panel.object.left + 16, "prompt starts inside the panel padding")
  assert.true!(walk.object.right <= panel.object.right - 16, "no overflow past the panel's right edge")
ensure
  DragonInput.reset!
end

def test_parallax_controller_clause_collapses_to_one_glyph(args, assert)
  ui = demo_hud_ui(ParallaxScene, style: :xbox)

  assert.true!(!ui.find(:walk_g0).nil?, "controller style: the left-stick override glyph")
  assert.nil!(ui.find(:walk_g1), "controller style: the two move actions collapse to one glyph")
ensure
  DragonInput.reset!
end
