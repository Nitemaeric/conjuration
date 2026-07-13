# Sequence: an ordered queue of steps ticked once per frame against a clock the
# host controls. SequenceHost includes the real Sequencing (and Scheduling, which
# `animate` drives through) modules Scene uses, and mirrors the scene's tick site
# (advance clock, tick_sequence, tick_schedules) — so these exercise the exact
# integration code with a clock we can freeze at will.

class SequenceHost
  include Conjuration::Scheduling
  include Conjuration::Sequencing

  attr_accessor :clock

  def initialize
    @clock = 0
    @game = FakeConfirmGame.new
    @inputs = FakeMouseInputs.new
  end

  # game/inputs feed the default sequence_confirm? (input seam + mouse click).
  attr_reader :game, :inputs

  # advance:false freezes the clock (a pause/hit-stop/stacked scene) while still
  # running the tick site — the whole performance must hold.
  def step(advance: true)
    @clock += 1 if advance
    tick_sequence
    tick_schedules
  end

  def sequence_allocated?
    !@sequence.nil?
  end
end

class FakeConfirmGame
  attr_accessor :confirm

  def input_source
    self
  end

  def ui_pad
    :one
  end

  def just_pressed?(_pad, action)
    action == :ui_confirm && @confirm ? true : false
  end
end

class FakeMouseInputs
  attr_accessor :click

  def mouse
    self
  end
end

def test_act_chains_resolve_in_a_single_tick(args, assert)
  host = SequenceHost.new
  fires = []
  host.play_sequence do
    act { fires << :a }
    act { fires << :b }
    act { fires << :c }
  end

  assert.equal!(fires, [], "the builder block does not run the acts, only queues them")

  host.step
  assert.equal!(fires, %i[a b c], "a run of synchronous acts completes in one tick")
  assert.false!(host.sequence_playing?, "the sequence finished")
end

def test_wait_blocks_n_ticks_then_advances(args, assert)
  host = SequenceHost.new
  fires = []
  host.play_sequence do
    act { fires << :before }
    wait(3)
    act { fires << :after }
  end

  host.step # enters :before, then the wait
  assert.equal!(fires, [:before], "the first act fires immediately, the wait blocks")

  host.step
  host.step
  assert.equal!(fires, [:before], "still waiting two ticks in")

  host.step # third tick past the wait's entry boundary
  assert.equal!(fires, %i[before after], "advances once the wait elapses")
end

def test_wait_until_completes_on_the_predicate(args, assert)
  host = SequenceHost.new
  flag = { ready: false }
  done = []
  host.play_sequence do
    wait_until { flag[:ready] }
    act { done << :go }
  end

  3.times { host.step }
  assert.equal!(done, [], "blocks while the predicate is false")

  flag[:ready] = true
  host.step
  assert.equal!(done, [:go], "advances the tick after the predicate turns true")
end

def test_wait_confirm_advances_on_a_confirm_edge_and_not_before(args, assert)
  host = SequenceHost.new
  done = []
  host.play_sequence do
    wait_confirm
    act { done << :advanced }
  end

  5.times { host.step }
  assert.equal!(done, [], "no confirm, no advance")

  host.game.confirm = true
  host.step
  assert.equal!(done, [:advanced], "the confirm edge advances the sequence")
end

def test_wait_confirm_also_advances_on_a_click(args, assert)
  host = SequenceHost.new
  done = []
  host.play_sequence do
    wait_confirm
    act { done << :tapped }
  end

  host.step
  assert.equal!(done, [], "no input yet")

  host.inputs.click = true
  host.step
  assert.equal!(done, [:tapped], "a mouse/touch click advances too")
end

def test_wait_confirm_ignores_a_confirm_held_from_entry(args, assert)
  host = SequenceHost.new
  host.game.confirm = true # held before the step even enters
  done = []
  host.play_sequence do
    act { done << :spoke }
    wait_confirm
    act { done << :next }
  end

  host.step # enters :spoke then the wait_confirm on the same tick
  assert.equal!(done, [:spoke], "does not consume a confirm on its own entry frame")

  host.step
  assert.equal!(done, %i[spoke next], "advances on the first frame after entry")
end

def test_animate_blocks_for_over_and_moves_the_target_via_the_real_tween(args, assert)
  host = SequenceHost.new
  target = { x: 0 }
  after = []
  host.play_sequence do
    animate(target, { x: 100 }, over: 10)
    act { after << :done }
  end

  host.step # enters the animate; tween kicked, elapsed 0
  assert.equal!(target[:x], 0, "start value untouched on the entry frame")
  assert.equal!(after, [], "the follow-up act is blocked by the animate")

  5.times { host.step }
  assert.close!(target[:x], 50, "linear midpoint halfway through `over`")

  5.times { host.step }
  assert.equal!(target[:x], 100, "reaches the exact target at `over`")
  assert.equal!(after, [:done], "the sequence advances once the motion lands")
end

def test_animate_with_ease_curves_through_the_scheduler(args, assert)
  host = SequenceHost.new
  target = { y: 0 }
  host.play_sequence do
    animate(target, { y: 100 }, over: 10, ease: :smooth_stop)
  end

  6.times { host.step } # entry frame + 5 elapsed
  assert.close!(target[:y], 75, "smooth_stop midpoint, proving the ease reaches the tween")
end

def test_parallel_completes_only_when_all_sub_steps_do(args, assert)
  host = SequenceHost.new
  a = { x: 0 }
  b = { x: 0 }
  host.play_sequence do
    parallel do
      animate(a, { x: 100 }, over: 10)
      animate(b, { x: 100 }, over: 20)
    end
  end

  11.times { host.step } # a's motion (10) has landed, b's (20) has not
  assert.equal!(a[:x], 100, "the faster move finished")
  assert.close!(b[:x], 50, "the slower move is halfway")
  assert.true!(host.sequence_playing?, "the parallel step waits for the slowest")

  10.times { host.step }
  assert.equal!(b[:x], 100, "the slower move finished")
  assert.false!(host.sequence_playing?, "the parallel step completes only when all do")
end

def test_a_frozen_clock_holds_a_sequence_mid_step(args, assert)
  host = SequenceHost.new
  done = []
  host.play_sequence do
    wait(3)
    act { done << :resumed }
  end

  host.step # clock 1: enters the wait
  10.times { host.step(advance: false) } # frozen: clock never moves
  assert.equal!(done, [], "a frozen clock never advances the wait")

  host.step # clock 2
  host.step # clock 3
  host.step # clock 4: wait (entered at 1) elapses
  assert.equal!(done, [:resumed], "resumes and completes once the clock moves again")
end

def test_a_scene_with_no_sequence_pays_nothing(args, assert)
  host = SequenceHost.new

  assert.false!(host.sequence_allocated?, "no Sequence is allocated until play_sequence")
  assert.false!(host.sequence_playing?, "nothing is playing")

  10.times { host.step } # the tick site is a bare nil check
  assert.false!(host.sequence_allocated?, "ticking an idle host allocates nothing")
end

def test_a_finished_sequence_is_dropped(args, assert)
  host = SequenceHost.new
  host.play_sequence { act { nil } }

  assert.true!(host.sequence_allocated?, "the sequence exists before it runs")
  host.step
  assert.false!(host.sequence_allocated?, "a finished sequence is released, back to zero cost")
end

def test_steps_appended_during_a_step_run_safely(args, assert)
  host = SequenceHost.new
  seq = nil
  fires = []
  seq = host.play_sequence do
    act { seq.append(Conjuration::Sequence::Act.new(-> { fires << :late })) }
  end

  host.step
  assert.equal!(fires, [:late], "a step appended mid-tick is picked up and runs")
  assert.false!(host.sequence_playing?, "the appended step also completed")
end

def test_stop_sequence_cancels_in_flight(args, assert)
  host = SequenceHost.new
  fires = []
  host.play_sequence do
    wait(5)
    act { fires << :never }
  end

  host.step
  host.stop_sequence
  assert.false!(host.sequence_playing?, "stopping clears the active sequence")
  assert.false!(host.sequence_allocated?, "and releases it")

  10.times { host.step }
  assert.equal!(fires, [], "a cancelled sequence never fires its remaining steps")
end

def test_play_sequence_replaces_any_in_flight(args, assert)
  host = SequenceHost.new
  fires = []
  host.play_sequence do
    wait(5)
    act { fires << :first }
  end
  host.step

  host.play_sequence do
    act { fires << :second }
  end
  host.step

  assert.equal!(fires, [:second], "a new play_sequence cancels the previous one (one active per scene)")
end

def test_dsl_outside_a_build_raises(args, assert)
  host = SequenceHost.new
  assert.raises!(RuntimeError, "the builder DSL is only valid inside play_sequence") do
    host.act { nil }
  end
end
