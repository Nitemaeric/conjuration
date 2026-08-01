# Time & motion reference

Three pieces on the time axis: a scheduler (timers and tweens), frame animation,
and sequences. All key to the owning scene's `clock`, never `Kernel.tick_count`.
Rationale lives in the framework's `docs/time.md`.

All three are transient — they live on the scene instance, never in save state —
and allocation-free until first used.

## Timers and tweens

Mixed into `Conjuration::Scene` as `Conjuration::Scheduling`:

```ruby
after(ticks) { }                      # once, `ticks` scene-clock ticks from now
every(ticks) { }                      # repeatedly until cancelled; ticks >= 1
tween(target, attr = nil, to: nil, over:, ease: :identity, **attrs)
scheduler                                 # the lazily-allocated Conjuration::Scheduler
```

Each returns a handle answering `#cancel` and `#done?`.

```ruby
tween(camera.target, :zoom, to: 2.0, over: 24, ease: :smooth_stop)
tween(state[:hero], over: 20, x: 400, y: 120)     # several attributes at once
handle = every(90) { spawn_wave }
handle.cancel
```

`target` may be a Hash (read/written by key) or any object with matching
accessors. The final frame writes the exact endpoint rather than an eased
approximation, so nothing drifts.

| Ease | Curve |
| --- | --- |
| `:identity` (default) | linear |
| `:smooth_start` | `t * t` |
| `:smooth_stop` | `1 - (1 - t)²` |
| `:smooth_step` | `t² * (3 - 2t)` |

Any callable taking `t` in 0..1 is accepted as-is (a DragonRuby easing lambda,
your own curve). An unknown Symbol raises `ArgumentError`.

Semantics that bite:

- A timer's boundary is absolute, so a held clock simply never reaches it —
  **no catch-up burst when a pause ends**.
- A schedule created *inside* a callback starts on the next tick, so a
  self-rescheduling timer can't spin.
- `every(0)` raises.

## Animation clips

```ruby
Conjuration::Animation.new(clips_hash)
```

The current frame is *derived* from `clock - started_at`, not incremented per
tick, so a frozen clock holds the frame and resumes mid-clip.

```ruby
@hero = Conjuration::Animation.new(
  walk:  { frames: Array.new(8) { |i| "sprites/hero/walk#{i}.png" }, hold: 5 },
  idle:  { frames: ["sprites/hero/idle.png"] },
  slash: { frames: SLASH_FRAMES, durations: [2, 2, 6, 3], mode: :once }
)
@hero.on(:walk, frame: 4) { play_footstep }
@hero.play(:idle)
```

A clip spec is an Array of frames, a Hash (`frames:`, `hold:` default 1,
`durations:`, `mode:` default `:loop`), or a pre-built `Animation::Clip`.

| Mode | Playback |
| --- | --- |
| `:loop` | 0..n-1, repeat |
| `:once` | 0..n-1, then hold the last frame; `#finished?` reports it |
| `:ping_pong` | 0..n-1 then n-2..1; turnarounds held once per cycle, interior frames entered twice (so their events fire twice) |

Instance API: `play(name)`, `update(clock)`, `path`, `frame_index`, `finished?`,
`on(clip_name, frame:) { }`, `current`, `clock`.

- `play` is idempotent while the same clip is current — call it unconditionally
  every frame. Switching clips re-anchors to frame 0.
- `update(clock)` is the poll step and the **only** thing that fires frame events.
  Events fire for every boundary crossed since the last poll, in playback order,
  so a slow frame that skips three footsteps still plays three. An event on frame
  0 fires when the clip begins.
- `path` is allocation-free; querying it per draw is fine.
- `play` / `on` with an unknown clip name raise `ArgumentError`.

```ruby
def update
  @hero.play(state[:hero][:moving] ? :walk : :idle)
  @hero.update(clock)
end

def draw_world(camera)
  hero = state[:hero]
  camera.draw({ x: hero[:x], y: hero[:y], w: 64, h: 64, path: @hero.path }, z: -hero[:y])
end
```

## Sequences

An ordered queue of steps ticked one at a time against the scene clock — the
cutscene primitive. Mixed into `Conjuration::Scene` as `Conjuration::Sequencing`.

```ruby
play_sequence { }   # cancels any in flight; returns the Sequence as a handle
stop_sequence
sequence_playing?
```

| Step | Completes when |
| --- | --- |
| `act { }` | immediately — runs once on entry |
| `wait(ticks)` | `ticks` scene-clock ticks have passed |
| `wait_until { }` | the predicate first reads true |
| `wait_confirm` (alias `wait_input`) | `sequence_confirm?` reads true |
| `animate(target, attrs, over:, ease: :identity)` | the motion lands |
| `parallel { }` | every sub-step in it has completed |

The DSL raises outside a `play_sequence` block.

**The block is a builder, not a coroutine.** mruby's fibers are unreliable, so it
runs once up front, appending steps, and never suspends. Everything outside a step
block is evaluated at build time:

```ruby
play_sequence do
  act { state[:speaker] = :hero }      # runs when this step is reached
  state[:speaker] = :hero              # runs immediately, when the queue is built
end
```

Put anything that reads or writes live state inside `act`, `wait_until`, or an
`animate` target you mutate.

- A run of consecutive `act`s resolves in a single tick.
- `wait_until`'s predicate is not evaluated until the tick *after* entry, so
  entry-frame state can't satisfy it prematurely.
- `animate` kicks a real scheduler tween on entry and blocks for `over` ticks.
  `parallel` enters all sub-steps on the same frame.
- **One active sequence per scene.** Concurrency lives *inside* one, via
  `parallel`.
- **Input locking is your choice** — gate the scene's own `input` on
  `sequence_playing?`.
- A sequence is never serialized; a save taken mid-cutscene does not resume it.

### `sequence_confirm?`

The predicate behind `wait_confirm`: the framework confirm edge (`:ui_confirm`)
**or** a mouse/touch click, so touch-only players are never stranded. Override it
to redefine what "advance" means — the classic typewriter:

```ruby
def sequence_confirm?
  return false unless super
  return true if line_fully_revealed?

  state[:reveal_all] = true   # first confirm snaps the line to full, and is consumed
  false
end
```

Derive the revealed text from the clock (`((clock - state[:line_at]) *
REVEAL_SPEED).to_i`) rather than storing it, so pausing holds the typewriter
mid-word.
