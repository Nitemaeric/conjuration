class DeviceToast
  HOLD = 40 # clock ticks held at full opacity before the fade
  FADE = 80 # clock ticks to ramp alpha to zero

  def initialize
    @category = nil
    @shown_at = nil
    @label = { x: 24, y: 24, text: "", size_px: 18, r: 235, g: 235, b: 240, a: 0, anchor_x: 0, anchor_y: 0 }
  end

  def poll(style, clock)
    category = style == :keyboard ? :keyboard : :controller
    return if category == @category

    first = @category.nil?
    @category = category
    return if first

    @label[:text] = category == :keyboard ? "Mouse & Keyboard detected" : "Controller detected"
    @shown_at = clock
  end

  def draw(outputs, clock)
    return unless @shown_at

    elapsed = clock - @shown_at
    return if elapsed >= HOLD + FADE

    remaining = HOLD + FADE - elapsed
    @label[:a] = remaining >= FADE ? 255 : 255 * remaining / FADE
    outputs.primitives << @label
  end
end
