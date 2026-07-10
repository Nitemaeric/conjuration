# Conjuration - DragonRuby GTK Framework

> [!WARNING]
> This project is a work in progress and is not yet ready for use.

Conjuration provides foundations for building a game in DragonRuby GTK.

The motivation behind Conjuration is to provide structure and convention to DragonRuby GTK projects,
without adding constraints or limiting access to the underlying DR APIs. Think what Ruby on Rails is to Ruby.

## Features

- [x] Gameloop conventions
  - [x] Order of operations
    - [x] Setup (Run once when a scene is loaded)
    - [x] Input (Handle user input logic)
    - [x] Update (Handle game logic)
    - [x] Render (Draw things to a scene / camera (HUD, UI))
- [x] Scene Management
  - [ ] Scene transitions
- [ ] Camera Management
  - [x] Look at
  - [x] Zooming
  - [x] Panning
  - [x] Following
  - [x] Multiple cameras
  - [ ] Minimaps
  - [x] Camera shake
  - [x] Impact frames (Hit stops)
- [x] Rendering
  - [x] Virtual scenes (worlds beyond the GPU texture limit)
  - [x] Viewport culling
  - [x] Chunked tile caching
  - [x] Parallax scrolling layers
  - [x] Deferred z-ordering (y-sort / depth)
  - [x] Grid projections (isometric & top-down)
- [x] UI & HUD Management
  - [ ] [Flexbox Layout](https://github.com/Nitemaeric/conjuration/issues/1)
  - [ ] Interactive node management
- [x] Input Management — via [dragon_input](https://github.com/Nitemaeric/dragon_input), bundled as a dependency
  - [x] Action-based bindings (keyboard, mouse, controller; pure-Ruby backend, optional native Steam Input)
  - [x] Default key mapping (reserved `:ui_*` actions injected automatically — see [Menu input](#menu-input--works-out-of-the-box))
  - [x] User remapping (in-game rebind UI, or the Steam overlay when available)
  - [x] Device-following input glyphs (prompts swap art with the last-used device)
- [ ] Debugging tools
  - [ ] Debug layers
  - [ ] Scene / Camera debug overlay

## Installation

The recommended way to install Conjuration is with [drenv](https://github.com/Nitemaeric/drenv), a DragonRuby environment and dependency manager.

From your project directory, add Conjuration as a dependency:

```sh
drenv add github:Nitemaeric/conjuration
```

Then require the generated bundle at the top of `mygame/app/main.rb`:

```ruby
require 'app/drenv_bundle.rb'
```

drenv vendors Conjuration into `mygame/vendor/` and pins it in `mygame/drenv.lock`. Run `drenv run` to sync dependencies and launch your game, or `drenv bundle` to refresh them without launching.

## Quick Start

View the following files to get started:

- [main.rb](demo/mygame/app/main.rb)
- [game.rb](demo/mygame/app/game.rb)
- [scenes/title_scene.rb](demo/mygame/app/scenes/title_scene.rb)
- [scenes/menu_scene.rb](demo/mygame/app/scenes/menu_scene.rb)

## Conventions

### Game clock — key timings to `game.clock`, not `Kernel.tick_count`

`Kernel.tick_count` advances every frame, including while the game is frozen by a hit stop (`Game#hit_stop`). An easing or timer keyed to it therefore *skips ahead* when the game thaws — the freeze that should hold an animation loses the frames instead.

`game.clock` (delegated to scenes as `scene.clock`) is a frame counter advanced once per **un-frozen** update, so it holds still through a hit stop (and, later, a paused scene). Key easings and hand-rolled timers to it:

```ruby
angle = clock * 0.02              # holds during a hit stop
angle = Kernel.tick_count * 0.02  # skips ahead when the freeze ends
```

DragonRuby's easing math (`Easing.ease`, `Numeric#ease`) is unchanged — Conjuration just provides the correct clock to key it to. See [basic_camera_scene.rb](demo/mygame/app/scenes/basic_camera_scene.rb) for the orbit animation driven off `clock`.

### Draw ordering — `camera.draw(sprite, z:)`

`camera.draw(sprite)` emits immediately, in call order — the fast path, unchanged. Pass `z:` to defer a draw into a per-frame buffer that is flushed sorted by `z` after the whole world pass, so an entity can be interleaved between tiles without the scene ordering every call:

```ruby
camera.draw(floor)                     # immediate — renders under everything z-ordered
camera.draw(sprite, z: -sprite[:y])    # y-sort: lower on screen draws in front
```

- Immediate (no-`z:`) draws always render **under** all z-ordered draws, whatever their `z`.
- Equal-`z:` draws keep their call order.
- y-sorting (`z: -y`) is a convention, not a separate feature; the same `z:` handles layering, depth, and iso ordering.

Only interleaving entities pay for the sort — tiles and backgrounds stay on the immediate fast path. See [basic_camera_scene.rb](demo/mygame/app/scenes/basic_camera_scene.rb) for the follow target y-sorted against pillars.

### Menu input — works out of the box

Conjuration depends on [dragon_input](https://github.com/Nitemaeric/dragon_input); drenv vendors it automatically when you add Conjuration, so you don't declare it yourself. Framework UI (menu navigation and confirm) needs **no setup at all** — if you never call `DragonInput.setup`, the first menu query bootstraps a minimal config, and either way the reserved UI actions (`:ui_confirm`, `:ui_up/down/left/right`, bound to Enter/arrows and controller A/D-pad) are injected into your action sets the first time a menu reads input, filling only gaps so your own bindings win. Calling your own `DragonInput.setup` later simply replaces the config; the reserved actions are re-injected into it.

- **Don't pump manually.** Conjuration calls `DragonInput.tick` once per frame inside `Game#tick`. The pump is gated on `DragonInput.config`, so a game that never uses input pays only a nil-check per tick.
- **Escape hatch:** assign `game.input_source = your_source` (any object answering `just_pressed?(pad, action)` / `pressed?(pad, action)`) to bypass the DragonInput wrapper entirely. `game.ui_pad` (default `:one`) picks the logical pad the framework UI listens to.

### Parallax — `camera.draw(layer, parallax:)`

Pass `parallax:` (a factor below 1.0) to make a background layer scroll slower than the camera, for depth from motion:

```ruby
camera.draw(far_hills, parallax: 0.3)          # scrolls at 30% of camera speed
camera.draw(clouds,    parallax: 0.5, z: -100) # composes with z-ordering
```

The camera culls and transforms each layer against its own *derived* view — the focal point scaled by the factor — not the real one. This is the reason it belongs in the framework: a hand-rolled parallax tests visibility against the real `view_rect` while drawing at the scaled position, so layer sprites near the view edges are culled (or kept) wrongly. `camera.draw` gets the boundary right.

- The default path (`parallax: 1.0`, i.e. omitted) is the memoized fast path, unchanged and allocation-free — only layers that pass `parallax:` do any extra work.
- Zoom applies **un-scaled**: only the translation parallaxes, so every layer stays at the same zoom and they never warp apart as you zoom.
- `parallax:` composes with `z:` — layer your backgrounds with `z:` and scroll them with `parallax:` independently.

See [parallax_scene.rb](demo/mygame/app/scenes/parallax_scene.rb) for a side-scroller with sky, hills, clouds, and tree layers over a 1:1 ground plane.
### Projections — grid ↔ world mapping (`Conjuration::Projection`)

Isometric is **not a camera feature**. The camera works in continuous world space and is projection-blind; so is `TileLayer`. What makes a view isometric is only (a) how grid cells map to world positions and (b) draw order — and draw order is already handled by `camera.draw(sprite, z:)` above. So `Projection` is pure, stateless maths — no engine changes:

```ruby
iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)

iso.to_world(col, row)   # => { x:, y: }   the tile's CENTRE in world space
iso.to_grid(x, y)        # => { col:, row: } which tile a world point falls in
```

- **`to_world` returns the tile centre**, so draw the tile sprite anchored there (`anchor_x: 0.5, anchor_y: 0.5`); for a `TileLayer`/rect entry the bounding box is `(x - tile_w/2, y - tile_h/2, tile_w, tile_h)`. An iso tile is still an axis-aligned world rect, so it chunks like any other sprite.
- **`to_grid` is the exact inverse** and does true *diamond* hit-testing (not the sprite's bounding box), so picking is correct right up to tile edges and corners. Feed it a world point from `camera.to_world(inputs.mouse.rect)` to pick under the cursor.
- **Depth is the convention `z: col + row`** — a greater `col + row` places a tile nearer the viewer (lower on screen) and draws it on top. It rides on the z-ordering above; it is not a separate feature.
- **Elevation is opt-in and free when unused.** `to_world(col, row, height)` raises the returned centre by `height * elevation_step` (a constructor param, default `tile_h / 2.0` — one block). `height` is a positional third arg, not a kwarg, so the per-frame draw/pick paths stay allocation-free; `to_world(col, row)` and `to_world(col, row, 0)` are identical. `TopDown#to_world` takes the same arg as a no-op so the family shares one signature.
  - **Height does not change the depth key.** A tall tile still occupies its cell, so keep `z: col + row`. Stacked/elevated content within one cell draws bottom-up simply by *emitting in that order* — the deferred z-sort is stable, so equal-`z` primitives keep call order.
  - **Picking an elevated tile: the probe technique.** `to_grid` is ground-plane only; `to_grid(x, y, height)` un-offsets the point by `height * elevation_step` before the diamond test. To pick under the cursor, iterate candidate heights **highest-first**, and take the first whose cell actually stands that tall (`heightmap[cell] == height`) — a raised tile occludes the lower cells drawn behind it, so the tallest match is the visible top face. The projection stays stateless; the heightmap lives in your scene.
- `Projection::TopDown` is the identity mapping with the same contract, so isometric reads as one option in a family rather than a special case — swap the projection object and the same tile/pick code drives either view.

See [isometric_scene.rb](demo/mygame/app/scenes/isometric_scene.rb): a diamond `TileLayer` floor, a hand-authored heightmap with a raised plateau (top diamond plus a stacked "cliff face"), elevation-aware mouse picking via the probe above, and a knight whose feet follow the terrain height while walking behind then in front of raised ground purely from `z: col + row`.
