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
  - [ ] Impact frames (Hit stops)
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
