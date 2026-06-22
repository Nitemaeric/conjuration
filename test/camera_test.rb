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

def test_to_viewport_transforms_line_endpoints(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 2 }) # view (320,180,...)
  vp = cam.to_viewport({ x: 320, y: 180, x2: 340, y2: 200, primitive_marker: :line })
  assert.close!(vp[:x], 0, "x endpoint")
  assert.close!(vp[:x2], 40, "x2 endpoint panned + scaled ((340-320)*2)")
  assert.close!(vp[:y2], 40, "y2 endpoint")
end

def test_to_viewport_scales_label_size(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 2 })
  vp = cam.to_viewport({ x: 320, y: 180, text: "hi", size_px: 30 })
  assert.equal!(vp[:text], "hi", "text preserved")
  assert.close!(vp[:size_px], 60, "font size scales with zoom (30 * 2)")
end

def test_to_viewport_carries_anchors_through(args, assert)
  vp = make_camera(current: { x: 640, y: 360, zoom: 2 }).to_viewport({ x: 320, y: 180, w: 10, h: 10, anchor_x: 0.5, anchor_y: 1 })
  assert.equal!(vp[:anchor_x], 0.5, "anchor_x unchanged")
  assert.equal!(vp[:anchor_y], 1, "anchor_y unchanged")
end

def test_from_helpers_are_viewport_relative(args, assert)
  cam = make_camera(w: 640, h: 360) # a non-full-screen camera
  assert.equal!(cam.from_top(20), 340, "from_top is viewport h - 20, not grid")
  assert.equal!(cam.from_right(20), 620, "from_right is viewport w - 20")
  assert.equal!(cam.from_left(20), 20, "from_left is the distance")
  assert.equal!(cam.from_bottom(20), 20, "from_bottom is the distance")
end

def test_follow_points_target_at_the_object_each_tick(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  object = { x: 1000, y: 800 }
  cam.follow(object)
  cam.send(:perform_update)

  assert.equal!(cam.target.x, 1000, "target tracks the object's x")
  assert.equal!(cam.target.y, 800, "target tracks the object's y")
  assert.close!(cam.current.x, 1000, "current eases onto the target (default speed locks)")
end

def test_follow_keeps_tracking_as_the_object_moves(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  object = { x: 1000, y: 800 }
  cam.follow(object)
  cam.send(:perform_update)
  object[:x] = 1500 # the object moved
  cam.send(:perform_update)

  assert.equal!(cam.target.x, 1500, "target follows the object to its new position")
end

def test_positional_look_at_stops_following(args, assert)
  cam = make_camera
  cam.follow({ x: 1000, y: 800 })
  cam.look_at(x: 200, y: 200)
  assert.true!(cam.following.nil?, "a positional look_at ends the follow")
end

def test_zoom_only_look_at_keeps_following(args, assert)
  cam = make_camera
  object = { x: 1000, y: 800 }
  cam.follow(object)
  cam.look_at(zoom: 2)
  assert.equal!(cam.following, object, "a zoom-only look_at leaves the follow running")
end

def test_unfollow_stops_following(args, assert)
  cam = make_camera
  cam.follow({ x: 1, y: 1 })
  cam.unfollow
  assert.true!(cam.following.nil?, "unfollow clears the followed object")
end

def test_shake_adds_and_caps_trauma(args, assert)
  cam = make_camera
  cam.shake(0.6)
  assert.close!(cam.trauma, 0.6, "trauma accumulates")
  cam.shake(1.0)
  assert.close!(cam.trauma, 1.0, "trauma is capped at 1.0")
end

def test_trauma_decays_each_update(args, assert)
  cam = make_camera
  cam.shake(0.5)
  cam.send(:perform_update)
  assert.true!(cam.trauma < 0.5, "trauma decays on update")
end

def test_view_is_unshaken_without_trauma(args, assert)
  v = make_camera(current: { x: 640, y: 360, zoom: 1 }).view_rect
  assert.equal!(v[:x], 0, "view x unshaken with no trauma")
  assert.equal!(v[:y], 0, "view y unshaken with no trauma")
end

def test_shake_offsets_view_within_magnitude(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  cam.shake(1.0) # peak trauma -> peak offset is SHAKE_MAGNITUDE
  v = cam.view_rect
  max = Conjuration::Camera::SHAKE_MAGNITUDE
  assert.true!(v[:x].abs <= max, "shake x within magnitude")
  assert.true!(v[:y].abs <= max, "shake y within magnitude")
end
