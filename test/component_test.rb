# Tests for view components (Phase 3). Subclassing Conjuration::UI::View defines
# a builder method named after the class, so `SomeView(**props)` reads as a call.
# Components are pure props -> descriptors, so most tests render them in isolation
# via UI.render_component; the reconcile-facing ones use a host + render_view.

class LabelView < Conjuration::UI::View
  def initialize(text:, id:)
    @text = text
    @id = id
  end

  def call
    node({ text: @text }, id: @id)
  end
end

class MenuView < Conjuration::UI::View
  def initialize(items:)
    @items = items
  end

  def render?
    @items.any?
  end

  def call
    node({ x: 0, y: 0, w: 200, h: 300 }, id: :menu) do
      @items.each { |item| node({ text: item[:name] }, id: "opt_#{item[:id]}") }
    end
  end
end

# Same key (:menu), different structure — the type-swap case.
class NestedMenuView < Conjuration::UI::View
  def initialize(items:)
    @items = items
  end

  def call
    node({ x: 0, y: 0, w: 200, h: 300 }, id: :menu) do
      node({ text: "nested" }, id: :heading)
    end
  end
end

# A wrapper component: places the caller's block children via `content`.
class PanelView < Conjuration::UI::View
  def initialize(title:, id:)
    @title = title
    @id = id
  end

  def call
    node({ x: 0, y: 0, w: 200, h: 200 }, id: @id) do
      node({ text: @title }, id: :panel_title)
      content
    end
  end
end

# Composes other components.
class ToolbarView < Conjuration::UI::View
  def initialize(id:)
    @id = id
  end

  def call
    node({ x: 0, y: 0, w: 300, h: 40, direction: :row }, id: @id) do
      LabelView(text: "File", id: :file)
      LabelView(text: "Edit", id: :edit)
    end
  end
end

# Opt-in props memo; counts how often #call actually runs.
class MemoBadgeView < Conjuration::UI::View
  memoize_props!

  class << self
    attr_accessor :calls
  end

  def initialize(count:, id:)
    @count = count
    @id = id
  end

  def call
    self.class.calls = (self.class.calls || 0) + 1
    node({ text: "count #{@count}" }, id: @id)
  end
end

module CompNs
  class Gadget < Conjuration::UI::View
    def call
      node({ text: "gadget" }, id: :gadget)
    end
  end
end

# --- Hosts (stand in for scenes) ---------------------------------------------

class ContentHost
  include Conjuration::UI::Builder

  def view
    PanelView(title: "Header", id: :panel) do
      node({ text: "body" }, id: :body)
    end
  end
end

class SwapHost
  include Conjuration::UI::Builder
  attr_accessor :nested

  def initialize
    @nested = false
  end

  def view
    if nested
      NestedMenuView(items: [{ id: 1, name: "x" }])
    else
      MenuView(items: [{ id: 1, name: "x" }])
    end
  end
end

class MemoHost
  include Conjuration::UI::Builder
  attr_accessor :count

  def initialize
    @count = 0
  end

  def view
    node({ x: 0, y: 0, w: 200, h: 200 }, id: :panel) do
      MemoBadgeView(count: count, id: :badge)
    end
  end
end

# --- Tests -------------------------------------------------------------------

def test_component_renders_props_to_nodes(args, assert)
  descriptors = Conjuration::UI.render_component(MenuView, items: [{ id: 1, name: "New" }, { id: 2, name: "Load" }])

  assert.equal!(descriptors.length, 1, "the component emits its single root")
  menu = descriptors[0]
  assert.equal!(menu.opts[:id], :menu, "the root carries the declared id")
  assert.equal!(menu.component_class, MenuView, "the root descriptor is tagged with the component class")
  assert.equal!(menu.children.map { |child| child.object[:text] }, ["New", "Load"], "props drive the emitted children")
end

def test_component_render_predicate_gates_output(args, assert)
  assert.equal!(Conjuration::UI.render_component(MenuView, items: []), [], "render? false emits nothing")
  assert.equal!(Conjuration::UI.render_component(MenuView, items: [{ id: 1, name: "x" }]).length, 1, "render? true emits the tree")
end

def test_component_content_places_caller_children(args, assert)
  host = ContentHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view

  panel = root.find(:panel)
  assert.equal!(panel.children.map(&:id), [:panel_title, :body], "content is placed where the component calls content")
end

def test_components_compose(args, assert)
  toolbar = Conjuration::UI.render_component(ToolbarView, id: :toolbar)[0]

  assert.equal!(toolbar.children.map { |child| child.opts[:id] }, [:file, :edit], "a component can render other components")
  assert.equal!(toolbar.children.map(&:component_class), [LabelView, LabelView], "nested components are tagged with their own class")
end

def test_component_type_swap_remounts(args, assert)
  host = SwapHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  menu_before = root.find(:menu)
  assert.equal!(menu_before.component_class, MenuView, "first mounted as MenuView")

  host.nested = true
  root.render_view
  menu_after = root.find(:menu)

  assert.equal!(menu_after.component_class, NestedMenuView, "remounted as NestedMenuView")
  assert.equal!(menu_after.equal?(menu_before), false, "a type swap at the same key remounts (new node), not prop-morph")
  assert.equal!(menu_after.children.map(&:id), [:heading], "the new component's subtree replaces the old one")
end

def test_same_component_type_is_reused(args, assert)
  host = SwapHost.new
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  menu = root.find(:menu)

  root.render_view # same type, same key

  assert.equal!(root.find(:menu).equal?(menu), true, "the same component type at the same key is reused, not remounted")
end

def test_memoized_component_skips_call_on_equal_props(args, assert)
  MemoBadgeView.calls = 0
  host = MemoHost.new
  host.count = 1
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view
  assert.equal!(MemoBadgeView.calls, 1, "#call runs on first build")

  root.render_view
  assert.equal!(MemoBadgeView.calls, 1, "#call is skipped while props compare equal")

  host.count = 2
  root.render_view
  assert.equal!(MemoBadgeView.calls, 2, "#call re-runs when a prop changes")
  assert.equal!(root.find(:badge).object.text, "count 2", "the memoized subtree updates to the new prop")
end

def test_memoized_component_warns_on_mutable_prop(args, assert)
  Conjuration::UI.warnings.clear
  MemoBadgeView.calls = 0
  host = MemoHost.new
  host.count = [1, 2] # a mutable prop under a memoized component
  root = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root)
  root.view(&host.method(:view))
  root.render_view

  assert.equal!(Conjuration::UI.warnings.any? { |warning| warning.include?("mutable prop") }, true, "a memoized component flags a mutable prop")
end

def test_namespaced_component_defines_a_demodulised_builder(args, assert)
  assert.equal!(Conjuration::UI::Builder.method_defined?(:Gadget), true, "a namespaced component defines a builder under its demodulised name")
  assert.equal!(Conjuration::UI.render_component(CompNs::Gadget)[0].opts[:id], :gadget, "and renders its subtree")
end
