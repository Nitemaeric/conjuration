# Cameras reference

A camera owns a rect on the screen, a focal point (x, y, zoom), its own render
target, and a HUD. A scene may have any number. Rationale lives in the framework's
`docs/cameras.md`.

```ruby
add_camera(name, x: 0, y: 0, w: grid.w, h: grid.h,
           current: { x: grid.w / 2, y: grid.h / 2, zoom: 1 },
           speed: SNAP, zoom_speed: 0.1)
```

Returns the camera and registers it in `scene.cameras[name]`. Render targets are
namespaced per scene instance, so two stacked scenes may both add a `:main`.

## Spaces

- **World** — where the game lives. `draw_world` and everything handed to
  `camera.draw` is world space.
- **Viewport** — the camera's own `w × h` render target, origin bottom-left.
  Camera HUDs live here: use `camera.from_top(20)` / `camera.from_right(20)` /
  `from_left` / `from_bottom`, **not** DragonRuby's grid-relative
  `Numeric#from_top`.
- **Screen** — the 1280×720 grid. `scene.render` and `scene.ui` draw here.

```ruby
camera.to_world(x:, y:, w: nil, h: nil)   # screen point -> world point (mouse picking)
camera.to_screen(x:, y:, w: nil, h: nil)  # world -> screen
camera.to_viewport(world_rect, parallax = 1.0)
camera.visible?(world_rect, parallax = 1.0)
camera.view_rect(parallax: 1.0)           # world rect currently seen (pan, zoom, shake)
```

`camera.to_world(**inputs.mouse.rect)` is the mouse-picking idiom.

The viewport target is always viewport-sized, never world-sized, so an arbitrarily
large world can't exceed the GPU texture limit.

`scene.virtual_w` / `virtual_h` declare world bounds; cameras clamp panning to
them. Leave nil for an unbounded world.

## Moving

```ruby
camera.look_at(x: 1200, y: 1600)   # pan
camera.look_at(zoom: 2.0)          # zoom only
camera.follow(state[:hero])        # keep centred on anything exposing x/y
camera.unfollow
camera.following                   # the followed object, or nil
```

Each camera has a `current` focal point and a `target`. You write the target;
`current` eases toward it every update and is what you read for display. **Mixing
them up is the usual cause of a HUD readout that never settles.**

- `speed` is world units per tick, clamped to the remaining distance — a constant
  approach, not eased or proportional. The default effectively snaps.
- `zoom_speed` is the per-tick zoom step; zoom is clamped to 0.1..10.
- A **positional** `look_at` ends an active follow. A **zoom-only** `look_at`
  leaves the follow running.
- To place a camera with no travel, write both points:
  `camera.current.x = camera.target.x = centre[:x]`.
- The focal point is a plain object with accessors, so the scheduler drives it:
  `tween(camera.target, :zoom, to: 2.0, over: 30, ease: :smooth_stop)`.

## Drawing and z-ordering

```ruby
camera.draw(world_rect, z: nil, parallax: 1.0)
```

Culls, transforms, and emits in call order — the fast path. Pass `z:` to defer the
draw into a per-frame buffer flushed, sorted by `z`, after the whole world pass.

```ruby
camera.draw(floor)                     # immediate — renders under everything z-ordered
camera.draw(sprite, z: -sprite[:y])    # y-sort: lower on screen draws in front
```

- Immediate (no-`z:`) draws always render **under** all z-ordered draws, whatever
  their `z`.
- **Equal-`z:` draws keep their call order** — the buffer carries an emission index
  and tie-breaks on it, because mruby's sort is not stable.
- y-sorting is a convention, not a feature; the same `z:` handles layering, depth,
  and isometric ordering (`z: col + row`).

Only interleaving entities pay for the sort. Static world content belongs in a
`Conjuration::TileLayer`, not in per-frame `camera.draw` calls.

## Parallax

```ruby
camera.draw(far_hills, parallax: 0.3)          # scrolls at 30% of camera speed
camera.draw(clouds,    parallax: 0.5, z: -100) # composes with z-ordering
```

The camera culls and transforms each layer against its own **derived** view — the
focal point scaled by the factor — not the real one. That is why this is in the
framework: a hand-rolled parallax tests visibility against the real `view_rect`
while drawing at the scaled position, so layer sprites near the view edges get
culled or kept wrongly.

- Zoom applies **un-scaled**: only the translation parallaxes, so layers never warp
  apart as you zoom.
- `parallax: 1.0` (omitted) is the memoized fast path, allocation-free.
- A factor-*f* layer's derived view sweeps `f * camera.x ± half a screen`, which
  goes negative near the world's left edge — **extend your layers past `x: 0`** or
  they pop out of view.

## Shake

```ruby
camera.shake(0.7, direction: { x: 1, y: 0.4 })   # along an impact axis
camera.shake                                     # omnidirectional, 0.6
```

Trauma-based: the amount stacks (capped at 1.0) and decays each tick, and the view
offset scales with trauma *squared*, so it falls off smoothly. The offset is part
of `view_rect`, so culling accounts for it. Pair with `game.hit_stop(frames)`.

## Multiple cameras

```ruby
left = add_camera(:left, x: 0, y: 0, w: grid.w / 2)
add_camera(:left_minimap, x: left.rect.right - 220, y: left.rect.top - 120, w: 200, h: 100)
```

`draw_world(camera)` is called once per camera per frame, so the same scene content
feeds every view and each culls for itself.

`scene.focused_camera` is whichever camera the mouse is inside, recomputed each
update (nil when the pointer is over none). Gate per-camera input on it:

```ruby
def input
  camera = focused_camera
  return unless camera

  camera.look_at(zoom: camera.target.zoom + inputs.mouse.wheel.y * 0.1) if inputs.mouse.wheel
end
```

## Camera feel is a recipe, not an API

Deadzones and lookahead are deliberately not framework features — each is a
handful of lines on `look_at` + `speed` with no hidden correctness trap. Both
**replace** `follow` rather than composing with it (a positional `look_at` ends a
follow).

```ruby
# lookahead: bias the target ahead of travel, let `speed` smooth it
cameras[:main].look_at(x: hero[:x] + hero[:facing] * LOOKAHEAD, y: hero[:y])
```

```ruby
# deadzone: hold still until the subject leaves a box, then move by the excess
x = camera.target.x
dx = hero[:x] - x
x += dx - DEADZONE_HALF_W if dx >  DEADZONE_HALF_W
x += dx + DEADZONE_HALF_W if dx < -DEADZONE_HALF_W
camera.look_at(x: x, y: camera.target.y)
```

For regional cameras (a fixed view per room), snap the target to the room's centre
on the frame the subject crosses a boundary.

## Debugging

With `game.debug?` on, each camera draws its own overlay into its viewport: cull
frame, crosshairs for current and target focal points, follow-target marker, world
bounds, and a corner readout. It builds nothing when debug is off.

`camera.dump_draw_order(io_or_path = nil)` serialises this frame's deferred buffer
in flush order — z band, emission index, viewport rect, anchors, path — and returns
the text. Tag primitives to make a dump readable:

```ruby
camera.draw({ **tile, dbg: "floor #{col},#{row}" }, z: col + row)
```

`dbg:` rides through untouched. `tools/analyze_draw_order.rb` reads the dump back.

## Projections

`Conjuration::Projection` is pure stateless maths — the camera is projection-blind.

```ruby
iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32, elevation_step: nil)
iso.to_world(col, row, height = 0)   # => { x:, y: }  the tile's CENTRE
iso.to_grid(x, y, height = 0)        # => { col:, row: }  true diamond hit test
```

`Projection::TopDown.new(tile_w:, tile_h:)` is the identity mapping with the same
contract. Depth is the convention `z: col + row`; height does not change the depth
key. Draw tiles anchored at the returned centre (`anchor_x: 0.5, anchor_y: 0.5`).
