# Conjuration - DragonRuby GTK Framework

> [!WARNING]
> This project is a work in progress and is not yet ready for use.

Conjuration provides foundations for building a game in DragonRuby GTK.

The motivation behind Conjuration is to provide structure and convention to DragonRuby GTK projects,
without adding constraints or limiting access to the underlying DR APIs. Think what Ruby on Rails is to Ruby.

## Features

- [x] Gameloop conventions
  - [x] Order of operations
    - [x] Setup (Run once when the scene is loaded)
    - [x] Input (Handle user input logic)
    - [x] Update (Handle game logic)
    - [x] Render (Draw things to the scene / camera (HUD, UI))
- [x] Scene Management
  - [ ] Scene transitions
- [ ] Camera Management
  - [x] Look at
  - [ ] Zooming
  - [ ] Panning
  - [ ] Following
  - [x] Multiple cameras
  - [ ] Minimaps
  - [ ] Camera shake
  - [ ] Impact frames (Hit stops)
- [ ] UI & HUD Management
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
