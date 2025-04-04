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
  - [ ] Zooming
  - [x] Panning
  - [ ] Following
  - [x] Multiple cameras
  - [ ] Minimaps
  - [ ] Camera shake
  - [ ] Impact frames (Hit stops)
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

You can install Conjuration into your DragonRuby project by following one of these methods:

- Copy the `lib` directory into your `mygame` directory.

- Using [Foodchain](https://github.com/pvande/foodchain)

  ```ruby
  github :nitemaeric, :conjuration, "lib"
  ```

## Quick Start

View the following files to get started:

- [main.rb](demo/mygame/app/main.rb)
- [game.rb](demo/mygame/app/game.rb)
- [scenes/menu_scene.rb](demo/mygame/app/scenes/menu_scene.rb)
