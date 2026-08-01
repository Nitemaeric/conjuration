# Virtual resolution (canvas): the resolution chain, the zoom/offset blit math,
# the canvas-space mouse, and the render path. The hard requirement is the nil
# case — with no canvas anywhere the primitive stream must be exactly what the
# framework emitted before canvases existed. See docs/canvas.md.
#
# Reuses StackHost (scene_stack_test.rb) as the game stand-in: it owns a scene
# stack and mixes in the real Conjuration::CanvasHost, so these drive the
# production resolution code, not a copy of it.

class NativeTestScene < Conjuration::Scene; end

class CanvasTestScene < Conjuration::Scene
  canvas w: 64, h: 64

  def fired
    @fired ||= []
  end

  def view
    fired = self.fired
    node({ x: 4, y: 4, w: 24, h: 10, path: :pixel, action: -> { fired << :back } }, id: :back, group: :hud)
  end
end

class FractionalCanvasScene < Conjuration::Scene
  canvas w: 64, h: 64, integer_scale: false
end

# A scene double that paints one primitive through the host's render_output —
# the seam Conjuration::Scene#outputs uses, so the canvas redirect is exercised
# exactly as a real scene exercises it.
class PaintScene
  attr_reader :name

  def initialize(host, name: :paint, canvas: nil)
    @host = host
    @name = name
    @canvas = Conjuration::Canvas.coerce(canvas)
  end

  def active_canvas
    @canvas || @host.canvas
  end

  def perform_setup; end
  def perform_input; end
  def perform_update; end

  def perform_render
    @host.render_output.primitives << { x: 1, y: 2, w: 3, h: 4, path: :pixel, dbg: @name }
    @host.render_output.debug << { x: 5, y: 6, text: "debug", dbg: @name }
  end
end

def canvas_key
  Conjuration::SceneManagement::CANVAS_KEY
end

def reset_canvas_globals
  $game.canvas = nil
  $game.current_scene = nil
  $game.inputs = nil
  $game.input_source = nil
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.focused_node = nil
  Conjuration::UI.pressed_node = nil
end

# --- resolution chain ------------------------------------------------------

def test_resolution_chain_scene_over_game_over_nil(args, assert)
  native = NativeTestScene.new(:native)
  assert.nil!(native.active_canvas, "no canvas anywhere resolves to nil (native window)")
  assert.equal!([native.view_w, native.view_h], [1280, 720], "nil canvas means scene space is window space")

  $game.canvas = { w: 320, h: 180 }
  defaulted = NativeTestScene.new(:defaulted)
  assert.equal!([defaulted.view_w, defaulted.view_h], [320, 180], "a scene with no declaration takes the game default")

  overriding = CanvasTestScene.new(:overriding)
  assert.equal!([overriding.view_w, overriding.view_h], [64, 64], "a scene-level declaration beats the game default")
ensure
  reset_canvas_globals
end

def test_active_canvas_follows_the_top_scene(args, assert)
  $game.canvas = { w: 320, h: 180 }
  $game.current_scene = CanvasTestScene.new(:top)
  assert.equal!($game.view_w, 64, "the game view follows the top scene's override")

  $game.current_scene = NativeTestScene.new(:top)
  assert.equal!($game.view_w, 320, "and falls back to the game default")

  $game.canvas = nil
  assert.equal!($game.view_w, 1280, "and to the window when neither declares one")
ensure
  reset_canvas_globals
end

def test_scene_size_and_canvas_survive_reconstruction(args, assert)
  scene = CanvasTestScene.new(:demo)
  assert.equal!([scene.w, scene.h], [64, 64], "the scene sizes itself in canvas space")

  # The (class, name, state) contract: a scene is rebuilt from its class, so a
  # class-level declaration always comes back with it.
  rebuilt = scene.class.new(scene.name)
  assert.equal!(rebuilt.canvas.w, 64, "the class-level DSL survives reconstruction")
  assert.equal!([rebuilt.w, rebuilt.h], [64, 64], "and so does the canvas-space sizing")
ensure
  reset_canvas_globals
end

def test_canvas_rejects_a_degenerate_size(args, assert)
  assert.raises!(ArgumentError, "a zero-sized canvas is refused") { Conjuration::Canvas.new(w: 0, h: 64) }
end

# --- zoom / offset math ----------------------------------------------------

def test_integer_scale_floors_the_zoom_and_centres_the_blit(args, assert)
  canvas = Conjuration::Canvas.new(w: 64, h: 64)
  view = canvas.metrics(1280, 720)

  assert.equal!(view[:zoom], 11, "720/64 = 11.25 floors to an 11x integer zoom")
  assert.equal!([view[:w], view[:h]], [704, 704], "the canvas draws at 704x704")
  assert.equal!([view[:offset_x], view[:offset_y]], [288.0, 8.0], "centred: (1280-704)/2 and (720-704)/2")

  blit = canvas.blit(1280, 720, canvas_key)
  assert.equal!(blit, { x: 288.0, y: 8.0, w: 704, h: 704, path: canvas_key }, "the blit is the letterboxed rect")
end

def test_fractional_scale_takes_the_max_fit(args, assert)
  canvas = Conjuration::Canvas.new(w: 64, h: 64, integer_scale: false)
  view = canvas.metrics(1280, 720)

  assert.close!(view[:zoom], 11.25, "the unfloored fit is 11.25x")
  assert.equal!([view[:w], view[:h]], [720.0, 720.0], "which fills the short axis exactly")
  assert.equal!([view[:offset_x], view[:offset_y]], [280.0, 0.0], "so only the left/right bars remain")
end

def test_a_window_too_small_for_1x_keeps_the_fractional_fit(args, assert)
  canvas = Conjuration::Canvas.new(w: 640, h: 640)
  view = canvas.metrics(320, 320)

  assert.close!(view[:zoom], 0.5, "integer_scale never collapses the canvas to nothing")
end

# --- mouse remap -----------------------------------------------------------

def canvas_mouse_at(x, y, canvas: { w: 64, h: 64 }, click: false, held: false)
  $game.canvas = canvas
  $game.inputs = { last_active: :mouse, mouse: { x: x, y: y, w: 1, h: 1, wheel: nil, click: click, held: held } }
  $game.mouse
end

def test_window_point_maps_into_canvas_pixels(args, assert)
  centre = canvas_mouse_at(640, 360)
  assert.equal!([centre.x, centre.y], [32, 32], "the window centre is the canvas centre pixel")

  # Round trip: canvas (10, 8) is drawn at 288 + 10*11, 8 + 8*11.
  point = canvas_mouse_at(288 + 10 * 11, 8 + 8 * 11)
  assert.equal!([point.x, point.y], [10, 8], "a window point round-trips to the pixel it lands in")
ensure
  reset_canvas_globals
end

def test_letterbox_points_map_outside_the_canvas(args, assert)
  left_bar = canvas_mouse_at(100, 360)
  assert.true!(left_bar.x < 0, "the left bar is left of pixel 0, not clamped onto it")

  bottom_bar = canvas_mouse_at(640, 2)
  assert.true!(bottom_bar.y < 0, "the bottom bar floors below 0 rather than phantom-hovering row 0")

  right_bar = canvas_mouse_at(1270, 360)
  assert.true!(right_bar.x > 63, "the right bar is past the last column")
ensure
  reset_canvas_globals
end

def test_the_mouse_is_raw_passthrough_without_a_canvas(args, assert)
  raw = { x: 640, y: 360, w: 1, h: 1, wheel: nil, click: false, held: false }
  $game.inputs = { last_active: :mouse, mouse: raw }

  assert.true!($game.mouse.equal?(raw), "no canvas means the framework sees the device mouse itself")
ensure
  reset_canvas_globals
end

def test_the_canvas_mouse_delegates_untransformed_state(args, assert)
  pointer = canvas_mouse_at(640, 360, click: true, held: true)

  assert.true!(pointer.click, "click rides through untouched")
  assert.true!(pointer.held, "so does held")
  assert.true!(pointer.inside_rect?({ x: 0, y: 0, w: 64, h: 64 }), "hit helpers work in canvas space")
  assert.false!(pointer.inside_rect?({ x: 0, y: 0, w: 8, h: 8 }), "and reject points outside")
ensure
  reset_canvas_globals
end

# --- UI hit-testing at 64x64 -----------------------------------------------

# Mounts the scene's view by hand rather than through perform_setup: mruby loses
# the super context of a method that built a block earlier in the same frame, so
# a real Scene#perform_setup with a `view` can't be driven from the harness.
def lowrez_scene_with_ui
  scene = CanvasTestScene.new(:lowrez)
  $game.current_scene = scene
  $game.input_source = FakeInputSource.new
  scene.ui.view { scene.view }
  scene.ui.render_view
  scene.ui.calculate_layout
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.focused_node = nil
  scene
end

def test_ui_hit_test_resolves_through_the_canvas(args, assert)
  scene = lowrez_scene_with_ui
  # Canvas (10, 8) is inside the 4,4 24x10 button; in window space that is a
  # point 400px from the left edge of the screen.
  $game.inputs = { last_active: :mouse, mouse: { x: 288 + 10 * 11, y: 8 + 8 * 11, w: 1, h: 1, wheel: nil, click: true, held: false } }

  scene.send(:perform_input)

  assert.equal!(Conjuration::UI.hovered_node.id, :back, "a window-space mouse hovers the node at its canvas coords")
  assert.equal!(scene.fired, [:back], "and the click fires its action")
ensure
  reset_canvas_globals
end

def test_a_letterbox_click_hovers_nothing(args, assert)
  scene = lowrez_scene_with_ui
  # Same canvas column as the button, but down in the bottom letterbox bar.
  $game.inputs = { last_active: :mouse, mouse: { x: 288 + 10 * 11, y: 2, w: 1, h: 1, wheel: nil, click: true, held: false } }

  scene.send(:perform_input)

  assert.nil!(Conjuration::UI.hovered_node, "the dead zone below the canvas hovers nothing")
  assert.equal!(scene.fired, [], "and clicking there fires nothing")
ensure
  reset_canvas_globals
end

# --- render path -----------------------------------------------------------

def test_no_canvas_leaves_the_primitive_stream_untouched(args, assert)
  host = StackHost.new
  host.current_scene = PaintScene.new(host)

  host.send(:perform_render)
  through_render_stack = host.outputs.primitives.dup

  assert.equal!(through_render_stack, [{ x: 1, y: 2, w: 3, h: 4, path: :pixel, dbg: :paint }],
                "the scene's own primitives reach the screen unwrapped")
  assert.nil!(host.outputs.targets[canvas_key], "no canvas means no canvas render target is ever touched")

  # The pre-canvas path, called directly: the streams must be identical.
  host.outputs.primitives.clear
  host.send(:render_scenes)
  assert.equal!(host.outputs.primitives, through_render_stack, "render_stack is a straight pass-through when no canvas resolves")
end

def test_a_canvas_composes_into_a_target_and_blits_letterboxed(args, assert)
  host = StackHost.new
  host.current_scene = PaintScene.new(host, canvas: { w: 64, h: 64 })

  host.send(:perform_render)

  target = host.outputs.targets[canvas_key]
  assert.equal!([target.width, target.height], [64, 64], "the target is canvas-sized")
  assert.equal!(target.primitives, [{ x: 1, y: 2, w: 3, h: 4, path: :pixel, dbg: :paint }], "scene content lands in the canvas, not on the screen")
  assert.equal!(host.outputs.primitives, [{ x: 288.0, y: 8.0, w: 704, h: 704, path: canvas_key }],
                "the screen gets one primitive: the centred, letterboxed blit")
end

def test_debug_output_bypasses_the_canvas(args, assert)
  host = StackHost.new
  host.current_scene = PaintScene.new(host, canvas: { w: 64, h: 64 })

  host.send(:perform_render)

  assert.equal!(host.outputs.debug.length, 1, "debug primitives stay on the screen's debug layer")
  assert.equal!(host.outputs.targets[canvas_key].debug, [], "they never enter the canvas target, so they never scale with the blit")
end

def test_the_canvas_redirect_is_restored_after_rendering(args, assert)
  host = StackHost.new
  host.current_scene = PaintScene.new(host, canvas: { w: 64, h: 64 })

  host.send(:perform_render)

  assert.true!(host.render_output.equal?(host.outputs), "render_output is handed back after the canvas pass")
end

# --- transitions across resolutions ----------------------------------------

def test_a_snapshot_captures_the_composed_window_frame(args, assert)
  host = StackHost.new
  host.current_scene = PaintScene.new(host, name: :lowrez, canvas: { w: 64, h: 64 })

  transition = ScriptedTransition.new(out: 2, inn: 2)
  host.change_scene(to: PaintScene.new(host, name: :native), transition: transition)

  snapshot = host.outputs.targets[Conjuration::SceneManagement::SNAPSHOT_KEY]
  assert.equal!([snapshot.width, snapshot.height], [1280, 720], "the snapshot stays window-sized")
  assert.equal!(snapshot.primitives, [{ x: 288.0, y: 8.0, w: 704, h: 704, path: canvas_key }],
                "it holds the letterboxed blit, so transitions never see the canvas")
end

def test_a_cross_resolution_transition_produces_both_blits(args, assert)
  host = StackHost.new
  host.current_scene = PaintScene.new(host, name: :native)

  transition = ScriptedTransition.new(out: 2, inn: 3)
  host.change_scene(to: PaintScene.new(host, name: :lowrez, canvas: { w: 64, h: 64 }), transition: transition)

  # Drive out -> in: the out phase blits the outgoing native snapshot, the in
  # phase composes and blits the incoming 64x64 canvas.
  8.times { host.step if host.transitioning? }

  paths = host.outputs.primitives.map { |primitive| primitive[:path] }
  assert.true!(paths.include?(Conjuration::SceneManagement::SNAPSHOT_KEY), "the outgoing native frame is blitted")
  assert.true!(paths.include?(canvas_key), "and the incoming 64x64 frame is blitted over it")
  assert.false!(host.transitioning?, "the cross-resolution handover completes")
end

# --- camera + debug coordinate spaces --------------------------------------

def test_cameras_default_to_the_canvas_viewport(args, assert)
  $game.canvas = { w: 64, h: 64 }
  camera = Conjuration::Camera.new(SceneDouble.new(nil, nil), name: :main)

  assert.equal!([camera.w, camera.h], [64, 64], "a camera fills the canvas, not the window")
  assert.equal!([camera.current.x, camera.current.y], [32, 32], "and centres on it")
ensure
  reset_canvas_globals
end

def test_the_inspector_hits_in_canvas_space_and_draws_in_window_space(args, assert)
  scene = lowrez_scene_with_ui
  $game.debug = true
  outputs = OutputsDouble.new

  window_mouse = { x: 288 + 10 * 11, y: 8 + 8 * 11, w: 1, h: 1 }
  canvas_mouse = Conjuration::CanvasMouse.new(window_mouse, scene.canvas, 1280, 720)

  hovered = Conjuration::UI::Inspector.node_at_point(scene.ui, canvas_mouse.x, canvas_mouse.y)
  assert.equal!(hovered.id, :back, "nodes are hit-tested with the canvas mouse")

  Conjuration::UI::Inspector.render(scene.ui, outputs, canvas_mouse, window_mouse)
  readout = outputs.debug.find { |primitive| primitive[:w] == 220 }
  assert.true!(!readout.nil?, "the hover readout is emitted")
  assert.equal!(readout[:x], window_mouse[:x] + 16, "positioned next to the RAW mouse, in window space")
  assert.true!(readout[:x] + readout[:w] <= 1280, "and clamped to the window, not the canvas")
ensure
  $game.debug = false
  reset_canvas_globals
end
