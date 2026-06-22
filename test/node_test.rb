# Node attribute merging and the zoom-/bound-aware focal point clamps.

def test_merge_sets_known_attributes(args, assert)
  klass = Class.new(Conjuration::Node) { attr_accessor :foo, :bar }
  obj = klass.new(foo: 1, bar: 2)
  assert.equal!(obj.foo, 1, "foo set")
  assert.equal!(obj.bar, 2, "bar set")
end

def test_merge_raises_on_unknown_attribute(args, assert)
  klass = Class.new(Conjuration::Node) { attr_accessor :foo }
  assert.raises!(ArgumentError, "unknown attribute should fail fast") do
    klass.new(nope: 1)
  end
end

def test_focal_point_clamps_within_virtual_bounds(args, assert)
  cam = make_camera(scene_virtual: 2000) # half = w/2 = 640 at zoom 1
  cam.current.x = 5000
  assert.equal!(cam.current.x, 1360, "clamped to virtual_w - half (2000 - 640)")
  cam.current.x = -100
  assert.equal!(cam.current.x, 640, "clamped to half")
end

def test_focal_point_pans_freely_when_unbounded(args, assert)
  cam = make_camera(scene_virtual: nil)
  cam.current.x = 5000
  assert.equal!(cam.current.x, 5000, "no clamp when virtual_w is nil")
end

def test_focal_point_clamp_widens_when_zoomed_in(args, assert)
  cam = make_camera(scene_virtual: 2000, current: { x: 640, y: 360, zoom: 2 })
  # half = (w/2)/zoom = 640/2 = 320, so reachable up to 2000 - 320 = 1680
  cam.current.x = 5000
  assert.equal!(cam.current.x, 1680, "zoomed-in view reaches closer to the edge")
end

def test_invisible_ui_node_is_not_interactive(args, assert)
  node = Conjuration::UI::Node.new({ x: 0, y: 0, w: 10, h: 10, action: -> {} })
  assert.true!(node.interactive?, "visible node with an action is interactive")
  node.visible = false
  assert.true!(!node.interactive?, "hidden node is not interactive")
end

def test_ui_node_without_action_is_not_interactive(args, assert)
  node = Conjuration::UI::Node.new({ x: 0, y: 0, w: 10, h: 10 })
  assert.true!(!node.interactive?, "no action -> not interactive")
end
