# TileLayer

`Conjuration::TileLayer` caches static world content into fixed-size chunk
render targets, so a dense world draws as a handful of textured quads instead of
thousands of primitives every frame.

This document is the **contract**. Conjuration ships no tilemap *format* support
and no plugin system — a tilemap importer is simply anything that reads a map
file and calls `TileLayer#add` with world-space primitives. Format packages
(e.g. `conjuration-tiled`, `conjuration-ldtk`) live as separate drenv packages
and target the interface described here.

## Example

```ruby
class OverworldScene < Conjuration::Scene
  def setup
    self.virtual_w = self.virtual_h = 2000
    add_camera(:main)

    @ground = Conjuration::TileLayer.new(name: :ground, chunk_size: 400)

    # An importer bakes its map into world-space primitives here, once.
    map.each_cell do |cell|
      @ground.add({ x: cell.x, y: cell.y, w: 32, h: 32, path: cell.sprite })
    end
  end

  def draw_world(camera)
    @ground.draw(camera)     # cached: only visible chunks are emitted
    # dynamic overlays (hover, entities, projectiles) go straight to camera.draw
  end
end
```

## The contract

### World-space primitives in

`#add(primitive)` takes a **DragonRuby primitive as a rect-like hash in
world-space coordinates** — the same `{ x:, y:, w:, h:, path:, ... }` you would
push to `camera.draw`, positioned in the world, not on screen. Any extra keys
(`r`, `g`, `b`, `a`, `angle`, `primitive_marker: :border`, …) are preserved and
passed through to the render target unchanged; `TileLayer` only reads `x`, `y`,
`w`, and `h` (a missing `w`/`h` is treated as `0`).

An importer's entire responsibility is to translate its map format into these
primitives and feed them to `#add`. It never needs to know about chunks.

### Chunking behaviour

The layer partitions the world into a grid of `chunk_size × chunk_size` cells
(default `512`). On `#add`, a primitive is filed into **every chunk its bounds
overlap**, stored in that chunk's local coordinates; a primitive straddling a
border is copied into each chunk it touches, and the chunk's render target clips
any overhang.

On `#draw(camera)`, only chunks overlapping the camera's view rect are
considered, and each visible chunk's texture is rendered **lazily — once — then
sampled** as a single sprite. Because chunk targets are bounded by `chunk_size`,
the world itself can be arbitrarily large without exceeding the GPU texture
limit, and zooming all the way out costs one draw per visible chunk rather than
one per tile.

### Static-content assumption

Content added to a `TileLayer` is assumed **static**: it is baked into a texture
and that texture is reused every frame until explicitly invalidated. Anything
that changes per frame — hover highlights, selection, entities, projectiles,
animation — does **not** belong in a `TileLayer`. Draw it directly in
`camera.draw` (see the demo's `BasicCameraScene#draw_world`, where the static
grid comes from a `TileLayer` and the hover highlight and moving target are
immediate `camera.draw` calls).

### Invalidation

`#remove(rect)` is the escape hatch for content that is static *until a
discrete event changes it* — a destructible wall blown open, a bridge that
collapses, a door that opens. It drops stored primitives and invalidates the
affected chunks so their textures re-bake on the next `#draw`, **chunk-granular**
so one destructible tile re-renders its chunk (and any chunk a spanning
primitive reached) rather than the whole layer.

- **Semantics: intersect, not contain.** A primitive is removed if its
  world-space bounds *overlap* `rect` at all — matching how "clear this region"
  reads. A primitive that only touches `rect` from a distance is untouched;
  overlap uses strict inequality, so merely sharing an edge does not count.
- **Every copy goes.** A primitive filed into several chunks (because it
  straddled their borders) is removed from **all** of them, even from chunks the
  `rect` itself does not cover. Removal is by geometry: two primitives sharing
  the same world-space bounds (e.g. a tile's fill and its border) are both
  removed — usually what you want when clearing a cell.
- **Only affected chunks re-render.** Chunks that lost nothing keep their cached
  textures untouched. A chunk emptied by a removal is dropped entirely and is no
  longer drawn.
- **`#remove` targets whole primitives, not sub-regions.** It removes the
  primitives that intersect `rect`; it does not carve a hole out of one. Add
  content at the granularity you intend to remove it (per-tile primitives for a
  per-tile destructible world).

`#remove` is an **event-time** operation, not a per-frame one. Calling it every
frame re-bakes textures every frame and defeats the cache — such content belongs
in `camera.draw` instead.

**Zero-cost when unused:** a layer that never calls `#remove` follows exactly the
same `add`/`draw` path as before invalidation existed. You pay for invalidation
only when you use it.

## API reference

### `Conjuration::TileLayer.new(name:, chunk_size: 512)`

Creates a layer. `name` must be unique per layer — it namespaces the chunk
render targets (`tile_layer_<name>_<cx>_<cy>`), so two layers sharing a name
would collide on `args.outputs`. `chunk_size` is the edge length, in world
units, of each cached chunk.

### `#add(primitive)`

Files a world-space primitive (rect-like hash) into every chunk it overlaps.
Call during setup / map load. Reads `x`, `y`, `w`, `h`; passes every other key
through to the render target.

### `#remove(rect)`

Removes every stored primitive whose world-space bounds intersect `rect`
(a rect-like hash), and invalidates the chunks that lost content so they re-bake
on the next `#draw`. See [Invalidation](#invalidation) for the full semantics.

### `#draw(camera)`

Emits each visible, populated chunk as a single sprite into `camera`, baking any
chunk whose texture is not cached yet. Call once per camera per frame from the
scene's world-draw hook.
