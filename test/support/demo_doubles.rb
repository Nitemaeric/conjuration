# Load-time dependencies of the demo scene files, so their HUD layouts run
# under the harness. Loaded after doubles.rb ($game), before the demo files.

# mruby has no Kernel#require (DragonRuby provides it); the demo files' requires
# are inert here — script/test.sh preloads everything with -r instead.
def require(_path); end

# Enough Draco for the demo's class bodies; the smoke tests never tick a world.
module Draco
  class World
    def self.systems(*); end
  end
end

class MovementSystem; end
class BounceSystem; end

# DragonRuby exposes the runtime as the $gtk global too; PromptView measures
# label text through it.
$gtk = $game.gtk

# DR numeric conveniences the demo layouts use (dragon/numeric.rb in contrib).
class Numeric
  def from_top
    $game.grid.h - self
  end

  def from_right
    $game.grid.w - self
  end

  def to_radians
    self * Math::PI / 180
  end
end

# The scenes' derived values key off game.clock; a frozen clock keeps them
# deterministic under the harness.
class GameDouble
  def clock
    0
  end
end
