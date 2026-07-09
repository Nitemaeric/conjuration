# A fake action source satisfying the contract by naming which reserved actions
# are down this tick (edges) and which are held. Drives the end-to-end UI tests.
class FakeInputSource
  def initialize(pressed: [], held: [])
    @pressed = pressed
    @held = held
  end

  def just_pressed?(_pad, action)
    @pressed.include?(action)
  end

  def pressed?(_pad, action)
    @held.include?(action) || @pressed.include?(action)
  end
end

# The action lambdas close over a local `log` because UIManagement instance_execs
# them with self rebound to the camera, so `@log` would not resolve.
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

# --- Game wiring: default source + opt-out ----------------------------------

def test_game_defaults_to_dragon_input_source(args, assert)
  game = Conjuration::Game.new(nil)
  source = game.input_source

  assert.true!(source.is_a?(Conjuration::DragonInputSource), "defaults to the DragonInput wrapper")
  assert.equal!(game.input_source.equal?(source), true, "memoized: one source, not one per frame")
end

def test_game_input_source_is_replaceable(args, assert)
  game = Conjuration::Game.new(nil)
  fake = FakeInputSource.new
  game.input_source = fake

  assert.equal!(game.input_source.equal?(fake), true, "an assigned source replaces the default")
end

def test_game_explicit_assignment_opts_out(args, assert)
  game = Conjuration::Game.new(nil)
  game.input_source = nil

  assert.nil!(game.input_source, "any explicit assignment disables the default")
end

# --- End-to-end: a fake source drives navigation and confirm ----------------

def menu_camera(host)
  camera = make_camera
  camera.ui.view(&host.method(:menu_view))
  camera.ui.render_view
  camera.ui.calculate_layout
  Conjuration::UI.active_navigation_group = :menu
  Conjuration::UI.focused_node = nil
  camera
end

def test_source_drives_navigation(args, assert)
  host = NavMenuHost.new
  camera = menu_camera(host)
  $game.inputs = { last_active: :controller, mouse: { wheel: nil, held: false } }
  $game.input_source = FakeInputSource.new(pressed: [:ui_right])

  camera.send(:perform_input)

  assert.equal!(Conjuration::UI.focused_node.id, :right, "a rightward edge moves focus to :right")
ensure
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
  $game.input_source = nil
  $game.inputs = nil
end

def test_source_drives_confirm(args, assert)
  host = NavMenuHost.new
  camera = menu_camera(host)
  Conjuration::UI.focused_node = camera.ui.find(:right)
  $game.inputs = { last_active: :controller, mouse: { wheel: nil, held: false } }
  $game.input_source = FakeInputSource.new(pressed: [:ui_confirm])

  camera.send(:perform_input)

  assert.equal!(host.log, [:right], "a confirm edge fires the focused node's action")
ensure
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
  $game.input_source = nil
  $game.inputs = nil
end

# --- Implicit dragon_input integration --------------------------------------

def test_dragon_input_injects_missing_actions_into_every_set(args, assert)
  DragonInput.setup do |c|
    c.action_set(:gameplay) { |s| s.digital(:jump, controller: :a, keyboard: :space) }
    c.action_set(:menu)
  end

  source = Conjuration::DragonInputSource.new
  source.just_pressed?(:one, :ui_confirm)

  Conjuration::UI_ACTIONS.each_key do |name|
    assert.true!(!DragonInput.config.action_sets[:gameplay].action(name).nil?, "gameplay gets #{name}")
    assert.true!(!DragonInput.config.action_sets[:menu].action(name).nil?, "menu gets #{name}")
  end

  assert.true!(!DragonInput.config.action_sets[:gameplay].action(:jump).nil?, "game-supplied :jump kept")
ensure
  DragonInput.reset!
end

def test_dragon_input_does_not_overwrite_custom_binding(args, assert)
  DragonInput.setup do |c|
    c.action_set(:menu) { |s| s.digital(:ui_confirm, controller: :b, keyboard: :space) }
  end

  source = Conjuration::DragonInputSource.new
  source.just_pressed?(:one, :ui_confirm)

  binding = DragonInput.config.action_sets[:menu].action(:ui_confirm)
  assert.equal!(binding[:controller], :b, "custom controller binding kept")
  assert.equal!(binding[:keyboard], :space, "custom keyboard binding kept")
ensure
  DragonInput.reset!
end

def test_dragon_input_reads_through_contract(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  source = Conjuration::DragonInputSource.new

  assert.false!(source.just_pressed?(:one, :ui_confirm), "not pressed before a press")
  DragonInput.press!(:one, :ui_confirm)
  assert.true!(source.just_pressed?(:one, :ui_confirm), "reads the down edge through the facade")
ensure
  DragonInput.reset!
end

def test_dragon_input_injection_is_lazy(args, assert)
  # Source chosen before setup — mirrors Conjuration booting before the game
  # calls DragonInput.setup.
  source = Conjuration::DragonInputSource.new
  assert.false!(source.just_pressed?(:one, :ui_confirm), "no config yet: not pressed, no raise")

  DragonInput.setup { |c| c.action_set(:menu) }
  source.just_pressed?(:one, :ui_confirm)

  assert.true!(!DragonInput.config.action_sets[:menu].action(:ui_confirm).nil?, "injects on first query after late setup")
ensure
  DragonInput.reset!
end

def test_dragon_input_unknown_action_is_false(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  source = Conjuration::DragonInputSource.new

  assert.false!(source.just_pressed?(:one, :ui_teleport), "unknown action reads as not pressed")
  assert.false!(source.pressed?(:one, :ui_teleport), "unknown action reads as not held")
ensure
  DragonInput.reset!
end

def test_game_default_source_injects_after_late_setup(args, assert)
  game = Conjuration::Game.new(nil)
  source = game.input_source
  assert.true!(source.is_a?(Conjuration::DragonInputSource), "unassigned game picks DragonInput")

  DragonInput.setup { |c| c.action_set(:menu) }
  source.just_pressed?(:one, :ui_up)

  assert.true!(!DragonInput.config.action_sets[:menu].action(:ui_up).nil?, "injects even though setup ran after boot")
ensure
  DragonInput.reset!
end
