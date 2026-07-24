module Conjuration
  # A mutable 2D vector with arithmetic and utility methods.
  #
  # Useful for spatial calculations, velocities, and directional logic.
  # Both x and y are directly mutable, so cached values (like magnitude)
  # would go stale on reassignment — calculations are performed on-demand.
  class Vector
    # @return [Numeric] x component
    attr_accessor :x
    # @return [Numeric] y component
    attr_accessor :y

    # Create a vector from x and y components.
    #
    # @param x [Numeric] x component
    # @param y [Numeric] y component
    def initialize(x:, y:)
      @x = x
      @y = y
    end

    # Add two vectors component-wise.
    #
    # @param vector [Vector] the vector to add
    # @return [Vector] new vector with summed components
    def +(vector)
      Vector.new(x: x + vector.x, y: y + vector.y)
    end

    # Subtract another vector component-wise.
    #
    # @param vector [Vector] the vector to subtract
    # @return [Vector] new vector with difference of components
    def -(vector)
      Vector.new(x: x - vector.x, y: y - vector.y)
    end

    # Multiply two vectors component-wise (Hadamard product).
    #
    # @param vector [Vector] the vector to multiply by
    # @return [Vector] new vector with products of components
    def *(vector)
      Vector.new(x: x * vector.x, y: y * vector.y)
    end

    # Calculate distance to another vector.
    #
    # @param vector [Vector] the target vector
    # @return [Numeric] Euclidean distance
    def distance(vector)
      (self - vector).magnitude
    end

    # Calculate the vector's Euclidean magnitude (length).
    #
    # Not memoized: x/y are mutable, so a cached value would go stale on reassignment.
    #
    # @return [Numeric] magnitude
    def magnitude
      # Not memoized: x/y are mutable, so a cached value would go stale on reassignment.
      Math.sqrt(x ** 2 + y ** 2)
    end

    # Return a unit vector in the same direction.
    #
    # @return [Vector] normalized vector with magnitude 1.0
    def normalize
      Vector.new(x: x / magnitude, y: y / magnitude)
    end

    # Return a general direction based on the vector's x and y values.
    #
    # @return [Symbol] +:up+, +:down+, +:left+, or +:right+
    # @note For diagonals, direction is chosen randomly between the two principal axes.
    def direction
      directions = x > y || (x == y && rand < 0.5) ? [:right, :down] : [:up, :left]

      (x+y) > 0 || (x + y == 0 && rand < 0.5) ? directions[0] : directions[1]
    end

    # String representation for debugging.
    #
    # @return [String]
    def inspect
      "#<Vector:0x#{object_id.to_s(16)} x: #{x}, y: #{y}>"
    end

    # Convert the vector to an array.
    #
    # @return [Array<Numeric>] +[x, y]+
    def to_a
      [x, y]
    end
  end
end
