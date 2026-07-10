# Frame animation: named clips keyed to a clock, derived (not incremented) so a
# frozen clock freezes the frame, plus frame events edge-detected on a poll step.

def walk_animation
  Conjuration::Animation.new(
    walk: { frames: %w[w0 w1 w2 w3 w4 w5 w6 w7], hold: 5 },
    idle: { frames: %w[idle] }
  )
end

def test_loop_frame_progression_at_exact_boundaries(args, assert)
  a = walk_animation
  a.play(:walk)
  a.update(0)
  assert.equal!(a.frame_index, 0, "elapsed 0 -> frame 0")
  assert.equal!(a.path, "w0", "path tracks the derived frame")

  a.update(4)
  assert.equal!(a.frame_index, 0, "elapsed 4 (< hold) still frame 0")
  a.update(5)
  assert.equal!(a.frame_index, 1, "elapsed 5 crosses to frame 1")
  a.update(39)
  assert.equal!(a.frame_index, 7, "elapsed 39 -> last frame 7")
  a.update(40)
  assert.equal!(a.frame_index, 0, "elapsed 40 wraps to frame 0")
  a.update(45)
  assert.equal!(a.frame_index, 1, "elapsed 45 -> frame 1 of the next cycle")
end

def test_frame_derived_from_started_at_not_absolute_clock(args, assert)
  a = walk_animation
  a.play(:walk)
  a.update(100)
  assert.equal!(a.frame_index, 0, "clip starts at frame 0 whenever it was played")
  a.update(105)
  assert.equal!(a.frame_index, 1, "elapsed since started_at, not the absolute clock")
end

def test_per_frame_durations_override_hold(args, assert)
  a = Conjuration::Animation.new(clip: { frames: %w[a b c], hold: 2, durations: [1, nil, 3] })
  a.play(:clip)
  a.update(0)
  assert.equal!(a.frame_index, 0, "0 -> a")
  a.update(1)
  assert.equal!(a.frame_index, 1, "a held only 1 tick (override), 1 -> b")
  a.update(2)
  assert.equal!(a.frame_index, 1, "b held 2 ticks (hold fallback)")
  a.update(3)
  assert.equal!(a.frame_index, 2, "3 -> c")
  a.update(5)
  assert.equal!(a.frame_index, 2, "c held 3 ticks")
  a.update(6)
  assert.equal!(a.frame_index, 0, "cycle length 6 wraps to a")
end

def test_once_holds_last_frame_and_reports_finished(args, assert)
  a = Conjuration::Animation.new(shoot: { frames: %w[a b c], hold: 2, mode: :once })
  a.play(:shoot)
  a.update(0)
  assert.false!(a.finished?, "not finished at start")
  a.update(5)
  assert.equal!(a.frame_index, 2, "elapsed 5 is the last frame")
  assert.false!(a.finished?, "not finished until the full length elapses")
  a.update(6)
  assert.equal!(a.frame_index, 2, "holds the last frame past its length")
  assert.true!(a.finished?, "finished once total length elapsed")
  a.update(100)
  assert.equal!(a.frame_index, 2, "keeps holding the last frame")
  assert.true!(a.finished?, "stays finished")
end

def test_loop_is_never_finished(args, assert)
  a = walk_animation
  a.play(:walk)
  a.update(0)
  a.update(10_000)
  assert.false!(a.finished?, "loop clips never report finished")
end

def test_ping_pong_sequence_turnaround_not_double_held(args, assert)
  a = Conjuration::Animation.new(bob: { frames: %w[a b c d], hold: 1, mode: :ping_pong })
  expected = [0, 1, 2, 3, 2, 1, 0, 1]
  expected.each_with_index do |frame, elapsed|
    a.play(:bob)
    a.update(0) if elapsed.zero?
    a.update(elapsed)
    assert.equal!(a.frame_index, frame, "ping_pong elapsed #{elapsed} -> frame #{frame}")
  end
end

def test_play_is_idempotent_and_restarts_on_change(args, assert)
  a = walk_animation
  a.play(:walk)
  a.update(0)
  a.update(10)
  assert.equal!(a.frame_index, 2, "walk at elapsed 10 -> frame 2")

  a.play(:walk)
  a.update(15)
  assert.equal!(a.frame_index, 3, "idempotent play keeps the running timeline")

  a.play(:idle)
  a.play(:walk)
  a.update(20)
  assert.equal!(a.frame_index, 0, "switching clips (idle then back) restarts walk at frame 0")
  assert.equal!(a.current, :walk, "current tracks the played clip")
end

def test_events_fire_once_per_frame_crossing(args, assert)
  fired = []
  a = Conjuration::Animation.new(walk: { frames: %w[w0 w1 w2 w3], hold: 1 })
  a.on(:walk, frame: 2) { fired << :two }
  a.play(:walk)
  (0..7).each { |t| a.update(t) }
  assert.equal!(fired.length, 2, "frame-2 event fires on each entry: elapsed 2 and 6")
end

def test_no_event_on_start_frame_without_a_declaration(args, assert)
  fired = []
  a = Conjuration::Animation.new(walk: { frames: %w[w0 w1 w2], hold: 1 })
  a.on(:walk, frame: 1) { fired << :one }
  a.play(:walk)
  a.update(0)
  assert.equal!(fired.length, 0, "no event fires on start frame 0 when frame 0 has none")
  a.update(1)
  assert.equal!(fired.length, 1, "frame-1 event fires when crossed")
end

def test_frame_zero_event_fires_on_start(args, assert)
  fired = []
  a = Conjuration::Animation.new(walk: { frames: %w[w0 w1], hold: 1 })
  a.on(:walk, frame: 0) { fired << :zero }
  a.play(:walk)
  a.update(0)
  assert.equal!(fired.length, 1, "an event on frame 0 fires as the clip starts")
end

def test_events_fire_in_order_across_a_multi_frame_skip(args, assert)
  fired = []
  a = Conjuration::Animation.new(walk: { frames: %w[w0 w1 w2 w3 w4], hold: 1 })
  a.on(:walk, frame: 1) { fired << 1 }
  a.on(:walk, frame: 2) { fired << 2 }
  a.on(:walk, frame: 3) { fired << 3 }
  a.play(:walk)
  a.update(0)
  a.update(4)
  assert.equal!(fired, [1, 2, 3], "a slow frame crossing several boundaries fires each in order")
end

def test_events_fire_in_time_order_across_a_loop_wrap(args, assert)
  fired = []
  a = Conjuration::Animation.new(walk: { frames: %w[w0 w1 w2], hold: 1 })
  a.on(:walk, frame: 0) { fired << 0 }
  a.on(:walk, frame: 2) { fired << 2 }
  a.play(:walk)
  a.update(0)
  a.update(5)
  assert.equal!(fired, [0, 2, 0, 2], "boundaries fire in time order across the loop wrap")
end

def test_frozen_clock_holds_frame_and_does_not_refire_events(args, assert)
  fired = []
  a = Conjuration::Animation.new(walk: { frames: %w[w0 w1 w2 w3], hold: 5 })
  a.on(:walk, frame: 1) { fired << 1 }
  a.play(:walk)
  a.update(0)
  a.update(5)
  assert.equal!(a.frame_index, 1, "advanced to frame 1")
  assert.equal!(fired.length, 1, "frame-1 event fired once")

  a.update(5)
  a.update(5)
  assert.equal!(a.frame_index, 1, "frame held while the clock is frozen")
  assert.equal!(fired.length, 1, "event does not refire while the clock is frozen")
end

def test_ping_pong_event_semantics(args, assert)
  fired = []
  a = Conjuration::Animation.new(bob: { frames: %w[a b c], hold: 1, mode: :ping_pong })
  a.on(:bob, frame: 1) { fired << 1 }
  a.on(:bob, frame: 2) { fired << 2 }
  a.play(:bob)
  (0..3).each { |t| a.update(t) }
  assert.equal!(fired, [1, 2, 1], "interior frame fires twice per cycle, the turnaround once")
end

def test_path_before_first_update_is_the_first_frame(args, assert)
  a = walk_animation
  a.play(:walk)
  assert.equal!(a.path, "w0", "path before the first update is the clip's first frame")
end

def test_unplayed_animation_has_no_path_or_frame(args, assert)
  a = walk_animation
  a.update(5)
  assert.nil!(a.path, "no clip playing -> nil path")
  assert.nil!(a.frame_index, "no clip playing -> nil frame")
  assert.false!(a.finished?, "no clip playing -> not finished")
end

def test_play_unknown_clip_raises(args, assert)
  a = walk_animation
  assert.raises!(ArgumentError) { a.play(:nope) }
end

def test_event_on_unknown_clip_raises(args, assert)
  a = walk_animation
  assert.raises!(ArgumentError) { a.on(:nope, frame: 0) { nil } }
end

def test_empty_clip_raises(args, assert)
  assert.raises!(ArgumentError) { Conjuration::Animation.new(bad: { frames: [] }) }
end

def test_non_positive_duration_raises(args, assert)
  assert.raises!(ArgumentError) { Conjuration::Animation.new(bad: { frames: %w[a b], durations: [0, 1] }) }
end
