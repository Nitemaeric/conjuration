# Debug overlays (roadmap H1): per-camera world-space introspection drawn into
# the camera's viewport, and the game's screen-space state panel. Every emission
# is debug?-gated — the helpers build nothing when debug is off.

def with_debug_game
  $game.debug = true
  yield
ensure
  $game.debug = false
end

# --- Camera overlay ---------------------------------------------------------

def test_camera_overlay_emits_nothing_when_debug_off(args, assert)
  cam = make_camera
  cam.outputs.debug.clear

  cam.send(:render_debug_overlay)

  assert.equal!(cam.outputs.debug.length, 0, "no debug primitives are emitted when debug? is false")
end

def test_camera_overlay_emits_when_debug_on(args, assert)
  with_debug_game do
    cam = make_camera
    cam.outputs.debug.clear

    cam.send(:render_debug_overlay)

    assert.true!(cam.outputs.debug.length > 0, "the overlay emits primitives when debug? is true")
  end
end

def test_camera_overlay_view_rect_outline_matches_view_rect(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  outline = cam.send(:debug_view_rect_outline)
  view = cam.view_rect

  assert.equal!(outline[:x], view[:x], "outline x matches view_rect")
  assert.equal!(outline[:y], view[:y], "outline y matches view_rect")
  assert.equal!(outline[:w], view[:w], "outline w matches view_rect")
  assert.equal!(outline[:h], view[:h], "outline h matches view_rect")
  assert.equal!(outline[:primitive_marker], :border, "the outline is a border primitive")
end

def test_camera_overlay_focal_markers_centre_on_current(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  markers = cam.send(:debug_focal_markers)
  current_vp = cam.to_viewport({ x: cam.current.x, y: cam.current.y })

  horizontal = markers.first
  radius = Conjuration::Camera::DEBUG_MARKER_RADIUS
  assert.close!(horizontal[:x] + radius, current_vp[:x], "the current crosshair centres on current x")
  assert.close!(horizontal[:y], current_vp[:y], "the current crosshair sits on current's row")
end

# The link between current and target is the white line; the crosshairs are
# coloured lines, so it is identified by colour, not by primitive_marker alone.
def focal_link(markers)
  markers.find { |m| m[:primitive_marker] == :line && m[:r] == 255 && m[:g] == 255 && m[:b] == 255 }
end

def test_camera_overlay_links_current_to_target_only_when_they_differ(args, assert)
  same = make_camera(current: { x: 640, y: 360, zoom: 1 })
  assert.nil!(focal_link(same.send(:debug_focal_markers)),
              "no link line when current and target coincide")

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  cam.look_at(x: 900, y: 500)
  line = focal_link(cam.send(:debug_focal_markers))
  current_vp = cam.to_viewport({ x: cam.current.x, y: cam.current.y })
  target_vp = cam.to_viewport({ x: cam.target.x, y: cam.target.y })

  assert.true!(!line.nil?, "a link line appears when current and target differ")
  assert.close!(line[:x], current_vp[:x], "the link starts at current x")
  assert.close!(line[:x2], target_vp[:x], "the link ends at target x")
  assert.close!(line[:y2], target_vp[:y], "the link ends at target y")
end

def test_camera_overlay_follow_marker_only_while_following(args, assert)
  with_debug_game do
    cam = make_camera(current: { x: 640, y: 360, zoom: 1 })

    cam.outputs.debug.clear
    cam.send(:render_debug_overlay)
    assert.false!(cam.outputs.debug.any? { |p| p[:g] == 160 && p[:b] == 255 },
                  "no follow marker before a follow starts")

    cam.follow({ x: 800, y: 500 })
    cam.outputs.debug.clear
    cam.send(:render_debug_overlay)
    assert.true!(cam.outputs.debug.any? { |p| p[:g] == 160 && p[:b] == 255 },
                 "a follow marker appears once following")
  end
end

def test_camera_overlay_follow_marker_centres_on_target(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  cam.follow({ x: 800, y: 500 })
  marker = cam.send(:debug_follow_marker)
  target_vp = cam.to_viewport({ x: 800, y: 500 })

  assert.close!(marker[:x] + marker[:w] / 2, target_vp[:x], "follow marker centres on the object x")
  assert.close!(marker[:y] + marker[:h] / 2, target_vp[:y], "follow marker centres on the object y")
end

def test_camera_overlay_world_bounds_only_with_virtual_bounds(args, assert)
  with_debug_game do
    unbounded = make_camera
    unbounded.outputs.debug.clear
    unbounded.send(:render_debug_overlay)
    assert.false!(unbounded.outputs.debug.any? { |p| p[:g] == 140 },
                  "no world-bounds rect for an unbounded scene")

    bounded = make_camera(scene_virtual: 4000)
    bounded.outputs.debug.clear
    bounded.send(:render_debug_overlay)
    assert.true!(bounded.outputs.debug.any? { |p| p[:g] == 140 },
                 "a world-bounds rect is emitted when the scene has virtual bounds")
  end
end

def test_camera_overlay_readout_reports_name_position_and_follow(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  text = cam.send(:debug_readout_labels).map { |label| label[:text] }.join(" ")

  assert.true!(text.include?("test"), "the readout names the camera")
  assert.true!(text.include?("x 640"), "the readout shows the focal x")
  assert.true!(text.include?("follow off"), "the readout shows the idle follow state")

  cam.follow({ x: 1, y: 1 })
  following_text = cam.send(:debug_readout_labels).map { |label| label[:text] }.join(" ")
  assert.true!(following_text.include?("follow on"), "the readout flips to follow on")
end

# --- Game/scene panel -------------------------------------------------------

class PanelCameraDouble
  attr_reader :name
  def initialize(name); @name = name; end
end

class PanelSceneDouble
  attr_reader :focused_camera
  def initialize(camera); @focused_camera = camera; end
  def name; :arena; end
  def perform_setup; end
  def perform_input; end
  def perform_update; end
  def perform_render; end
end

class PanelArgsDouble
  def outputs; @outputs ||= OutputsDouble.new; end
end

def panel_game
  game = Conjuration::Game.new(PanelArgsDouble.new)
  game.current_scene = PanelSceneDouble.new(PanelCameraDouble.new(:main))
  game
end

def test_game_panel_reports_scene_clock_and_camera(args, assert)
  game = panel_game
  game.tick # advance the clock once

  text = game.send(:game_debug_panel_lines).join(" | ")

  assert.true!(text.include?("PanelSceneDouble"), "the panel names the scene class")
  assert.true!(text.include?("arena"), "the panel shows the scene name")
  assert.true!(text.include?("clock: 1"), "the panel shows the game clock")
  assert.true!(text.include?("main"), "the panel shows the focused camera name")
end

def test_game_panel_reports_hit_stop_remaining(args, assert)
  game = panel_game
  game.hit_stop(3)
  game.tick # consumes one frozen frame

  text = game.send(:game_debug_panel_lines).join(" | ")
  assert.true!(text.include?("hit-stop: 2"), "the panel shows the remaining hit-stop frames")
end

def test_game_panel_emits_one_label_per_line_when_debug_on(args, assert)
  game = panel_game
  game.debug = true

  game.send(:render_game_debug_panel)

  lines = game.send(:game_debug_panel_lines)
  assert.equal!(game.outputs.debug.length, lines.length + 1, "a backing rect plus one label per panel line")
  backing = game.outputs.debug.first
  assert.true!(backing[:text].nil? && backing[:a] && backing[:a] < 255, "the first primitive is a translucent backing")
  assert.true!(game.outputs.debug.drop(1).all? { |p| p[:text] }, "every primitive after the backing is a label")
end

def test_game_panel_emits_nothing_when_debug_off(args, assert)
  game = panel_game

  game.send(:render_game_debug_panel)

  assert.equal!(game.outputs.debug.length, 0, "the panel builds nothing when debug? is false")
end
