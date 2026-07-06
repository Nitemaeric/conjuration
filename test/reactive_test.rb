# Tests for the reactive UI reconciler. A host object stands in for a scene: it
# includes the Builder so node() resolves against it, and its view methods read
# plain instance state — demonstrating that the view block keeps its own self
# (no instance_exec). Phase 1 covers declared-props diffing on stable trees;
# Phase 2 covers keyed structural reconcile, conditional rendering, focus/scroll
# preservation, and memo.

class ReconcileHost
  include Conjuration::UI::Builder

  attr_accessor :items, :count, :show_banner, :memo_key, :dep_list, :build_count

  def initialize(items: [])
    @items = items
    @count = 0
    @show_banner = false
    @memo_key = 0
    @dep_list = []
    @build_count = 0
  end

  # A conditionally-rendered banner ahead of a keyed list — the whole sibling
  # group is keyed, so a toggle reconciles cleanly.
  def conditional_view
    node({ x: 0, y: 0, w: 200, h: 400 }, id: :panel, gap: 4) do
      node({ text: "banner" }, id: :banner) if show_banner
      items.each { |item| node({ w: 180, h: 20, path: :pixel, r: item[:r], g: 0, b: 0 }, id: "item_#{item[:id]}") }
    end
  end

  # An UNkeyed list — rows have no id, so a length change can't reconcile by key
  # and the reconciler warns.
  def unkeyed_view
    node({ x: 0, y: 0, w: 200, h: 400 }, id: :panel, gap: 4) do
      items.each { node({ w: 180, h: 20, path: :pixel }) }
    end
  end

  # A scroll container whose children change structurally — the container itself
  # is reused, so its scroll offset must survive.
  def scroll_view
    node({ x: 0, y: 0, w: 200, h: 100 }, id: :scroller, overflow: :scroll) do
      items.each { |item| node({ w: 180, h: 40, path: :pixel, r: item[:r], g: 0, b: 0 }, id: "item_#{item[:id]}") }
    end
  end

  # A memoized subtree; the block bumps build_count whenever it actually runs.
  def memo_view
    node({ x: 0, y: 0, w: 200, h: 400 }, id: :panel) do
      memo(:section, memo_key) do
        @build_count += 1
        node({ text: "memoized #{memo_key}" }, id: :memoized)
      end
    end
  end

  # A memo keyed on a mutable collection — the footgun the warning flags.
  def mutable_memo_view
    node({ x: 0, y: 0, w: 200, h: 400 }, id: :panel) do
      memo(:section, dep_list) { node({ text: "x" }, id: :memoized) }
    end
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

# --- Phase 2: structural reconcile, conditional rendering, memo --------------

def build_reactive(host, view_method)
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(view_method))
  root.render_view
  root.calculate_layout
  root
end

def test_keyed_create_adds_a_node_and_reuses_the_rest(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, r: 40 }])
  root = build_reactive(host, :list_view)
  item1 = root.find(:item_1)

  host.items = [{ id: 1, r: 40 }, { id: 2, r: 80 }]
  root.render_view
  root.calculate_layout

  assert.equal!(root.find(:item_1).equal?(item1), true, "the existing keyed node is reused")
  assert.equal!(root.find(:item_2).nil?, false, "a new keyed node is created for the added item")
  assert.equal!(root.find(:list).children.map(&:id), [:item_1, :item_2], "both items present in order")
end

def test_keyed_remove_drops_the_node_and_preserves_order(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, r: 40 }, { id: 2, r: 60 }, { id: 3, r: 80 }])
  root = build_reactive(host, :list_view)
  item1 = root.find(:item_1)
  item3 = root.find(:item_3)

  host.items = [{ id: 1, r: 40 }, { id: 3, r: 80 }] # middle removed
  root.render_view
  root.calculate_layout

  assert.equal!(root.find(:list).children.map(&:id), [:item_1, :item_3], "the middle node is removed and order is preserved")
  assert.equal!(root.find(:item_1).equal?(item1), true, "surviving nodes are reused, not rebuilt")
  assert.equal!(root.find(:item_3).equal?(item3), true, "surviving nodes are reused, not rebuilt")
  assert.equal!(root.find(:item_2), nil, "the removed node is gone")
end

def test_keyed_reorder_reuses_nodes_and_follows_declaration_order(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, r: 40 }, { id: 2, r: 80 }])
  root = build_reactive(host, :list_view)
  item1 = root.find(:item_1)
  item2 = root.find(:item_2)

  host.items = [{ id: 2, r: 80 }, { id: 1, r: 40 }] # swapped
  root.render_view
  root.calculate_layout

  list = root.find(:list)
  assert.equal!(list.children.map(&:id), [:item_2, :item_1], "children order follows the new declaration")
  assert.equal!(list.children[0].equal?(item2), true, "reordered nodes are reused by key, not rebuilt")
  assert.equal!(list.children[1].equal?(item1), true, "reordered nodes are reused by key, not rebuilt")
end

def test_conditional_node_appears_and_disappears(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, r: 40 }])
  root = build_reactive(host, :conditional_view)
  assert.equal!(root.find(:banner), nil, "the conditional node is absent while its flag is false")

  host.show_banner = true
  root.render_view
  root.calculate_layout
  assert.equal!(root.find(:banner).nil?, false, "it appears when the flag flips true")

  host.show_banner = false
  root.render_view
  root.calculate_layout
  assert.equal!(root.find(:banner), nil, "it disappears again when the flag flips false")
end

def test_removing_a_focused_node_clears_focus(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, r: 40 }, { id: 2, r: 60 }])
  root = build_reactive(host, :list_view)
  Conjuration::UI.focused_node = root.find(:item_2)

  host.items = [{ id: 1, r: 40 }] # item_2 removed
  root.render_view

  assert.equal!(Conjuration::UI.focused_node, nil, "focus is cleared when the focused node is discarded")
end

def test_reused_focused_node_keeps_focus(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, r: 40 }, { id: 2, r: 60 }])
  root = build_reactive(host, :list_view)
  item1 = root.find(:item_1)
  Conjuration::UI.focused_node = item1

  host.items = [{ id: 2, r: 60 }, { id: 1, r: 40 }] # reorder; item_1 survives
  root.render_view

  assert.equal!(Conjuration::UI.focused_node.equal?(item1), true, "focus survives a reorder that reuses the node")
ensure
  Conjuration::UI.focused_node = nil
end

def test_scroll_offset_survives_structural_change(args, assert)
  host = ReconcileHost.new(items: [{ id: 1, r: 40 }, { id: 2, r: 60 }])
  root = build_reactive(host, :scroll_view)
  scroller = root.find(:scroller)
  scroller.scroll_offset = 42

  host.items = [{ id: 1, r: 40 }, { id: 2, r: 60 }, { id: 3, r: 80 }] # child added
  root.render_view

  assert.equal!(root.find(:scroller).equal?(scroller), true, "the scroll container is reused")
  assert.equal!(root.find(:scroller).scroll_offset, 42, "its scroll offset survives a structural change to its children")
end

def test_memo_skips_the_block_while_deps_are_unchanged(args, assert)
  host = ReconcileHost.new
  host.memo_key = 5
  root = build_reactive(host, :memo_view)
  assert.equal!(host.build_count, 1, "the memo block runs on first build")

  root.render_view
  root.render_view

  assert.equal!(host.build_count, 1, "the memo block is not re-run while its dep is unchanged")
  assert.equal!(root.find(:memoized).object.text, "memoized 5", "the memoized subtree is intact")
end

def test_memo_reruns_when_a_dep_changes(args, assert)
  host = ReconcileHost.new
  host.memo_key = 5
  root = build_reactive(host, :memo_view)

  host.memo_key = 6
  root.render_view
  root.calculate_layout

  assert.equal!(host.build_count, 2, "the memo block re-runs when its dep changes")
  assert.equal!(root.find(:memoized).object.text, "memoized 6", "the subtree updates to the new value")
end

def test_memo_warns_on_a_mutable_dep(args, assert)
  Conjuration::UI.warnings.clear
  host = ReconcileHost.new
  host.dep_list = [1, 2]
  build_reactive(host, :mutable_memo_view)

  assert.equal!(Conjuration::UI.warnings.any? { |warning| warning.include?("mutable collection") }, true, "a mutable memo dep is flagged")
end

def test_unkeyed_sibling_change_warns(args, assert)
  Conjuration::UI.warnings.clear
  host = ReconcileHost.new(items: [{ id: 1 }, { id: 2 }])
  root = build_reactive(host, :unkeyed_view)

  host.items = [{ id: 1 }] # unkeyed list shrinks
  root.render_view

  assert.equal!(Conjuration::UI.warnings.any? { |warning| warning.include?("unkeyed sibling list") }, true, "an unkeyed sibling list changing length is flagged")
end

class StrayKeywordHost
  include Conjuration::UI::Builder

  def view
    node({ w: 100, h: 20, direction: :row }, id: :oops) # direction belongs as a keyword
  end
end

def test_layout_keyword_in_object_hash_warns(args, assert)
  Conjuration::UI.warnings.clear
  host = StrayKeywordHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view

  assert.equal!(Conjuration::UI.warnings.any? { |warning| warning.include?("direction") && warning.include?("object hash") }, true, "a node keyword placed inside the object hash is flagged")
end

class SwapChildHost
  include Conjuration::UI::Builder
  attr_accessor :mode

  def initialize
    @mode = :a
  end

  # Always one child, but its identity changes — a structural change that keeps
  # the child count the same.
  def swap_view
    node({ x: 0, y: 0, w: 200, h: 200 }, id: :panel, gap: 4) do
      if mode == :a
        node({ w: 100, h: 20, path: :pixel }, id: :a)
      else
        node({ w: 100, h: 20, path: :pixel }, id: :b)
      end
    end
  end
end

def test_same_count_child_swap_relayouts(args, assert)
  host = SwapChildHost.new
  root = build_reactive(host, :swap_view)
  a_y = root.find(:a).object.y

  host.mode = :b
  root.render_view

  panel = root.find(:panel)
  assert.equal!(panel.dirty?, true, "a same-count child swap forces the container dirty (a signature check would no-op — the child count is unchanged)")

  root.calculate_layout
  assert.equal!(root.find(:a), nil, "the old child is discarded")
  assert.equal!(root.find(:b).object.y, a_y, "the swapped-in child is laid out into the old child's slot")
end
