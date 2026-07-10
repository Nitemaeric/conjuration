# Test doubles, the global game object, shared builders, and the assertion API.
# Loaded after the lib (it references Conjuration::Camera) and before the test
# files. No `require` here — the runner (script/test.sh / DR --test) controls
# load order.
#
# Source material — the open-source Ruby layer of the DragonRuby API:
#   https://github.com/DragonRuby/dragonruby-game-toolkit-contrib
# GtkDouble stubs the native `gtk.calcstringbox`/`set_cursor`; the Assert class
# mirrors dragon/assert.rb (see notes on it below).

class GridDouble
  def w; 1280; end
  def h; 720; end
  def rect; { x: 0, y: 0, w: 1280, h: 720 }; end
end

class GtkDouble
  # Deterministic, font-independent measurement so text layout is reproducible
  # without real font metrics.
  def calcstringbox(text, *)
    [text.to_s.length * 8, 22]
  end

  def set_cursor(*)
    nil
  end

  # No filesystem in the harness: art probes miss, exercising fallback paths.
  def read_file(*)
    nil
  end

  # No write sandbox either: record the last write so tests can assert the
  # path-routing branch of Camera#dump_draw_order without touching disk.
  def write_file(path, contents)
    @last_write = { path: path, contents: contents }
  end

  attr_reader :last_write
end

# A render target: tracks its size and accumulates primitives.
class RenderTargetDouble
  attr_accessor :width, :height

  def primitives
    @primitives ||= []
  end

  def debug
    @debug ||= []
  end
end

# args.outputs: the screen, plus named render targets via outputs[:name].
class OutputsDouble
  def [](name)
    targets[name] ||= RenderTargetDouble.new
  end

  def primitives
    @primitives ||= []
  end

  def debug
    @debug ||= []
  end

  def targets
    @targets ||= {}
  end
end

# args.events: only orientation_changed is read (UIManagement#perform_update).
class EventsDouble
  def orientation_changed; false; end
end

class GameDouble
  def grid; @grid ||= GridDouble.new; end
  def gtk; @gtk ||= GtkDouble.new; end
  def outputs; @outputs ||= OutputsDouble.new; end
  # Screen indirection for transition snapshots (SceneManagement#render_output).
  def render_output; @render_output || outputs; end
  attr_writer :render_output
  def events; @events ||= EventsDouble.new; end
  def state; @state ||= {}; end
  def audio; @audio ||= {}; end

  # Off by default so the lib's debug? paths stay dormant across the suite; the
  # overlay tests flip it on for a single camera and reset it after.
  attr_writer :debug
  def debug?; @debug || false; end

  attr_accessor :inputs

  def input_source
    return @input_source if @input_source_assigned

    @input_source ||= Conjuration::DragonInputSource.new
  end

  def input_source=(source)
    @input_source_assigned = true
    @input_source = source
  end

  def ui_pad
    @ui_pad ||= :one
  end
end

# Stands in for a Conjuration::Scene where a camera only needs its world bounds.
# uid namespaces the camera's render target (camera.rb keys targets by it).
SceneDouble = Struct.new(:virtual_w, :virtual_h) do
  def uid
    object_id
  end
end

# Conjuration::Node delegates inputs/grid/gtk/events/debug? to $game.
$game = GameDouble.new

# A camera wired to a bounds-only scene double. Pass scene_virtual to exercise
# the focal-point clamps; leave nil for free panning.
def make_camera(scene_virtual: nil, x: 0, y: 0, w: 1280, h: 720, current: { x: 640, y: 360, zoom: 1 })
  scene = SceneDouble.new(scene_virtual, scene_virtual)
  Conjuration::Camera.new(scene, name: :test, x: x, y: y, w: w, h: h, current: current)
end

class AssertionError < StandardError; end

# Mirrors the `assert` DragonRuby passes to `def test_*(args, assert)`, so the
# same test files run here and under `dragonruby --test`.
#
# Modeled on dragon/assert.rb from the contrib repo:
#   https://github.com/DragonRuby/dragonruby-game-toolkit-contrib/blob/main/dragon/assert.rb
# The standard surface (equal!/true!/false!/not_equal!/nil!/ok!) matches it
# exactly. close! and raises! are harness-only EXTENSIONS — DR's assert has no
# float-tolerance or exception assertion, so any test using them runs here but
# not under `dragonruby --test`.
class Assert
  def equal!(actual, expected, message = nil)
    return if actual == expected

    raise AssertionError, "#{message || "values differ"}: expected #{expected.inspect}, got #{actual.inspect}"
  end

  def not_equal!(actual, unexpected, message = nil)
    return if actual != unexpected

    raise AssertionError, "#{message || "values should differ"}: both were #{actual.inspect}"
  end

  def true!(value, message = nil)
    return if value

    raise AssertionError, message || "expected truthy, got #{value.inspect}"
  end

  def false!(value, message = nil)
    return unless value

    raise AssertionError, message || "expected falsey, got #{value.inspect}"
  end

  def nil!(value, message = nil)
    return if value.nil?

    raise AssertionError, message || "expected nil, got #{value.inspect}"
  end

  def ok!
    nil
  end

  # --- harness-only extensions (not available under `dragonruby --test`) ---

  def close!(actual, expected, message = nil)
    return if (actual - expected).abs <= 0.001

    raise AssertionError, "#{message || "not close"}: expected ~#{expected}, got #{actual}"
  end

  def raises!(klass, message = nil)
    yield
    raise AssertionError, message || "expected #{klass}, but nothing was raised"
  rescue AssertionError
    raise
  rescue => e
    return if e.is_a?(klass)

    raise AssertionError, "#{message || "wrong error"}: expected #{klass}, got #{e.class} (#{e.message})"
  end
end
