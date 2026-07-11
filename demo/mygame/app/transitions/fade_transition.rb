# A transition is duck-typed: out_duration / in_duration (frames) and a draw hook
# the framework calls with the current phase, its 0..1 progress, the snapshot
# target key, and the grid. The framework owns the phase machine (out -> hold-
# while-loading -> in) and composites the base (snapshot while out/hold, the live
# incoming scene while in); a transition only draws its effect over that base.
#
# Fade-to-black: darken the outgoing frame to black, hold black while the
# incoming scene loads, then lighten to reveal it.
class FadeTransition
  def initialize(frames: 24)
    @frames = frames
  end

  def out_duration
    @frames
  end

  def in_duration
    @frames
  end

  def draw(outputs, phase:, progress:, snapshot_key:, grid:)
    alpha =
      case phase
      when :out  then (progress * 255).to_i
      when :hold then 255
      when :in   then ((1.0 - progress) * 255).to_i
      end

    outputs.primitives << { x: 0, y: 0, w: grid.w, h: grid.h, path: :pixel, r: 0, g: 0, b: 0, a: alpha }
  end
end
