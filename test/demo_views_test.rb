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

# Zoom's loading_view builds nodes inside a framework-owned loading root — the
# same reactive machinery as the HUDs, driven here with a live progress value.
def test_zoom_loading_view_layout(args, assert)
  scene = ZoomScene.new(:smoke)
  progress = { value: 0.25 }

  Conjuration::UI.warnings.clear
  ui = Conjuration::UI.build
  ui.view { scene.loading_view(progress[:value]) }
  ui.render_view
  ui.calculate_layout
  assert_no_justify_fallbacks!(assert, "zoom_loading")

  track = ui.find(:loading_track)
  fill = ui.find(:loading_fill)
  assert.equal!(fill.object.w, track.object.w * 0.25, "the fill spans the reported fraction of the track")
  assert.true!(ui.find(:loading_label).object.text.include?("25%"), "the label reads the same progress")

  progress[:value] = 0.75
  ui.render_view
  ui.calculate_layout

  assert.true!(fill.equal?(ui.find(:loading_fill)), "the fill node reconciles in place across loading frames")
  assert.equal!(fill.object.w, track.object.w * 0.75, "and its width follows the progress")
  assert.equal!(ui.interactive_nodes, [], "the loading view is render-only: nothing interactive")
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

# --- ShortcutBadgeView (the demo's shortcut display pattern) ---

# Every probe hits, so art paths resolve deterministically off-engine.
class GtkAllFilesDouble < GtkDouble
  def read_file(*)
    "x"
  end
end

class BadgeHost
  include Conjuration::UI::Builder

  def initialize(shortcut)
    @shortcut = shortcut
  end

  def view
    node({ x: 0, y: 0, w: 100, h: 50, primitive_marker: :solid, action: -> {} }, id: :btn, shortcut: @shortcut) do
      ShortcutBadgeView(id: :badge, shortcut: @shortcut, height: 50, pad: :one)
    end
  end
end

def badge_ui(shortcut: { keyboard: :escape, controller: :b }, style: nil, gtk: GtkAllFilesDouble.new)
  DragonInput.setup { |c| c.action_set(:gameplay) }
  DragonInput.glyph_style = style
  $gtk = gtk

  host = BadgeHost.new(shortcut)
  camera = make_camera
  camera.ui.view(&host.method(:view))
  camera.ui.render_view
  camera.ui.calculate_layout
  camera.ui
end

def test_badge_pins_key_art_inside_the_corner(args, assert)
  ui = badge_ui
  badge = ui.find(:badge)
  btn = ui.find(:btn)

  assert.true!(badge.object.path.include?("keyboard/escape"), "keyboard style shows the key's art")
  assert.equal!(badge.object.w, 20, "40% of the 50px host button")
  assert.equal!(badge.object.right, btn.object.right - 4, "pinned 4px in from the right edge")
  assert.equal!(badge.object.bottom, btn.object.bottom + 4, "pinned 4px up from the bottom edge")
ensure
  $gtk = $game.gtk
  DragonInput.reset!
end

def test_badge_follows_the_device_style(args, assert)
  ui = badge_ui(style: :xbox)

  assert.true!(ui.find(:badge).object.path.include?("xbox/b"), "controller style shows the button's art")
ensure
  $gtk = $game.gtk
  DragonInput.reset!
end

def test_badge_falls_back_to_a_keycap_chip(args, assert)
  ui = badge_ui(gtk: $game.gtk) # the default GtkDouble: every art probe misses

  badge = ui.find(:badge)
  assert.equal!(badge.object.path, :solid, "no art: a drawn chip")
  assert.equal!(badge.children.first.object.text, "ESCAPE", "labelled with the key")
ensure
  $gtk = $game.gtk
  DragonInput.reset!
end

class ButtonHost
  include Conjuration::UI::Builder

  def initialize(shortcut)
    @shortcut = shortcut
  end

  def view
    ButtonView(id: :go, label: "Go", action: -> {}, shortcut: @shortcut, pad: :one)
  end
end

def button_view_ui(shortcut)
  host = ButtonHost.new(shortcut)
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  root
end

def test_button_view_renders_a_badge_only_with_a_shortcut(args, assert)
  DragonInput.setup { |c| c.action_set(:gameplay) }
  $gtk = GtkAllFilesDouble.new

  assert.nil!(button_view_ui(nil).find(:go_badge), "no shortcut, no badge node")

  with = button_view_ui({ keyboard: :m, controller: :y })
  assert.true!(!with.find(:go_badge).nil?, "shortcut declared: the badge partial mounts")
  assert.true!(with.find(:go_badge).object.path.include?("keyboard/m"), "badge resolves the key's art")
ensure
  $gtk = $game.gtk
  DragonInput.reset!
end

# --- migrated reactive scenes: ui_scene (scroll + multi-group) + multiple_cameras ---

def ui_scene_ui
  DragonInput.setup do |c|
    c.action_set(:gameplay) { |s| s.digital(:attack, controller: :b, keyboard: :space) }
  end

  scene = UIScene.new(:smoke)
  Conjuration::UI.warnings.clear
  scene.ui.view { scene.view }
  scene.ui.render_view
  scene.ui.calculate_layout
  scene.ui
end

def test_ui_scene_reactive_layout_groups_and_scroll(args, assert)
  ui = ui_scene_ui
  assert_no_justify_fallbacks!(assert, "ui_scene")

  groups = ui.navigation_groups
  UIScene::NAV_GROUPS.each do |name|
    assert.true!(!groups[name].nil? && !groups[name].empty?, "pane #{name} has navigable members")
  end

  assert.equal!(groups[:skills].length, 7, "8 skills minus the disabled one")

  scroll = ui.find(:scroll_list)
  assert.true!(scroll.scroll?, "the list pane is a scroll container")
  assert.true!(scroll.max_scroll > 0, "16 items overflow the 240px box")
  assert.true!(groups[:list].any? { |member| member.equal?(scroll) }, "the scroll container is its pane's navigable member")

  assert.true!(!ui.find(:back_badge).nil?, "the Back shortcut badge mounts as a component")
ensure
  Conjuration::UI.focused_node = nil
  Conjuration::UI.active_navigation_group = nil
  DragonInput.reset!
end

def test_ui_scene_rerender_keeps_retained_nodes_and_groups(args, assert)
  ui = ui_scene_ui

  scroll = ui.find(:scroll_list)
  scroll.scroll_offset = 30
  button = ui.find(:button)
  skills_before = ui.navigation_groups[:skills]

  ui.render_view
  ui.calculate_layout

  assert.true!(ui.find(:scroll_list).equal?(scroll), "the scroll container survives a re-render as the same node")
  assert.equal!(scroll.scroll_offset, 30, "its scroll offset rides along")
  assert.true!(ui.find(:button).equal?(button), "the party button keeps its identity")

  skills_after = ui.navigation_groups[:skills]
  assert.equal!(skills_after.length, skills_before.length, "group size is stable across re-renders")
  skills_before.each_with_index do |member, index|
    assert.true!(skills_after[index].equal?(member), "skills member #{index} keeps its identity")
  end
ensure
  Conjuration::UI.focused_node = nil
  Conjuration::UI.active_navigation_group = nil
  DragonInput.reset!
end

def test_multiple_cameras_hud_layout(args, assert)
  DragonInput.setup { |c| c.action_set(:gameplay) }

  scene = MultipleCamerasScene.new(:smoke)
  camera = make_camera
  Conjuration::UI.warnings.clear
  camera.ui.view { scene.hud(camera) }
  camera.ui.render_view
  camera.ui.calculate_layout
  assert_no_justify_fallbacks!(assert, "multiple_cameras")

  back = camera.ui.find(:back)
  assert.true!(!back.nil? && back.interactive?, "the Back button is navigable")
  assert.true!(!camera.ui.find(:back_badge).nil?, "its shortcut badge mounts as a component")
  badge = camera.ui.find(:back_badge)
  assert.equal!(badge.object.right, back.object.right - 4, "badge pinned inside the button's corner")
ensure
  Conjuration::UI.focused_node = nil
  DragonInput.reset!
end
