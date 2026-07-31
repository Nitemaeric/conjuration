# Hold-to-repeat navigation: the press edge steps at once, then a held direction
# re-fires after UI.nav_repeat_delay ticks and every UI.nav_repeat_interval after
# that. Timing comes off Kernel.tick_count (settable in the harness shims), never
# a scene clock - menus are exactly what you navigate while paused.
#
# FakeInputSource (input_source_test) already splits the two queries: `pressed:`
# is the edge and also reads as held, `held:` is a hold with no edge.

NAV_DOWN = { x: 0, y: -1 }.freeze
NAV_RIGHT = { x: 1, y: 0 }.freeze

def reset_repeat_globals
  Conjuration::UI.reset_nav_repeat!
  Conjuration::UI.nav_repeat_delay = 18
  Conjuration::UI.nav_repeat_interval = 6
  Kernel.tick_count = 0
  reset_input_globals
end

def test_the_press_edge_steps_immediately(args, assert)
  assert.equal!(Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0), NAV_DOWN, "the edge fires on the tick it arrives")
ensure
  reset_repeat_globals
end

def test_a_held_direction_waits_out_the_delay_then_repeats_on_the_interval(args, assert)
  Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0)

  quiet = (1..17).map { |tick| Conjuration::UI.navigation_step(nil, NAV_DOWN, tick) }
  assert.equal!(quiet.compact, [], "nothing fires while the initial delay runs")

  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 18), NAV_DOWN, "the delay elapsing fires the first repeat")
  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 19), "and the interval starts over")
  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 23), "still inside the interval")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 24), NAV_DOWN, "the interval elapsing fires the next repeat")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 30), NAV_DOWN, "and it keeps ticking at that cadence")
ensure
  reset_repeat_globals
end

def test_releasing_resets_the_timer(args, assert)
  Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0)
  Conjuration::UI.navigation_step(nil, NAV_DOWN, 18)
  Conjuration::UI.navigation_step(nil, nil, 19) # released

  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 20), "a fresh hold starts its delay from scratch")
  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 24), "the old cadence is gone")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 38), NAV_DOWN, "it fires a full delay after the new hold began")
ensure
  reset_repeat_globals
end

def test_a_new_direction_fires_at_once_and_restarts_the_delay(args, assert)
  Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0)
  Conjuration::UI.navigation_step(nil, NAV_DOWN, 18)

  assert.equal!(Conjuration::UI.navigation_step(NAV_RIGHT, NAV_RIGHT, 20), NAV_RIGHT, "the new press edge steps immediately")
  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_RIGHT, 24), "it does not inherit the old direction's cadence")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_RIGHT, 38), NAV_RIGHT, "its own delay is what elapses")
ensure
  reset_repeat_globals
end

def test_an_axis_flip_without_an_edge_does_not_inherit_the_timer(args, assert)
  # Releasing one axis of a held diagonal changes the direction with no new edge.
  Conjuration::UI.navigation_step({ x: 1, y: -1 }, { x: 1, y: -1 }, 0)

  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 17), "the changed direction starts a fresh hold")
  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 18), "so the old direction's due tick passes quietly")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 35), NAV_DOWN, "and it fires a delay after the change")
ensure
  reset_repeat_globals
end

def test_a_nil_delay_disables_repeat(args, assert)
  Conjuration::UI.nav_repeat_delay = nil

  assert.equal!(Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0), NAV_DOWN, "the edge still steps")
  fired = (1..120).map { |tick| Conjuration::UI.navigation_step(nil, NAV_DOWN, tick) }
  assert.equal!(fired.compact, [], "holding never repeats with repeat switched off")
ensure
  reset_repeat_globals
end

def test_repeat_settings_are_writable(args, assert)
  Conjuration::UI.nav_repeat_delay = 4
  Conjuration::UI.nav_repeat_interval = 2
  Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0)

  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 3), "the shorter delay is respected")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 4), NAV_DOWN, "first repeat at the configured delay")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 6), NAV_DOWN, "then at the configured interval")
ensure
  reset_repeat_globals
end

def test_two_queries_in_one_tick_resolve_once(args, assert)
  Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0)

  first = Conjuration::UI.navigation_step(nil, NAV_DOWN, 18)
  second = Conjuration::UI.navigation_step(nil, NAV_DOWN, 18)
  assert.equal!([first, second], [NAV_DOWN, NAV_DOWN], "both hosts see the same vector for the tick")

  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 23), "the second query did not push the next repeat out")
  assert.equal!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 24), NAV_DOWN, "the cadence is one interval, not two")
ensure
  reset_repeat_globals
end

def test_the_repeat_state_clears_with_the_other_focus_globals(args, assert)
  Conjuration::UI.navigation_step(NAV_DOWN, NAV_DOWN, 0)

  Conjuration::Scene.new(:repeat_reset_probe).send(:perform_setup)

  assert.nil!(Conjuration::UI.navigation_step(nil, NAV_DOWN, 18), "a scene change drops the held direction's timer")
ensure
  reset_repeat_globals
end

# --- through the input loop ---------------------------------------------------

class RepeatListHost
  include Conjuration::UI::Builder

  def list_view
    node({ x: 0, y: 200, w: 120, h: 200 }, id: :list, group: :menu, nav_wrap: :y, gap: 10) do
      4.times do |i|
        node({ w: 80, h: 30, primitive_marker: :solid, action: -> {} }, id: :"item_#{i}")
      end
    end
  end
end

class RepeatOtherHost
  include Conjuration::UI::Builder

  def other_view
    node({ x: 300, y: 200, w: 80, h: 80 }, id: :elsewhere, group: :other) do
      node({ w: 40, h: 40, primitive_marker: :solid, action: -> {} }, id: :stray)
    end
  end
end

class FlickOnlySource
  def initialize(vector)
    @vector = vector
  end

  def just_pressed?(_pad, _action)
    false
  end

  def pressed?(_pad, _action)
    false
  end

  def shortcut_just_pressed?(_pad, _name, _bindings)
    false
  end

  def navigation_flick(_pad)
    @vector
  end
end

def repeat_camera(host = RepeatListHost.new, view = :list_view)
  camera = make_camera
  camera.ui.view(&host.method(view))
  camera.ui.render_view
  camera.ui.calculate_layout
  Conjuration::UI.active_navigation_group = :menu
  Conjuration::UI.hovered_node = nil
  camera
end

# One frame: set the tick, then run each host's input pass with these actions.
def repeat_frame(cameras, tick, pressed: [], held: [])
  Kernel.tick_count = tick
  $game.inputs = { last_active: :controller, mouse: mouse_nowhere, controller_one: { right_analog_y_perc: 0 } }
  $game.input_source = FakeInputSource.new(pressed: pressed, held: held)
  Array(cameras).each { |camera| camera.send(:perform_input) }
end

def test_holding_a_direction_walks_the_list_through_the_input_loop(args, assert)
  camera = repeat_camera
  Conjuration::UI.focused_node = camera.ui.find(:item_0)

  repeat_frame(camera, 0, pressed: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_1, "the edge steps on the press")

  repeat_frame(camera, 10, held: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_1, "holding through the delay changes nothing")

  repeat_frame(camera, 18, held: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_2, "the delay elapsing steps again")

  repeat_frame(camera, 24, held: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_3, "and it keeps stepping on the interval")
ensure
  reset_repeat_globals
end

def test_two_hosts_in_one_tick_take_a_single_step(args, assert)
  camera = repeat_camera
  other = repeat_camera(RepeatOtherHost.new, :other_view)
  Conjuration::UI.active_navigation_group = :menu
  Conjuration::UI.focused_node = camera.ui.find(:item_0)

  repeat_frame([camera, other], 0, pressed: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_1, "two hosts, one step on the edge tick")

  repeat_frame([camera, other], 18, held: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_2, "and one step on the repeat tick")

  repeat_frame([camera, other], 24, held: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_3, "the extra host never doubled the cadence")
ensure
  reset_repeat_globals
end

def test_repeat_composes_with_wrap(args, assert)
  camera = repeat_camera
  Conjuration::UI.focused_node = camera.ui.find(:item_3)

  repeat_frame(camera, 0, pressed: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_0, "the edge at the last row wraps to the first")

  repeat_frame(camera, 18, held: [:ui_down])
  assert.equal!(Conjuration::UI.focused_node.id, :item_1, "and the repeat carries on from the top")
ensure
  reset_repeat_globals
end

def test_the_stick_flick_still_steps_once(args, assert)
  camera = repeat_camera
  Conjuration::UI.focused_node = camera.ui.find(:item_0)
  Kernel.tick_count = 0
  $game.inputs = { last_active: :controller, mouse: mouse_nowhere, controller_one: { right_analog_y_perc: 0 } }
  $game.input_source = FlickOnlySource.new(NAV_DOWN)

  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.focused_node.id, :item_1, "a flick with no digital direction still navigates")

  Kernel.tick_count = 60
  camera.send(:perform_input)
  assert.equal!(Conjuration::UI.focused_node.id, :item_2, "the flick keeps its own one-step-per-call semantics")
ensure
  reset_repeat_globals
end
