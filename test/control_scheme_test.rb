# The control-scheme seam: the one place framework UI reads raw input. Two
# concerns are covered here —
#   1. the default scheme preserves today's bindings (Enter/A, Space excluded);
#   2. a drop-in double scheme drives UIManagement's navigation and confirm
#      end-to-end, with zero changes to UIManagement (acceptance).

# A nested-hash `inputs` double. The shims give Hash a method_missing so
# `inputs.keyboard.key_down.enter` reads `[:keyboard][:key_down][:enter]`, which
# is exactly the surface the default ControlScheme touches.
def make_inputs(enter_down: false, a_down: false, enter_held: false, a_held: false, space_down: false, nav: { x: 0, y: 0 })
  {
    keyboard: {
      key_down: { enter: enter_down, space: space_down },
      key_held: { enter: enter_held }
    },
    controller_one: {
      key_down: { a: a_down },
      key_held: { a: a_held }
    },
    key_down: { directional_vector: nav }
  }
end

# A library/user scheme stand-in — the same three methods, canned answers. That
# it drives the UI unchanged is the whole point of the seam.
class FakeControlScheme
  attr_accessor :vector, :confirm, :held

  def initialize(vector: { x: 0, y: 0 }, confirm: false, held: false)
    @vector, @confirm, @held = vector, confirm, held
  end

  def navigation_vector; @vector; end
  def confirm_down?;     @confirm; end
  def confirm_held?;     @held; end
end

# A Builder host (like the reconcile host) whose view is a two-button menu pane.
# The action lambdas close over a local `log`, so they still record when
# UIManagement instance_execs them with self rebound to the camera.
class NavMenuHost
  include Conjuration::UI::Builder

  attr_reader :log

  def initialize
    @log = []
  end

  def menu_view
    log = @log
    node({ x: 0, y: 0, w: 400, h: 100 }, id: :bar, group: :menu, direction: :row, gap: 10) do
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> { log << :left } }, id: :left)
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> { log << :right } }, id: :right)
    end
  end
end

# --- default scheme: today's bindings, verbatim -------------------------------

def test_default_scheme_confirms_on_enter(args, assert)
  assert.true!(Conjuration::ControlScheme.new(make_inputs(enter_down: true)).confirm_down?, "Enter confirms")
end

def test_default_scheme_confirms_on_controller_a(args, assert)
  assert.true!(Conjuration::ControlScheme.new(make_inputs(a_down: true)).confirm_down?, "controller A confirms")
end

def test_default_scheme_excludes_space(args, assert)
  # The deliberate exclusion: games bind Space, so confirming on it double-fires.
  assert.false!(Conjuration::ControlScheme.new(make_inputs(space_down: true)).confirm_down?, "Space does not confirm")
end

def test_default_scheme_confirm_held_tracks_enter_and_a(args, assert)
  assert.true!(Conjuration::ControlScheme.new(make_inputs(enter_held: true)).confirm_held?, "Enter held presses")
  assert.true!(Conjuration::ControlScheme.new(make_inputs(a_held: true)).confirm_held?, "A held presses")
  assert.false!(Conjuration::ControlScheme.new(make_inputs).confirm_held?, "nothing held")
end

def test_default_scheme_navigation_vector_passes_through(args, assert)
  scheme = Conjuration::ControlScheme.new(make_inputs(nav: { x: 1, y: 0 }))
  assert.equal!(scheme.navigation_vector, { x: 1, y: 0 }, "reads the raw directional vector")
end

# --- game seam: default, memoized, replaceable --------------------------------

def test_game_defaults_to_the_framework_control_scheme(args, assert)
  game = Conjuration::Game.new(nil)
  scheme = game.control_scheme

  assert.true!(scheme.is_a?(Conjuration::ControlScheme), "defaults to the framework ControlScheme")
  assert.equal!(game.control_scheme.equal?(scheme), true, "memoized: one instance, not one per frame")
end

def test_game_control_scheme_is_replaceable(args, assert)
  game = Conjuration::Game.new(nil)
  fake = FakeControlScheme.new
  game.control_scheme = fake

  assert.equal!(game.control_scheme.equal?(fake), true, "an assigned scheme replaces the default")
end

# --- end-to-end: a double scheme drives UIManagement, unchanged ---------------

# Build a camera whose UI is the two-button menu pane, with navigation active.
def menu_camera(host)
  camera = make_camera
  camera.ui.view(&host.method(:menu_view))
  camera.ui.render_view
  camera.ui.calculate_layout
  Conjuration::UI.active_navigation_group = :menu
  Conjuration::UI.focused_node = nil
  camera
end

def test_double_scheme_drives_navigation(args, assert)
  host = NavMenuHost.new
  camera = menu_camera(host)
  $game.inputs = { last_active: :controller, mouse: { wheel: nil, held: false } }
  $game.control_scheme = FakeControlScheme.new(vector: { x: 1, y: 0 })

  camera.send(:perform_input) # seeds focus into :left, then navigates right

  assert.equal!(Conjuration::UI.focused_node.id, :right, "the scheme's rightward vector moves focus to :right")
ensure
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
  $game.control_scheme = nil
  $game.inputs = nil
end

def test_double_scheme_drives_confirm(args, assert)
  host = NavMenuHost.new
  camera = menu_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:right)
  $game.inputs = { last_active: :controller, mouse: { wheel: nil, held: false } }
  $game.control_scheme = FakeControlScheme.new(vector: { x: 0, y: 0 }, confirm: true)

  camera.send(:perform_input)

  assert.equal!(host.log, [:right], "confirm from the scheme fires the focused node's action")
ensure
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
  $game.control_scheme = nil
  $game.inputs = nil
end
