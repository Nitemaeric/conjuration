# Chunk-caching tile layer: bucketing into chunks, lazy one-time chunk rendering,
# and view-based culling. Each test uses a unique layer name so its chunk render
# targets don't collide on the shared $game.outputs.

def test_add_files_primitive_into_its_chunk(args, assert)
  layer = Conjuration::TileLayer.new(name: :add, chunk_size: 400)
  layer.add({ x: 450, y: 50, w: 40, h: 40, path: :pixel })

  layer.draw(make_camera(current: { x: 640, y: 360, zoom: 1 })) # view (0,0,1280,720)

  target = $game.outputs["tile_layer_add_1_0"]
  assert.equal!(target.primitives.length, 1, "filed into chunk (1,0)")
  assert.equal!(target.primitives.first[:x], 50, "stored in chunk-local x (450 - 400)")
  assert.equal!(target.primitives.first[:y], 50, "chunk-local y")
end

def test_draw_culls_chunks_outside_view(args, assert)
  layer = Conjuration::TileLayer.new(name: :cull, chunk_size: 400)
  layer.add({ x: 10, y: 10, w: 40, h: 40, path: :pixel })     # chunk (0,0)
  layer.add({ x: 5000, y: 5000, w: 40, h: 40, path: :pixel }) # chunk (12,12), far off

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })     # view (0,0,1280,720)
  layer.draw(cam)

  assert.true!($game.outputs.targets.key?("tile_layer_cull_0_0"), "near chunk rendered")
  assert.false!($game.outputs.targets.key?("tile_layer_cull_12_12"), "far chunk never touched")

  sprites = cam.outputs.primitives.select { |p| p[:path].to_s.start_with?("tile_layer_cull_") }
  assert.equal!(sprites.length, 1, "only the visible chunk is drawn")
  assert.equal!(sprites.first[:path], "tile_layer_cull_0_0", "and it is the near chunk")
end

def test_draw_transforms_chunk_sprite_to_viewport(args, assert)
  layer = Conjuration::TileLayer.new(name: :pos, chunk_size: 400)
  layer.add({ x: 410, y: 10, w: 40, h: 40, path: :pixel }) # chunk (1,0)

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  layer.draw(cam)

  sprite = cam.outputs.primitives.find { |p| p[:path] == "tile_layer_pos_1_0" }
  assert.true!(!sprite.nil?, "chunk (1,0) sprite emitted")
  # World chunk (400,0,400,400) at zoom 1 with view origin (0,0) -> same coords.
  assert.equal!([sprite[:x], sprite[:y], sprite[:w], sprite[:h]], [400, 0, 400, 400], "world chunk mapped to viewport")
end

def test_chunk_renders_only_once(args, assert)
  layer = Conjuration::TileLayer.new(name: :once, chunk_size: 400)
  layer.add({ x: 10, y: 10, w: 40, h: 40, path: :pixel })

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  layer.draw(cam)
  layer.draw(cam)

  assert.equal!($game.outputs["tile_layer_once_0_0"].primitives.length, 1, "chunk rendered once despite two draws")
end

def test_remove_drops_intersecting_primitive(args, assert)
  layer = Conjuration::TileLayer.new(name: :rm_hit, chunk_size: 400)
  layer.add({ x: 10, y: 10, w: 40, h: 40, path: :pixel })

  layer.remove({ x: 20, y: 20, w: 5, h: 5 })

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  layer.draw(cam)

  sprites = cam.outputs.primitives.select { |p| p[:path].to_s.start_with?("tile_layer_rm_hit_") }
  assert.equal!(sprites.length, 0, "emptied chunk is dropped, nothing emitted")
end

def test_remove_ignores_primitives_it_does_not_touch(args, assert)
  layer = Conjuration::TileLayer.new(name: :rm_miss, chunk_size: 400)
  layer.add({ x: 10, y: 10, w: 40, h: 40, path: :pixel })

  layer.remove({ x: 200, y: 200, w: 20, h: 20 })

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  layer.draw(cam)

  assert.equal!($game.outputs["tile_layer_rm_miss_0_0"].primitives.length, 1, "untouched primitive survives")
end

def test_remove_reinvalidates_only_affected_chunks(args, assert)
  layer = Conjuration::TileLayer.new(name: :rm_scope, chunk_size: 400)
  layer.add({ x: 10, y: 10, w: 40, h: 40, path: :pixel })
  layer.add({ x: 100, y: 100, w: 40, h: 40, path: :pixel })
  layer.add({ x: 450, y: 10, w: 40, h: 40, path: :pixel })

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  layer.draw(cam)

  t00 = $game.outputs["tile_layer_rm_scope_0_0"]
  t10 = $game.outputs["tile_layer_rm_scope_1_0"]
  t00.primitives << :sentinel
  t10.primitives << :sentinel

  layer.remove({ x: 0, y: 0, w: 60, h: 60 })

  layer.draw(cam)

  assert.false!(t00.primitives.include?(:sentinel), "affected chunk (0,0) was re-baked (texture cleared)")
  assert.equal!(t00.primitives.length, 1, "and holds only the surviving primitive B")
  assert.true!(t10.primitives.include?(:sentinel), "untouched chunk (1,0) was not re-rendered")
end

def test_remove_drops_a_border_spanning_primitive_from_every_chunk(args, assert)
  layer = Conjuration::TileLayer.new(name: :rm_span, chunk_size: 400)
  layer.add({ x: 390, y: 10, w: 20, h: 20, path: :pixel })

  cam = make_camera(current: { x: 640, y: 360, zoom: 1 })
  layer.draw(cam)
  assert.equal!($game.outputs["tile_layer_rm_span_0_0"].primitives.length, 1, "filed into chunk (0,0)")
  assert.equal!($game.outputs["tile_layer_rm_span_1_0"].primitives.length, 1, "filed into chunk (1,0)")

  layer.remove({ x: 392, y: 12, w: 2, h: 2 })

  cam.outputs.primitives.clear
  layer.draw(cam)

  sprites = cam.outputs.primitives.select { |p| p[:path].to_s.start_with?("tile_layer_rm_span_") }
  assert.equal!(sprites.length, 0, "both chunks emptied and dropped, nothing emitted")
end
