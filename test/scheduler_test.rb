# Scheduler: after/every/tween keyed to a clock the host controls. SchedulerHost
# includes the real Conjuration::Scheduling module Scene uses, and mirrors the
# scene's tick site (advance clock, then tick_schedules) — so these exercise the
# exact integration code with a clock we can freeze at will.

class SchedulerHost
  include Conjuration::Scheduling

  attr_accessor :clock

  def initialize
    @clock = 0
  end

  def step
    @clock += 1
    tick_schedules
  end

  def scheduler_allocated?
    !@scheduler.nil?
  end
end

class TweenAccessorTarget
  attr_accessor :x, :y

  def initialize
    @x = 0
    @y = 0
  end
end

def test_after_fires_once_at_the_boundary(args, assert)
  host = SchedulerHost.new
  fires = []
  host.after(3) { fires << host.clock }

  host.step
  host.step
  assert.equal!(fires.length, 0, "does not fire before the boundary")

  host.step
  assert.equal!(fires, [3], "fires exactly on the boundary tick")

  host.step
  host.step
  assert.equal!(fires, [3], "never fires again")
end

def test_after_can_be_cancelled_before_it_fires(args, assert)
  host = SchedulerHost.new
  fires = 0
  handle = host.after(3) { fires += 1 }

  host.step
  handle.cancel
  5.times { host.step }

  assert.equal!(fires, 0, "a cancelled after never fires")
end

def test_every_repeats_and_cancels(args, assert)
  host = SchedulerHost.new
  fires = []
  handle = host.every(2) { fires << host.clock }

  6.times { host.step }
  assert.equal!(fires, [2, 4, 6], "fires on each interval boundary")

  handle.cancel
  4.times { host.step }
  assert.equal!(fires, [2, 4, 6], "stops firing once cancelled")
end

def test_tween_hits_exact_endpoints(args, assert)
  host = SchedulerHost.new
  target = { x: 0 }
  host.tween(target, :x, to: 100, over: 10)

  assert.equal!(target[:x], 0, "start value untouched before the first tick")

  5.times { host.step }
  assert.close!(target[:x], 50, "linear midpoint at half the duration")

  5.times { host.step }
  assert.equal!(target[:x], 100, "reaches the exact target at `over`")
end

def test_tween_start_value_is_exact_at_elapsed_zero(args, assert)
  sched = Conjuration::Scheduler.new
  target = { x: 20 }
  sched.tween(0, target, { x: 120 }, 10, :identity)

  sched.tick(0)
  assert.equal!(target[:x], 20, "at elapsed 0 the value equals the start")

  sched.tick(10)
  assert.equal!(target[:x], 120, "at elapsed `over` the value equals the target")
end

def test_each_builtin_ease_curves_correctly(args, assert)
  midpoints = {
    identity: 50,
    smooth_start: 25,
    smooth_stop: 75,
    smooth_step: 50
  }

  midpoints.each do |ease, mid|
    sched = Conjuration::Scheduler.new
    target = { v: 0 }
    sched.tween(0, target, { v: 100 }, 10, ease)

    sched.tick(5)
    assert.close!(target[:v], mid, "#{ease} midpoint")

    sched.tick(10)
    assert.equal!(target[:v], 100, "#{ease} endpoint is exact")
  end
end

def test_tween_accepts_a_callable_ease(args, assert)
  sched = Conjuration::Scheduler.new
  target = { v: 0 }
  sched.tween(0, target, { v: 100 }, 10, ->(t) { t * t * t })

  sched.tick(5)
  assert.close!(target[:v], 12.5, "custom cubic ease applied at the midpoint")
end

def test_tween_drives_multiple_attrs_on_an_accessor_object(args, assert)
  host = SchedulerHost.new
  obj = TweenAccessorTarget.new
  host.tween(obj, x: 100, y: 50, over: 4)

  4.times { host.step }

  assert.equal!(obj.x, 100, "x reaches its target on an attr_accessor object")
  assert.equal!(obj.y, 50, "y reaches its target on an attr_accessor object")
end

def test_frozen_clock_holds_everything_and_resumes_without_double_firing(args, assert)
  sched = Conjuration::Scheduler.new
  afters = 0
  everies = 0
  target = { x: 0 }
  sched.after(0, 5, -> { afters += 1 })
  sched.every(0, 2, -> { everies += 1 })
  sched.tween(0, target, { x: 100 }, 10, :identity)

  (1..5).each { |c| sched.tick(c) }
  assert.equal!(afters, 1, "after fired once by clock 5")
  assert.equal!(everies, 2, "every fired at 2 and 4")
  assert.close!(target[:x], 50, "tween at its midpoint")

  # A hit stop: the clock holds at 5 across several ticks.
  4.times { sched.tick(5) }
  assert.equal!(afters, 1, "held clock does not re-fire the after")
  assert.equal!(everies, 2, "held clock does not re-fire the every")
  assert.close!(target[:x], 50, "tween holds its value while frozen")

  (6..10).each { |c| sched.tick(c) }
  assert.equal!(everies, 5, "every resumes on the boundaries after the freeze (6,8,10)")
  assert.equal!(target[:x], 100, "tween resumes to the exact endpoint")
end

def test_schedule_created_during_a_callback_runs_on_the_next_tick(args, assert)
  host = SchedulerHost.new
  order = []
  host.after(1) do
    order << [:outer, host.clock]
    host.after(1) { order << [:inner, host.clock] }
  end

  host.step # clock 1: outer fires and appends inner mid-iteration
  assert.equal!(order, [[:outer, 1]], "the appended schedule does not run in the same tick")

  host.step # clock 2: inner reaches its own boundary
  assert.equal!(order, [[:outer, 1], [:inner, 2]], "the appended schedule fires on the following boundary")
end

def test_a_host_that_never_schedules_allocates_nothing(args, assert)
  host = SchedulerHost.new
  10.times { host.step }

  assert.false!(host.scheduler_allocated?, "no scheduler object is created for a schedule-free host")
end

def test_scheduler_holds_no_collection_until_first_use(args, assert)
  sched = Conjuration::Scheduler.new
  assert.false!(sched.active?, "a fresh scheduler is inert")

  sched.tick(5) # a tick before anything is scheduled is a no-op
  assert.false!(sched.active?, "ticking an empty scheduler allocates nothing")
end

def test_unknown_ease_symbol_raises(args, assert)
  sched = Conjuration::Scheduler.new
  assert.raises!(ArgumentError, "an unknown ease symbol is rejected") do
    sched.tween(0, { v: 0 }, { v: 1 }, 10, :bogus_curve)
  end
end

def test_scene_exposes_the_scheduling_api(args, assert)
  assert.true!(Conjuration::Scene.include?(Conjuration::Scheduling), "Scene mixes in the scheduling API")
end
