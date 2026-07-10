# Scene stack: hooks, push/pop/change ordering, input/update/render scoping,
# per-scene clock freeze, focus snapshot/restore, audio policy, and the guards.
# See docs/design/scene-lifecycle.md. AudioSpy is defined in scene_management_test.rb.

# A host with the stack mixed in plus a clearable audio (change_scene owns the
# audio policy). perform_input/update/render are private on the mixin; tests
# reach them with .send.
class StackHost
  include Conjuration::SceneManagement

  def audio
    @audio ||= AudioSpy.new
  end

  # Transitions capture snapshots into a render target and read the grid.
  def outputs
    @outputs ||= OutputsDouble.new
  end

  def grid
    @grid ||= GridDouble.new
  end

  # Mimics Game#tick's dispatch so tests drive transitions realistically: a
  # handover suspends input/update, otherwise the top scene ticks.
  def step
    if transitioning?
      advance_handover
    else
      send(:perform_input)
      send(:perform_update)
    end
    send(:perform_render)
  end
end

# Records every lifecycle call into a shared log so ordering is asserted exactly.
# Deliberately does NOT define retain_audio? (so change_scene clears by default).
class RecordingScene
  attr_accessor :saved_focus
  attr_reader :name
  attr_writer :covers

  def initialize(name, log, covers: false)
    @name = name
    @log = log
    @covers = covers
  end

  def covers_below?
    @covers
  end

  def perform_setup;  @log << [@name, :setup];  end
  def perform_input;  @log << [@name, :input];  end
  def perform_update; @log << [@name, :update]; end
  def perform_render; @log << [@name, :render]; end
  def on_enter;  @log << [@name, :on_enter];  end
  def on_exit;   @log << [@name, :on_exit];   end
  def on_pause;  @log << [@name, :on_pause];  end
  def on_resume; @log << [@name, :on_resume]; end
end

class RetainAudioScene < RecordingScene
  def retain_audio?
    true
  end
end

# A scene whose clock advances one per perform_update, exactly like Conjuration::Scene.
class ClockScene < RecordingScene
  attr_reader :clock

  def initialize(name, log)
    super(name, log)
    @clock = 0
  end

  def perform_update
    super
    @clock += 1
  end
end

def stack_of(host, *scenes)
  host.current_scene = scenes.first
  scenes.drop(1).each { |scene| host.push_scene(scene) }
end

# --- hook ordering --------------------------------------------------------

def test_change_scene_hook_order_single(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)
  log.clear

  host.change_scene(to: RecordingScene.new(:b, log))

  assert.equal!(log, [[:a, :on_exit], [:b, :setup], [:b, :on_enter]],
                "change: outgoing on_exit, then incoming setup then on_enter")
end

def test_change_scene_drains_stack_exit_hooks_top_down(args, assert)
  log = []
  host = StackHost.new
  stack_of(host, RecordingScene.new(:a, log), RecordingScene.new(:b, log), RecordingScene.new(:c, log))
  log.clear

  host.change_scene(to: RecordingScene.new(:d, log))

  assert.equal!(log, [[:c, :on_exit], [:b, :on_exit], [:a, :on_exit], [:d, :setup], [:d, :on_enter]],
                "change drains the whole stack top-down, then sets up the target")
end

def test_push_hook_order(args, assert)
  log = []
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, log)
  log.clear

  host.push_scene(RecordingScene.new(:b, log))

  assert.equal!(log, [[:a, :on_pause], [:b, :setup], [:b, :on_enter]],
                "push: paused on_pause, then overlay setup then on_enter")
end

def test_pop_hook_order(args, assert)
  log = []
  host = StackHost.new
  stack_of(host, RecordingScene.new(:a, log), RecordingScene.new(:b, log))
  log.clear

  host.pop_scene

  assert.equal!(log, [[:b, :on_exit], [:a, :on_resume]],
                "pop: removed on_exit, then underneath on_resume")
end

# --- input / update / render scoping --------------------------------------

def test_input_and_update_reach_top_only(args, assert)
  log = []
  host = StackHost.new
  stack_of(host, RecordingScene.new(:a, log), RecordingScene.new(:b, log))
  log.clear

  host.send(:perform_input)
  host.send(:perform_update)

  assert.equal!(log, [[:b, :input], [:b, :update]], "only the top scene gets input/update")
end

def test_render_is_bottom_up(args, assert)
  log = []
  host = StackHost.new
  stack_of(host, RecordingScene.new(:a, log), RecordingScene.new(:b, log))
  log.clear

  host.send(:perform_render)

  assert.equal!(log, [[:a, :render], [:b, :render]], "render walks the stack bottom-up")
end

def test_render_skips_beneath_opaque_scene(args, assert)
  log = []
  host = StackHost.new
  stack_of(host, RecordingScene.new(:a, log), RecordingScene.new(:b, log, covers: true))
  log.clear

  host.send(:perform_render)

  assert.equal!(log, [[:b, :render]], "an opaque overlay skips everything beneath it")
end

# --- per-scene clock ------------------------------------------------------

def test_clock_freezes_while_paused_and_resumes(args, assert)
  log = []
  host = StackHost.new
  bottom = ClockScene.new(:a, log)
  host.current_scene = bottom

  3.times { host.send(:perform_update) }
  assert.equal!(bottom.clock, 3, "active scene clock advances per update")

  top = ClockScene.new(:b, log)
  host.push_scene(top)
  2.times { host.send(:perform_update) }

  assert.equal!(bottom.clock, 3, "paused scene clock is frozen")
  assert.equal!(top.clock, 2, "the new top advances")

  host.pop_scene
  2.times { host.send(:perform_update) }
  assert.equal!(bottom.clock, 5, "resumed scene clock advances again")
end

def test_hit_stop_freezes_active_scene_clock(args, assert)
  game = Conjuration::Game.new(nil)
  scene = ClockScene.new(:a, [])
  game.current_scene = scene
  game.hit_stop(2)

  game.tick
  game.tick
  assert.equal!(scene.clock, 0, "active scene clock is frozen through a hit stop")

  game.tick
  assert.equal!(scene.clock, 1, "and resumes once the freeze ends")
end

# --- focus snapshot / restore ---------------------------------------------

def test_focus_snapshot_restore_round_trips(args, assert)
  log = []
  host = StackHost.new
  bottom = RecordingScene.new(:a, log)
  host.current_scene = bottom

  node_a = Object.new
  Conjuration::UI.focused_node = node_a
  Conjuration::UI.active_navigation_group = :group_a
  Conjuration::UI.pressed_node = node_a
  Conjuration::UI.hovered_node = node_a
  cursor = Conjuration::UI.focus_cursor
  cursor[:x], cursor[:y], cursor[:w], cursor[:h] = 10, 20, 30, 40

  # A real Scene overlay resets the globals to inert as its setup runs.
  host.push_scene(Conjuration::Scene.new(:overlay))
  assert.nil!(Conjuration::UI.focused_node, "push resets focus for the overlay")
  assert.nil!(Conjuration::UI.active_navigation_group, "push resets the nav group")
  assert.equal!(Conjuration::UI.focus_cursor[:w], 0, "push re-snaps the cursor")

  # Overlay drives its own selection, then pops.
  node_b = Object.new
  Conjuration::UI.focused_node = node_b
  Conjuration::UI.active_navigation_group = :group_b
  b_cursor = Conjuration::UI.focus_cursor
  b_cursor[:x], b_cursor[:y], b_cursor[:w], b_cursor[:h] = 99, 99, 99, 99

  host.pop_scene

  assert.equal!(Conjuration::UI.focused_node, node_a, "pop restores focused_node")
  assert.equal!(Conjuration::UI.active_navigation_group, :group_a, "pop restores the nav group")
  assert.equal!(Conjuration::UI.pressed_node, node_a, "pop restores pressed_node")
  assert.equal!(Conjuration::UI.hovered_node, node_a, "pop restores hovered_node")
  restored = Conjuration::UI.focus_cursor
  assert.equal!([restored[:x], restored[:y], restored[:w], restored[:h]], [10, 20, 30, 40],
                "pop restores the focus cursor verbatim (snaps back in place)")
ensure
  Conjuration::UI.focused_node = nil
  Conjuration::UI.active_navigation_group = nil
  Conjuration::UI.pressed_node = nil
  Conjuration::UI.hovered_node = nil
  Conjuration::UI.focus_cursor[:w] = 0
end

# --- audio policy ---------------------------------------------------------

def test_audio_cleared_on_change_unless_retained(args, assert)
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, [])

  host.change_scene(to: RecordingScene.new(:b, []))
  assert.equal!(host.audio.clears, 1, "change clears audio by default")

  host.change_scene(to: RetainAudioScene.new(:c, []))
  assert.equal!(host.audio.clears, 1, "retain_audio? scene keeps audio")
end

def test_audio_never_cleared_on_push_or_pop(args, assert)
  host = StackHost.new
  stack_of(host, RecordingScene.new(:a, []), RecordingScene.new(:b, []))
  before = host.audio.clears

  host.pop_scene
  host.push_scene(RecordingScene.new(:c, []))

  assert.equal!(host.audio.clears, before, "push/pop never clear audio (bgm survives a pause)")
end

# --- guards ---------------------------------------------------------------

def test_double_push_of_same_instance_raises(args, assert)
  host = StackHost.new
  host.current_scene = RecordingScene.new(:a, [])
  overlay = RecordingScene.new(:b, [])
  host.push_scene(overlay)

  assert.raises!(ArgumentError, "pushing the same instance twice raises") do
    host.push_scene(overlay)
  end
end

def test_pop_of_last_scene_is_a_no_op(args, assert)
  log = []
  host = StackHost.new
  only = RecordingScene.new(:a, log)
  host.current_scene = only
  log.clear

  host.pop_scene

  assert.equal!(host.current_scene, only, "the last scene stays put")
  assert.equal!(log, [], "no on_exit fires when popping the last scene")
end

# --- camera render-target namespacing -------------------------------------

def test_same_named_cameras_get_distinct_targets(args, assert)
  scene_a = Conjuration::Scene.new(:same)
  scene_b = Conjuration::Scene.new(:same)
  cam_a = scene_a.add_camera(:main)
  cam_b = scene_b.add_camera(:main)

  key_a = cam_a.instance_variable_get(:@output_key)
  key_b = cam_b.instance_variable_get(:@output_key)

  assert.not_equal!(key_a, key_b, "two scenes' same-named cameras resolve to distinct targets")
  assert.true!(key_a.include?("main"), "the camera name is still in the target key")
end
