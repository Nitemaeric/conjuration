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

def test_zoom_out_reclamps_focal_point_to_bounds(args, assert)
  cam = make_camera(scene_virtual: 2000, current: { x: 640, y: 360, zoom: 2 })
  # half = (w/2)/zoom = 320 at zoom 2, so the focal point reaches 2000 - 320.
  cam.current.x = 5000
  assert.equal!(cam.current.x, 1680, "parked at the zoomed-in right edge")

  # Zoom out to 1: half widens to 640, so the edge is now 2000 - 640 = 1360.
  cam.current.zoom = 1
  assert.equal!(cam.current.x, 1360, "zooming out re-clamps x to the widened bound")
end

def test_delegate_forwards_kwargs_and_block(args, assert)
  target_class = Class.new do
    def record(*args, **kwargs, &block)
      { args: args, kwargs: kwargs, block: block && block.call }
    end
  end

  node_class = Class.new(Conjuration::Node) do
    attr_accessor :target
    delegate :record, to: :target
  end

  node = node_class.new
  node.target = target_class.new

  result = node.record(1, 2, key: :value) { :from_block }
  assert.equal!(result[:args], [1, 2], "positional args forwarded")
  assert.equal!(result[:kwargs], { key: :value }, "keyword args forwarded (were dropped before)")
  assert.equal!(result[:block], :from_block, "block forwarded (was dropped before)")
end

def test_delegate_forwards_plain_call_without_stray_hash(args, assert)
  # A zero-arity target: a stray empty-kwargs {} positional would raise here.
  target_class = Class.new { def ping; :pong; end }

  node_class = Class.new(Conjuration::Node) do
    attr_accessor :target
    delegate :ping, to: :target
  end

  node = node_class.new
  node.target = target_class.new
  assert.equal!(node.ping, :pong, "a no-arg delegate forwards nothing extra")
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
