# Opt-in wrap-around navigation (nav_wrap: on the node declaring the group):
# a press that finds nothing ahead lands on the far end instead of staying put.
# Reuses the input doubles and press_nav/mouse helpers from the input_source,
# hover_focus and nav_scroll suites (every file is preloaded before run.rb).

def wrap_column_ui(nav_wrap: true)
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 100, h: 300 }, id: :col, group: :menu, nav_wrap: nav_wrap, gap: 10) do
      node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :a)
      node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :b)
      node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :c)
    end
  end
end

def wrap_row_ui
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 300, h: 60 }, id: :row, group: :menu, nav_wrap: true, direction: :row, gap: 10) do
      node({ w: 60, h: 40, primitive_marker: :solid, action: -> {} }, id: :a)
      node({ w: 60, h: 40, primitive_marker: :solid, action: -> {} }, id: :b)
      node({ w: 60, h: 40, primitive_marker: :solid, action: -> {} }, id: :c)
    end
  end
end

# Two columns side by side: wrapping must stay inside the source's own column.
def wrap_grid_ui
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 300, h: 300 }, id: :grid, group: :menu, nav_wrap: true, direction: :row, gap: 60) do
      node({ w: 80, h: 300 }, id: :col_a, gap: 20) do
        node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :a1)
        node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :a2)
      end
      node({ w: 80, h: 300 }, id: :col_b, gap: 20) do
        node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :b1)
        node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :b2)
      end
    end
  end
end

def navigate_in_group(ui, from, direction, group: :menu)
  ui.spatial_navigate(ui.find(from), direction, candidates: ui.navigation_groups[group], wrap: ui.navigation_group_wrap?(group))
end

def test_down_at_the_bottom_wraps_to_the_top(args, assert)
  ui = wrap_column_ui

  target = navigate_in_group(ui, :c, { x: 0, y: -1 })

  assert.equal!(target.id, :a, "the last item wraps onto the first")
end

def test_up_at_the_top_wraps_to_the_bottom(args, assert)
  ui = wrap_column_ui

  target = navigate_in_group(ui, :a, { x: 0, y: 1 })

  assert.equal!(target.id, :c, "the first item wraps onto the last")
end

def test_wrapping_only_happens_at_the_edge(args, assert)
  ui = wrap_column_ui

  assert.equal!(navigate_in_group(ui, :a, { x: 0, y: -1 }).id, :b, "a step with a neighbour ahead is unaffected")
  assert.equal!(navigate_in_group(ui, :b, { x: 0, y: 1 }).id, :a, "and so is a step back up")
end

def test_horizontal_wrap(args, assert)
  ui = wrap_row_ui

  assert.equal!(navigate_in_group(ui, :c, { x: 1, y: 0 }).id, :a, "right at the right edge wraps to the leftmost")
  assert.equal!(navigate_in_group(ui, :a, { x: -1, y: 0 }).id, :c, "left at the left edge wraps to the rightmost")
end

def test_wrap_prefers_the_sources_own_column(args, assert)
  ui = wrap_grid_ui

  assert.equal!(navigate_in_group(ui, :a2, { x: 0, y: -1 }).id, :a1, "wrapping down stays in column A")
  assert.equal!(navigate_in_group(ui, :b2, { x: 0, y: -1 }).id, :b1, "and in column B from column B")
  assert.equal!(navigate_in_group(ui, :b1, { x: 0, y: 1 }).id, :b2, "wrapping up likewise")
end

def test_wrap_falls_back_to_the_nearest_candidate_when_nothing_aligns(args, assert)
  # A staggered column: no candidate shares :low's cross-axis span, so the far-end
  # pick is decided by nearness to the source's axis instead.
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 300, h: 300 }, id: :stack, group: :menu, nav_wrap: true) do
      node({ x: 10, y: 300, w: 40, h: 20, primitive_marker: :solid, action: -> {} }, id: :near_top, position: :absolute, top: 0, left: 10)
      node({ x: 200, y: 300, w: 40, h: 20, primitive_marker: :solid, action: -> {} }, id: :far_top, position: :absolute, top: 0, left: 200)
      node({ x: 10, y: 20, w: 40, h: 20, primitive_marker: :solid, action: -> {} }, id: :low, position: :absolute, bottom: 0, left: 100)
    end
  end

  target = navigate_in_group(ui, :low, { x: 0, y: -1 })

  assert.equal!(target.id, :near_top, "an unaligned wrap reaches the far end, nearest the source's axis")
end

def test_no_wrap_without_the_flag(args, assert)
  ui = wrap_column_ui(nav_wrap: false)

  assert.equal!(ui.navigation_group_wrap?(:menu), false, "the group does not wrap")
  assert.nil!(navigate_in_group(ui, :c, { x: 0, y: -1 }), "down at the bottom stays put, as before")
  assert.nil!(navigate_in_group(ui, :a, { x: 0, y: 1 }), "and up at the top")
end

def test_wrap_defaults_off_and_spatial_navigate_keeps_its_old_signature(args, assert)
  ui = wrap_column_ui

  assert.nil!(ui.spatial_navigate(ui.find(:c), { x: 0, y: -1 }, candidates: ui.navigation_groups[:menu]), "wrap: is opt-in per call")
  assert.equal!(ui.spatial_navigate(ui.find(:a), { x: 0, y: -1 }).id, :b, "the two-argument form still works")
end

# --- the flag through the reconciler ------------------------------------------

class WrapToggleHost
  include Conjuration::UI::Builder

  attr_accessor :wrapping

  def initialize
    @wrapping = true
  end

  def menu_view
    node({ x: 0, y: 0, w: 100, h: 300 }, id: :col, group: :menu, nav_wrap: @wrapping, gap: 10) do
      node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :a)
      node({ w: 80, h: 40, primitive_marker: :solid, action: -> {} }, id: :b)
    end
  end
end

def test_nav_wrap_reconciles_frame_to_frame(args, assert)
  host = WrapToggleHost.new
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  ui.view(&host.method(:menu_view))
  ui.render_view
  ui.calculate_layout

  assert.equal!(ui.navigation_group_wrap?(:menu), true, "a declared nav_wrap reaches the group registry")

  host.wrapping = false
  ui.render_view
  ui.calculate_layout

  assert.equal!(ui.navigation_group_wrap?(:menu), false, "turning it off re-derives the registry")
  assert.nil!(navigate_in_group(ui, :b, { x: 0, y: -1 }), "and navigation stops wrapping")
end

# --- wrapping into a scroll pane ----------------------------------------------

class WrapListHost
  include Conjuration::UI::Builder

  def list_view
    node({ x: 0, y: 300, w: 120, h: 100, path: :pixel }, id: :pane, overflow: :scroll, group: :list, nav_wrap: true, justify: :start, align: :start, gap: 10) do
      5.times do |i|
        node({ w: 80, h: 30, primitive_marker: :solid, action: -> {} }, id: :"item_#{i}")
      end
    end
  end
end

def wrap_list_camera
  camera = make_camera
  camera.ui.view(&WrapListHost.new.method(:list_view))
  camera.ui.render_view
  camera.ui.calculate_layout
  Conjuration::UI.active_navigation_group = :list
  Conjuration::UI.focused_node = nil
  Conjuration::UI.hovered_node = nil
  camera
end

def test_wrapping_down_onto_the_top_row_scrolls_the_pane_back(args, assert)
  camera = wrap_list_camera
  pane = camera.ui.find(:pane)
  Conjuration::UI.focused_node = camera.ui.find(:item_4)
  pane.scroll_offset = 90

  press_nav(camera, :ui_down)

  assert.equal!(Conjuration::UI.focused_node.id, :item_0, "the bottom row wraps onto the top one")
  assert.equal!(pane.scroll_offset, 0, "and the pane scrolls back to reveal it, with item_1 ahead of it in view")
  assert.true!(camera.ui.find(:item_1).object.bottom + pane.scroll_offset >= pane.object.bottom, "the lookahead row is visible too")
ensure
  reset_input_globals
end

def test_wrapping_up_onto_the_last_row_scrolls_the_pane_down(args, assert)
  camera = wrap_list_camera
  pane = camera.ui.find(:pane)
  Conjuration::UI.focused_node = camera.ui.find(:item_0)

  press_nav(camera, :ui_up)

  assert.equal!(Conjuration::UI.focused_node.id, :item_4, "the top row wraps onto the bottom one")
  assert.equal!(pane.scroll_offset, 90, "the pane scrolls to the end to reveal it")
ensure
  reset_input_globals
end
