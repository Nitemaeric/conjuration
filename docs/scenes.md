# Scenes

A scene is one screen of the game: a menu, an overworld, a battle. It owns
cameras, a UI root, a clock, and a bag of state; the game owns a **stack** of
them.

The design record — every corner case with a decided answer — is
[design/scene-lifecycle.md](design/scene-lifecycle.md). This page is the working
guide.

- [A scene is (class, name, state)](#a-scene-is-class-name-state)
- [The tick](#the-tick)
- [Hooks](#hooks)
- [Clocks](#clocks)
- [The stack](#the-stack)
- [Transitions](#transitions)
- [Loading](#loading)
- [Audio](#audio)

## A scene is (class, name, state)

```ruby
change_scene(to: OverworldScene.new(:overworld))
```

A scene is constructed from its class and a name, and its `state` is keyed by
that name **on the game**, not on the instance:

```ruby
def state
  game.state["scene_#{name}"] ||= {}
end
```

So `MenuScene.new(:main)` gets the same state back every time you return to it,
and two scenes sharing a name share state deliberately. The contract this buys
is the one a save file needs: **a scene must be reconstructible from its class,
its name, and its name-keyed state.** Nothing load-bearing may live only in
instance variables.

That is why schedules, sequences, and the per-scene clock are transient by
design — they are render polish and restart from nothing on rehydrate. Save/load
is not implemented yet; §17 of the design doc records what it will need
(stack identities, per-scene state, per-camera focal points), and the decisions
above already satisfy it.

## The tick

`Game#tick` drives one scene — the top of the stack — through four phases. Each
is `respond_to?`-gated, so define only the ones you need.

```ruby
class OverworldScene < Conjuration::Scene
  def setup;  end               # once, on entry
  def input;  end               # read input, mutate intent
  def update; end               # simulate
  def render; end               # screen-space primitives (HUD backdrops, letterboxing)
  def view;   end               # the reactive UI tree — see docs/ui.md
  def draw_world(camera); end   # world-space content, once per camera per frame
end
```

Ordering within a phase, which matters more than it looks:

- **setup** — your `setup` runs *first*, then the UI root builds its view, then
  each camera sets up. That's why `camera.ui.view { … }` is registered inside
  `setup`.
- **input** — each camera's UI pass, then the scene's UI pass (hover, focus,
  confirm, shortcuts), then your `input`. So by the time your code runs, this
  frame's clicks have already fired their node actions.
- **update** — cameras follow and ease, then your `update`, then the active
  sequence, then the scheduler. Sequences tick before schedules so a step's
  freshly-kicked tween moves on the same frame.
- **render** — cameras render (world content, then their own HUD, then the blit
  onto the screen), then your `render`, then the scene's UI. Scene UI therefore
  draws over camera viewports.

`render` is screen space; `draw_world(camera)` is world space and runs once per
camera. See [cameras.md](cameras.md).

## Hooks

Four optional lifecycle hooks, duck-typed like everything else:

| Hook | Fires when |
| --- | --- |
| `on_enter` | after this scene's `setup`, once it is actually live |
| `on_exit` | before this scene is removed (a change, or being popped) |
| `on_pause` | another scene is pushed above this one |
| `on_resume` | this scene becomes the top again after a pop |

`on_pause` fires *before* the paused scene's focus state is snapshotted;
`on_resume` fires *after* it is restored — so a hook always sees focus in the
shape you'd expect. With a transition, `on_enter`/`on_resume` fire when loading
finishes, just before the reveal, so a hook that reads loaded assets always runs
after they exist.

Do stack changes from `input`, `update`, or a node action — not from an `on_*`
hook. Re-entrant stack edits mid-handover are undefined.

Other optional overrides: `covers_below?` (below), `load_tick` /
`loading_view(progress)` (below), `focus_indicator_enabled?`
([ui.md](ui.md#interaction-state)), and `sequence_confirm?`
([time.md](time.md#sequences)).

## Clocks

`scene.clock` counts frames in which *this scene* updated. It starts at 0 on
entry and advances at the top of `perform_update`, which means it freezes
whenever the scene isn't updating: during a hit stop, during a transition, and
for the whole time the scene sits paused underneath a pushed one.

```ruby
angle = clock * 0.02              # holds through a hit stop and while paused
angle = Kernel.tick_count * 0.02  # skips ahead when the freeze ends
```

This is the framework's main value-add on the time axis. Key anything timed to a
clock, and pause correctness comes for free — the alternative is per-object pause
plumbing. `game.clock` is the same counter at game scope, for game-level effects
that shouldn't care which scene is on top.

`game.hit_stop(frames)` freezes input and update for a few frames while rendering
continues — the impact freeze. It is global and short; pair it with
`camera.shake`.

Because scene clocks start at 0 on each entry, key on deltas (`clock -
started_at`) or an angle rather than on an absolute phase. The
[scheduler, animations, and sequences](time.md) all do this for you.

## The stack

Three verbs, all reachable from a scene:

```ruby
change_scene(to: scene, transition: nil)   # drain the whole stack, replace with `scene`
push_scene(scene, transition: nil)         # overlay: the top pauses, `scene` becomes the top
pop_scene(transition: nil)                 # drop the top, resume what's underneath
```

**Input and update reach the top only.** A paused scene gets neither, so its
clock freezes and its simulation holds exactly where it was. It keeps rendering,
though, so the frozen world stays visible behind an overlay.

**Render walks bottom-up**, starting at the highest scene that declares itself
opaque:

```ruby
def covers_below?
  true
end
```

An inventory screen or a house interior that fully hides the world sets this and
reclaims the cost of drawing what's behind it; a translucent overlay leaves it
alone.

**Focus is snapshotted across a push.** The paused scene's focused node, active
navigation group, press/hover, and focus-cursor position are stashed on it, and
the pushed scene starts inert so it can opt into its own group. A pop restores
them, so the selection comes back exactly as it was.

**Popping the last scene is a no-op** — the game must always have a top.
`push_scene` with an instance already on the stack raises.

### The case the stack exists for

Walking into a doorway:

```ruby
# in the overworld
in_door = hero.x > DOOR_X - DOOR_HALF && hero.x < DOOR_X + DOOR_HALF
push_scene(InteriorScene.new(:interior), transition: FadeTransition.new) if in_door && !@was_in_door
@was_in_door = in_door
```

```ruby
class InteriorScene < Conjuration::Scene
  def covers_below?
    true
  end

  def view
    node({ x: 0, y: 0, w: grid.w, h: grid.h }, id: :room, justify: :center, align: :center, group: :interior) do
      node({ w: 160, h: 44, path: :pixel, r: 60, g: 60, b: 70, action: -> { pop_scene(transition: FadeTransition.new) } }, id: :exit) do
        node({ text: "Exit", r: 255, g: 255, b: 255 })
      end
    end
  end
end
```

The overworld is *paused, not torn down*: its walk cycle holds, the hero stays
where he stood, the camera keeps its focal point, and the pop hands it all back
verbatim. That is a different place with different assets — the thing you can't
get from intra-scene state. Note the edge trigger: without it, a pop that lands
the hero back in the doorway immediately re-enters.

### Pause is not a pushed scene

A pause menu is intra-scene state. You stop *updating* the world; rendering
continues, so it stays on screen, frozen:

```ruby
def input;  state[:paused] = !state[:paused] if start_pressed?; end
def update; return if state[:paused]; end
def view;   state[:paused] ? pause_panel : hud; end
```

That is cheaper than a push (no snapshot, no per-scene render-target
namespacing) and it's the pattern to reach for unless the overlay is genuinely a
different scene. Menu navigation still works while the world is frozen: UI
repeat timing runs off `Kernel.tick_count`, not the scene clock, precisely
because menus are what you use while everything else is held.

## Transitions

A transition animates a handover. Pass one to any of the three verbs; pass
nothing and the swap is instant, on exactly the code path that existed before
transitions did.

The framework owns the phase machine and the snapshot; a transition is a small
duck-typed object that only draws:

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

Phases run `:out` → (`:hold`, only while the incoming scene is still loading) →
`:in`. The framework composites the base — a captured snapshot of the outgoing
frame during `:out`/`:hold`, the live incoming stack during `:in` — and the
transition paints over it.

Pass a **fresh instance per launch**; a transition carries no state of its own
here, but reusing one across concurrent handovers isn't a supported shape. The
demo stores factories (`-> { FadeTransition.new }`) in its menu table.

While a handover is in flight, `Game#tick` runs it *instead of* input and update,
so every clock — game and scene — freezes for the duration. The transition
advances on its own counter, so a stray hit stop can't stall it.

Two references ship in the demo: `FadeTransition` and `BoxWipeTransition`
(a Pokémon-style centre-out box). Nothing transition-specific lives in `lib`
beyond the phase driver.

## Loading

A scene that can't set up in one frame implements `load_tick`, called once per
frame after `setup` until it returns `:done`; anything else it returns is read as
0..1 progress. Absent, a scene is instantly ready, so the protocol costs nothing
for scenes that don't need it.

```ruby
def load_tick
  return :done if @build_row >= @dim

  target = @build_row + ROWS_PER_TICK
  target = @dim if target > @dim

  while @build_row < target
    paint_row(@build_row)
    @build_row += 1
  end

  @build_row >= @dim ? :done : @build_row.to_f / @dim
end

def loading_view(progress)
  node({ x: 0, y: 0, w: grid.w, h: grid.h }, id: :loading, justify: :center, align: :center, gap: 10) do
    node({ text: "Loading…", r: 255, g: 255, b: 255 }, id: :label)
    node({ w: 300, h: 12, path: :pixel, r: 40, g: 40, b: 40 }, id: :track, direction: :row) do
      node({ w: 0, h: 12, path: :pixel, r: 200, g: 200, b: 210 }, id: :fill, grow: progress)
      node({ h: 12 }, id: :rest, grow: 1.0 - progress)
    end
  end
end
```

`loading_view` is a **view method** — it builds nodes, like `view`, into a
framework-owned root, and progress arrives as an argument so it stays a pure
function of it. The root reconciles frame to frame like any other, and is
discarded when the handover completes. It is render-only: input and update are
suspended for the whole handover, so nothing in it can take focus.

With a transition, loading hides under the `:hold` phase. Without one, the
framework draws black plus your loading view (or just black). Loading is
cooperative and single-threaded — `load_tick` budgets its own per-frame work.

## Audio

**The lifecycle never touches audio.** No clear on setup, on change, or on
push/pop. Menu music playing on into gameplay is a legitimate thing to want, and
a policy that guessed wrong would be worse than none; the situation matrix
(per-area themes, transition stings, sfx tails, overlay ducking) has to be
enumerated before any API is designed, and the eventual shape is a standalone
audio library rather than scene plumbing.

A game that wants silence on a scene change writes `audio.clear` in its own
`setup`. `audio` is delegated straight through to DragonRuby.

## See also

- [ui.md](ui.md) — `view`, navigation groups, the UI roots a scene owns.
- [cameras.md](cameras.md) — `draw_world`, viewports, world bounds.
- [canvas.md](canvas.md) — declaring a scene's virtual resolution.
- [time.md](time.md) — schedulers, animations, and sequences on the scene clock.
- [design/scene-lifecycle.md](design/scene-lifecycle.md) — the decision record.
