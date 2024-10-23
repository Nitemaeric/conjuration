# Conjuration - DragonRuby GTK Framework

> [!WARNING]
> This project is a work in progress and is not yet ready for use.

Conjuration provides foundations for building a game in DragonRuby GTK.

The motivation behind Conjuration is to provide structure and convention to DragonRuby GTK projects,
without adding constraints or limiting access to the underlying DR APIs.

## Features

- Gameloop conventions
  - Order of operations
- Scene Management
  - Scene transitions
- Camera Management
  - Zooming
  - Panning
  - Following
  - Multiple Cameras
  - Minimaps
  - Camera shake
- Input Management
  - Default key mapping
  - User remapping
- Debugging tools
  - Debug layers
  - Scene / Camera debug overlay

## Installation

Copy the `lib` directory to into your `mygame` directory.

- Using [Foodchain](https://github.com/pvande/foodchain)

  ```ruby
  github :nitemaeric, :conjuration, "lib"
  ```

## Quickstart

```ruby
class Game < Conjuration::Game
  def setup
    # Add your initial scene. This could be a splash screen, main menu, etc.
    # scene_manager.initial_scene(:main, MainScene)
  end

  def handle_input
    # Handle game-wide input here. Ideal for development key-bindings.
    # if input_manager.key_down?(:f1)
    #   debug_manager.toggle
    # end
  end
end

class MainScene < Conjuration::Scene
  # Setup your scene size here. Below is the default.
  # size width: 1280, height: 720

  # You can add `attr_accessor` calls here.
  # attr_accessor :player

  def setup
    # Setup your keymap configuration for this scene.
    # input_manager.use_keymap(:main)

    # If your scene is dynamically sized, you can also set it up here.
    # size width: tile_count * 20, height: tile_count * 10

    # Configure scene camera(s) here.
    # By default, you'll have a single camera covering 1280x720.
    # camera_manager.add_camera(:main, x: 0, y: 0, width: 1280, height: 720)

    # Setup your game objects.
    # @player = Player.new
  end

  def handle_input
    # What to do when input is received.
    # if input_manager.key_down?(:left)
    #   player.move(x: -1)
    # end
  end

  def update
    # On-going calculations and updates happen here.
    # The majority of you game logic of this scene will happen within this method.
    # update_positions
  end

  def render
    # Draw your scene here.
    # outputs.primitives << [0, 0, 1280, 720, 255, 0, 0].solid!
    # outputs.primitives << @player
  end

  private

  # Example of splitting logic into smaller chunks.
  # def update_positions
  #   player.update_position
  # end
end
```
