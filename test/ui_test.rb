# Characterization tests for the UI layout core (Conjuration::UI::Node).
#
# Note: the root node is an absolute canvas — calculate_layout only positions a
# node's children when `id != :root`. So flex layout is exercised inside a
# non-root :container that has explicit bounds; its children get laid out.
#
# Builds a 400x400 container and asserts the resolved child geometry.

def build_container(direction:, justify:, align:, padding: 0, gap: 0, &block)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node(
      { x: 0, y: 0, w: 400, h: 400 },
      id: :container,
      direction: direction,
      justify: justify,
      align: align,
      padding: padding,
      gap: gap,
      &block
    )
  end
  ui.find(:container)
end

def two_solids
  proc do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1)
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2)
  end
end

def test_column_start_start(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.equal!([n1.object.x, n1.object.y, n1.object.anchor_x, n1.object.anchor_y], [0, 400, 0, 1], "n1 top-left")
  assert.equal!([n2.object.x, n2.object.y, n2.object.anchor_x, n2.object.anchor_y], [0, 300, 0, 1], "n2 stacked below")
end

def test_column_start_start_with_padding(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, padding: 10, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.equal!([n1.object.x, n1.object.y], [10, 390], "n1 inset by padding")
  assert.equal!([n2.object.x, n2.object.y], [10, 290], "n2 below n1")
end

def test_column_start_start_with_padding_and_gap(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, padding: 10, gap: 10, &two_solids)
  n2 = c.find(:n2)

  assert.equal!(n2.object.y, 280, "gap pushes n2 down by 10")
end

def test_column_start_center_aligns_on_center_x(args, assert)
  c = build_container(direction: :column, justify: :start, align: :center, &two_solids)
  n1 = c.find(:n1)

  assert.equal!([n1.object.x, n1.object.anchor_x], [200, 0.5], "centered on container center x")
end

def test_column_start_end_aligns_to_right(args, assert)
  c = build_container(direction: :column, justify: :start, align: :end, &two_solids)
  n1 = c.find(:n1)

  assert.equal!([n1.object.x, n1.object.anchor_x], [400, 1], "anchored to right edge")
end

def test_column_align_stretch_fills_inner_width(args, assert)
  c = build_container(direction: :column, justify: :start, align: :stretch, padding: 20, &two_solids)
  n1 = c.find(:n1)

  assert.equal!(n1.object.w, 360, "stretched to inner width (400 - 2*20)")
end

def test_row_start_start_lays_out_horizontally(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.equal!([n1.object.x, n1.object.anchor_x], [0, 0], "n1 at left")
  assert.equal!(n2.object.x, 100, "n2 to the right of n1")
end

def test_find_locates_nested_node(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, &two_solids)

  assert.equal!(c.find(:n2).id, :n2, "find resolves a child by id")
end

def test_primitives_excludes_non_renderable_container(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, &two_solids)

  assert.equal!(c.primitives.length, 2, "only renderable nodes are primitives")
end

def test_interactive_nodes_require_visible_action(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container) do
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> {} }, id: :button)
      node({ w: 50, h: 50, primitive_marker: :solid }, id: :label)
    end
  end

  assert.equal!(ui.interactive_nodes.map(&:id), [:button], "only the node with an action is interactive")
end

# --- justify: :between / :around / :evenly (issue #1) ---
# Container inner main-axis = 400; two 100-tall/wide children => 200 free.

def test_column_between_pins_children_to_edges(args, assert)
  c = build_container(direction: :column, justify: :between, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  # spacing = 200 / (2 - 1); first at the top edge, last at the bottom edge.
  assert.equal!([n1.object.y, n1.object.anchor_y], [400, 1], "n1 pinned to the top")
  assert.equal!([n2.object.y, n2.object.anchor_y], [100, 1], "n2 pinned to the bottom")
end

def test_column_around_splits_space_around_each(args, assert)
  c = build_container(direction: :column, justify: :around, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  # spacing = 200 / 2 = 100; leading = 50 before the first child.
  assert.equal!(n1.object.y, 350, "n1 down by half a spacing")
  assert.equal!(n2.object.y, 150, "n2 a full spacing below n1")
end

def test_column_evenly_equalizes_every_gap(args, assert)
  c = build_container(direction: :column, justify: :evenly, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  # free 200 / (2 + 1) = 66.67 before, between, and after (DR's `/` is float).
  assert.close!(n1.object.y, 333.333, "n1 down by one gap")
  assert.close!(n2.object.y, 166.667, "n2 one gap below n1")
end

def test_row_between_pins_children_to_edges(args, assert)
  c = build_container(direction: :row, justify: :between, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.equal!([n1.object.x, n1.object.anchor_x], [0, 0], "n1 pinned to the left")
  assert.equal!(n2.object.x, 300, "n2 pinned to the right")
end

# --- per-side padding (issue #1) ---

def test_column_array_padding_is_css_shorthand(args, assert)
  # [20, 10] => 20 left/right, 10 top/bottom.
  c = build_container(direction: :column, justify: :start, align: :start, padding: [20, 10], &two_solids)
  n1 = c.find(:n1)

  assert.equal!([n1.object.x, n1.object.y], [20, 390], "x inset by left:20, y inset by top:10")
end

def test_column_hash_padding_applies_per_side(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, padding: { left: 5, top: 15, right: 25, bottom: 35 }, &two_solids)
  n1 = c.find(:n1)

  assert.equal!([n1.object.x, n1.object.y], [5, 385], "x by left:5, y by top:15")
end

def test_column_stretch_respects_per_side_padding(args, assert)
  c = build_container(direction: :column, justify: :start, align: :stretch, padding: { left: 5, right: 25 }, &two_solids)
  n1 = c.find(:n1)

  assert.equal!(n1.object.w, 370, "stretched to inner width (400 - 5 - 25)")
end

# --- cursor globals (issue #1) ---

def test_ui_cursor_globals_round_trip(args, assert)
  saved_hover = Conjuration::UI.hover_cursor
  saved_default = Conjuration::UI.default_cursor

  Conjuration::UI.hover_cursor = ["sprites/hand.png", 6, 4]
  Conjuration::UI.default_cursor = ["sprites/none.png", 9, 4]

  assert.equal!(Conjuration::UI.hover_cursor, ["sprites/hand.png", 6, 4], "hover_cursor round-trips")
  assert.equal!(Conjuration::UI.default_cursor, ["sprites/none.png", 9, 4], "default_cursor round-trips")
ensure
  Conjuration::UI.hover_cursor = saved_hover
  Conjuration::UI.default_cursor = saved_default
end

# --- debug: invisible container bounds (issue #1) ---

def test_non_renderable_nodes_are_the_containers(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container) do
      node({ w: 50, h: 50, primitive_marker: :solid }, id: :box)
    end
  end

  assert.equal!(ui.nodes.reject(&:renderable?).map(&:id), [:root, :container], "containers are non-renderable; the solid box renders")
end

# --- spatial navigation ---

# Five interactive nodes placed in a cross around (200, 200). DR origin is
# bottom-left, so :north has the higher y.
def navigation_cross
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container) do
      node({ w: 40, h: 40, action: -> {} }, id: :north)
      node({ w: 40, h: 40, action: -> {} }, id: :south)
      node({ w: 40, h: 40, action: -> {} }, id: :west)
      node({ w: 40, h: 40, action: -> {} }, id: :east)
      node({ w: 40, h: 40, action: -> {} }, id: :middle)
    end
  end
  ui.find(:north).object.merge!(x: 200, y: 300, anchor_x: 0.5, anchor_y: 0.5)
  ui.find(:south).object.merge!(x: 200, y: 100, anchor_x: 0.5, anchor_y: 0.5)
  ui.find(:west).object.merge!(x: 100, y: 200, anchor_x: 0.5, anchor_y: 0.5)
  ui.find(:east).object.merge!(x: 300, y: 200, anchor_x: 0.5, anchor_y: 0.5)
  ui.find(:middle).object.merge!(x: 200, y: 200, anchor_x: 0.5, anchor_y: 0.5)
  ui
end

def test_spatial_navigate_picks_the_node_in_each_direction(args, assert)
  ui = navigation_cross
  middle = ui.find(:middle)

  assert.equal!(ui.spatial_navigate(middle, { x: 0, y: 1 }).id, :north, "up")
  assert.equal!(ui.spatial_navigate(middle, { x: 0, y: -1 }).id, :south, "down")
  assert.equal!(ui.spatial_navigate(middle, { x: -1, y: 0 }).id, :west, "left")
  assert.equal!(ui.spatial_navigate(middle, { x: 1, y: 0 }).id, :east, "right")
end

def test_spatial_navigate_reaches_an_off_axis_node(args, assert)
  # The case grid nav can't do: a node up-and-to-the-right is reachable via
  # "right" (within a 45-degree cone), not just a same-row node.
  ui = navigation_cross
  ui.find(:east).object.merge!(x: 300, y: 260)

  assert.equal!(ui.spatial_navigate(ui.find(:middle), { x: 1, y: 0 }).id, :east, "right reaches the off-row node")
end

def test_spatial_navigate_from_nil_returns_the_first_interactive(args, assert)
  assert.equal!(navigation_cross.spatial_navigate(nil, { x: 1, y: 0 }).id, :north, "nil from -> first interactive node")
end

def test_spatial_navigate_returns_nil_when_nothing_is_in_the_direction(args, assert)
  ui = navigation_cross
  assert.equal!(ui.spatial_navigate(ui.find(:north), { x: 0, y: 1 }), nil, "nothing above the topmost node")
end

# Builds interactive nodes at explicit bottom-left corners (anchor 0,0) so edge
# and span reasoning is exact. `rects` is an ordered array of { id:, x:, y:, w:, h: }.
def nav_layout(rects)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 4000, h: 4000 }, id: :root) do
    node({ x: 0, y: 0, w: 4000, h: 4000 }, id: :container) do
      rects.each { |r| node({ w: 10, h: 10, action: -> {} }, id: r[:id]) }
    end
  end
  rects.each do |r|
    ui.find(r[:id]).object.merge!(x: r[:x], y: r[:y], w: r[:w], h: r[:h], anchor_x: 0, anchor_y: 0)
  end
  ui
end

# The canonical regression: two row-aligned buttons (ECS, Parallax) with Quit
# centred a row below, its centre nearer to ECS and inside the old 45-degree Right
# cone. Right from ECS must reach the aligned Parallax, not the nearer Quit.
def menu_grid
  nav_layout([
    { id: :ecs, x: 420, y: 274, w: 213, h: 46 },
    { id: :parallax, x: 647, y: 274, w: 213, h: 46 },
    { id: :quit, x: 533.5, y: 214, w: 213, h: 46 }
  ])
end

def test_spatial_navigate_right_prefers_the_aligned_button_over_the_nearer_diagonal(args, assert)
  ui = menu_grid
  assert.equal!(ui.spatial_navigate(ui.find(:ecs), { x: 1, y: 0 }).id, :parallax, "Right from ECS -> aligned Parallax, not nearer Quit")
end

def test_spatial_navigate_down_reaches_quit_from_either_column(args, assert)
  ui = menu_grid
  assert.equal!(ui.spatial_navigate(ui.find(:ecs), { x: 0, y: -1 }).id, :quit, "Down from ECS -> Quit")
  assert.equal!(ui.spatial_navigate(ui.find(:parallax), { x: 0, y: -1 }).id, :quit, "Down from Parallax -> Quit")
end

def test_spatial_navigate_left_returns_to_the_first_column(args, assert)
  ui = menu_grid
  assert.equal!(ui.spatial_navigate(ui.find(:parallax), { x: -1, y: 0 }).id, :ecs, "Left from Parallax -> ECS")
end

def test_spatial_navigate_beam_beats_a_nearer_diagonal(args, assert)
  ui = nav_layout([
    { id: :source, x: 0, y: 0, w: 10, h: 10 },
    { id: :aligned_far, x: 200, y: 0, w: 10, h: 10 },
    { id: :near_diagonal, x: 30, y: 20, w: 10, h: 10 }
  ])
  assert.equal!(ui.spatial_navigate(ui.find(:source), { x: 1, y: 0 }).id, :aligned_far, "an aligned far candidate outranks a near diagonal one")
end

def test_spatial_navigate_beam_is_span_overlap_not_centre_in_band(args, assert)
  # `overlapping` is offset most of a row up — its centre sits outside any centre
  # band, but its span still overlaps the source, so it wins over the fallback tier.
  ui = nav_layout([
    { id: :source, x: 0, y: 0, w: 10, h: 46 },
    { id: :overlapping, x: 200, y: 30, w: 10, h: 46 },
    { id: :off_row, x: 40, y: 52, w: 10, h: 10 }
  ])
  assert.equal!(ui.spatial_navigate(ui.find(:source), { x: 1, y: 0 }).id, :overlapping, "a half-row-overlapping candidate beats the cone fallback")
end

def test_spatial_navigate_beam_ranks_by_edge_not_centre(args, assert)
  # The long button's centre is far, but its near edge is closest; edge distance
  # must pick it over the short button whose centre is nearer.
  ui = nav_layout([
    { id: :source, x: 0, y: 0, w: 10, h: 10 },
    { id: :long, x: 20, y: 0, w: 300, h: 10 },
    { id: :short, x: 40, y: 0, w: 10, h: 10 }
  ])
  assert.equal!(ui.spatial_navigate(ui.find(:source), { x: 1, y: 0 }).id, :long, "edge distance picks the adjacent long button")
end

def test_spatial_navigate_empty_beam_falls_back_to_the_cone(args, assert)
  ui = nav_layout([
    { id: :source, x: 0, y: 0, w: 10, h: 10 },
    { id: :diagonal, x: 60, y: 40, w: 10, h: 10 }
  ])
  assert.equal!(ui.spatial_navigate(ui.find(:source), { x: 1, y: 0 }).id, :diagonal, "a diagonal-only layout still navigates via the cone")
end

def test_spatial_navigate_tie_break_is_deterministic(args, assert)
  near = { id: :near, x: 50, y: 40, w: 10, h: 10 }  # equal edge, smaller cross offset
  far  = { id: :far,  x: 50, y: 90, w: 10, h: 10 }  # equal edge, larger cross offset
  source = { id: :source, x: 0, y: 0, w: 10, h: 100 }
  right = { x: 1, y: 0 }

  a = nav_layout([source, near, far])
  b = nav_layout([source, far, near])
  assert.equal!(a.spatial_navigate(a.find(:source), right).id, :near, "smaller cross offset wins")
  assert.equal!(b.spatial_navigate(b.find(:source), right).id, :near, "winner is order-independent")
end

# --- interaction states ---

def interaction_ui
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container) do
      node({ w: 50, h: 50, path: "base.png", action: -> {}, hover: { path: "hover.png" } }, id: :button)
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> {}, disabled: true }, id: :off)
    end
  end
end

def test_styled_object_merges_the_hover_override_when_hovered(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.pressed_node = nil

  assert.equal!(button.styled_object[:path], "base.png", "default state renders the base object")

  Conjuration::UI.hovered_node = button
  assert.equal!(button.styled_object[:path], "hover.png", "hover merges the override")
ensure
  Conjuration::UI.hovered_node = nil
end

def test_styled_object_focused_state_prefers_focused_and_falls_back_to_hover(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  Conjuration::UI.focused_node = button

  assert.equal!(button.styled_object[:path], "hover.png", "no focused: override -> the hover style stands in")

  button.object.merge!(focused: { path: "focused.png" })
  assert.equal!(button.styled_object[:path], "focused.png", "a focused: override wins for keyboard/pad focus")
ensure
  Conjuration::UI.focused_node = nil
end

def test_hover_state_outranks_focus_state(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  Conjuration::UI.focused_node = button
  Conjuration::UI.hovered_node = button

  assert.equal!(button.interaction_state, :hover, "hovered + focused reads as hover")
ensure
  Conjuration::UI.focused_node = nil
  Conjuration::UI.hovered_node = nil
end

def test_disabled_nodes_are_excluded_from_interactive_nodes(args, assert)
  assert.equal!(interaction_ui.interactive_nodes.map(&:id), [:button], "disabled nodes drop out of interactive_nodes")
end

def test_pressed_state_takes_priority_over_hover(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  button.object.merge!(pressed: { path: "pressed.png" })
  Conjuration::UI.hovered_node = button
  Conjuration::UI.pressed_node = button

  assert.equal!(button.styled_object[:path], "pressed.png", "pressed wins over hover")
ensure
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.pressed_node = nil
end

def test_a_node_knows_its_own_focused_hovered_and_pressed_state(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  Conjuration::UI.focused_node = nil
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.pressed_node = nil

  assert.equal!(button.focused?, false, "not focused by default")
  assert.equal!(button.hovered?, false, "not hovered by default")

  Conjuration::UI.focused_node = button
  assert.equal!(button.focused?, true, "focused? reflects UI.focused_node")
  assert.equal!(ui.find(:off).focused?, false, "a sibling node is not focused")

  Conjuration::UI.hovered_node = button
  assert.equal!(button.hovered?, true, "hovered? reflects UI.hovered_node")
  assert.equal!(ui.find(:off).hovered?, false, "a sibling node is not hovered")

  Conjuration::UI.pressed_node = button
  assert.equal!(button.pressed?, true, "pressed? reflects UI.pressed_node")
ensure
  Conjuration::UI.focused_node = nil
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.pressed_node = nil
end

# --- Absolute positioning (3.1) -----------------------------------------------
# build_container is a 400x400 box at the origin: left 0, right 400, bottom 0,
# top 400 (y-up).

def test_absolute_child_is_excluded_from_flow(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1)
    node({ w: 20, h: 20, primitive_marker: :solid }, id: :badge, position: :absolute, top: 0, right: 0)
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2)
  end
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.equal!([n1.object.y, n2.object.y], [400, 300], "flow stacks n1/n2 as if the absolute badge weren't there")
end

def test_absolute_child_is_excluded_from_free_space(args, assert)
  c = build_container(direction: :column, justify: :between, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1)
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2)
    node({ w: 20, h: 20, primitive_marker: :solid }, id: :badge, position: :absolute, top: 0, right: 0)
  end
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.equal!([n1.object.y, n2.object.y], [400, 100], ":between spreads only the two flow children")
end

def test_absolute_child_pins_to_top_right_corner(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ w: 20, h: 20, primitive_marker: :solid }, id: :badge, position: :absolute, top: 10, right: 10)
  end
  badge = c.find(:badge)

  assert.equal!([badge.object.x, badge.object.anchor_x], [390, 1], "10px in from the right edge")
  assert.equal!([badge.object.y, badge.object.anchor_y], [390, 1], "10px down from the top edge")
end

def test_absolute_child_pins_to_bottom_left_corner(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ w: 20, h: 20, primitive_marker: :solid }, id: :badge, position: :absolute, bottom: 10, left: 10)
  end
  badge = c.find(:badge)

  assert.equal!([badge.object.x, badge.object.anchor_x], [10, 0], "10px in from the left edge")
  assert.equal!([badge.object.y, badge.object.anchor_y], [10, 0], "10px up from the bottom edge")
end

def test_absolute_child_stretches_between_opposing_insets(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ h: 20, primitive_marker: :solid }, id: :bar, position: :absolute, left: 10, right: 30, bottom: 0)
  end
  bar = c.find(:bar)

  assert.equal!([bar.object.x, bar.object.anchor_x, bar.object.w], [10, 0, 360], "spans 400 - 10 - 30 between the left/right insets")
end

def test_absolute_child_pins_inside_parent_padding(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, padding: 20) do
    node({ w: 20, h: 20, primitive_marker: :solid }, id: :badge, position: :absolute, top: 0, right: 0)
  end
  badge = c.find(:badge)

  assert.equal!([badge.object.x, badge.object.y], [380, 380], "pinned to the padded inner corner (400 - 20)")
end

def test_absolute_child_still_lays_out_its_subtree(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ w: 100, h: 40, primitive_marker: :solid }, id: :panel, position: :absolute, top: 0, left: 0) do
      node({ w: 30, h: 30, primitive_marker: :solid }, id: :inner)
    end
  end
  panel, inner = c.find(:panel), c.find(:inner)

  assert.equal!([panel.object.x, panel.object.y], [0, 400], "panel pinned to the top-left corner")
  assert.equal!([inner.object.x, inner.object.y], [0, 400], "inner flows from the absolute panel's own top-left")
end

# --- Dirty-flag relayout (3.5) ------------------------------------------------

def test_invalidate_marks_node_and_ancestors_dirty(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, &two_solids)
  n1 = c.find(:n1)
  assert.equal!([c.dirty?, n1.dirty?], [false, false], "clean after the build's layout")

  n1.object.h = 200 # a real layout change
  n1.invalidate!
  assert.equal!([n1.dirty?, c.dirty?], [true, true], "invalidate! marks the node and its ancestors")
end

def test_calculate_layout_skips_clean_subtrees(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)
  original_y = n2.object.y

  n1.object.h = 200  # mutate the raw object without invalidating
  c.calculate_layout # clean subtree -> early-out, nothing recomputed
  assert.equal!(n2.object.y, original_y, "no invalidate! leaves the clean subtree untouched")

  n1.invalidate!
  c.calculate_layout
  assert.equal!(n2.object.y, 200, "invalidate! -> n2 restacks under the now-taller n1")
end

def test_invalidate_ignores_no_op_and_render_only_changes(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start, &two_solids)
  n1 = c.find(:n1)

  n1.object.r = 255 # a render-only field, not in the layout signature
  n1.invalidate!
  assert.equal!([n1.dirty?, c.dirty?], [false, false], "a render-only change doesn't invalidate")

  n1.object.w = 100 # the same width it already has
  n1.invalidate!
  assert.equal!(n1.dirty?, false, "writing the same value doesn't dirty")

  n1.object.w = 150 # a real size change
  n1.invalidate!
  assert.equal!([n1.dirty?, c.dirty?], [true, true], "a size change invalidates the node and its ancestors")
end

def test_relayout_does_not_clobber_a_nodes_own_visibility(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 100, h: 100, primitive_marker: :solid }, id: :panel)
  end
  panel = ui.find(:panel)

  panel.visible = false
  panel.invalidate!
  ui.calculate_layout

  assert.equal!(panel.visible, false, "the per-frame relayout leaves the node's own visible alone")
  assert.equal!(ui.primitives.length, 0, "an invisible node is excluded from primitives")
end

def test_invisible_ancestor_hides_descendants(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 200, h: 200 }, id: :panel) do
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> {} }, id: :child)
    end
  end
  ui.find(:panel).visible = false
  child = ui.find(:child)

  assert.equal!(child.visible, true, "the child keeps its own visible")
  assert.equal!([child.renderable?, child.interactive?], [false, false], "an invisible ancestor hides and disables it")
end

def test_text_children_stack_without_overlap(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 200, h: 100 }, id: :root) do
    node({ x: 0, y: 0, w: 200, h: 100 }, id: :col, gap: 5) do
      node({ text: "First line" }, id: :a)
      node({ text: "Second line" }, id: :b)
    end
  end
  a, b = ui.find(:a), ui.find(:b)

  # The double measures text height as 22; the second label must clear the first
  # by its height + gap, which only holds if the first was measured before being
  # positioned (an unmeasured height of 0 would overlap them).
  assert.equal!(a.object.h, 22, "the first label's height is measured")
  assert.equal!(a.object.y - b.object.y, a.object.h + 5, "the second label clears the first by its height + the gap")
end

def test_nodes_is_memoized(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 100, h: 100 }, id: :root) do
    node({ w: 10, h: 10 }, id: :a)
  end

  assert.equal!(ui.nodes.equal?(ui.nodes), true, "nodes returns the same cached array on repeated reads")
end

def test_structural_change_invalidates_caches_up_the_tree(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 100, h: 100 }, id: :root) do
    node({ x: 0, y: 0, w: 50, h: 50 }, id: :panel) do
      node({ w: 10, h: 10 }, id: :a)
    end
  end
  assert.equal!(ui.nodes.length, 3, "root + panel + a (primes the caches)")

  ui.find(:panel).node({ w: 10, h: 10 }, id: :b) # add deep in the tree

  assert.equal!(ui.nodes.length, 4, "ancestor node cache rebuilt to include b")
  assert.equal!(ui.find(:b).id, :b, "ancestor descendants cache rebuilt to find b")
end

# --- Navigation groups (named, dev-managed) -----------------------------------

def test_navigation_groups_bucket_named_groups_only(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ x: 0, y: 0, w: 10, h: 20 }, id: :left, group: :left) do
      node({ w: 10, h: 10, action: -> {} }, id: :l1)
      node({ w: 10, h: 10, action: -> {} }, id: :l2)
    end
    node({ w: 10, h: 10, action: -> {} }, id: :loose) # no group
  end

  groups = c.navigation_groups
  assert.equal!(groups.keys, [:left], "only named groups — ungrouped nodes are not bucketed")
  assert.equal!(groups[:left].map(&:id), [:l1, :l2], "left pane members in tree order")
end

def test_group_of_returns_named_group_or_nil(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ x: 0, y: 0, w: 10, h: 10 }, id: :pane, group: :pane) do
      node({ w: 10, h: 10, action: -> {} }, id: :item)
    end
    node({ w: 10, h: 10, action: -> {} }, id: :loose)
  end

  assert.equal!(c.group_of(c.find(:item)), :pane, "a grouped node resolves to its pane")
  assert.equal!(c.group_of(c.find(:loose)), nil, "an ungrouped node has no group")
end

def test_spatial_navigate_restricts_to_candidates(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start) do
    node({ w: 50, h: 50, action: -> {} }, id: :a)
    node({ w: 50, h: 50, action: -> {} }, id: :b)
    node({ w: 50, h: 50, action: -> {} }, id: :c)
  end
  a, cc = c.find(:a), c.find(:c)
  right = { x: 1, y: 0 }

  assert.equal!(c.spatial_navigate(a, right).id, :b, "unrestricted -> nearest neighbour b")
  assert.equal!(c.spatial_navigate(a, right, candidates: [a, cc]).id, :c, "candidates restrict the search, skipping b")
end

def test_a_root_group_names_the_whole_ui_as_one_pane(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 100, h: 100 }, id: :root) do
    node({ x: 0, y: 0, w: 50, h: 50, action: -> {} }, id: :a)
    node({ x: 0, y: 0, w: 50, h: 50, action: -> {} }, id: :b)
  end
  ui.group = :hud # set the group on the whole ui

  groups = ui.navigation_groups
  assert.equal!(groups.keys, [:hud], "the root group names the whole ui as one pane")
  assert.equal!(groups[:hud].map(&:id), [:a, :b], "every interactive node inherits it")
end

# --- Scroll containers (overflow: :scroll, 3.4) -------------------------------

def test_scroll_container_emits_a_target_sprite_not_its_children(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 300, w: 100, h: 100, primitive_marker: :solid }, id: :scroller, overflow: :scroll, justify: :start, align: :start) do
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :a)
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :b)
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :c)
    end
  end
  scroller = ui.find(:scroller)
  prims = ui.primitives

  assert.equal!(prims.any? { |p| p[:path] == scroller.scroll_target_path }, true, "emits the render-target blit sprite")
  assert.equal!(prims.any? { |p| p[:w] == 80 }, false, "the 80px children are clipped into the target, not the flat list")
end

def test_scroll_content_height_and_max_scroll(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 300, w: 100, h: 100 }, id: :scroller, overflow: :scroll, justify: :start, align: :start, gap: 10) do
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :a)
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :b)
    end
  end
  scroller = ui.find(:scroller)

  assert.equal!(scroller.content_height, 170, "children span (80 + 10 gap + 80)")
  assert.equal!(scroller.max_scroll, 70, "content 170 - box 100")
  assert.equal!(scroller.scroll?, true, "overflow: :scroll marks it a scroll container")
end

def test_scroll_container_is_focusable(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 200, h: 200 }, id: :root) do
    node({ x: 0, y: 0, w: 100, h: 100 }, id: :scroller, overflow: :scroll) do
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :item)
    end
  end

  assert.equal!(ui.interactive_nodes.map(&:id), [:scroller], "a scroll container is focusable even without an action")
end

def test_scroll_content_height_includes_padding(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 300, w: 100, h: 100 }, id: :scroller, overflow: :scroll, justify: :start, align: :start, padding: 10) do
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :a)
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :b)
    end
  end
  scroller = ui.find(:scroller)

  # children span 160 (two 80s, no gap) + 10 top + 10 bottom padding.
  assert.equal!(scroller.content_height, 180, "content height includes the container's top and bottom padding")
end

# --- Text wrapping (wrap:, 3.6) -----------------------------------------------

def test_wrapped_text_breaks_into_lines(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 48, h: 100 }, id: :box, wrap: true) do
      node({ text: "aa bb cc dd" }, id: :para)
    end
  end
  para = ui.find(:para)

  # box content width = 48 (no padding). The double measures width as length * 8:
  # "aa bb" (5 chars) = 40 <= 48 fits; "aa bb cc" (8 chars) = 64 > 48, so it breaks.
  assert.equal!(para.wrap_lines, ["aa bb", "cc dd"], "wraps to the parent's content width")
  assert.equal!([para.object.w, para.object.h], [48, 44], "sized to the wrap width and lines * line height (22)")
end

def test_wrapped_text_emits_one_label_per_line(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 100, w: 48, h: 100 }, id: :box, wrap: true) do
      node({ text: "aa bb cc dd", r: 1, g: 2, b: 3 }, id: :para)
    end
  end

  labels = ui.primitives.select { |p| p[:text] }
  assert.equal!(labels.map { |p| p[:text] }, ["aa bb", "cc dd"], "one label primitive per wrapped line")
end

def test_letter_break_splits_mid_word(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 40, h: 100 }, id: :box, wrap: true) do
      node({ text: "abcdefgh" }, id: :para, text_break: :letter)
    end
  end
  para = ui.find(:para)

  # width 40 = 5 chars (8px each); "abcdefgh" packs 5 then breaks mid-word.
  assert.equal!(para.wrap_lines, ["abcde", "fgh"], "letter break splits within a word to fit the width")
end

def test_break_false_disables_wrapping(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 40, h: 100 }, id: :box, wrap: true) do
      node({ text: "aa bb cc" }, id: :para, text_break: false)
    end
  end
  para = ui.find(:para)

  assert.equal!(para.wrapped?, false, "text_break: false opts out even under a wrapping parent")
  assert.equal!(para.object.w, 64, "stays a single line (8 chars * 8px)")
end

# --- justify without a resolved main-axis size ---

def test_widthless_justify_center_row_auto_sizes_to_content(args, assert)
  Conjuration::UI.warnings.clear

  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container, direction: :column) do
      node({ h: 100 }, id: :toolbar, direction: :row, justify: :center) do
        node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1)
        node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2)
      end
    end
  end

  toolbar = ui.find(:toolbar)
  n1, n2 = ui.find(:n1), ui.find(:n2)
  assert.equal!(toolbar.object.w, 200, "toolbar auto-sizes to its two 100-wide children")
  assert.equal!([n1.object.x, n1.object.anchor_x], [0, 0], "no free space: n1 packs at the start")
  assert.equal!(n2.object.x, 100, "n2 to the right of n1")
  assert.equal!(Conjuration::UI.warnings.any? { |warning| warning.include?(":toolbar") && warning.include?("width") }, false, "auto-sized: no missing-width fallback")
end

def test_heightless_justify_center_column_auto_sizes_to_content(args, assert)
  Conjuration::UI.warnings.clear

  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container, direction: :row) do
      node({ w: 100 }, id: :sidebar, direction: :column, justify: :center) do
        node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1)
        node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2)
      end
    end
  end

  sidebar = ui.find(:sidebar)
  n1, n2 = ui.find(:n1), ui.find(:n2)
  assert.equal!(sidebar.object.h, 200, "sidebar auto-sizes to its two 100-tall children")
  assert.equal!([n1.object.y, n1.object.anchor_y], [400, 1], "no free space: n1 packs at the top")
  assert.equal!(n2.object.y, 300, "n2 stacked below n1")
  assert.equal!(Conjuration::UI.warnings.any? { |warning| warning.include?(":sidebar") && warning.include?("height") }, false, "auto-sized: no missing-height fallback")
end

def test_widthless_justify_end_row_anchors_off_the_trailing_edge(args, assert)
  Conjuration::UI.warnings.clear

  ui = Conjuration::UI.build({ x: 0, y: 0, w: 1280, h: 720 }, id: :root) do
    node({ x: 1270, y: 710, anchor_x: 1, anchor_y: 1 }, id: :mute_bar, direction: :row, justify: :end) do
      node({ w: 120, h: 40, primitive_marker: :solid }, id: :mute)
    end
  end

  mute = ui.find(:mute)
  assert.equal!([mute.object.x, mute.object.anchor_x], [1270, 1], "child's right edge anchors at the container's right edge")
  assert.equal!(Conjuration::UI.warnings.empty?, true, ":end without a width is legitimate — no warning")
end

# --- shortcut display stays out of core + reconcile ---

def build_shortcut_ui
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container) do
      node({ w: 100, h: 44, primitive_marker: :solid, action: -> {} }, id: :with, shortcut: { keyboard: :escape, controller: :b })
      node({ w: 100, h: 44, primitive_marker: :solid, action: -> {} }, id: :without)
    end
  end
end

def test_core_emits_no_primitives_for_a_shortcut(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  ui = build_shortcut_ui
  source = Conjuration::DragonInputSource.new
  ui.shortcut_nodes.each { |node| source.shortcut_just_pressed?(:one, node.shortcut_action_name, node.shortcut) }

  assert.equal!(ui.primitives.length, 2, "a shortcut adds nothing to the primitives — display is game code")
ensure
  DragonInput.reset!
end

def test_shortcut_action_name_is_deterministic_and_public(args, assert)
  ui = build_shortcut_ui

  assert.equal!(ui.find(:with).shortcut_action_name, :ui_shortcut_with, "display code can key glyph lookups off the injected action's name")
end

class ShortcutReconcileHost
  include Conjuration::UI::Builder

  attr_accessor :shortcut

  def initialize
    @shortcut = nil
  end

  def view
    node({ w: 100, h: 44, primitive_marker: :solid, action: -> {} }, id: :btn, shortcut: @shortcut)
  end
end

def test_shortcut_reconciles_like_a_node_opt(args, assert)
  DragonInput.setup { |c| c.action_set(:menu) }
  host = ShortcutReconcileHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  root.calculate_layout
  assert.equal!(root.shortcut_nodes.length, 0, "no shortcut node before one is declared")

  host.shortcut = { keyboard: :escape, controller: :b }
  root.render_view
  root.calculate_layout
  assert.equal!(root.shortcut_nodes.map(&:id), [:btn], "adding a shortcut re-enters the cached list")
  assert.equal!(root.find(:btn).shortcut, { keyboard: :escape, controller: :b }, "the value is written onto the retained node")

  host.shortcut = nil
  root.render_view
  root.calculate_layout
  assert.equal!(root.shortcut_nodes.length, 0, "removing it drops the node from the list")
ensure
  DragonInput.reset!
end

# --- main-axis grow (flex-grow) -----------------------------------------------
# Container is 400x400. grow expands a child's main size by its share of leftover
# free space (inner main size − Σ bases − gaps). No shrink when leftover ≤ 0.

def test_row_single_grow_fills_leftover(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: 1)
  end
  n1 = c.find(:n1)

  # leftover = 400 - 100 = 300; n1.w = 100 + 300
  assert.equal!(n1.object.w, 400, "single grow:1 child absorbs the full leftover")
end

def test_row_two_grow_factors_split_leftover_2_to_1(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: 2)
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2, grow: 1)
  end
  n1, n2 = c.find(:n1), c.find(:n2)

  # leftover = 400 - 200 = 200; n1 gets 2/3, n2 gets 1/3
  assert.close!(n1.object.w, 100 + 200 * 2 / 3.0, "n1 takes two thirds of leftover")
  assert.close!(n2.object.w, 100 + 200 * 1 / 3.0, "n2 takes one third of leftover")
end

def test_column_single_grow_fills_leftover(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: 1)
  end
  n1 = c.find(:n1)

  assert.equal!(n1.object.h, 400, "column grow:1 child absorbs the full leftover height")
end

def test_column_two_grow_factors_split_leftover_2_to_1(args, assert)
  c = build_container(direction: :column, justify: :start, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: 2)
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2, grow: 1)
  end
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.close!(n1.object.h, 100 + 200 * 2 / 3.0, "n1 takes two thirds of leftover height")
  assert.close!(n2.object.h, 100 + 200 * 1 / 3.0, "n2 takes one third of leftover height")
end

def test_grow_leftover_excludes_padding_and_gaps(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start, padding: 20, gap: 10) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: 1)
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2)
  end
  n1, n2 = c.find(:n1), c.find(:n2)

  # inner = 400 - 40 = 360; used = 100 + 100 + 10 = 210; leftover = 150
  assert.equal!(n1.object.w, 250, "grow fills leftover after padding and gap")
  assert.equal!(n2.object.w, 100, "non-grow sibling stays at its basis")
end

def test_grow_expands_from_explicit_basis(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start) do
    node({ w: 50, h: 100, primitive_marker: :solid }, id: :n1, grow: 1)
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n2)
  end
  n1 = c.find(:n1)

  # leftover = 400 - 150 = 250; n1.w = 50 + 250
  assert.equal!(n1.object.w, 300, "final size is basis plus full leftover share")
end

def test_grow_noop_when_leftover_non_positive(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start) do
    node({ w: 250, h: 100, primitive_marker: :solid }, id: :n1, grow: 1)
    node({ w: 250, h: 100, primitive_marker: :solid }, id: :n2, grow: 1)
  end
  n1, n2 = c.find(:n1), c.find(:n2)

  # used = 500 > inner 400; leftover negative → no shrink in v1
  assert.equal!([n1.object.w, n2.object.w], [250, 250], "sizes untouched when leftover ≤ 0")
end

def test_absolute_child_neither_grows_nor_counts_toward_leftover(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: 1)
    node({ w: 50, h: 50, primitive_marker: :solid }, id: :badge, position: :absolute, top: 0, right: 0, grow: 1)
  end
  n1, badge = c.find(:n1), c.find(:badge)

  # absolute is out of flow: leftover = 400 - 100 = 300
  assert.equal!(n1.object.w, 400, "only the in-flow grower expands")
  assert.equal!(badge.object.w, 50, "absolute child keeps its declared size")
end

def test_grow_on_unresolved_main_size_warns_and_skips(args, assert)
  Conjuration::UI.warnings.clear

  # wrap: keeps a container out of content-aware auto-sizing (its width is
  # parent-driven), so its width stays unresolved and grow hits the warn path.
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container, direction: :column) do
      node({ h: 100 }, id: :toolbar, direction: :row, wrap: true) do
        node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: 1)
      end
    end
  end

  n1 = ui.find(:n1)
  assert.equal!(n1.object.w, 100, "size stays at basis when container width is unresolved")
  assert.equal!(
    Conjuration::UI.warnings.any? { |warning| warning.include?(":toolbar") && warning.include?("width") && warning.include?("grow") },
    true,
    "unresolved main size is flagged once"
  )
end

class GrowReconcileHost
  include Conjuration::UI::Builder

  attr_accessor :grow_factor

  def initialize
    @grow_factor = nil
  end

  def view
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container, direction: :row) do
      node({ w: 100, h: 100, primitive_marker: :solid }, id: :n1, grow: @grow_factor)
    end
  end
end

def test_grow_reconciles_and_relayouts(args, assert)
  host = GrowReconcileHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  root.calculate_layout
  n1 = root.find(:n1)
  assert.equal!(n1.object.w, 100, "no grow → basis width")

  host.grow_factor = 1
  root.render_view
  root.calculate_layout
  assert.equal!(root.find(:n1).grow, 1, "grow is written onto the retained node")
  assert.equal!(root.find(:n1).object.w, 400, "re-render with grow:1 fills leftover")
end

def test_grow_rederives_from_authored_basis_on_factor_change(args, assert)
  host = GrowReconcileHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))

  host.grow_factor = 1
  root.render_view
  root.calculate_layout
  assert.equal!(root.find(:n1).object.w, 400, "first distribution fills from the 100 basis")

  host.grow_factor = 3
  root.render_view
  root.calculate_layout
  assert.equal!(root.find(:n1).object.w, 400, "changed factor re-derives from the authored basis, not the grown 400")
end

def test_no_grow_tree_layout_unchanged(args, assert)
  c = build_container(direction: :row, justify: :start, align: :start, &two_solids)
  n1, n2 = c.find(:n1), c.find(:n2)

  assert.equal!([n1.object.x, n1.object.w, n1.object.h], [0, 100, 100], "n1 geometry matches pre-grow baseline")
  assert.equal!([n2.object.x, n2.object.w, n2.object.h], [100, 100, 100], "n2 geometry matches pre-grow baseline")
end

# --- justify: :stretch ------------------------------------------------------

def test_row_stretch_fills_sizeless_children_equally(args, assert)
  c = build_container(direction: :row, justify: :stretch, align: :start) do
    node({ h: 100, primitive_marker: :solid }, id: :n1)
    node({ h: 100, primitive_marker: :solid }, id: :n2)
  end
  assert.close!(c.find(:n1).object.w, 200, "sizeless child stretches to half")
  assert.close!(c.find(:n2).object.w, 200, "second sizeless child takes the other half")
  assert.close!(c.find(:n2).object.x, 200, "positioned as :start after stretch")
end

def test_column_stretch_fills_sizeless_children_equally(args, assert)
  c = build_container(direction: :column, justify: :stretch, align: :start) do
    node({ w: 100, primitive_marker: :solid }, id: :n1)
    node({ w: 100, primitive_marker: :solid }, id: :n2)
  end
  assert.close!(c.find(:n1).object.h, 200, "sizeless child stretches to half height")
  assert.close!(c.find(:n2).object.h, 200, "second child takes the rest")
end

def test_stretch_leaves_sized_children_and_composes_factors(args, assert)
  c = build_container(direction: :row, justify: :stretch, align: :start) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :fixed)
    node({ h: 100, primitive_marker: :solid }, id: :auto)
    node({ h: 100, primitive_marker: :solid }, id: :heavy, grow: 2)
  end
  assert.close!(c.find(:fixed).object.w, 100, "authored size untouched")
  assert.close!(c.find(:auto).object.w, 100, "stretch share = leftover * 1/3")
  assert.close!(c.find(:heavy).object.w, 200, "explicit factor composes at 2x")
end

def test_stretch_respects_gaps_padding_and_grow_zero_optout(args, assert)
  c = build_container(direction: :row, justify: :stretch, align: :start, padding: 20, gap: 10) do
    node({ h: 50, primitive_marker: :solid }, id: :fill)
    node({ w: 80, h: 50, primitive_marker: :solid }, id: :opted_out, grow: 0)
  end
  assert.close!(c.find(:fill).object.w, 400 - 40 - 10 - 80, "leftover excludes padding, gap, and the opted-out child")
  assert.close!(c.find(:opted_out).object.w, 80, "grow: 0 opts out of stretching")
end

def test_stretch_never_stretches_text(args, assert)
  c = build_container(direction: :row, justify: :stretch, align: :start) do
    node({ text: "label" }, id: :label)
    node({ h: 40, primitive_marker: :solid }, id: :fill)
  end
  label_w = c.find(:label).object.w
  assert.true!(label_w < 200, "text keeps its measured width (got #{label_w})")
  assert.close!(c.find(:fill).object.w, 400 - label_w, "the solid takes all remaining space")
end

def test_stretch_on_unresolved_container_warns_and_writes_nothing(args, assert)
  Conjuration::UI.warnings.clear
  # wrap: opts out of content-aware auto-sizing, so the width stays unresolved
  # and the stretch fallback/warn path is exercised.
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 100, h: 100 }, id: :nowidth, direction: :row, justify: :stretch, wrap: true) do
      node({ h: 50, primitive_marker: :solid }, id: :kid)
    end
  end
  assert.nil!(ui.find(:kid).object.w, "no size written without a resolved container width")
  assert.equal!(
    Conjuration::UI.warnings.any? { |w| w.include?(":nowidth") && w.include?("width") },
    true,
    "the unresolved stretch container is flagged"
  )
end

class StretchReconcileHost
  include Conjuration::UI::Builder

  attr_accessor :mode

  def initialize
    @mode = :start
  end

  def view
    node({ x: 0, y: 0, w: 400, h: 100 }, id: :bar, direction: :row, justify: @mode) do
      node({ h: 100, primitive_marker: :solid }, id: :n1)
    end
  end
end

def test_justify_stretch_reconciles(args, assert)
  host = StretchReconcileHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  root.calculate_layout
  assert.nil!(root.find(:n1).object.w, ":start leaves the sizeless child unsized")

  host.mode = :stretch
  root.render_view
  root.calculate_layout
  assert.close!(root.find(:n1).object.w, 400, "switching to :stretch fills the bar")
end

# --- Content-aware sizing (auto size, max bounds, universal overflow) ----------
# A container with no declared size on an axis derives it from content: main axis
# = Σ in-flow children + gaps + padding; cross axis = max in-flow child + padding.
# max_w/max_h clamp the result. Overflow past resolved bounds lazily scrolls.

# Counts resolve_content_size! per node id so tests can prove which nodes the
# measure pass actually touched. A fully-sized subtree touches none.
$measured_ids = []
class Conjuration::UI::Node
  alias_method :__audit_orig_resolve_content_size!, :resolve_content_size!
  def resolve_content_size!
    $measured_ids << id
    __audit_orig_resolve_content_size!
  end
end

def test_auto_column_sizes_to_children_gaps_and_padding(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 100, y: 700, anchor_x: 0, anchor_y: 1 }, id: :box, direction: :column, gap: 10, padding: 20) do
      node({ w: 60, h: 50, primitive_marker: :solid }, id: :a)
      node({ w: 40, h: 30, primitive_marker: :solid }, id: :b)
    end
  end
  box = ui.find(:box)

  assert.equal!(box.object.h, 130, "main axis: 50 + 30 + 10 gap + 20*2 padding")
  assert.equal!(box.object.w, 100, "cross axis: max child 60 + 20*2 padding")
end

def test_auto_row_sizes_to_children_gaps_and_padding(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 100, y: 700, anchor_x: 0, anchor_y: 1 }, id: :box, direction: :row, gap: 8, padding: 5) do
      node({ w: 60, h: 50, primitive_marker: :solid }, id: :a)
      node({ w: 40, h: 30, primitive_marker: :solid }, id: :b)
    end
  end
  box = ui.find(:box)

  assert.equal!(box.object.w, 118, "main axis: 60 + 40 + 8 gap + 5*2 padding")
  assert.equal!(box.object.h, 60, "cross axis: max child 50 + 5*2 padding")
end

def test_auto_sizing_nests_bottom_up(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 0, y: 700, anchor_x: 0, anchor_y: 1 }, id: :outer, direction: :column, gap: 0) do
      node({}, id: :inner, direction: :row, gap: 0) do
        node({ w: 30, h: 20, primitive_marker: :solid }, id: :a)
        node({ w: 30, h: 20, primitive_marker: :solid }, id: :b)
      end
      node({ w: 10, h: 15, primitive_marker: :solid }, id: :c)
    end
  end
  inner, outer = ui.find(:inner), ui.find(:outer)

  assert.equal!([inner.object.w, inner.object.h], [60, 20], "inner row sizes to its two children first")
  assert.equal!([outer.object.w, outer.object.h], [60, 35], "outer column then sizes to the resolved inner + c")
end

def test_max_w_clamps_auto_size(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 0, y: 700, anchor_x: 0, anchor_y: 1 }, id: :box, direction: :row, max_w: 100) do
      node({ w: 150, h: 20, primitive_marker: :solid }, id: :a)
      node({ w: 150, h: 20, primitive_marker: :solid }, id: :b)
    end
  end
  box = ui.find(:box)

  assert.equal!(box.object.w, 100, "auto width 300 is clamped to max_w 100")
  assert.equal!(box.object.h, 20, "the uncapped cross axis still sizes to content")
end

def test_max_h_clamps_an_explicit_size(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 0, y: 700, w: 100, h: 500, anchor_x: 0, anchor_y: 1, primitive_marker: :solid }, id: :box, max_h: 300) do
      node({ w: 20, h: 20, primitive_marker: :solid }, id: :a)
    end
  end

  assert.equal!(ui.find(:box).object.h, 300, "a cap clamps a declared size too")
end

def test_explicit_size_wins_over_auto(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 0, y: 700, w: 500, anchor_x: 0, anchor_y: 1 }, id: :box, direction: :column) do
      node({ w: 60, h: 20, primitive_marker: :solid }, id: :a)
    end
  end
  box = ui.find(:box)

  assert.equal!(box.object.w, 500, "a declared width is kept, not derived from content")
  assert.equal!(box.object.h, 20, "the undeclared height still auto-sizes")
end

# The precedence seam: an externally assigned size (align: :stretch here; grow
# will arrive on a sibling branch) overrides auto-from-content. Auto runs in the
# measure pass, the external assignment in the later positioning pass, so it wins.
def test_external_assignment_overrides_auto_from_content(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 0, y: 700, w: 400, h: 400, anchor_x: 0, anchor_y: 1 }, id: :parent, direction: :column, align: :stretch) do
      node({ h: 30 }, id: :child, direction: :row) do
        node({ w: 20, h: 10, primitive_marker: :solid }, id: :leaf)
      end
    end
  end

  assert.equal!(ui.find(:child).object.w, 400, "stretch (external) overrides the child's auto content width of 20")
end

def test_absolute_children_excluded_from_auto_size(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 0, y: 700, anchor_x: 0, anchor_y: 1 }, id: :box, direction: :column) do
      node({ w: 40, h: 40, primitive_marker: :solid }, id: :flow)
      node({ w: 200, h: 200, primitive_marker: :solid }, id: :badge, position: :absolute, top: 0, right: 0)
    end
  end
  box = ui.find(:box)

  assert.equal!([box.object.w, box.object.h], [40, 40], "the absolute badge doesn't count toward either axis")
end

def test_fully_sized_tree_never_enters_measure_pass(args, assert)
  $measured_ids = []
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 200, h: 200 }, id: :panel, gap: 5, padding: 10) do
      node({ w: 50, h: 50, primitive_marker: :solid }, id: :a)
      node({ w: 50, h: 50, primitive_marker: :solid }, id: :b)
    end
  end

  assert.equal!($measured_ids, [], "no node resolves a content size in a fully-sized tree")
  assert.equal!(ui.needs_measure?, false, "the root reports the whole tree needs no measure")

  $measured_ids = []
  ui.find(:a).object.h = 80
  ui.find(:a).invalidate!
  ui.calculate_layout
  assert.equal!($measured_ids, [], "a dirtied fully-sized subtree still never measures")
end

def test_auto_container_enters_measure_pass(args, assert)
  $measured_ids = []
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0 }, id: :box, direction: :column) do
      node({ w: 30, h: 20, primitive_marker: :solid }, id: :a)
    end
  end

  assert.true!($measured_ids.include?(:box), "the auto container is measured")
  assert.equal!(ui.find(:box).needs_measure?, true, "and it reports needing measure")
end

# Dirty tracking: a change inside the auto container re-derives its size; a change
# confined to a fully-sized sibling subtree does not enter the measure pass.
def dirty_tracking_ui
  Conjuration::UI.build({ x: 0, y: 0, w: 800, h: 800 }, id: :root) do
    node({ x: 0, y: 700, anchor_x: 0, anchor_y: 1 }, id: :auto_box, direction: :column) do
      node({ w: 40, h: 40, primitive_marker: :solid }, id: :leaf)
    end
    node({ x: 400, y: 700, w: 100, h: 100, anchor_x: 0, anchor_y: 1 }, id: :sized_box) do
      node({ w: 50, h: 50, primitive_marker: :solid }, id: :sized_child)
    end
  end
end

def test_content_change_in_auto_container_rederives_it(args, assert)
  ui = dirty_tracking_ui
  auto_box = ui.find(:auto_box)
  assert.equal!(auto_box.object.h, 40, "initial auto height from the 40px leaf")

  $measured_ids = []
  ui.find(:leaf).object.h = 90
  ui.find(:leaf).invalidate!
  ui.calculate_layout

  assert.true!($measured_ids.include?(:auto_box), "the auto container re-derives on a content change")
  assert.equal!(auto_box.object.h, 90, "and its height follows the leaf")
end

def test_sized_subtree_change_does_not_trigger_measurement(args, assert)
  ui = dirty_tracking_ui

  $measured_ids = []
  ui.find(:sized_child).object.h = 70
  ui.find(:sized_child).invalidate!
  ui.calculate_layout

  assert.equal!($measured_ids.include?(:auto_box), false, "a fixed-subtree change leaves the auto container unmeasured")
  assert.equal!($measured_ids.include?(:sized_box), false, "and the fixed container itself never measures")
end

# --- Universal overflow default (lazy scroll / clip / visible) -----------------

class OverflowReconcileHost
  include Conjuration::UI::Builder

  attr_accessor :item_count, :mode

  def initialize
    @item_count = 1
    @mode = nil
  end

  def view
    node({ x: 0, y: 300, w: 100, h: 100, anchor_x: 0, anchor_y: 1, primitive_marker: :solid }, id: :box, overflow: @mode, gap: 0) do
      @item_count.times { |i| node({ w: 80, h: 40, primitive_marker: :solid }, id: "item_#{i}") }
    end
  end
end

def overflow_root(host)
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  root.calculate_layout
  root
end

def test_scroll_materializes_lazily_only_once_content_overflows(args, assert)
  host = OverflowReconcileHost.new
  root = overflow_root(host)
  box = root.find(:box)

  assert.equal!(box.scroll?, false, "one 40px item fits the 100px box: not a scroll container")
  assert.equal!(root.primitives.any? { |p| p[:path] == box.scroll_target_path }, false, "no render target is materialized")
  assert.equal!(root.primitives.any? { |p| p[:w] == 80 }, true, "the child renders directly in the flat list")

  host.item_count = 3 # 120px of content in the 100px box
  root.render_view
  root.calculate_layout

  assert.equal!(box.scroll?, true, "overflow flips it into a scroll container")
  assert.equal!(root.primitives.any? { |p| p[:path] == box.scroll_target_path }, true, "the render target is now materialized")
  assert.equal!(root.primitives.any? { |p| p[:w] == 80 }, false, "the children are clipped into the target, not the flat list")
  assert.true!(box.max_scroll > 0, "it reports scrollable extent")
end

def test_overflowing_default_container_becomes_focusable(args, assert)
  host = OverflowReconcileHost.new
  host.item_count = 3
  root = overflow_root(host)

  assert.equal!(root.interactive_nodes.map(&:id), [:box], "the lazily-scrolling container is navigable, like an explicit one")
end

def test_overflow_warns_once(args, assert)
  host = OverflowReconcileHost.new
  root = overflow_root(host)
  Conjuration::UI.warnings.clear

  host.item_count = 3
  root.render_view
  root.calculate_layout

  host.item_count = 5 # still overflowing, relayout again
  root.render_view
  root.calculate_layout

  overflow_warnings = Conjuration::UI.warnings.select { |w| w.include?("overflows") && w.include?(":box") }
  assert.equal!(overflow_warnings.length, 1, "the overflow warning fires once per node, not every relayout")
end

def test_clip_clips_without_a_scrollbar_or_interaction(args, assert)
  host = OverflowReconcileHost.new
  host.mode = :clip
  host.item_count = 3
  root = overflow_root(host)
  box = root.find(:box)

  assert.equal!([box.clip?, box.scroll?], [true, false], "clip uses a render target but is not a scroll container")
  assert.equal!(root.primitives.any? { |p| p[:path] == box.scroll_target_path }, true, "content is clipped into the target")
  assert.equal!(root.primitives.any? { |p| p[:w] == 4 }, false, "no scrollbar thumb is drawn")
  assert.equal!(root.interactive_nodes, [], "a clip container is not focusable")
end

def test_visible_spills_without_scrolling(args, assert)
  host = OverflowReconcileHost.new
  host.mode = :visible
  host.item_count = 3
  root = overflow_root(host)
  box = root.find(:box)

  assert.equal!([box.scroll?, box.clip?], [false, false], "explicit :visible never scrolls or clips")
  assert.equal!(root.primitives.any? { |p| p[:path] == box.scroll_target_path }, false, "no render target")
  assert.equal!(root.primitives.select { |p| p[:w] == 80 }.length, 3, "all children spill into the flat list")
end

def test_absolute_child_never_counts_toward_overflow(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 300, w: 100, h: 50, anchor_x: 0, anchor_y: 1, primitive_marker: :solid }, id: :box) do
      node({ w: 80, h: 200, primitive_marker: :solid }, id: :overhang, position: :absolute, top: 0, left: 0)
    end
  end
  box = ui.find(:box)

  assert.equal!(box.scroll?, false, "a 200px absolute child overhanging a 50px box is not overflow")
end
