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

# --- interaction states ---

def interaction_ui
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :container) do
      node({ w: 50, h: 50, path: "base.png", action: -> {}, hover: { path: "hover.png" } }, id: :button)
      node({ w: 50, h: 50, primitive_marker: :solid, action: -> {}, disabled: true }, id: :off)
    end
  end
end

def test_styled_object_merges_the_hover_override_when_focused(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil

  assert.equal!(button.styled_object[:path], "base.png", "default state renders the base object")

  Conjuration::UI.focused_node = button
  assert.equal!(button.styled_object[:path], "hover.png", "hover merges the override")
ensure
  Conjuration::UI.focused_node = nil
end

def test_disabled_nodes_are_excluded_from_interactive_nodes(args, assert)
  assert.equal!(interaction_ui.interactive_nodes.map(&:id), [:button], "disabled nodes drop out of interactive_nodes")
end

def test_pressed_state_takes_priority_over_hover(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  button.object.merge!(pressed: { path: "pressed.png" })
  Conjuration::UI.focused_node = button
  Conjuration::UI.pressed_node = button

  assert.equal!(button.styled_object[:path], "pressed.png", "pressed wins over hover")
ensure
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
end

def test_a_node_knows_its_own_focused_and_pressed_state(args, assert)
  ui = interaction_ui
  button = ui.find(:button)
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil

  assert.equal!(button.focused?, false, "not focused by default")

  Conjuration::UI.focused_node = button
  assert.equal!(button.focused?, true, "focused? reflects UI.focused_node")
  assert.equal!(ui.find(:off).focused?, false, "a sibling node is not focused")

  Conjuration::UI.pressed_node = button
  assert.equal!(button.pressed?, true, "pressed? reflects UI.pressed_node")
ensure
  Conjuration::UI.focused_node = nil
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
    node({ x: 0, y: 0, w: 10, h: 10 }, id: :left, group: :left) do
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
