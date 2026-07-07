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
- [x] UI & HUD Management
  - [ ] [Flexbox Layout](https://github.com/Nitemaeric/conjuration/issues/1)
  - [ ] Interactive node management
- [ ] Input Management
  - [ ] Default key mapping
  - [ ] User remapping
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
