# Cameras

A camera is a viewport onto the world. It owns a rect on the screen, a focal
point (x, y, zoom), its own render target, and a HUD. A scene may have any
number of them.

```ruby
class OverworldScene < Conjuration::Scene
  def setup
    self.virtual_w = self.virtual_h = 4000

    camera = add_camera(:main, speed: 12)
    camera.ui.group = :hud
    camera.ui.view { hud(camera) }
    camera.follow(state.hero)
  end

  def draw_world(camera)
    @ground.draw(camera)                                   # a cached TileLayer
    camera.draw(hero_sprite, z: -state.hero[:y])           # y-sorted against the world
  end
end
```

- [Spaces](#spaces)
- [Moving the camera](#moving-the-camera)
- [Drawing and z-ordering](#drawing-and-z-ordering)
- [Parallax](#parallax)
- [Shake](#shake)
- [Multiple cameras](#multiple-cameras)
- [Camera feel: a recipe, not an API](#camera-feel-a-recipe-not-an-api)
- [Debugging](#debugging)

## Spaces

Three coordinate spaces, and it pays to be exact about which one you're in.

- **World** — where your game lives. `draw_world` and everything you hand to
  `camera.draw` is in world space.
- **Viewport** — the camera's own `w × h` render target, origin at its
  bottom-left. Camera HUDs live here, which is why they use
  `camera.from_top(20)` / `camera.from_right(20)` rather than DragonRuby's
  grid-relative `Numeric#from_top`.
- **Screen** — the 1280×720 grid. The scene's `render` and `scene.ui` draw here,
  and each camera's viewport is blitted onto its rect.

Conversions:

```ruby
camera.to_world(**inputs.mouse.rect)     # screen point -> world point (mouse picking)
camera.to_screen(x: 100, y: 200)         # world -> screen
camera.to_viewport(world_rect)           # world -> this camera's target
camera.visible?(world_rect)              # AABB test against the current view
camera.view_rect                         # world rect currently seen (pan, zoom, shake)
```

The viewport target is always viewport-sized, never world-sized, so an
arbitrarily large world can't exceed the GPU texture limit.

`scene.virtual_w` / `virtual_h` declare world bounds; cameras clamp panning so
the view never leaves them. Leave them nil for an unbounded world.

## Moving the camera

Each camera has a `current` focal point and a `target` one. You write the target;
`current` eases toward it every update and is what you read for display.

```ruby
camera.look_at(x: 1200, y: 1600)     # pan
camera.look_at(zoom: 2.0)            # zoom only
camera.follow(state.hero)            # keep centred on anything exposing x/y
camera.unfollow
```

`speed` is world units per tick, clamped to the remaining distance — a constant
approach, not an eased or proportional one. A low speed gives a lagging, smooth
follow; the default effectively snaps. `zoom_speed` is the per-tick zoom step;
zoom itself is clamped to 0.1..10.

```ruby
add_camera(:main, speed: 30, zoom_speed: 0.05)
```

A **positional** `look_at` ends an active follow — you just took manual control.
A **zoom-only** `look_at` leaves the follow running, so you can zoom while
tracking. To place a camera with no travel at all, write both points directly:

```ruby
camera.current.x = camera.target.x = centre[:x]
camera.current.y = camera.target.y = centre[:y]
```

Read `camera.current.zoom` for a HUD readout and write `camera.target.zoom` from
input — mixing them up is the usual cause of a readout that never settles.

Because the focal point is a plain object with accessors, the
[scheduler](time.md#timers-and-tweens) drives it:

```ruby
tween(camera.target, :zoom, to: 2.0, over: 30, ease: :smooth_stop)
```

## Drawing and z-ordering

`camera.draw(world_rect)` culls, transforms, and emits in call order — the fast
path. Pass `z:` to defer the draw into a per-frame buffer that is flushed, sorted
by `z`, after the whole world pass:

```ruby
camera.draw(floor)                     # immediate — renders under everything z-ordered
camera.draw(sprite, z: -sprite[:y])    # y-sort: lower on screen draws in front
```

- Immediate (no-`z:`) draws always render **under** all z-ordered draws, whatever
  their `z`.
- **Equal-`z:` draws keep their call order.** The buffer carries an emission
  index and sorts on it as a tie-break, because mruby's sort is not stable —
  without that, equal-z primitives would flicker between frames.
- y-sorting is a convention, not a separate feature; the same `z:` handles
  layering, depth, and isometric ordering (`z: col + row` — see the Projections
  section of the [README](../README.md)).

Only interleaving entities pay for the sort. Tiles and backgrounds stay on the
immediate path, and a scene that never passes `z:` never touches the buffer.

Static world content belongs in a [TileLayer](tile_layer.md), not in per-frame
`camera.draw` calls.

## Parallax

```ruby
camera.draw(far_hills, parallax: 0.3)          # scrolls at 30% of camera speed
camera.draw(clouds,    parallax: 0.5, z: -100) # composes with z-ordering
```

The camera culls and transforms each layer against its own **derived** view — the
focal point scaled by the factor — not the real one. That is why this is in the
framework rather than a docs recipe: a hand-rolled parallax tests visibility
against the real `view_rect` while drawing at the scaled position, so layer
sprites near the view edges get culled (or kept) wrongly. The derived view rects
are memoized per factor per frame.

- Zoom applies **un-scaled**: only the translation parallaxes, so layers never
  warp apart as you zoom.
- `parallax: 1.0` (omitted) is the memoized fast path, allocation-free and
  unchanged.
- A factor-*f* layer's derived view sweeps `f * camera.x ± half a screen`, which
  goes negative near the world's left edge — extend your layers past `x: 0` or
  they pop out of view.

Packing the pair into a constant keeps call sites readable:

```ruby
HILLS = { parallax: 0.3, z: -300 }.freeze

@hills.each { |hill| camera.draw(hill, **HILLS) }
```

## Shake

```ruby
camera.shake(0.7, direction: { x: 1, y: 0.4 })   # along an impact axis
camera.shake                                     # omnidirectional, 0.6
```

Shake is trauma-based: the amount stacks (capped at 1.0) and decays each tick,
and the view offset scales with trauma *squared*, so it falls off smoothly rather
than stopping dead. Passing a `direction:` shakes along that axis; omitting it
shakes both. The offset is part of `view_rect`, so culling accounts for it.

Pair it with `game.hit_stop(frames)` for impact — the freeze holds the frame
while the shake reads.

## Multiple cameras

`add_camera` returns the camera and registers it under its name in
`scene.cameras`. Give each one a viewport rect on the screen:

```ruby
left = add_camera(:left, x: 0, y: 0, w: grid.w / 2)
add_camera(:left_minimap, x: left.rect.right - 220, y: left.rect.top - 120, w: 200, h: 100)
add_camera(:right, x: grid.w / 2, y: 0, w: grid.w / 2)
```

`draw_world(camera)` is called once per camera per frame, so the same scene
content feeds every view and each culls for itself. Render targets are namespaced
per scene instance, so two stacked scenes that both add a `:main` camera don't
collide.

`scene.focused_camera` is whichever camera the mouse is inside, recomputed each
update (nil when the pointer is over none). Gate per-camera input on it:

```ruby
def input
  camera = focused_camera
  return unless camera

  camera.look_at(zoom: camera.target.zoom + inputs.mouse.wheel.y * 0.1) if inputs.mouse.wheel
end
```

## Camera feel: a recipe, not an API

Deadzones and lookahead are deliberately **not** framework features. They are
each a handful of honest lines on `look_at` + `speed`, with no hidden correctness
trap in the arithmetic — which is the admission test a feature has to fail to
stay out of core. (Parallax passes that test in the other direction: the DIY
version mis-culls.) Here they are; the two sharp edges are in wiring the camera
up around them, and are spelled out after the code.

**Lookahead** — bias the target ahead of the direction of travel, and let `speed`
do the smoothing:

```ruby
LOOKAHEAD = 120

def update
  hero = state.hero
  cameras[:main].look_at(x: hero[:x] + hero[:facing] * LOOKAHEAD, y: hero[:y])
end
```

**Deadzone** — hold the camera still until the subject leaves a box around the
focal point, then move only by the excess:

```ruby
DEADZONE_HALF_W = 80
DEADZONE_HALF_H = 48

def update
  camera = cameras[:main]
  hero = state.hero

  x = camera.target.x
  y = camera.target.y

  dx = hero[:x] - x
  x += dx - DEADZONE_HALF_W if dx >  DEADZONE_HALF_W
  x += dx + DEADZONE_HALF_W if dx < -DEADZONE_HALF_W

  dy = hero[:y] - y
  y += dy - DEADZONE_HALF_H if dy >  DEADZONE_HALF_H
  y += dy + DEADZONE_HALF_H if dy < -DEADZONE_HALF_H

  camera.look_at(x: x, y: y)
end
```

Both replace `follow` rather than composing with it — a positional `look_at`
ends a follow, so drive one or the other. Compose them by computing the
lookahead-biased point first and feeding *that* into the deadzone test.

Two things the deadzone needs from the rest of the camera, both of which look
like the recipe misbehaving when they're missing:

- **Seed the focal point.** The box accumulates from `target.x`/`target.y`, and a
  fresh camera starts at the centre of its viewport — so an unseeded camera
  crawls in from there on the first frames. Write both points in `setup`, as in
  [Moving the camera](#moving-the-camera):
  `camera.current.x = camera.target.x = state.hero[:x]`.
- **Leave the axis room to move.** The focal point is clamped to
  `[h / 2, virtual_h - h / 2]`, so a world exactly one screen tall pins `y` and
  the vertical half-extent does nothing at all. The box also has to be centred
  somewhere the *clamped* point can rest: aim at the subject plus a constant
  rise, rather than at the subject itself, or the resting relation isn't
  expressible and the axis reads as dead.

**Platformer variant** — track the surface underfoot rather than the subject on
the vertical axis. Airborne frames then never scroll the view, however high the
jump goes, and the camera settles only once the subject has landed somewhere new:

```ruby
CAMERA_RISE = 240   # seats a standing hero in the lower third of the frame

dy = hero[:support_y] + CAMERA_RISE - y
y += dy - DEADZONE_HALF_H if dy >  DEADZONE_HALF_H
y += dy + DEADZONE_HALF_H if dy < -DEADZONE_HALF_H
```

`support_y` is the top of whatever the subject last landed on. Note the deadzone
is symmetric and therefore sticky in the usual way: having pushed up for a high
ledge, the camera holds that height while the subject is back on ground inside
the box. Snap it if you'd rather it fell back — `demo/mygame/app/scenes/parallax_scene.rb`
runs the version above as written.

For regional cameras (a fixed view per room, Zelda-style), snap the target to the
room's centre on the frame the subject crosses a boundary and leave the camera
alone otherwise.

## Debugging

With `game.debug?` on, each camera draws its own overlay into its viewport: the
cull frame, crosshairs for the current and target focal points (linked by a line
when they differ), a marker on the follow target, the scene's world bounds, and a
corner readout of name, position, zoom, and follow state. World elements route
through `to_viewport`, so they track pan and zoom exactly as scene content does.
It builds nothing when debug is off.

`camera.dump_draw_order` serialises this frame's deferred buffer in flush order —
z band, emission index, viewport rect, anchors, path — to a file (or to any sink
answering `<<`), and returns the text. Ordering comes from the same code path as
the real flush, so a dump can't disagree with what DragonRuby composites.

Tag primitives to make a dump readable:

```ruby
camera.draw({ **tile, dbg: "floor #{col},#{row}" }, z: col + row)
```

`dbg:` rides through untouched — `to_viewport` dups the hash and DR ignores keys
it doesn't know — so it costs nothing when absent and nothing meaningful when
present. `tools/analyze_draw_order.rb` reads the dump back.

## See also

- [scenes.md](scenes.md) — `draw_world`, world bounds, the scene stack.
- [tile_layer.md](tile_layer.md) — caching static world content into chunks.
- [canvas.md](canvas.md) — virtual resolution; a camera defaults to the canvas viewport.
- [time.md](time.md) — tweening focal points and zoom on the scene clock.
