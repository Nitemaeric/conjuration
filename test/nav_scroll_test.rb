# Navigation inside scroll panes: a pane holding interactive items is not itself
# a navigation target (its items represent it), and moving focus scrolls the pane
# so the focused item AND the one it leads to next are visible.
#
# Geometry of ScrollNavHost's list (layout rects are unshifted; screen y =
# layout y + scroll_offset):
#
#   pane box  top 400, bottom 300, max_scroll 90
#   item_0    400..370   item_1  360..330   item_2  320..290
#   item_3    280..250   item_4  240..210

class ScrollNavHost
  include Conjuration::UI::Builder

  attr_reader :log

  def initialize
    @log = []
  end

  def list_view
    log = @log
    node({ x: 0, y: 300, w: 120, h: 100, path: :pixel }, id: :pane, overflow: :scroll, group: :list, justify: :start, align: :start, gap: 10) do
      5.times do |i|
        node({ w: 80, h: 30, primitive_marker: :solid, action: -> { log << i } }, id: :"item_#{i}")
      end
    end
  end

  # No interactive descendants: the pane stays focusable so it can be scrolled.
  def prose_view
    node({ x: 0, y: 300, w: 120, h: 100, path: :pixel }, id: :pane, overflow: :scroll, group: :list, justify: :start, align: :start) do
      node({ w: 80, h: 300, primitive_marker: :solid }, id: :prose)
    end
  end
end

def scroll_nav_camera(view = :list_view)
  camera = make_camera
  camera.ui.view(&ScrollNavHost.new.method(view))
  camera.ui.render_view
  camera.ui.calculate_layout
  Conjuration::UI.active_navigation_group = :list
  Conjuration::UI.focused_node = nil
  Conjuration::UI.hovered_node = nil
  camera
end

def nav_inputs(device: :controller, stick: 0)
  { last_active: device, mouse: mouse_nowhere, controller_one: { right_analog_y_perc: stick } }
end

# One frame of input with the given actions edge-pressed.
def press_nav(camera, *actions, stick: 0)
  $game.inputs = nav_inputs(stick: stick)
  $game.input_source = FakeInputSource.new(pressed: actions)
  camera.send(:perform_input)
end

def test_pane_with_interactive_items_is_not_a_navigation_candidate(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)

  assert.true!(pane.interactive?, "the pane stays interactive for hit-testing and hover")
  assert.equal!(pane.navigable?, false, "but its items represent it in navigation")
  assert.equal!(camera.ui.navigation_groups[:list].map(&:id), [:item_0, :item_1, :item_2, :item_3, :item_4], "the group is the rows, not the pane")
  assert.true!(camera.ui.navigable_nodes.none? { |node| node.equal?(pane) }, "and it is out of the global candidate list too")
ensure
  reset_input_globals
end

def test_pane_without_interactive_items_stays_navigable(args, assert)
  camera = scroll_nav_camera(:prose_view)
  pane = camera.ui.find(:pane)

  assert.true!(pane.scroll?, "sanity: the prose overflows into a scroll pane")
  assert.true!(pane.navigable?, "an empty pane is still a navigation target, so it can be stick-scrolled")
  assert.equal!(camera.ui.navigation_groups[:list].map(&:id), [:pane], "it is its group's only member")
ensure
  reset_input_globals
end

def test_navigating_down_scrolls_the_next_item_into_view(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)
  Conjuration::UI.focused_node = camera.ui.find(:item_0)

  press_nav(camera, :ui_down)
  assert.equal!(Conjuration::UI.focused_node.id, :item_1, "focus steps one item at a time")
  assert.equal!(pane.scroll_offset, 10, "the pane scrolls just enough to reveal item_2, the lookahead")

  press_nav(camera, :ui_down)
  assert.equal!(Conjuration::UI.focused_node.id, :item_2, "the next step lands on the revealed item")
  assert.equal!(pane.scroll_offset, 50, "and reveals item_3 in turn")
ensure
  reset_input_globals
end

def test_scroll_offset_clamps_at_the_end_of_the_list(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)
  Conjuration::UI.focused_node = camera.ui.find(:item_3)
  pane.scroll_offset = 50

  press_nav(camera, :ui_down)

  assert.equal!(Conjuration::UI.focused_node.id, :item_4, "the last item is reachable")
  assert.equal!(pane.scroll_offset, 90, "with no item after it the offset stops at max_scroll")
  assert.equal!(pane.max_scroll, 90, "sanity: that is the clamp, not a coincidence")
ensure
  reset_input_globals
end

def test_navigating_up_reveals_the_preceding_item_and_clamps_at_the_top(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)
  Conjuration::UI.focused_node = camera.ui.find(:item_3)
  pane.scroll_offset = 90

  press_nav(camera, :ui_up)
  assert.equal!(Conjuration::UI.focused_node.id, :item_2, "focus walks back up one item")
  assert.equal!(pane.scroll_offset, 40, "scrolling back reveals item_1 above it")

  press_nav(camera, :ui_up)
  assert.equal!(Conjuration::UI.focused_node.id, :item_1, "and again")
  assert.equal!(pane.scroll_offset, 0, "revealing item_0 puts the list back at the top")

  press_nav(camera, :ui_up)
  assert.equal!(Conjuration::UI.focused_node.id, :item_0, "reaching the first item")
  assert.equal!(pane.scroll_offset, 0, "with nothing above it the offset clamps at 0")
ensure
  reset_input_globals
end

def test_seeded_focus_reveals_itself_without_lookahead(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)
  pane.scroll_offset = 90

  press_nav(camera)

  assert.equal!(Conjuration::UI.focused_node.id, :item_0, "activating the group seeds its first member")
  assert.equal!(pane.scroll_offset, 0, "the seeded node is revealed, but nothing is scrolled for a lookahead")
ensure
  reset_input_globals
end

def test_hovering_an_item_never_scrolls_its_pane(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)
  pane.scroll_offset = 30
  $game.inputs = { last_active: :mouse, mouse: mouse_over(camera.ui.find(:item_1)), controller_one: { right_analog_y_perc: 0 } }
  $game.input_source = FakeInputSource.new

  camera.send(:perform_input)

  assert.equal!(pane.scroll_offset, 30, "the mouse points without scrolling")
ensure
  reset_input_globals
end

def test_focus_indicator_follows_the_panes_scroll_offset(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)
  item = camera.ui.find(:item_2)
  Conjuration::UI.focused_node = item
  $game.inputs = nav_inputs(device: :keyboard)

  Conjuration::UI.focus_cursor[:w] = 0
  camera.send(:focus_indicator)
  assert.equal!(Conjuration::UI.focus_cursor[:y], item.object.bottom, "unscrolled, the indicator sits on the layout rect")

  pane.scroll_offset = 40
  Conjuration::UI.focus_cursor[:w] = 0
  camera.send(:focus_indicator)
  assert.equal!(Conjuration::UI.focus_cursor[:y], item.object.bottom + 40, "scrolled, it follows the drawn position")
ensure
  reset_input_globals
  Conjuration::UI.focus_cursor[:w] = 0
end

def test_right_stick_scrolls_the_pane_holding_focus(args, assert)
  camera = scroll_nav_camera
  pane = camera.ui.find(:pane)
  Conjuration::UI.focused_node = camera.ui.find(:item_0)

  press_nav(camera, stick: -0.5)

  assert.equal!(pane.scroll_offset, 7, "the stick scrolls the enclosing pane of the focused item")
ensure
  reset_input_globals
end

def test_right_stick_still_scrolls_a_focused_empty_pane(args, assert)
  camera = scroll_nav_camera(:prose_view)
  pane = camera.ui.find(:pane)
  Conjuration::UI.focused_node = pane

  press_nav(camera, stick: -0.5)

  assert.equal!(pane.scroll_offset, 7, "a focused pane scrolls itself, as before")
ensure
  reset_input_globals
end
