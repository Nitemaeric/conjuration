require "app/ecs/components/position.rb"
require "app/ecs/components/velocity.rb"
require "app/ecs/components/sprite.rb"

class Critter < Draco::Entity
  component Position
  component Velocity
  component Sprite
end
