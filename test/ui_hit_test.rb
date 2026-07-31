# Deepest-hit mouse resolution (Node#deepest_hit): buttons inside interactive
# containers win over the container, scrolled children are hit at their DRAWN
# position (layout rect + scroll_offset), and a render-target pane clips its
# subtree from hit-testing exactly as it clips it from rendering.

def hit_ui
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 300, w: 100, h: 100 }, id: :scroller, overflow: :scroll, justify: :start, align: :start) do
      node({ w: 80, h: 80, primitive_marker: :solid, action: -> {} }, id: :a)
      node({ w: 80, h: 80, primitive_marker: :solid, action: -> {} }, id: :b)
      node({ w: 80, h: 80, primitive_marker: :solid, action: -> {} }, id: :c)
    end
  end
end

def centre_point(node, dy: 0)
  obj = node.object
  x = obj.x - (obj[:anchor_x] || 0) * obj.w + obj.w / 2
  y = obj.y - (obj[:anchor_y] || 0) * obj.h + obj.h / 2
  { x: x, y: y + dy, w: 0, h: 0 }
end

def test_button_inside_interactive_container_wins(args, assert)
  ui = hit_ui
  a = ui.find(:a)

  hit = ui.find_interactive_intersect(centre_point(a))

  assert.equal!(hit.id, :a, "the deepest interactive node wins, not the enclosing scroll pane")
end

def test_scroll_pane_itself_hit_on_empty_area(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 300, w: 100, h: 100 }, id: :scroller, overflow: :scroll, justify: :start, align: :start) do
      node({ w: 80, h: 20, primitive_marker: :solid, action: -> {} }, id: :small)
    end
  end
  small = ui.find(:small)

  hit = ui.find_interactive_intersect({ x: 50, y: small.object.y - 30, w: 0, h: 0 })

  assert.equal!(hit.id, :scroller, "empty pane area still hits the pane, keeping it wheel/stick scrollable")
end

def test_scrolled_children_hit_at_drawn_position(args, assert)
  ui = hit_ui
  scroller = ui.find(:scroller)
  b = ui.find(:b)
  scroller.scroll_offset = 70

  drawn = ui.find_interactive_intersect(centre_point(b, dy: 70))
  stale = ui.find_interactive_intersect(centre_point(b))

  assert.equal!(drawn.id, :b, "a scrolled child is hit where it is drawn (layout + scroll_offset)")
  assert.true!(stale.nil? || stale.id != :b, "its unshifted layout position no longer hits it")
end

def test_overflowing_children_not_hit_outside_the_pane(args, assert)
  ui = hit_ui
  c = ui.find(:c)
  below_pane = centre_point(c)

  assert.true!(below_pane[:y] < ui.find(:scroller).object.y, "sanity: c's layout rect overflows below the pane box")
  assert.nil!(ui.find_interactive_intersect(below_pane), "clipped-away content is not clickable outside the pane")
end

def test_wheel_targets_the_innermost_scroll_pane(args, assert)
  ui = Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root) do
    node({ x: 0, y: 100, w: 300, h: 300 }, id: :outer, overflow: :scroll, justify: :start, align: :start) do
      node({ w: 200, h: 200 }, id: :inner, overflow: :scroll, justify: :start, align: :start) do
        node({ w: 180, h: 400, primitive_marker: :solid }, id: :tall)
      end
      node({ w: 200, h: 300, primitive_marker: :solid }, id: :filler)
    end
  end
  inner = ui.find(:inner)

  hit = ui.find_scroll_intersect(centre_point(inner))

  assert.equal!(hit.id, :inner, "the innermost scroll pane under the cursor takes the wheel")
end
