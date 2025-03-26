class Array
  def to_vector
    Conjuration::Vector.new(x: self[0], y: self[1])
  end
end
