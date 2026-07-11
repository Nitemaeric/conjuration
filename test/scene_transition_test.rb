# Scene transitions + loading protocol. Reuses StackHost / RecordingScene /
# ClockScene from scene_stack_test.rb (loaded first). See the design doc's
# "Transitions" and "Loading" sections.

# Records each draw as [phase, progress] so phase sequencing is asserted exactly.
class ScriptedTransition
  attr_reader :draws

  def initialize(out:, inn:)
    @out = out
    @inn = inn
    @draws = []
  end

  def out_duration
    @out
  end

  def in_duration
    @inn
  end

  def draw(_outputs, phase:, progress:, snapshot_key:, grid:)
    @draws << [phase, progress]
  end
end

# A scene that reports progress for `frames` load_ticks, then :done. Counts calls
# so we can prove load_tick stops firing once ready.
class LoadingScene < RecordingScene
  attr_reader :load_calls

  def initialize(name, log, frames:)
    super(name, log)
    @frames = frames
    @load_calls = 0
  end

  def load_tick
    @load_calls += 1
    return :done if @load_calls >= @frames

    @load_calls.to_f / @frames
  end
end

# A loading scene with a view-building loading_view — the new contract: node
# emission inside the framework's loading root, no raw outputs writes.
class LoadingViewScene < LoadingScene
  include Conjuration::UI::Builder

  BAR_W = 480

  def loading_view(progress)
    node({ x: 640, y: 420, text: "Loading #{(progress * 100).to_i}%", anchor_x: 0.5 }, id: :loading_label)
    node({ x: 400, y: 340, w: BAR_W, h: 24, path: :pixel, r: 40, g: 40, b: 48 }, id: :loading_track)
    node({ x: 400, y: 340, w: BAR_W * progress, h: 24, path: :pixel, r: 120, g: 200, b: 130 }, id: :loading_fill)
  end
end

# --- degenerate (no-transition) path --------------------------------------

def test_change_without_transition_stays_synchronous(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)
  log.clear

  host.change_scene(to: RecordingScene.new(:b, log))

  assert.false!(host.transitioning?, "no transition means no handover state")
  assert.equal!(log, [[:a, :on_exit], [:b, :setup], [:b, :on_enter]],
                "hooks fire synchronously, exactly as before transitions existed")
end

# --- transition phase sequencing ------------------------------------------

def test_transition_phase_sequence_out_then_in(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)
  log.clear

  transition = ScriptedTransition.new(out: 2, inn: 2)
  host.change_scene(to: RecordingScene.new(:b, log), transition: transition)

  # Handover is live immediately. The snapshot capture rendered A's final frame
  # (logs :render), then on_exit + setup ran; on_enter has NOT yet fired.
  assert.true!(host.transitioning?, "change with a transition defers over frames")
  assert.equal!(log, [[:a, :render], [:a, :on_exit], [:b, :setup]],
                "snapshot render, then on_exit + setup up front; on_enter deferred")

  12.times { host.step if host.transitioning? }

  assert.false!(host.transitioning?, "the transition completes")
  assert.true!(log.include?([:b, :on_enter]), "on_enter fires at the in-phase boundary, after load")
  out_draws = transition.draws.select { |phase, _| phase == :out }
  in_draws = transition.draws.select { |phase, _| phase == :in }
  assert.true!(out_draws.length >= 1, "the out phase drew")
  assert.true!(in_draws.length >= 1, "the in phase drew")
end

def test_loading_holds_the_handover(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)
  log.clear

  # out is 1 frame, but the incoming needs 3 load frames: the machine must HOLD.
  transition = ScriptedTransition.new(out: 1, inn: 1)
  incoming = LoadingScene.new(:b, log, frames: 3)
  host.change_scene(to: incoming, transition: transition)

  saw_hold = false
  10.times do
    break unless host.transitioning?

    host.step
    phase = host.send(:instance_variable_get, :@handover)&.fetch(:phase)
    saw_hold = true if phase == :hold
  end

  assert.true!(saw_hold, "a still-loading incoming scene parks the transition in :hold")
  assert.false!(host.transitioning?, "and completes once loading finishes")
end

def test_load_tick_called_until_done_then_never(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)

  incoming = LoadingScene.new(:b, log, frames: 3)
  host.change_scene(to: incoming) # no transition: loading_view path

  20.times { host.step if host.transitioning? }

  assert.equal!(incoming.load_calls, 3, "load_tick is called exactly until :done, never after")
  assert.false!(host.transitioning?, "handover ends when loading reports done")
  assert.true!(log.include?([:b, :on_enter]), "on_enter fires once loaded")
end

def test_incoming_gets_no_input_or_update_until_ready(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)

  transition = ScriptedTransition.new(out: 2, inn: 2)
  incoming = LoadingScene.new(:b, log, frames: 2)
  host.change_scene(to: incoming, transition: transition)
  log.clear

  # Drive the tick dispatch until the handover ends. step() suspends input/update
  # while transitioning?, exactly as Game#tick does.
  12.times do
    break unless host.transitioning?

    host.step
  end

  assert.false!(log.include?([:b, :input]), "the incoming scene never gets input while handing over")
  assert.false!(log.include?([:b, :update]), "nor update")

  # Once ready, the normal tick resumes and the incoming scene ticks.
  host.step
  assert.true!(log.include?([:b, :input]), "input resumes once the handover completes")
  assert.true!(log.include?([:b, :update]), "and update")
end

# --- snapshot target lifecycle --------------------------------------------

def test_snapshot_target_present_during_and_released_after(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)

  transition = ScriptedTransition.new(out: 2, inn: 2)
  host.change_scene(to: RecordingScene.new(:b, log), transition: transition)

  key = Conjuration::SceneManagement::SNAPSHOT_KEY
  target = host.outputs[key]
  assert.equal!([target.width, target.height], [1280, 720], "snapshot target is sized to the screen on capture")

  host.step # out frame: snapshot is blit to screen
  assert.true!(host.outputs.primitives.any? { |primitive| primitive[:path] == key },
               "the snapshot is composited while transitioning out")

  10.times { host.step if host.transitioning? }
  assert.true!(target.primitives.empty?, "the snapshot target is released (cleared) after the transition")
end

# --- push-with-transition + pop (the house case) --------------------------

def test_push_transition_then_pop_restores_underneath(args, assert)
  log = []
  host = StackHost.new
  overworld = ClockScene.new(:overworld, log)
  host.current_scene = overworld

  3.times { host.send(:perform_update) }
  node = Object.new
  Conjuration::UI.focused_node = node
  Conjuration::UI.active_navigation_group = :overworld

  transition = ScriptedTransition.new(out: 2, inn: 2)
  host.push_scene(ClockScene.new(:interior, log), transition: transition)
  10.times { host.step if host.transitioning? }

  assert.equal!(overworld.clock, 3, "the overworld froze while the interior was entered")

  host.pop_scene(transition: ScriptedTransition.new(out: 2, inn: 2))
  10.times { host.step if host.transitioning? }

  assert.equal!(host.current_scene, overworld, "popping the interior lands back on the overworld")
  assert.equal!(Conjuration::UI.focused_node, node, "the overworld's selection is restored on pop")
  assert.equal!(Conjuration::UI.active_navigation_group, :overworld, "and its navigation group")
ensure
  Conjuration::UI.focused_node = nil
  Conjuration::UI.active_navigation_group = nil
end

# --- loading: sliced build equivalence ------------------------------------

def zoom_chunk_signature(layer)
  chunks = layer.instance_variable_get(:@chunks)
  chunks.keys.sort.map do |key|
    primitives = chunks[key]
    checksum = 0
    primitives.each { |primitive| checksum += (primitive[:x] || 0) + (primitive[:y] || 0) + (primitive[:r] || 0) }
    [key, primitives.length, checksum]
  end
end

def test_zoom_sliced_build_matches_synchronous(args, assert)
  dim = 16

  synchronous = Conjuration::TileLayer.new(name: :zoom_sync, chunk_size: 400)
  dim.times { |row| ZoomScene.paint_row(synchronous, row, dim, ZoomScene::TILE_SIZE) }

  # Mimic load_tick's ROWS_PER_TICK stepping — the arithmetic that could skip or
  # double a row.
  sliced = Conjuration::TileLayer.new(name: :zoom_sliced, chunk_size: 400)
  build_row = 0
  while build_row < dim
    target = build_row + ZoomScene::ROWS_PER_TICK
    target = dim if target > dim
    while build_row < target
      ZoomScene.paint_row(sliced, build_row, dim, ZoomScene::TILE_SIZE)
      build_row += 1
    end
  end

  assert.equal!(zoom_chunk_signature(sliced), zoom_chunk_signature(synchronous),
                "the time-sliced build produces the identical tile layer")
end

# --- loading view root ------------------------------------------------------

def loading_ui_of(host)
  handover = host.instance_variable_get(:@handover)
  handover && handover[:loading_ui]
end

def test_loading_root_renders_through_reactive_path(args, assert)
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, [])
  incoming = LoadingViewScene.new(:b, [], frames: 4)

  Conjuration::UI.warnings.clear
  host.change_scene(to: incoming) # no transition: black + loading root

  ui = loading_ui_of(host)
  assert.true!(!ui.nil?, "a loading_view scene gets a dedicated view root for the handover")

  host.outputs.primitives.clear
  host.step # one loading frame

  assert.true!(!ui.find(:loading_track).nil?, "the view's nodes exist in the root")
  fill = ui.find(:loading_fill)
  assert.equal!(fill.object.w, LoadingViewScene::BAR_W * 0.25, "layout ran with the reported progress")

  fallbacks = Conjuration::UI.warnings.select { |warning| warning.include?("falling back to :start") }
  assert.equal!(fallbacks, [], "the loading root lays out without justify fallbacks")

  emitted = host.outputs.primitives.flatten
  assert.true!(emitted.any? { |primitive| primitive.respond_to?(:[]) && primitive[:text].to_s.start_with?("Loading") },
               "the root's primitives reach the screen via the normal reactive path")
end

def test_loading_root_reconciles_progress_across_frames(args, assert)
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, [])
  incoming = LoadingViewScene.new(:b, [], frames: 4)
  host.change_scene(to: incoming)

  ui = loading_ui_of(host)
  host.step # 25%
  fill_before = ui.find(:loading_fill)
  label_before = ui.find(:loading_label)

  host.step # 50%
  fill_after = ui.find(:loading_fill)

  assert.true!(fill_before.equal?(fill_after), "the fill node is the same object across loading frames (reconciled, not rebuilt)")
  assert.equal!(fill_after.object.w, LoadingViewScene::BAR_W * 0.5, "its width advanced with the progress")
  assert.true!(label_before.equal?(ui.find(:loading_label)), "the label node identity is stable too")
  assert.equal!(ui.find(:loading_label).object.text, "Loading 50%", "and its text re-derived")
end

def test_loading_root_discarded_after_load_completes(args, assert)
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, [])
  incoming = LoadingViewScene.new(:b, [], frames: 2)
  host.change_scene(to: incoming)

  10.times { host.step if host.transitioning? }
  assert.false!(host.transitioning?, "the handover completed")
  assert.nil!(loading_ui_of(host), "no handover (and no loading root) is retained")

  host.outputs.primitives.clear
  host.step # a normal post-load frame

  emitted = host.outputs.primitives.flatten
  assert.false!(emitted.any? { |primitive| primitive.respond_to?(:[]) && primitive[:text].to_s.start_with?("Loading") },
                "subsequent frames render no loading nodes")
end

def test_loading_root_is_invisible_to_focus_and_navigation(args, assert)
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, [])
  incoming = LoadingViewScene.new(:b, [], frames: 4)
  host.change_scene(to: incoming)

  ui = loading_ui_of(host)
  host.step
  host.step

  assert.equal!(ui.interactive_nodes, [], "the loading root exposes no interactive nodes")
  assert.nil!(Conjuration::UI.focused_node, "nothing in the loading root can take focus")
  assert.nil!(Conjuration::UI.hovered_node, "nor hover")
  assert.nil!(Conjuration::UI.pressed_node, "nor press")
end
