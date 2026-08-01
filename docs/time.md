# Time & motion

Three pieces sit on the time axis: a **scheduler** (timers and tweens), **frame
animation** (named clips with events), and **sequences** (the cutscene
primitive). All three key to the owning scene's clock rather than
`Kernel.tick_count`.

That is the whole point of them existing in the framework. `Kernel.tick_count`
advances during a hit stop, during a transition, and while a scene sits paused
under a pushed one — so anything keyed to it *skips* when the freeze ends
instead of holding. `scene.clock` advances only on frames that scene actually
updated, so a freeze freezes every timer, tween, clip, and cutscene step at once,
with no per-object pause plumbing. See [scenes.md](scenes.md#clocks).

All three are transient: they live on the scene instance, never in save state,
and a re-entered scene starts with none. All three are allocation-free until
first used.

- [Timers and tweens](#timers-and-tweens)
- [Animation clips](#animation-clips)
- [Sequences](#sequences)

## Timers and tweens

```ruby
after(30) { state.flash = false }               # once, 30 scene ticks from now
handle = every(90) { spawn_wave }               # repeatedly, until cancelled
tween(camera.target, :zoom, to: 2.0, over: 24, ease: :smooth_stop)
tween(state.hero, over: 20, x: 400, y: 120)     # several attributes at once
```

Each returns a handle with `#cancel`. `every` requires at least 1 tick.

`tween` interpolates numeric attributes toward their targets. The target may be
a Hash (read and written by key) or any object with matching accessors, so it
drives plain state hashes and real objects alike. The final frame writes the
exact endpoint rather than an eased approximation, so nothing drifts.

Four eases ship, carried inline so they work in the test harness as well as in
DragonRuby:

| Ease | Curve |
| --- | --- |
| `:identity` (default) | linear |
| `:smooth_start` | accelerates out of rest |
| `:smooth_stop` | decelerates into rest |
| `:smooth_step` | eases both ends |

Any callable taking `t` in 0..1 is accepted as-is, so you can pass your own curve
or a DragonRuby easing lambda. This is a scheduler, not an easing library — DR
already has the maths; Conjuration supplies the correct clock to key it to.

A timer's boundary is absolute, so a held clock simply never reaches it: there is
no catch-up burst when a pause ends. A schedule created *inside* a callback
starts on the next tick, so a self-rescheduling timer can't spin.

```ruby
def emphasize(entity)
  entity[:gesture] = 0.0
  tween(entity, :gesture, to: 1.0, over: 10, ease: :smooth_stop)
  after(10) { tween(entity, :gesture, to: 0.0, over: 16, ease: :smooth_start) }
end
```

## Animation clips

`Conjuration::Animation` holds named clips of frames. The current frame is
*derived* from `clock - started_at` rather than incremented per tick, so a frozen
clock holds the frame and resumes mid-clip.

```ruby
def setup
  @hero_anim = Conjuration::Animation.new(
    walk: { frames: Array.new(8) { |i| "sprites/hero/walk#{i}.png" }, hold: 5 },
    idle: { frames: ["sprites/hero/idle.png"] },
    slash: { frames: SLASH_FRAMES, durations: [2, 2, 6, 3], mode: :once }
  )
  @hero_anim.on(:walk, frame: 4) { play_footstep }
  @hero_anim.play(:idle)
end

def update
  @hero_anim.play(state.hero.moving ? :walk : :idle)
  @hero_anim.update(clock)
end

def draw_world(camera)
  hero = state.hero
  camera.draw({ x: hero[:x], y: hero[:y], w: 64, h: 64, path: @hero_anim.path }, z: -hero[:y])
end
```

A clip is an array of frames, a spec hash (`frames:`, `hold:`, `durations:`,
`mode:`), or a pre-built `Animation::Clip`. Modes:

- `:loop` (default) — 0..n-1, repeat.
- `:once` — 0..n-1, then hold the last frame; `#finished?` reports it.
- `:ping_pong` — 0..n-1 then n-2..1. Turnaround frames are held once per cycle,
  not double-held; interior frames are entered twice, so their events fire twice.

`play` is idempotent while the same clip is current, which is why calling it
unconditionally every frame (as above) is correct; switching clips re-anchors so
the new one starts at frame 0.

`update(clock)` is the poll step, and the only thing that fires frame events.
`on(clip, frame:) { … }` registers a callback fired once each time the clip
*enters* that frame — the thing that separates an animation system from a modulo.
Events fire for every boundary crossed since the last poll, in playback order, so
a slow frame that skips over three footsteps still plays three. An event on frame
0 fires when the clip begins.

`#path` is allocation-free, so querying it per draw is fine; `#frame_index` gives
the raw index for hand-rolled sheet maths.

## Sequences

A sequence is an ordered queue of steps ticked one at a time against the scene
clock — the scripted-events primitive a cutscene needs.

```ruby
def setup
  play_sequence do
    say(:hero, "The seal is failing.")

    parallel do
      animate(state.hero,  { x: HERO_CLOSE },  over: 26, ease: :smooth_stop)
      animate(state.rival, { x: RIVAL_CLOSE }, over: 26, ease: :smooth_stop)
    end

    act { emphasize(state.rival) }
    say(:rival, "Then we don't have long. Show me.")

    act { change_scene(to: MenuScene.new(:main)) }
  end
end
```

| Step | Completes when |
| --- | --- |
| `act { }` | immediately — runs once on entry |
| `wait(ticks)` | `ticks` scene-clock ticks have passed |
| `wait_until { }` | the predicate first reads true |
| `wait_confirm` (alias `wait_input`) | the player confirms — see below |
| `animate(target, attrs, over:, ease:)` | the motion lands |
| `parallel { }` | every sub-step in it has completed |

`animate` kicks a real scheduler tween on entry and blocks for `over` ticks, so
the sequence waits for the motion. `parallel` enters all its sub-steps on the
same frame — two characters stepping toward each other together.

### The block is a builder, not a coroutine

mruby's fibers are unreliable, so `play_sequence`'s block **runs once, up front**,
appending steps; it never suspends. That has one consequence worth internalising:
everything outside a step block is evaluated at build time.

```ruby
play_sequence do
  act { state.speaker = :hero }      # runs when this step is reached
  state.speaker = :hero              # runs immediately, when the queue is built
end
```

Put anything that must read or write live state inside `act`, `wait_until`, or an
`animate` target you mutate. A run of consecutive `act`s resolves in a single
tick, so synchronous state changes chain without burning a frame each.

`wait_until`'s predicate is not evaluated until the tick *after* entry, so
entry-frame state can't satisfy it prematurely.

### Confirm

`wait_confirm` advances on the framework confirm edge (`:ui_confirm`) **or** a
mouse/touch click, so touch-only players are never stranded mid-cutscene.
`sequence_confirm?` is the predicate behind it, and overriding it redefines what
"advance" means. The classic RPG typewriter is exactly that override:

```ruby
REVEAL_SPEED = 1.6 # characters per tick

# Queue a line, then wait for the player. The sequence primitive knows nothing
# of dialogue — this is act + wait_confirm.
def say(who, line)
  act do
    state.speaker = who
    state.line = line
    state.line_at = clock
    state.reveal_all = false
  end
  wait_confirm
end

def revealed_count
  return 0 if state.line.nil?
  return state.line.length if state.reveal_all

  ((clock - state.line_at) * REVEAL_SPEED).to_i.clamp(0, state.line.length)
end

def line_fully_revealed?
  revealed_count >= state.line.to_s.length
end

# The first confirm while a line is still typing snaps it to full and is
# consumed; a confirm on a complete line advances the sequence.
def sequence_confirm?
  return false unless super
  return true if line_fully_revealed?

  state.reveal_all = true
  false
end
```

The revealed text is derived from the clock, never stored, so pausing holds the
typewriter mid-word. The scene's `view` then renders
`state.line.to_s[0, revealed_count]` like any other reactive value.

### Scope and control

- **One active sequence per scene.** A cutscene is one linear performance;
  concurrency lives *inside* it via `parallel`. `play_sequence` cancels any
  sequence already in flight.
- `stop_sequence` cancels; `sequence_playing?` queries; `play_sequence` returns
  the sequence as a handle.
- **Input locking is your choice**, not enforced. Gate the scene's own `input` on
  `sequence_playing?` if the player shouldn't be able to walk off mid-scene.
- A sequence is never serialized. A save taken mid-cutscene does not resume it.

The demo's `CutsceneScene` is the living version of all of this: two characters
talking in turns, portraits swapping, idle bobs and gestures as scheduler tweens,
every one of them frozen by a pause because they all key to the same clock.

## See also

- [scenes.md](scenes.md#clocks) — what freezes a clock, and when.
- [cameras.md](cameras.md) — tweening a camera's focal point and zoom.
- [ui.md](ui.md) — reactive views reading the state these drive.
