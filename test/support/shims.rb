# DragonRuby runtime surface, reimplemented for plain mruby (and CRuby) so the
# framework loads and runs without the proprietary GTK engine.
#
# Source material — the open-source Ruby layer of the DragonRuby API:
#   https://github.com/DragonRuby/dragonruby-game-toolkit-contrib
# See dragon/attr_gtk.rb, dragon/geometry.rb, and dragon/numeric.rb there. These
# shims reproduce only the surface the framework touches; anything implemented
# natively (in C) in DragonRuby is reimplemented in Ruby here (noted inline).
#
# Load order matters: this file must load BEFORE the lib, because
#   - game.rb does `include AttrGTK` at load time, and
#   - the lib treats hashes as objects whose keys are methods (`hash.x` <=>
#     `hash[:x]`), which extensions/hash.rb and ui.rb rely on.

# game.rb mixes this in at load time. DragonRuby's real AttrGTK
# (dragon/attr_gtk.rb in the contrib repo) wires up args/state/outputs/etc. Most
# tests never touch it, but the hit-stop test instantiates a Game (which assigns
# `args` in its initializer), so expose that accessor; the debug-panel test also
# reads outputs, which real AttrGTK sources from args.
module AttrGTK
  attr_accessor :args

  def outputs
    args.outputs
  end
end

# DragonRuby exposes hash values as methods: `h.x` reads `h[:x]`, `h.x = v`
# writes it. The framework leans on this throughout (rects, primitives, the
# `object` a UI::Node wraps). In DragonRuby this is engine-level behavior rather
# than a single contrib file; reproduced here with method_missing.
class Hash
  def method_missing(name, *args)
    key = name.to_s
    if key.end_with?("=")
      self[key[0..-2].to_sym] = args.first
    else
      self[name]
    end
  end

  def respond_to_missing?(_name, _include_private = false)
    true
  end
end

# Minimal Geometry stand-in. Only hit-testing (`intersect_rect?`,
# `find_interactive_intersect`) and camera panning (`vec2_normalize`) use it; the
# layout math never does.
#
# Note: in DragonRuby `intersect_rect?`/`find_intersect_rect` are NATIVE (C)
# methods — they have no Ruby source in dragonruby-game-toolkit-contrib (which
# only exposes `inside_rect?` delegating to native `__inside_rect__?`). So these
# are reimplemented here rather than vendored. Plain AABB overlap; sufficient for
# the hit-testing/navigation tests.
module Geometry
  def self.intersect_rect?(a, b)
    (a[:x] || 0) < (b[:x] || 0) + (b[:w] || 0) &&
      (a[:x] || 0) + (a[:w] || 0) > (b[:x] || 0) &&
      (a[:y] || 0) < (b[:y] || 0) + (b[:h] || 0) &&
      (a[:y] || 0) + (a[:h] || 0) > (b[:y] || 0)
  end

  def self.find_intersect_rect(rect, others)
    others.find do |other|
      intersect_rect?(rect, other.respond_to?(:rect) ? other.rect : other)
    end
  end

  # Ports dragon/geometry.rb's `vec2_normalize` from the contrib repo. (DR
  # returns nil at zero magnitude; this returns a zero vector instead, which is
  # immaterial — camera.rb only calls it when magnitude > 0.)
  def self.vec2_normalize(vec)
    x = vec[:x]
    y = vec[:y]
    magnitude = Math.sqrt(x * x + y * y)
    return { x: 0, y: 0 } if magnitude.zero?

    { x: x / magnitude, y: y / magnitude }
  end
end
