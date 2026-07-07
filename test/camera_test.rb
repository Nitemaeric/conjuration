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

# Parallax. `view_rect(parallax:)` scales the focal point by the factor, giving
# a background layer its own view; culling and transforming happen against that
# derived view. The exact bug a hand-rolled parallax has: it tests `visible?`
# against the REAL view, so layer sprites near the edges cull wrongly.

def test_parallax_culls_against_the_derived_view_not_the_real_view(args, assert)
  # Camera far from the origin so the derived view diverges from the real one.
  # Real view spans x 1360..2640; the 0.5 parallax view spans 360..1640.
  cam = make_camera(current: { x: 2000, y: 360, zoom: 1 })
  near = { x: 500,  y: 360, w: 40, h: 40 } # inside the parallax view, NOT the real view
  far  = { x: 2600, y: 360, w: 40, h: 40 } # inside the real view, NOT the parallax view

  assert.true!(cam.visible?(near, 0.5), "a sprite inside the parallax view is kept")
  assert.false!(cam.visible?(far, 0.5), "a sprite outside the parallax view is culled")

  # The DIY bug: culling against the real view (factor 1.0) gets both backwards.
  assert.false!(cam.visible?(near), "the real view wrongly culls the near sprite (the DIY bug)")
  assert.true!(cam.visible?(far), "the real view wrongly keeps the far sprite (the DIY bug)")
end

def test_parallax_edge_inclusivity_matches_the_default_cull(args, assert)
  # A sprite whose right edge just reaches the parallax view's left edge is out;
  # nudged one unit right, it is in — same boundary rule as the default cull.
  cam = make_camera(current: { x: 2000, y: 360, zoom: 1 }) # parallax .5 view x = 360
  assert.false!(cam.visible?({ x: 320, y: 360, w: 40, h: 40 }, 0.5), "touching the edge does not overlap")
  assert.true!(cam.visible?({ x: 321, y: 360, w: 40, h: 40 }, 0.5), "one unit inside the edge overlaps")
end

def test_view_rect_scales_only_translation_not_zoom(args, assert)
  cam = make_camera(current: { x: 2000, y: 360, zoom: 2 }) # zoomed view is 640x360
  v = cam.view_rect(parallax: 0.5)
  assert.equal!(v[:x], 2000 * 0.5 - 320, "focal x scaled by the factor")
  assert.equal!(v[:w], 640, "width (zoom) is un-scaled by parallax")
  assert.equal!(v[:h], 360, "height (zoom) is un-scaled by parallax")
end

def test_view_rect_parallax_one_is_the_memoized_default(args, assert)
  cam = make_camera
  # Factor 1.0 must return the very same object as the no-arg default — proving
  # the no-parallax path allocates no new view and never touches the factor hash.
  assert.true!(cam.view_rect(parallax: 1.0).equal?(cam.view_rect), "factor 1.0 is the memoized default view")
end

def test_to_viewport_at_parallax_one_matches_the_default_transform(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 2 })
  rect = { x: 320, y: 180, w: 40, h: 40, x2: 340, y2: 200, size_px: 30 }
  base = cam.to_viewport(rect)
  para = cam.to_viewport(rect, 1.0)

  assert.equal!(para[:x], base[:x], "x matches the default transform")
  assert.equal!(para[:y], base[:y], "y matches the default transform")
  assert.equal!(para[:w], base[:w], "w matches the default transform")
  assert.equal!(para[:x2], base[:x2], "x2 matches the default transform")
  assert.equal!(para[:size_px], base[:size_px], "size_px matches the default transform")
end

def test_to_viewport_transforms_against_the_parallax_view(args, assert)
  cam = make_camera(current: { x: 2000, y: 360, zoom: 1 }) # parallax .5 view x = 360
  vp = cam.to_viewport({ x: 360, y: 360, w: 40, h: 40 }, 0.5)
  assert.close!(vp[:x], 0, "a world point on the parallax view's left edge maps to viewport 0")
end

def test_draw_with_parallax_emits_via_the_derived_view(args, assert)
  cam = make_camera(current: { x: 2000, y: 360, zoom: 1 })
  cam.outputs.primitives.clear

  # This sprite is offscreen for the real view but on for the 0.5 layer, so the
  # naive path would drop it; parallax keeps and positions it.
  cam.draw({ x: 500, y: 360, w: 40, h: 40, tag: :hill }, parallax: 0.5)

  assert.equal!(cam.outputs.primitives.length, 1, "the parallax sprite is emitted, not culled")
  assert.close!(cam.outputs.primitives.first[:x], 500 - 360, "emitted at its parallax-view position")
end

def test_no_parallax_draw_never_creates_the_factor_cache(args, assert)
  # Zero-cost acceptance: a frame that never passes `parallax:` must not allocate
  # the per-factor view hash. It stays nil until a parallax draw needs it.
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 10, y: 10, w: 10, h: 10 })
  cam.draw({ x: 20, y: 20, w: 10, h: 10 }, z: 1)
  assert.nil!(cam.instance_variable_get(:@parallax_view_rects), "no-parallax draws leave the factor cache unallocated")

  cam.draw({ x: 30, y: 30, w: 10, h: 10 }, parallax: 0.5)
  assert.true!(!cam.instance_variable_get(:@parallax_view_rects).nil?, "a parallax draw lazily creates the cache")
end

def test_parallax_composes_with_z_ordering(args, assert)
  cam = make_camera(current: { x: 2000, y: 360, zoom: 1 })
  cam.outputs.primitives.clear

  cam.draw({ x: 500, y: 360, w: 40, h: 40, tag: :clouds }, parallax: 0.5, z: -100)
  assert.equal!(cam.outputs.primitives, [], "a z + parallax draw defers like any z draw")

  cam.send(:flush_ordered_draws)
  assert.equal!(cam.outputs.primitives.map { |p| p[:tag] }, [:clouds], "it flushes through the derived view")
end

# Deferred z-ordering in Camera#draw. make_camera's view is (0,0,1280,720) at
# zoom 1, so the small rects below are all visible. The camera's outputs double
# accumulates across tests (shared $game), so each test clears it first.

def test_draw_without_z_emits_immediately_in_call_order(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :a })
  cam.draw({ x: 20, y: 20, w: 10, h: 10, tag: :b })

  assert.equal!(cam.outputs.primitives.map { |p| p[:tag] }, [:a, :b], "no-z draws emit immediately, in call order")
end

def test_z_draws_are_deferred_until_flush(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :a }, z: 1)

  assert.equal!(cam.outputs.primitives, [], "a z-draw does not emit until the flush")
end

def test_deferred_draws_flush_sorted_by_z(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :top }, z: 5)
  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :bottom }, z: -5)
  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :mid }, z: 0)
  cam.send(:flush_ordered_draws)

  assert.equal!(cam.outputs.primitives.map { |p| p[:tag] }, [:bottom, :mid, :top], "deferred draws flush in ascending z order")
end

def test_equal_z_preserves_call_order(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :first }, z: 1)
  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :second }, z: 1)
  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :third }, z: 1)
  cam.send(:flush_ordered_draws)

  assert.equal!(cam.outputs.primitives.map { |p| p[:tag] }, [:first, :second, :third], "equal-z draws keep call order (stable)")
end

def test_unordered_draws_render_under_all_ordered_draws(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :ground })        # immediate
  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :hero }, z: -100) # deferred, very low z
  cam.send(:flush_ordered_draws)

  assert.equal!(cam.outputs.primitives.map { |p| p[:tag] }, [:ground, :hero], "unordered draws sit under all ordered draws, whatever their z")
end

def test_deferred_draw_still_culls_offscreen(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 5000, y: 5000, w: 10, h: 10, tag: :offscreen }, z: 1)
  cam.send(:flush_ordered_draws)

  assert.equal!(cam.outputs.primitives, [], "an offscreen z-draw is culled, never buffered")
end

def test_deferred_buffer_clears_between_flushes(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 10, y: 10, w: 10, h: 10, tag: :a }, z: 1)
  cam.send(:flush_ordered_draws)
  cam.outputs.primitives.clear
  cam.send(:flush_ordered_draws) # buffer already drained

  assert.equal!(cam.outputs.primitives, [], "the buffer is empty after a flush; a second flush emits nothing")
end

def test_deferred_draws_transform_like_immediate_draws(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 2 }) # view (320,180,640,360)
  cam.outputs.primitives.clear

  cam.draw({ x: 320, y: 180, w: 40, h: 40 }, z: 1)
  cam.send(:flush_ordered_draws)
  vp = cam.outputs.primitives.first

  assert.close!(vp[:x], 0, "deferred draw is panned to the viewport like an immediate one")
  assert.close!(vp[:w], 80, "deferred draw is zoom-scaled like an immediate one")
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

def test_directional_shake_oscillates_along_its_axis(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 }) # base view (0, 0)
  cam.shake(1.0, direction: { x: 1, y: 0 })
  v = cam.view_rect
  assert.equal!(v[:y], 0, "a horizontal impact has no vertical shake")
  assert.true!(v[:x].abs <= Conjuration::Camera::SHAKE_MAGNITUDE, "horizontal shake within magnitude")
end

def test_directional_shake_vertical_axis(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  cam.shake(1.0, direction: { x: 0, y: 1 })
  assert.equal!(cam.view_rect[:x], 0, "a vertical impact has no horizontal shake")
end

def test_directional_shake_normalizes_the_direction(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  cam.shake(1.0, direction: { x: 10, y: 0 }) # length 10, not unit
  assert.true!(cam.view_rect[:x].abs <= Conjuration::Camera::SHAKE_MAGNITUDE, "offset bounded despite a long direction vector")
end
