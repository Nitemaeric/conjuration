# Camera coordinate transforms + viewport culling (zoom math and virtual-scene
# rendering). Pure arithmetic, no DragonRuby needed.

def test_view_rect_at_zoom_one(args, assert)
  v = make_camera(current: { x: 640, y: 360, zoom: 1 }).view_rect
  assert.equal!(v[:x], 0, "view x")
  assert.equal!(v[:y], 0, "view y")
  assert.equal!(v[:w], 1280, "view w")
  assert.equal!(v[:h], 720, "view h")
end

def test_view_rect_shrinks_when_zoomed_in(args, assert)
  v = make_camera(current: { x: 640, y: 360, zoom: 2 }).view_rect
  assert.equal!(v[:w], 640, "view w halves at 2x zoom")
  assert.equal!(v[:h], 360, "view h halves at 2x zoom")
  assert.equal!(v[:x], 320, "view recentred on focal point")
  assert.equal!(v[:y], 180, "view recentred on focal point")
end

def test_to_world_maps_viewport_centre_to_focal_point(args, assert)
  cam = make_camera(current: { x: 800, y: 600, zoom: 2 })
  w = cam.to_world(x: 640, y: 360) # screen centre
  assert.close!(w[:x], 800, "centre -> focal x")
  assert.close!(w[:y], 600, "centre -> focal y")
end

def test_to_screen_inverts_to_world(args, assert)
  cam = make_camera(x: 100, y: 50, w: 640, h: 720, current: { x: 800, y: 600, zoom: 2 })
  back = cam.to_screen(**cam.to_world(x: 300, y: 220).slice(:x, :y))
  assert.close!(back[:x], 300, "round-trip x")
  assert.close!(back[:y], 220, "round-trip y")
end

def test_to_viewport_applies_pan_and_zoom(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 2 })
  # World rect at the view's top-left corner (320,180) should land at (0,0)
  # and be scaled 2x.
  vp = cam.to_viewport({ x: 320, y: 180, w: 40, h: 40 })
  assert.close!(vp[:x], 0, "viewport x")
  assert.close!(vp[:y], 0, "viewport y")
  assert.close!(vp[:w], 80, "viewport w scaled by zoom")
  assert.close!(vp[:h], 80, "viewport h scaled by zoom")
end

def test_to_viewport_preserves_render_keys(args, assert)
  vp = make_camera.to_viewport({ x: 0, y: 0, w: 10, h: 10, path: :pixel, r: 1, g: 2, b: 3 })
  assert.equal!(vp[:path], :pixel, "path preserved")
  assert.equal!(vp[:r], 1, "colour preserved")
end

def test_visible_culls_offscreen_rects(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  assert.true!(cam.visible?({ x: 100, y: 100, w: 40, h: 40 }), "rect inside view is visible")
  assert.true!(!cam.visible?({ x: 2000, y: 100, w: 40, h: 40 }), "rect right of view is culled")
  assert.true!(!cam.visible?({ x: -100, y: 100, w: 40, h: 40 }), "rect left of view is culled")
end

def test_visible_respects_zoomed_in_view(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 2 }) # view (320,180,640,360)
  assert.true!(cam.visible?({ x: 330, y: 190, w: 10, h: 10 }), "inside the tighter zoomed view")
  assert.true!(!cam.visible?({ x: 1000, y: 190, w: 10, h: 10 }), "outside the tighter zoomed view")
end
