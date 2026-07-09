# The hover/focus split: the mouse drives UI.hovered_node (styling + click
# targeting) and never writes UI.focused_node, so keyboard/pad navigation
# resumes from the retained node after a mouse interlude. Drives a camera's
# perform_input with the input_source_test doubles ($game.inputs hash +
# FakeInputSource, defined there; load order doesn't matter — run.rb runs
# after every file is loaded).

class HoverNavHost
  include Conjuration::UI::Builder

  attr_reader :log

  def initialize
    @log = []
  end

  def menu_view
    log = @log
    node({ x: 0, y: 0, w: 400, h: 100 }, id: :bar, group: :menu, direction: :row, gap: 10) do
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> { log << :a } }, id: :a)
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> { log << :b } }, id: :b)
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> { log << :c } }, id: :c)
    end
  end
end

def hover_camera(host)
  camera = make_camera
  camera.ui.view(&host.method(:menu_view))
  camera.ui.render_view
  camera.ui.calculate_layout
  Conjuration::UI.active_navigation_group = :menu
  Conjuration::UI.focused_node = nil
  Conjuration::UI.hovered_node = nil
  camera
end

# The Geometry shim ignores anchors, so a point just inside the node's raw x/y
# box hits it.
def mouse_over(node, click: false, held: false)
  { x: node.object.x + 1, y: node.object.y + 1, w: 1, h: 1, wheel: nil, click: click, held: held }
end

def mouse_nowhere
  { x: -100, y: -100, w: 1, h: 1, wheel: nil, click: false, held: false }
end

def reset_input_globals
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.pressed_node = nil
  $game.input_source = nil
  $game.inputs = nil
end

def test_hover_does_not_move_focus(args, assert)
  host = HoverNavHost.new
  camera = hover_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:a)
  $game.inputs = { last_active: :mouse, mouse: mouse_over(camera.ui.find(:c)) }
  $game.input_source = FakeInputSource.new

  camera.send(:perform_input)

  assert.equal!(Conjuration::UI.focused_node.id, :a, "hovering never writes focused_node")
  assert.equal!(Conjuration::UI.hovered_node.id, :c, "the node under the mouse becomes hovered_node")
ensure
  reset_input_globals
end

def test_focus_survives_a_mouse_interlude(args, assert)
  host = HoverNavHost.new
  camera = hover_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:b)

  $game.inputs = { last_active: :mouse, mouse: mouse_over(camera.ui.find(:c)) }
  $game.input_source = FakeInputSource.new
  camera.send(:perform_input)

  # Back on the controller with no direction pressed: nothing reseeds.
  $game.inputs = { last_active: :controller, mouse: mouse_nowhere }
  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.focused_node.id, :b, "retained focus is not reseeded on device switch")
  assert.nil!(Conjuration::UI.hovered_node, "hover clears once the mouse stops being the active device")

  $game.input_source = FakeInputSource.new(pressed: [:ui_right])
  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.focused_node.id, :c, "navigation resumes from the retained node")
ensure
  reset_input_globals
end

def test_click_activates_the_hovered_node_not_the_focused_one(args, assert)
  host = HoverNavHost.new
  camera = hover_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:a)
  $game.inputs = { last_active: :mouse, mouse: mouse_over(camera.ui.find(:c), click: true) }
  $game.input_source = FakeInputSource.new

  camera.send(:perform_input)

  assert.equal!(host.log, [:c], "the click fires the hovered node's action")
  assert.equal!(Conjuration::UI.focused_node.id, :a, "the click leaves focus untouched")
ensure
  reset_input_globals
end

def test_confirm_activates_the_focused_node_not_the_hovered_one(args, assert)
  host = HoverNavHost.new
  camera = hover_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:a)
  Conjuration::UI.hovered_node = camera.ui.find(:c) # stale from a mouse frame
  $game.inputs = { last_active: :controller, mouse: mouse_nowhere }
  $game.input_source = FakeInputSource.new(pressed: [:ui_confirm])

  camera.send(:perform_input)

  assert.equal!(host.log, [:a], "confirm fires the focused node's action")
ensure
  reset_input_globals
end

def test_ensure_focus_seeds_only_without_a_retained_focus(args, assert)
  host = HoverNavHost.new
  camera = hover_camera(host)
  $game.inputs = { last_active: :controller, mouse: mouse_nowhere }
  $game.input_source = FakeInputSource.new

  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.focused_node.id, :a, "no focus: the active group's first member is seeded")

  Conjuration::UI.focused_node = camera.ui.find(:c)
  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.focused_node.id, :c, "a retained focus in the group is left alone")
ensure
  reset_input_globals
end

def test_pressed_node_splits_between_mouse_and_confirm(args, assert)
  host = HoverNavHost.new
  camera = hover_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:a)

  $game.inputs = { last_active: :mouse, mouse: mouse_over(camera.ui.find(:c), held: true) }
  $game.input_source = FakeInputSource.new
  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.pressed_node.id, :c, "a held mouse presses the hovered node")

  $game.inputs = { last_active: :controller, mouse: mouse_nowhere }
  $game.input_source = FakeInputSource.new(held: [:ui_confirm])
  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.pressed_node.id, :a, "a held confirm presses the focused node")
ensure
  reset_input_globals
end

def test_focus_indicator_hides_while_the_mouse_is_active(args, assert)
  host = HoverNavHost.new
  camera = hover_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:a)
  Conjuration::UI.focus_cursor[:w] = 0

  $game.inputs = { last_active: :mouse, mouse: mouse_nowhere }
  assert.nil!(camera.send(:focus_indicator), "no indicator while the mouse is the active device")

  $game.inputs = { last_active: :keyboard, mouse: mouse_nowhere }
  assert.true!(camera.send(:focus_indicator), "the indicator returns with the keyboard")
ensure
  reset_input_globals
  Conjuration::UI.focus_cursor[:w] = 0
end

def test_scene_setup_resets_hover_and_press(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 100, h: 100 }, id: :root) do
    node({ x: 0, y: 0, w: 50, h: 50, action: -> {} }, id: :stale)
  end
  Conjuration::UI.hovered_node = ui.find(:stale)
  Conjuration::UI.pressed_node = ui.find(:stale)
  Conjuration::UI.focused_node = ui.find(:stale)

  Conjuration::Scene.new(:hover_reset_probe).send(:perform_setup)

  assert.nil!(Conjuration::UI.hovered_node, "scene change clears hovered_node")
  assert.nil!(Conjuration::UI.pressed_node, "scene change clears pressed_node")
  assert.nil!(Conjuration::UI.focused_node, "scene change clears focused_node")
ensure
  reset_input_globals
end

# --- ButtonView demo states -----------------------------------------------

class HoverButtonHost
  include Conjuration::UI::Builder

  def button_view
    node({ x: 0, y: 0, w: 400, h: 200 }, id: :wrap, group: :menu) do
      ButtonView(id: :go, label: "Go", action: -> {}, pad: :one)
    end
  end
end

def hover_button_ui
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  ui.view(&HoverButtonHost.new.method(:button_view))
  ui.render_view
  ui.calculate_layout
  ui
end

def test_button_view_default_state_has_no_overlays(args, assert)
  ui = hover_button_ui

  assert.nil!(ui.find(:go_sheen), "no hover sheen by default")
  assert.nil!(ui.find(:go_fb_tl_h), "no focus brackets by default")
ensure
  reset_input_globals
end

def test_button_view_hover_adds_the_sheen(args, assert)
  ui = hover_button_ui
  Conjuration::UI.hovered_node = ui.find(:go)
  $game.inputs = { last_active: :mouse, mouse: mouse_nowhere }

  ui.render_view
  ui.calculate_layout

  assert.true!(ui.find(:go_sheen), "hover emits the additive sheen overlay")
  assert.nil!(ui.find(:go_fb_tl_h), "hover draws no focus brackets")
  assert.equal!(ui.find(:go).interaction_state, :hover, "the button reports the hover state")
ensure
  reset_input_globals
end

def test_button_view_focus_draws_pulsing_brackets(args, assert)
  ui = hover_button_ui
  Conjuration::UI.focused_node = ui.find(:go)
  $game.inputs = { last_active: :keyboard, mouse: mouse_nowhere }

  ui.render_view
  ui.calculate_layout

  bracket = ui.find(:go_fb_tl_h)
  assert.true!(bracket, "focus emits the corner brackets")
  assert.equal!(bracket.object.a, 195, "the pulse is keyed to the game clock (frozen at 0 -> sin(0) -> 195)")
  assert.equal!(bracket.object.x, ui.find(:go).object.left - ButtonView::BRACKET_REACH, "the bracket overhangs the corner")
  assert.nil!(ui.find(:go_sheen), "focus draws no hover sheen")
ensure
  reset_input_globals
end

def test_button_view_focus_brackets_hide_while_the_mouse_is_active(args, assert)
  ui = hover_button_ui
  Conjuration::UI.focused_node = ui.find(:go)
  $game.inputs = { last_active: :mouse, mouse: mouse_nowhere }

  ui.render_view
  ui.calculate_layout

  assert.nil!(ui.find(:go_fb_tl_h), "brackets follow the framework rule: hidden while the mouse is active")
ensure
  reset_input_globals
end
