class Vector
  attr_accessor :x, :y

  def initialize(x:, y:)
    @x = x
    @y = y
  end

  def +(vector)
    Vector.new(x: x + vector.x, y: y + vector.y)
  end

  def -(vector)
    Vector.new(x: x - vector.x, y: y - vector.y)
  end

  def *(vector)
    Vector.new(x: x * vector.x, y: y * vector.y)
  end

  def distance(vector)
    (self - vector).magnitude
  end

  def magnitude
    @magnitude ||= Math.sqrt(x ** 2 + y ** 2)
  end

  def normalize
    Vector.new(x: x / magnitude, y: y / magnitude)
  end

  # Returns a general direction based on the vector's x and y values.
  #
  # @note If the vector is a diagonal, the direction will be chosen randomly.
  #
  # @return [Symbol] :up, :down, :left, :right
  def direction
    directions = x > y || (x == y && rand < 0.5) ? [:right, :down] : [:up, :left]

    (x+y) > 0 || (x + y == 0 && rand < 0.5) ? directions[0] : directions[1]
  end

  def inspect
    "#<Vector:0x#{object_id.to_s(16)} x: #{x}, y: #{y}>"
  end

  def to_a
    [x, y]
  end
end

class Array
  def to_vector
    Vector.new(x: self[0], y: self[1])
  end
end
