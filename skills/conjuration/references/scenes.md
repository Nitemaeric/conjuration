# Scenes reference

A scene owns cameras, a UI root, a clock, and a bag of state; the game owns a
stack of them. Rationale lives in the framework's `docs/scenes.md` and
`docs/design/scene-lifecycle.md`.

## Identity and state

```ruby
class OverworldScene < Conjuration::Scene; end
OverworldScene.new(:overworld)
```

`Conjuration::Scene#initialize(name, **config)`. `state` is
`game.state["scene_#{name}"] ||= {}` — keyed by name **on the game**, not the
instance. Two scenes sharing a name share state deliberately.

The contract: **a scene must be reconstructible from (class, name, state).**
Nothing load-bearing in instance variables. Schedules, sequences, and the clock
are transient by design and restart from nothing.

`scene.uid` (`object_id`) namespaces render targets, so two stacked scenes that
both add a `:main` camera don't collide.

## Tick phases

`Game#tick` drives the top of the stack. Every hook is `respond_to?`-gated —
define only what you need.

| Method | Space |
| --- | --- |
| `setup` | once, on entry |
| `input` | read input, mutate intent |
| `update` | simulate |
| `render` | screen-space primitives |
| `view` | the reactive UI tree (screen space) |
| `draw_world(camera)` | world space, once per camera per frame |

Ordering inside a phase, which matters:

- **setup** — your `setup` first, then the scene UI root builds its view, then
  each camera sets up. That is why `camera.ui.view { … }` is registered in `setup`.
- **input** — each camera's UI pass, then the scene's UI pass (hover, focus,
  confirm, shortcuts), then your `input`. This frame's clicks have already fired
  their node actions by the time your code runs.
- **update** — cameras follow and ease, then your `update`, then the active
  sequence, then the scheduler. Sequences before schedules, so a step's
  freshly-kicked tween moves on the same frame.
- **render** — cameras render (world, then their HUD, then the blit), then your
  `render`, then the scene UI. Scene UI draws over camera viewports.

## Clocks

`scene.clock` counts frames in which *this scene* updated. It starts at 0 on
entry and advances at the top of `perform_update`, so it freezes during a hit
stop, during a transition, and for the whole time the scene sits paused under a
pushed one. `game.clock` is the same counter at game scope.

Because it restarts at 0 on each entry, key on deltas (`clock - started_at`) or an
angle, never an absolute phase.

`game.hit_stop(frames)` freezes input and update globally while rendering
continues. Pair it with `camera.shake`.

## Hooks

| Hook | Fires |
| --- | --- |
| `on_enter` | after this scene's `setup`, once it is live |
| `on_exit` | before it is removed (a change, or being popped) |
| `on_pause` | another scene is pushed above it |
| `on_resume` | it becomes the top again after a pop |

`on_pause` fires *before* focus is snapshotted, `on_resume` *after* it is
restored. With a transition, `on_enter`/`on_resume` fire when loading finishes,
just before the reveal.

**Do stack changes from `input`, `update`, or a node action — never from an `on_*`
hook.** Re-entrant stack edits mid-handover are undefined.

Other optional overrides: `covers_below?`, `load_tick`, `loading_view(progress)`,
`focus_indicator_enabled?`, `sequence_confirm?`.

## The stack

```ruby
change_scene(to: scene, transition: nil)   # drain the whole stack, replace
push_scene(scene, transition: nil)         # overlay: the top pauses
pop_scene(transition: nil)                 # drop the top, resume underneath
```

- **Input and update reach the top only.** A paused scene's clock freezes and its
  simulation holds. It keeps rendering.
- **Render walks bottom-up** from the highest scene whose `covers_below?` is true.
  Set it on an opaque overlay to reclaim the cost of drawing what's behind.
- **Focus is snapshotted across a push** — focused node, active group, press,
  hover, focus-cursor position — and restored on pop. The pushed scene starts
  inert and must opt into its own group.
- **Popping the last scene is a no-op**; the game must always have a top.
- `push_scene` with an instance already on the stack raises `ArgumentError`.

Use a push when the overlay is genuinely a different place with different assets
and the scene underneath must survive intact (a house interior). Use intra-scene
view state for a pause menu:

```ruby
def input;  state[:paused] = !state[:paused] if start_pressed?; end
def update; return if state[:paused]; end
def view;   state[:paused] ? pause_panel : hud; end
```

Watch for re-entry loops on a proximity push — edge-trigger it:

```ruby
in_door = hero[:x] > DOOR_X - DOOR_HALF && hero[:x] < DOOR_X + DOOR_HALF
push_scene(InteriorScene.new(:interior), transition: FadeTransition.new) if in_door && !@was_in_door
@was_in_door = in_door
```

## Transitions

A transition is a duck-typed object that only draws; the framework owns the phase
machine and the snapshot. Nothing transition-specific lives in `lib` beyond the
phase driver — `FadeTransition` and `BoxWipeTransition` ship in the demo.

```ruby
class FadeTransition
  def initialize(frames: 24)
    @frames = frames
  end

  def out_duration
    @frames
  end

  def in_duration
    @frames
  end

  def draw(outputs, phase:, progress:, snapshot_key:, grid:)
    alpha =
      case phase
      when :out  then (progress * 255).to_i
      when :hold then 255
      when :in   then ((1.0 - progress) * 255).to_i
      end

    outputs.primitives << { x: 0, y: 0, w: grid.w, h: grid.h, path: :pixel, r: 0, g: 0, b: 0, a: alpha }
  end
end
```

Phases: `:out` → (`:hold`, only while the incoming scene is still loading) →
`:in`. The framework composites the base — a snapshot of the outgoing frame during
`:out`/`:hold`, the live incoming stack during `:in`.

**Pass a fresh instance per launch.** Store factories (`-> { FadeTransition.new }`)
if you keep them in a table.

While a handover is in flight `Game#tick` runs it *instead of* input and update,
so every clock freezes. The transition advances on its own counter, so a stray
hit stop can't stall it.

## Loading

`load_tick` is called once per frame after `setup` until it returns `:done`;
anything else is read as 0..1 progress. Absent, a scene is instantly ready.

`loading_view(progress)` is a **view method** — it builds nodes into a
framework-owned root, and progress arrives as an argument so it stays a pure
function of it. Render-only: input and update are suspended for the whole
handover, so nothing in it can take focus. With a transition, loading hides under
the `:hold` phase; without one the framework draws black plus your loading view.

Loading is cooperative and single-threaded — `load_tick` budgets its own per-frame
work.

## Audio

The lifecycle never touches audio: no clear on setup, change, or push/pop. A game
that wants silence on a scene change writes `audio.clear` in its own `setup`.
`audio` is delegated straight through to DragonRuby.

## Delegated to the game

`layout`, `geometry`, `gtk`, `audio`, `change_scene`, `push_scene`, `pop_scene`
(via `Scene`), plus `inputs`, `grid`, `events`, `debug?` (via `Conjuration::Node`).
`scene.outputs` is screen space, routed so a transition can capture it into a
snapshot target.
