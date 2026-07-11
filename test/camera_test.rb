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

def test_visible_accounts_for_anchors(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 }) # view (0,0,1280,720)
  # anchor 0.5, w 460 -> visual bounds 1170..1630
  assert.true!(cam.visible?({ x: 1400, y: 100, w: 460, h: 210, anchor_x: 0.5 }),
               "half-anchored sprite straddling the right edge is visible")
  assert.true!(!cam.visible?({ x: 1400, y: 100, w: 460, h: 210 }),
               "same rect without anchor stays culled (bounds 1400..1860)")
  assert.true!(cam.visible?({ x: 100, y: 750, w: 40, h: 80, anchor_y: 0.5 }),
               "half-anchored sprite straddling the top edge is visible")
  assert.true!(!cam.visible?({ x: -60, y: 100, w: 40, h: 40, anchor_x: 0.5 }),
               "anchored sprite fully left of view is culled")
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

def test_parallax_culls_against_the_derived_view_not_the_real_view(args, assert)
  # Real view spans x 1360..2640; the 0.5 parallax view spans 360..1640.
  cam = make_camera(current: { x: 2000, y: 360, zoom: 1 })
  near = { x: 500,  y: 360, w: 40, h: 40 }
  far  = { x: 2600, y: 360, w: 40, h: 40 }

  assert.true!(cam.visible?(near, 0.5), "a sprite inside the parallax view is kept")
  assert.false!(cam.visible?(far, 0.5), "a sprite outside the parallax view is culled")

  assert.false!(cam.visible?(near), "the real view wrongly culls the near sprite (the DIY bug)")
  assert.true!(cam.visible?(far), "the real view wrongly keeps the far sprite (the DIY bug)")
end

def test_parallax_edge_inclusivity_matches_the_default_cull(args, assert)
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

  cam.draw({ x: 500, y: 360, w: 40, h: 40, tag: :hill }, parallax: 0.5)

  assert.equal!(cam.outputs.primitives.length, 1, "the parallax sprite is emitted, not culled")
  assert.close!(cam.outputs.primitives.first[:x], 500 - 360, "emitted at its parallax-view position")
end

def test_no_parallax_draw_never_creates_the_factor_cache(args, assert)
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

# Draw-order inspector (Camera#dump_draw_order). The dump reads through the same
# #each_ordered_draw the render flush uses, so its order can't drift from what DR
# composites. Value tokens are `key=value`; this pulls one out of a prim line.

def draw_order_field(line, key)
  token = line.split(" ").find { |t| t.start_with?("#{key}=") }
  token && token.split("=", 2)[1]
end

def test_dump_draw_order_matches_the_actual_flush_order(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "top" }, z: 5)
  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "bottom" }, z: -5)
  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "mid" }, z: 0)
  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "mid2" }, z: 0)

  dump_order = cam.dump_draw_order.split("\n")
    .select { |l| l.start_with?("prim ") }
    .map { |l| draw_order_field(l, "tag") }

  cam.send(:flush_ordered_draws)
  flush_order = cam.outputs.primitives.map { |p| p[:dbg] }

  assert.equal!(dump_order, ["bottom", "mid", "mid2", "top"], "dump lists prims in z then emission order")
  assert.equal!(dump_order, flush_order, "dump order equals the real flush order (shared comparator)")
end

def test_dump_draw_order_header_fields(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 2 })
  cam.outputs.primitives.clear

  lines = cam.dump_draw_order.split("\n")
  cam_line = lines.find { |l| l.start_with?("camera ") }
  view_line = lines.find { |l| l.start_with?("view ") }

  assert.true!(lines[0].start_with?("# conjuration draw-order dump v1"), "versioned header comment")
  assert.equal!(draw_order_field(cam_line, "name"), "test", "camera name in the header")
  assert.equal!(draw_order_field(cam_line, "x"), "640", "camera focal x")
  assert.equal!(draw_order_field(cam_line, "zoom"), "2", "camera zoom")
  assert.equal!(draw_order_field(view_line, "w"), "640.0", "view width reflects the 2x zoom")
end

def test_dump_draw_order_tag_passthrough_and_absence(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "hero" }, z: 1)
  cam.draw({ x: 120, y: 100, w: 10, h: 10 }, z: 2) # no dbg tag

  prim_lines = cam.dump_draw_order.split("\n").select { |l| l.start_with?("prim ") }
  tagged = prim_lines.find { |l| draw_order_field(l, "z") == "1" }
  untagged = prim_lines.find { |l| draw_order_field(l, "z") == "2" }

  assert.equal!(draw_order_field(tagged, "tag"), "hero", "a dbg-tagged prim carries its tag into the dump")
  assert.equal!(draw_order_field(untagged, "tag"), "", "an untagged prim serialises an empty tag")
end

def test_draw_carries_dbg_only_when_present(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.draw({ x: 100, y: 100, w: 10, h: 10 })                 # untagged immediate
  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "flagged" }) # tagged immediate

  plain, flagged = cam.outputs.primitives
  assert.true!(!plain.key?(:dbg), "an untagged primitive never gains a dbg key (free on the render path)")
  assert.equal!(flagged[:dbg], "flagged", "a tagged primitive rides dbg through to_viewport unchanged")
end

def test_dump_draw_order_writes_to_an_io_ish_sink(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear
  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "a" }, z: 1)

  sink = []
  returned = cam.dump_draw_order(sink)

  assert.equal!(sink.length, 1, "the io-ish sink received the text via <<")
  assert.equal!(sink.first, returned, "the returned text is exactly what was written")
  assert.true!(sink.first.include?("tag=a"), "the sink holds the serialised prim")
end

def test_dump_draw_order_defaults_to_a_sandboxed_gtk_write(args, assert)
  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  cam.outputs.primitives.clear

  text = cam.dump_draw_order
  write = cam.gtk.last_write

  assert.equal!(write[:path], "draw_order_test.txt", "nil arg routes to a per-camera sandboxed filename")
  assert.equal!(write[:contents], text, "gtk.write_file gets the same text that is returned")
end

def test_dump_draw_order_string_path_routes_through_gtk(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear

  cam.dump_draw_order("custom_dump.txt")
  assert.equal!(cam.gtk.last_write[:path], "custom_dump.txt", "a String path is treated as a gtk write target")
end

def test_dump_draw_order_keeps_no_state_between_calls(args, assert)
  cam = make_camera
  cam.outputs.primitives.clear
  cam.view_rect # warm the per-frame view memo so it isn't counted as new state

  before = cam.instance_variables.sort
  cam.draw({ x: 100, y: 100, w: 10, h: 10, dbg: "a" }, z: 1)
  cam.dump_draw_order([])
  cam.send(:flush_ordered_draws)

  assert.equal!(cam.instance_variables.sort, before, "dumping introduces no new instance variables")
  assert.true!(cam.instance_variable_get(:@draw_buffer).empty?, "the buffer still drains on flush")
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
