require "app/ecs/components/position.rb"
require "app/ecs/components/velocity.rb"
require "app/ecs/components/sprite.rb"

class BounceSystem < Draco::System
  filter Position, Velocity, Sprite

  def tick(context)
    max_x = context.virtual_w
    max_y = context.virtual_h

    entities.each do |entity|
      position = entity.position
      velocity = entity.velocity
      sprite = entity.sprite

      if position.x < 0
        position.x = 0
        velocity.dx = velocity.dx.abs
      elsif position.x + sprite.w > max_x
        position.x = max_x - sprite.w
        velocity.dx = -velocity.dx.abs
      end

      if position.y < 0
        position.y = 0
        velocity.dy = velocity.dy.abs
      elsif position.y + sprite.h > max_y
        position.y = max_y - sprite.h
        velocity.dy = -velocity.dy.abs
      end
    end
  end
end
