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

  def shortcut_just_pressed?(_pad, name, _bindings)
    @pressed.include?(name)
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
  DragonInput.reset!
  source = Conjuration::DragonInputSource.new
  assert.false!(source.just_pressed?(:one, :ui_confirm), "not pressed before setup, no raise")

  DragonInput.setup { |c| c.action_set(:menu) }
  source.just_pressed?(:one, :ui_confirm)

  assert.true!(!DragonInput.config.action_sets[:menu].action(:ui_confirm).nil?, "injects on first query after late setup")
ensure
  DragonInput.reset!
end

def test_ui_query_bootstraps_config_without_game_setup(args, assert)
  DragonInput.reset!
  source = Conjuration::DragonInputSource.new

  assert.false!(source.just_pressed?(:one, :ui_confirm), "bootstrap query reads not-pressed")
  assert.true!(!DragonInput.config.nil?, "first reserved query bootstraps a config")

  ui_set = DragonInput.config.action_sets[:ui]
  assert.true!(!ui_set.nil?, "bootstrap creates the :ui set")
  Conjuration::UI_ACTIONS.each_key do |name|
    assert.true!(!ui_set.action(name).nil?, ":ui set gets #{name}")
  end

  host = NavMenuHost.new
  camera = menu_camera(host)
  $game.inputs = { last_active: :controller, mouse: { wheel: nil, held: false } }
  $game.input_source = source
  DragonInput.press!(:one, :ui_right)

  camera.send(:perform_input)

  assert.equal!(Conjuration::UI.focused_node.id, :right, "navigation works with no game setup at all")
ensure
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
  $game.input_source = nil
  $game.inputs = nil
  DragonInput.reset!
end

def test_game_setup_after_bootstrap_reinjects_and_wins(args, assert)
  DragonInput.reset!
  source = Conjuration::DragonInputSource.new
  source.just_pressed?(:one, :ui_confirm)
  bootstrapped = DragonInput.config

  DragonInput.setup do |c|
    c.action_set(:menu) { |s| s.digital(:ui_confirm, controller: :b, keyboard: :space) }
  end
  assert.true!(!DragonInput.config.equal?(bootstrapped), "game setup replaces the config wholesale")

  source.just_pressed?(:one, :ui_up)

  assert.true!(!DragonInput.config.action_sets[:menu].action(:ui_up).nil?, "re-injects into the new config")
  binding = DragonInput.config.action_sets[:menu].action(:ui_confirm)
  assert.equal!(binding[:controller], :b, "game's own binding wins after re-injection")
ensure
  DragonInput.reset!
end

def test_non_reserved_query_does_not_bootstrap(args, assert)
  DragonInput.reset!
  source = Conjuration::DragonInputSource.new

  assert.false!(source.just_pressed?(:one, :attack), "not pressed")
  assert.false!(source.pressed?(:one, :attack), "not held")
  assert.nil!(DragonInput.config, "non-reserved queries never create a config")
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

# A camera HUD with one shortcut-bearing button and no navigation group, so the
# shortcut is exercised with focus off.
class ShortcutHost
  include Conjuration::UI::Builder

  attr_reader :log

  def initialize
    @log = []
  end

  def view
    log = @log
    node({ x: 0, y: 0, w: 200, h: 100 }, id: :panel) do
      node({ w: 100, h: 50, primitive_marker: :solid, action: -> { log << :back } }, id: :back, shortcut: { keyboard: :escape, controller: :b })
    end
  end
end

def test_shortcut_injects_a_deterministic_gaps_only_action(args, assert)
  DragonInput.setup do |c|
    c.action_set(:menu)
    c.action_set(:gameplay)
  end
  source = Conjuration::DragonInputSource.new

  assert.false!(source.shortcut_just_pressed?(:one, :ui_shortcut_back, { keyboard: :escape, controller: :b }), "not pressed yet")

  DragonInput.config.action_sets.each_value do |set|
    binding = set.action(:ui_shortcut_back)
    assert.true!(!binding.nil?, "injected into #{set.name}")
    assert.equal!(binding[:keyboard], :escape, "keeps declared keyboard binding")
    assert.equal!(binding[:controller], :b, "keeps declared controller binding")
  end

  DragonInput.press!(:one, :ui_shortcut_back)
  assert.true!(source.shortcut_just_pressed?(:one, :ui_shortcut_back, { keyboard: :escape, controller: :b }), "reads the down edge through the facade")
ensure
  DragonInput.reset!
end

def test_shortcut_injection_is_gaps_only(args, assert)
  DragonInput.setup do |c|
    c.action_set(:menu) { |s| s.digital(:ui_shortcut_back, controller: :y, keyboard: :q) }
  end
  source = Conjuration::DragonInputSource.new
  source.shortcut_just_pressed?(:one, :ui_shortcut_back, { keyboard: :escape, controller: :b })

  binding = DragonInput.config.action_sets[:menu].action(:ui_shortcut_back)
  assert.equal!(binding[:controller], :y, "a game's own binding is not overwritten")
  assert.equal!(binding[:keyboard], :q, "a game's own binding is not overwritten")
ensure
  DragonInput.reset!
end

def test_shortcut_fires_the_action_without_focus(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  host = ShortcutHost.new
  camera = make_camera
  camera.ui.view(&host.method(:view))
  camera.ui.render_view
  camera.ui.calculate_layout
  Conjuration::UI.active_navigation_group = nil # navigation OFF
  Conjuration::UI.focused_node = nil
  $game.inputs = { last_active: :controller, mouse: { wheel: nil, held: false } }
  $game.input_source = Conjuration::DragonInputSource.new

  back = camera.ui.find(:back)
  DragonInput.press!(:one, back.shortcut_action_name)

  camera.send(:perform_input)

  assert.equal!(host.log, [:back], "the shortcut fired the action with no focus and nav off")
ensure
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
  $game.input_source = nil
  $game.inputs = nil
  DragonInput.reset!
end

def test_ui_navigate_is_injected_as_an_analog_action(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  source = Conjuration::DragonInputSource.new
  source.just_pressed?(:one, :ui_confirm) # trigger injection

  set = DragonInput.config.action_sets[:menu]
  assert.true!(!set.analogs[:ui_navigate].nil?, ":ui_navigate injected via set.analog")
  assert.true!(set.digitals[:ui_navigate].nil?, ":ui_navigate is not a digital")
  assert.equal!(set.action(:ui_navigate)[:controller], :right_analog, "bound to the right stick")
ensure
  DragonInput.reset!
end

def test_navigation_flick_fires_once_per_crossing_and_rearms(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  source = Conjuration::DragonInputSource.new

  DragonInput.deflect!(:one, :ui_navigate, 0.0, 0.0)
  assert.nil!(source.navigation_flick(:one), "neutral emits no step (and arms)")

  DragonInput.deflect!(:one, :ui_navigate, 0.9, 0.1)
  assert.equal!(source.navigation_flick(:one), { x: 1, y: 0 }, "the first crossing fires one step in the dominant axis")

  assert.nil!(source.navigation_flick(:one), "held past the threshold does not repeat")

  DragonInput.deflect!(:one, :ui_navigate, 0.0, 0.0)
  assert.nil!(source.navigation_flick(:one), "returning to neutral re-arms with no step")

  DragonInput.deflect!(:one, :ui_navigate, -0.1, -0.8)
  assert.equal!(source.navigation_flick(:one), { x: 0, y: -1 }, "the next crossing fires down (dominant axis y)")
ensure
  DragonInput.reset!
end

def test_right_stick_flick_drives_navigation(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  host = NavMenuHost.new
  camera = menu_camera(host)
  $game.inputs = { last_active: :controller, mouse: { wheel: nil, held: false } }
  $game.input_source = Conjuration::DragonInputSource.new

  DragonInput.deflect!(:one, :ui_navigate, 0.0, 0.0)
  camera.send(:perform_input) # seeds focus to :left, arms the flick

  DragonInput.deflect!(:one, :ui_navigate, 0.9, 0.0)
  camera.send(:perform_input)

  assert.equal!(Conjuration::UI.focused_node.id, :right, "a rightward stick flick moves focus to :right")
ensure
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
  $game.input_source = nil
  $game.inputs = nil
  DragonInput.reset!
end

def test_raw_source_has_no_stick_support(args, assert)
  assert.false!(FakeInputSource.new.respond_to?(:navigation_flick), "a raw keyboard-only source has no flick (untouched)")
  assert.true!(Conjuration::DragonInputSource.new.respond_to?(:navigation_flick), "the DragonInput source drives the stick")
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
