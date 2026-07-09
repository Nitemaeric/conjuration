require "app/components/position.rb"
require "app/components/velocity.rb"
require "app/components/sprite.rb"

class Critter < Draco::Entity
  component Position
  component Velocity
  component Sprite
end
