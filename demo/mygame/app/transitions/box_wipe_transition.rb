# A Pokemon-style box wipe: a black rectangle grows from the centre until it
# covers the outgoing frame, holds full-screen while the incoming scene loads,
# then shrinks back to reveal it. Pure :pixel rects — no assets. Same duck-typed
# contract as FadeTransition (see it for the phase-machine notes).
class BoxWipeTransition
  def initialize(frames: 20)
    @frames = frames
  end

  def out_duration
    @frames
  end

  def in_duration
    @frames
  end

  def draw(outputs, phase:, progress:, snapshot_key:, grid:)
    coverage =
      case phase
      when :out  then progress
      when :hold then 1.0
      when :in   then 1.0 - progress
      end

    outputs.primitives << {
      x: grid.w / 2,
      y: grid.h / 2,
      w: grid.w * coverage,
      h: grid.h * coverage,
      anchor_x: 0.5,
      anchor_y: 0.5,
      path: :pixel,
      r: 0,
      g: 0,
      b: 0
    }
  end
end
