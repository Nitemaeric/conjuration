class Sprite < Draco::Component
  attribute :w, default: 24
  attribute :h, default: 24
  attribute :r, default: 255
  attribute :g, default: 255
  attribute :b, default: 255

  # attr_reader, not a draco attribute: a `{}` default is shared across all entities.
  attr_reader :primitive

  def after_initialize
    @primitive = { w: w, h: h, path: :pixel, r: r, g: g, b: b }
  end
end
