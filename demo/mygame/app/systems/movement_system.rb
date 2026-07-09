require "app/components/position.rb"
require "app/components/velocity.rb"

class MovementSystem < Draco::System
  filter Position, Velocity

  def tick(_context)
    entities.each do |entity|
      entity.position.x += entity.velocity.dx
      entity.position.y += entity.velocity.dy
    end
  end
end
