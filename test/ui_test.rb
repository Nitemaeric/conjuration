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

  # The container has no primitive_marker, so only the two solid children render.
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
