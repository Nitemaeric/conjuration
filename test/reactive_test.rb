# Tests for the reactive UI reconciler (Phase 1: view + declared-props diffing,
# stable trees). A host object stands in for a scene: it includes the Builder so
# node() resolves against it, and its view methods read plain instance state —
# demonstrating that the view block keeps its own self (no instance_exec).

class ReconcileHost
  include Conjuration::UI::Builder

  attr_accessor :items, :count

  def initialize(items: [])
    @items = items
    @count = 0
  end

  # A button (interactive node whose action lambda is recreated every frame).
  def button_view
    node({ x: 0, y: 0, w: 100, h: 40, path: :pixel, r: 40, g: 40, b: 40, action: -> {} }, id: :btn) do
      node({ text: "count: #{count}" }, id: :btn_label)
    end
  end

  # A container of item rows, each row wrapping a text label — enough structure
  # to exercise nested reconciliation and both object and text props.
  def list_view
    node({ x: 0, y: 0, w: 200, h: 400 }, id: :list, gap: 4) do
      items.each do |item|
        node({ w: 180, h: 20, path: :pixel, r: item[:r], g: 0, b: 0 }, id: "item_#{item[:id]}") do
          node({ text: "v #{item[:v]}" }, id: "label_#{item[:id]}")
        end
      end
    end
  end

  # Emits a node, then raises — to prove the descriptor build is fully separate
  # from reconciliation (nothing it emitted reaches the retained tree).
  def boom_view
    node({ text: "partial" }, id: :ghost)
    raise "boom"
  end
end

def test_view_produces_identical_primitives_to_imperative_build(args, assert)
  imperative = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 0, w: 200, h: 400 }, id: :list, gap: 4) do
      node({ w: 180, h: 20, path: :pixel, r: 40, g: 0, b: 0 }, id: :item_1) do
        node({ text: "v 10" }, id: :label_1)
      end
      node({ w: 180, h: 20, path: :pixel, r: 80, g: 0, b: 0 }, id: :item_2) do
        node({ text: "v 20" }, id: :label_2)
      end
    end
  end
  imperative.calculate_layout

  host = ReconcileHost.new(items: [{ id: 1, v: 10, r: 40 }, { id: 2, v: 20, r: 80 }])
  reactive = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  reactive.view(&host.method(:list_view))
  reactive.render_view
  reactive.calculate_layout

  assert.equal!(reactive.primitives, imperative.primitives, "the view build is byte-for-byte identical to the imperative build")
end

def test_reconcile_updates_props_and_preserves_node_identity(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, v: 10, r: 40 }])
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:list_view))
  root.render_view
  root.calculate_layout

  item = root.find(:item_1)
  label = root.find(:label_1)

  host.items = [{ id: 1, v: 99, r: 40 }]
  root.render_view
  root.calculate_layout

  assert.equal!(root.find(:item_1).equal?(item), true, "the retained item node is reused, not rebuilt")
  assert.equal!(root.find(:label_1).equal?(label), true, "the retained label node is reused, not rebuilt")
  assert.equal!(root.find(:label_1).object.text, "v 99", "the changed text is written onto the retained node")
end

def test_clean_frame_reconcile_dirties_nothing(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, v: 10, r: 40 }, { id: 2, v: 20, r: 80 }])
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:list_view))
  root.render_view
  root.calculate_layout

  # Re-run the view with identical state. The bench-gate invariant: an unchanged
  # frame is a hash compare per node and nothing re-dirties.
  root.render_view

  assert.equal!(root.nodes.select(&:dirty?), [], "an unchanged view leaves every node clean — zero layout work")
end

def test_render_only_change_updates_without_relayout(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, v: 10, r: 40 }])
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:list_view))
  root.render_view
  root.calculate_layout

  item = root.find(:item_1)
  host.items = [{ id: 1, v: 10, r: 200 }] # only the colour changed
  root.render_view

  assert.equal!(item.dirty?, false, "a colour-only change does not re-dirty layout (colour is not a layout input)")
  assert.equal!(item.object[:r], 200, "the new colour is still written to the node for the next primitives pass")
end

def test_view_exception_leaves_last_frame_intact(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, v: 10, r: 40 }])
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:list_view))
  root.render_view
  root.calculate_layout
  before = root.primitives

  # A view that raises partway through must not mutate the retained tree —
  # the descriptor build completes before reconciliation touches any node.
  root.view(&host.method(:boom_view))
  raised = false
  begin
    root.render_view
  rescue StandardError
    raised = true
  end

  assert.equal!(raised, true, "the exception propagates out of render_view")
  assert.equal!(root.find(:ghost), nil, "no partially-emitted node leaked into the retained tree")
  assert.equal!(root.primitives, before, "last frame's tree is fully intact")
end

def test_action_lambda_does_not_dirty_a_clean_frame(args, assert)
  host = ReconcileHost.new
  host.count = 1
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:button_view))
  root.render_view
  root.calculate_layout

  btn = root.find(:btn)
  root.render_view # the action lambda is a fresh object, but nothing else changed

  assert.equal!(btn.dirty?, false, "a recreated action lambda does not re-dirty the node")
  assert.equal!(btn.interactive?, true, "the node stays interactive — its action is written through")
end

def test_render_view_without_a_view_is_a_noop(args, assert)
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ w: 100, h: 100, primitive_marker: :solid }, id: :box)
  end
  root.calculate_layout
  before = root.primitives

  root.render_view # no view registered — the imperative path is untouched

  assert.equal!(root.primitives, before, "render_view no-ops when no view is registered")
  assert.equal!(root.find(:box).nil?, false, "the imperatively-built tree is left alone")
end
