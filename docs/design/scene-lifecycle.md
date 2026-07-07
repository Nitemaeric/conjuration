# Scene lifecycle: hooks, stack, and audio policy

Design pass for roadmap **C1 (PR 6)**. This is a discussion document, not an
implementation. The roadmap flagged this item as *the one place semantics can
paint us into a corner*, so the bulk of the doc is the corner cases and a
**recommended, decided** answer for each — not a list of open questions.

Nothing here is committed as code. The goal is to agree the contract, then
implement against it.

## Table of contents

- [1. Motivation](#1-motivation)
- [2. Current state of the code](#2-current-state-of-the-code)
- [3. Proposed API](#3-proposed-api)
- [4. Hook ordering](#4-hook-ordering)
- [5. Stack semantics](#5-stack-semantics)
- [6. Corner cases (decided)](#6-corner-cases-decided)
- [7. Audio policy](#7-audio-policy)
- [8. Per-scene clock](#8-per-scene-clock)
- [9. Camera render targets on a stack](#9-camera-render-targets-on-a-stack)
- [10. Migration & compatibility](#10-migration--compatibility)
- [11. Demo (acceptance)](#11-demo-acceptance)
- [12. Test plan](#12-test-plan)
- [13. Open questions for the PR discussion](#13-open-questions-for-the-pr-discussion)
- [14. Divergences from the roadmap starting point](#14-divergences-from-the-roadmap-starting-point)

---

## 1. Motivation

Three concrete gaps, all from the roadmap problem statement:

1. **No symmetric teardown.** `change_scene` swaps `@current_scene` and calls
   the new scene's `perform_setup`. The outgoing scene is never told it is
   leaving — nowhere to persist state, stop a loop, or release a resource.
2. **No stack.** A pause menu over live gameplay — the single most common scene
   need across all three target genres — currently forces replace-and-rebuild:
   you throw the gameplay scene away and reconstruct it on resume.
3. **Two mislocated policies.**
   - `Scene#perform_setup` calls `audio.clear`, so *entering any scene* silently
     kills whatever music was playing. Cross-scene music is impossible today.
   - Per-name `state` persistence (`game.state["scene_#{name}"]`) has no
     documented contract for what survives a transition and what doesn't.

---

## 2. Current state of the code

The lifecycle is a fixed four-phase pass (`perform_setup`, `perform_input`,
`perform_update`, `perform_render`) threaded through a `super` chain. Each mixin
adds behaviour and calls `super`; `BaseLifecycleMethods` is the no-op base that
terminates the chain.

`Game#tick` (`lib/conjuration/game.rb`):

```ruby
def tick
  if @hit_stop && @hit_stop > 0
    @hit_stop -= 1
  else
    perform_input
    perform_update
  end
  perform_render
end
```

`SceneManagement` (`lib/conjuration/scene_management.rb`) is a thin forwarder —
the whole of the current scene contract:

```ruby
def change_scene(to:)
  @current_scene = to
  @current_scene.perform_setup
end

def perform_input;  current_scene.perform_input;  end
def perform_update; current_scene.perform_update; end
def perform_render; current_scene.perform_render; end
```

`Scene#perform_setup` (`lib/conjuration/scene.rb`) is where the two mislocated
policies live:

```ruby
def perform_setup
  audio.clear                          # (1) kills cross-scene music
  UI.focused_node = nil                # (2) focus globals reset here...
  UI.active_navigation_group = nil     #     ...unconditionally, every entry
  UI.focus_cursor[:w] = 0
  setup if respond_to?(:setup)
  super
end
```

Key facts the design has to respect:

- **Focus/navigation is global singleton state**, not per-scene. `UI.focused_node`,
  `UI.active_navigation_group`, `UI.pressed_node`, and `UI.focus_cursor` are
  module-level accessors on `Conjuration::UI`. Every scene *and every camera*
  reads/writes them each frame; the "do I own this node?" guards in
  `UIManagement` exist precisely because the state is shared. A stack that pauses
  a scene must **snapshot and restore** these globals, or a resumed scene loses
  its selection.
- **Cameras belong to the scene.** `CameraManagement` is mixed into `Scene`;
  `scene.cameras` is a per-scene hash. Each camera renders into a DR render
  target **named globally** as `"camera_#{name}"` (`camera.rb:163,285`). Two
  stacked scenes that both add a `:main` camera collide on that name. This is
  the single biggest corner and is handled in §9.
- **`clock` is currently delegated to the game** (`scene.rb:15`,
  `delegate ... :clock, to: :game`). A2/A1 already shipped `game.clock` (frozen
  during hit-stop). C1 gives each scene its *own* clock (§8).
- **`state` is name-keyed:** `game.state["scene_#{name}"] ||= {}`. Two scenes
  sharing a `name` share a state hash. This is load-bearing for §6.5.
- **`hit_stop` is global**, owned by the game, and freezes the entire tick's
  input+update by skipping them (§6.7).

---

## 3. Proposed API

Three verbs on the game (reachable from a scene through the existing
`delegate ... :change_scene` seam; we add `push_scene`/`pop_scene` to it):

```ruby
change_scene(to: scene)   # full transition: replace the ENTIRE stack with `scene`
push_scene(scene)         # overlay: current top pauses, `scene` becomes the new top
pop_scene                 # remove the top, resume whatever is underneath
```

Four **optional** hooks, opt-in exactly like `setup`/`input`/`update`/`render`
today (`respond_to?`-gated, no base class required):

| Hook        | Fires when…                                   | Typical use                              |
| ----------- | --------------------------------------------- | ---------------------------------------- |
| `on_enter`  | after this scene's `setup` completes          | one-time entry FX, analytics             |
| `on_exit`   | before this scene is removed (change or pop)  | persist to `state`, stop loops, cleanup  |
| `on_pause`  | another scene is pushed above this one        | pause music, dim, mark "backgrounded"    |
| `on_resume` | this scene becomes the top again after a pop  | resume music, refresh from `state`       |

Design constraints carried from the roadmap (these are **decisions**, not
suggestions):

- **Opt-in, zero-cost-when-unused.** A game that only ever calls `change_scene`
  with a single scene pays nothing: no stack traversal beyond a one-element
  array, no hook dispatch beyond the `respond_to?` checks it already does.
- **No required base class.** Hooks are duck-typed. `covers_below?` and the
  audio predicate (§7) default via `respond_to?` too, so a plain scene needs to
  define none of them.
- **Raw DR stays reachable.** `outputs`, `inputs`, `audio` are untouched. The
  stack changes *who is called*, never *what a scene can call*.

`current_scene` stays as an alias for "top of stack" so existing reads keep
working (`main.rb` exposes `current_scene`; demos assign `self.current_scene =`
in `Game#setup`).

---

## 4. Hook ordering

The stack is an array, bottom (`[0]`) to top (`[-1]`). "Top" is the active
scene. All three operations are synchronous within the call — no deferral.

### `change_scene(to: B)` — full transition (stack was `[A]`, or `[A, X, Y]`)

```
change_scene(to: B)
│
├─ for each scene in stack, TOP-DOWN:        # Y, X, A  (whole stack drains)
│    └─ scene.on_exit            (if defined) # last chance to persist to `state`
│
├─ stack.clear
│
├─ AUDIO POLICY  (§7):                        # only change_scene consults this
│    audio.clear  UNLESS  B.retain_audio?     # default retain_audio? => false
│
├─ stack.push(B)                              # B is now the sole entry / top
├─ B.perform_setup                            # resets focus globals, runs B.setup,
│                                             # sets up B's cameras + ui
└─ B.on_enter                   (if defined)  # after setup
```

### `push_scene(B)` — overlay (stack `[A]` → `[A, B]`)

```
push_scene(B)
│
├─ raise if B is already in the stack (§6.3)  # same *instance* twice is illegal
│
├─ A.on_pause                   (if defined)  # A may stop music, mark paused
├─ snapshot A's focus globals INTO A          # AFTER on_pause, so hook edits stick
│    (focused_node, active_navigation_group,
│     focus_cursor.dup, pressed_node)
│
│   (NO audio.clear — push never clears audio)
│
├─ stack.push(B)
├─ B.perform_setup                            # resets focus globals to inert;
│                                             # B.setup opts into its own nav group
└─ B.on_enter                   (if defined)
```

### `pop_scene` — resume underneath (stack `[A, B]` → `[A]`)

```
pop_scene
│
├─ return / no-op if stack.size <= 1 (§6.9)   # can't pop the last scene
│
├─ B.on_exit                    (if defined)  # B is being removed
├─ stack.pop                                  # drop B (see §9 re: its render target)
│
│   (NO audio.clear — pop never clears audio)
│
├─ restore A's focus globals FROM A snapshot  # A's selection comes back exactly
└─ A.on_resume                  (if defined)  # AFTER restore, so hook sees real focus
```

**Symmetry rules that make this predictable:**

- `on_pause` fires *before* the snapshot; `on_resume` fires *after* the restore.
  A hook always runs with focus state in the shape the author expects (the paused
  scene's own selection).
- `on_exit` is the single "you are being removed" hook — it fires for both
  `change_scene` (replacement) and `pop_scene` (overlay dismissed). A scene that
  needs to distinguish can check whether it landed back on the stack, but the
  common case (persist to `state`, stop loops) is identical either way.
- `perform_setup` continues to own the focus-globals *reset* (it already does).
  The stack layers *snapshot/restore of the underneath scene* around that; it
  does not move the reset.

---

## 5. Stack semantics

**Input / update — top only.** `Game#tick` drives `perform_input` /
`perform_update` on `stack.last` alone. Paused scenes receive neither, so their
`update` never runs and their `scene.clock` freezes (§8). This is also what keeps
focus sane: only the top scene mutates the global focus singletons.

**Render — bottom-up, with an opaque cutoff.** `perform_render` walks the stack
from the bottom, so overlays composite over gameplay. A scene may declare itself
opaque:

```ruby
def covers_below? = true    # optional; default false via respond_to?
```

Render then starts at the **highest** scene whose `covers_below?` is true (the
scenes below it are skipped entirely — no world draw, no layout, no blit). A pause
menu that wants the frozen gameplay visible behind it leaves `covers_below?`
false (default); a full-screen inventory screen that hides gameplay sets it true
to reclaim the cost.

**Paused scenes still render every frame (v1).** See §6.8 — this is a real cost,
consciously accepted, with `covers_below?` as the escape hatch and a render-target
cache noted as a future optimization.

---

## 6. Corner cases (decided)

Each is a decision with rationale, not an open question. The genuinely
still-open ones are collected in §13.

### 6.1 Focus / navigation globals on push and pop

**Decision.** On `push`, after `on_pause`, snapshot the four global focus fields
into the paused scene instance (`@saved_focus`). The pushed scene's
`perform_setup` then resets them to inert as it does today, giving the overlay a
clean slate to opt into its own navigation group. On `pop`, restore the snapshot
into the globals *before* `on_resume`.

Snapshot payload:

```ruby
@saved_focus = {
  focused_node:            UI.focused_node,
  active_navigation_group: UI.active_navigation_group,
  pressed_node:            UI.pressed_node,
  focus_cursor:            UI.focus_cursor.dup   # dup: it's a mutated singleton hash
}
```

**Rationale.** Focus is global singleton state shared by scene + cameras. Without
snapshot/restore, resuming a gameplay scene would find `focused_node = nil` and
`active_navigation_group = nil` (whatever the overlay left behind, or the reset),
and the player's selection / HUD highlight would vanish. Restoring
`focus_cursor` verbatim makes the highlight **snap back** to where it was rather
than sliding from the overlay's last position. This is the roadmap's explicit
test: *"focus/navigation globals reset correctly on push and restored on pop."*

**Note on `focus_cursor[:w]`.** `perform_setup` sets `focus_cursor[:w] = 0` to
force a snap on scene entry. Restoring the paused scene's saved cursor (with real
`w`) intentionally *skips* that snap on resume, so the highlight reappears in
place. That is the desired feel; documented so it is not "fixed" later by
accident.

### 6.2 Do cameras / render targets belong to the scene or the game?

**Decision.** Cameras remain **scene-owned** (no change to ownership). Their DR
render targets are retained by the engine across frames and are keyed by name; to
survive a stack we **namespace the target name per scene instance** (§9). A paused
scene's render targets are simply not redrawn while it is paused — the world is
frozen, so the retained texture is still correct — but the scene is re-blitted
each frame (or skipped entirely under an opaque scene above it).

**Rationale.** Moving cameras to the game would break `scene.cameras`,
`camera.scene`, virtual-bounds clamping (`FocalPoint` reaches
`camera.scene.virtual_w`), and every demo. Scene ownership is right; the only real
problem is the global target *name*, which §9 fixes.

### 6.3 Can you push the same scene instance twice?

**Decision.** **No — raise `ArgumentError`.** Pushing a *new instance of the same
class* is fine.

**Rationale.** The lifecycle assumes each instance has a single status
(active | paused). The `@saved_focus` snapshot, the frozen clock, and the "which
entry is the paused one" bookkeeping all assume one stack slot per instance. Two
entries pointing at the same object would have the second push clobber the first's
focus snapshot, and `pop` would restore garbage. A one-line identity guard
(`raise if stack.any? { _1.equal?(scene) }`) removes a nasty footgun for a
trivial cost.

### 6.4 `change_scene` while a stack exists — top or whole stack?

**Decision.** **Replaces the entire stack.** `on_exit` fires for every scene
top-down, the stack is cleared, and the target becomes the sole entry.

**Rationale.** `change_scene` means "go to this scene" — a full transition. It is
also the only verb that carries the `audio.clear` policy. A pause menu that calls
`change_scene(to: MainMenu)` must not leave the frozen gameplay scene lurking
underneath the main menu. With no stack (the only case that exists today) "replace
the whole stack" is identical to "replace the one scene", so existing behaviour is
preserved exactly. If a game genuinely wants "swap the top, keep the rest", that
is `pop_scene` then `push_scene`, and we can add a named `replace_top` later
without disturbing this contract.

### 6.5 Per-name `state` and stacked scenes with the same name

**Decision.** `state` stays **name-keyed and intentionally shared** across every
instance/stack-entry with the same `name`. Per-instance transient data lives in
**instance variables**, which already die with the instance. Document the split:

- `state` (`game.state["scene_#{name}"]`) = **the survivor.** Persists across
  transitions and across instances of the same name. This is *"where the game
  decides what survives"* — put it in `state`, or don't and let it die.
- `@ivars` = **transient.** Scoped to the instance; gone when the instance leaves
  the stack. Use `on_exit` to flush anything from an ivar into `state` if it
  should outlive the instance.

**Rationale.** Name-keyed persistence is a feature: returning to `:level_1` keeps
its progress. Pushing a *pause* menu (`:pause`) over *gameplay* (`:gameplay`) is
the normal case and the names differ, so no collision. The pathological case
(pushing `:gameplay` over another `:gameplay`) shares state by name — which is
correct if you think of `state` as "the level's save data" and wrong only if you
expected per-instance isolation, which is exactly what ivars are for. Documenting
the two-tier model resolves the roadmap's "no place for the game to decide what
survives" without adding new machinery.

### 6.6 What does `scene.clock` return for a paused scene?

**Decision.** It returns the tick count **frozen at the moment it was paused**,
resuming from there on `pop`. See §8 for the mechanism.

**Rationale.** `scene.clock` advances only in *that scene's* `perform_update`,
and paused scenes don't get one. This is what makes "paused gameplay visibly
frozen underneath" free: any animation keyed to `scene.clock` (the demos'
orbit/swing already are) holds, exactly like the hit-stop hold, with no per-object
pause plumbing.

### 6.7 `hit_stop` interaction with the stack

**Decision.** `hit_stop` stays **global** and unchanged. It freezes the whole
tick's input+update (`Game#tick`), which means it freezes the active top scene
too; paused scenes are already frozen. A push does **not** clear an in-flight
hit-stop.

**Rationale.** Hit-stop is a whole-game impact freeze; it is short (≤ ~12 frames /
~200 ms) and self-decaying. Making it per-scene would be over-engineering for C1.
One consequence to document: if you push a pause menu on the exact frame a
hit-stop is mid-flight, the menu's input is also frozen for the few remaining
freeze frames before it becomes responsive. That is acceptable and barely
perceptible; per-scene freeze is explicitly out of scope. (Because `scene.clock`
advances inside `perform_update`, and hit-stop skips `perform_update`, the active
scene's clock also freezes during a hit-stop — consistent with today.)

### 6.8 Does `perform_render` run every frame for paused scenes, or is it cached?

**Decision.** **v1: paused visible scenes re-run `perform_render` every frame.**
Opaque overlays (`covers_below? => true`) skip the scenes beneath them entirely.
A render-target snapshot cache is a **documented future optimization**, not v1.

**Rationale.** DR clears the top-level `outputs.primitives` every tick, but
*retains render targets*. A paused scene's world content lives in retained camera
targets (cheap to keep), but its **screen-space** HUD/background primitives are
emitted straight into `game.outputs.primitives` each frame (e.g.
`HitStopScene#render`, `MenuScene#render`) and would vanish if we skipped the
render. So a correct cache has to split `perform_render` into *produce* (draw
world into targets, run layout — skippable while frozen) and *present* (re-emit
screen primitives + blit targets — required every frame). That split is a real
change and a real risk; correctness-first says re-render for v1. The cost is
bounded: `update` is gone (the expensive simulation doesn't run), and any game
that can't afford a frozen full-scene render sets `covers_below?` on its overlay.
The optimization is worth revisiting only if profiling on a target-genre game
shows the frozen render dominating a frame.

### 6.9 Popping the last scene

**Decision.** `pop_scene` on a single-element stack is a **no-op** (return early;
optionally warn in debug). The game must always have a top scene.

**Rationale.** There is no "underneath" to resume, and a nil top would crash the
next `tick`. A game ending a level should `change_scene` to a results/menu scene,
not pop into the void.

### 6.10 `push_scene` / `pop_scene` during a hook

**Decision.** Nested stack mutations from within a hook are **not supported in
v1**; behaviour is "last writer wins" and undefined ordering. Document: do stack
transitions from `input`/`update`/actions, not from `on_*` hooks.

**Rationale.** Re-entrant stack edits mid-transition (e.g. `pop` inside an
`on_resume`) invite exactly the "paint into a corner" the roadmap warns about.
Forbidding it in the doc costs nothing and can be relaxed later (e.g. by queuing
transitions to the end of the tick) if a real need appears.

---

## 7. Audio policy

**Move `audio.clear` out of `Scene#perform_setup`** and into a policy consulted
**only by `change_scene`**:

```ruby
# in change_scene, before the incoming scene's perform_setup:
audio.clear unless to.retain_audio?

# Scene, overridable, default false via respond_to?:
def retain_audio? = false     # opt in to keep the previous scene's audio playing
```

- `change_scene`: clears audio **by default** (preserves today's behaviour), so a
  scene that wants cross-scene music sets `retain_audio? => true`.
- `push_scene` / `pop_scene`: **never** clear audio. Music started under gameplay
  keeps playing under the pause menu, which is the whole point.

**Why on the incoming scene (not the game).** The scene being *entered* is the one
that knows whether it wants the previous soundscape to survive (a results screen
keeping the level's music vs. a menu wanting silence). A game that wants a blanket
policy can still override `change_scene` or set a shared module flag; the scene
predicate is the low-ceremony default. This is a **breaking-change candidate** and
must be called out in the changelog: any game relying on "entering a scene silences
everything" is unaffected (that is still the default), but the *mechanism* moved,
so a game that subclassed and called `super` in `perform_setup` for the clear will
need to know it no longer happens there.

**Demo check.** `MenuScene#setup` starts `bgm`; today every `change_scene` into a
demo clears audio via the new scene's `perform_setup`. Under the new default
(`change_scene` clears unless `retain_audio?`), the bgm still stops when you leave
the menu. Behaviour preserved, demos unmodified.

---

## 8. Per-scene clock

Today `Scene` delegates `:clock` to the game. C1 gives each scene its own:

```ruby
# Scene: remove :clock from the delegate list; own it instead.
attr_reader :clock            # 0 at setup

def perform_update
  @clock += 1                 # advances ONLY while this scene is the active top
  super
  update if respond_to?(:update)
end
```

- A paused scene gets no `perform_update`, so its `@clock` freezes (§6.6).
- The active scene's `@clock` also freezes during a `hit_stop`, because
  `Game#tick` skips `perform_update` entirely during the freeze — same mechanism
  as `game.clock`.
- `game.clock` stays as the global game-time counter for game-level effects.

**Compatibility.** The demos call bare `clock` inside scene methods
(`basic_camera_scene`, `hit_stop_scene`). With `:clock` removed from the delegate
and defined as a scene reader, `clock` now resolves to `scene.clock`. For a single
always-top scene (every current demo, entered via `change_scene`), `scene.clock`
advances one-per-active-update — identical progression to `game.clock`. The orbit
and swing animations behave exactly as before. This is the acceptance criterion
for A1's worked example and it still holds.

**Seam note.** Removing `:clock` from `Scene`'s `delegate` list is the only
line in `scene.rb:15` that changes; `layout`, `geometry`, `gtk`, `audio`,
`change_scene` stay delegated (and `push_scene`/`pop_scene` get added).

---

## 9. Camera render targets on a stack

**This is the sharpest corner.** Cameras render into DR targets named globally as
`"camera_#{name}"` — set in two places in `camera.rb`:

```ruby
def outputs
  game.outputs["camera_#{name}"]          # line 163
end
# ...and the blit:
game.outputs.primitives << { x:, y:, w:, h:, path: "camera_#{name}" }  # line 285
```

The moment two stacked scenes each add a camera named `:main`, they **share one
render target**. The overlay's camera would draw into the same texture the paused
gameplay camera is being blitted from — visual corruption, and no error.

**Decision.** Namespace the target name by a **per-scene-instance token**. Assign
each scene a uid at construction (the object id is enough, or a small incrementing
counter on the game) and build the target name from it:

```ruby
# camera.rb, both sites:
"camera_#{scene.uid}_#{name}"
```

Both the write (`outputs`) and the blit (`path:`) change together, so the string
is never referenced across the seam — and a grep confirms **nothing outside
`camera.rb` references the literal** (`camera_label` in the demos is an unrelated
UI id). Existing single-scene demos are unaffected: the target name changes, but
only `camera.rb` reads it.

**Paused scene targets.** DR retains render targets across frames, so a paused
scene's world texture stays valid (frozen world → still-correct pixels). We skip
*redrawing* it (no `perform_update`, and under §6.8 v1 we still re-run render;
under a future cache we would skip the produce step) and simply re-blit — or, if
an opaque scene sits above it, skip it entirely.

**Popped scene targets — known limitation.** DR does not free a render target when
we drop the scene; the texture lingers in memory keyed by its (now unused) name.
For the target use cases (a handful of scenes, uids that repeat if we reuse a
counter) this is negligible. Documented so it is a known quantity, not a surprise:
if a game churns thousands of uniquely-named scene instances, target memory grows.
A uid *pool*/reuse strategy is a future mitigation, not v1.

---

## 10. Migration & compatibility

**Acceptance criterion (roadmap):** *existing demos run unmodified through
`change_scene`.* This holds because:

1. **`change_scene` semantics are preserved.** With no stack, "replace the whole
   stack" (§6.4) == "replace the one scene". The added `on_exit` pass is
   `respond_to?`-gated and no demo defines it, so it is a no-op.
2. **Audio behaviour is preserved.** The `audio.clear` *moves* from
   `perform_setup` to `change_scene`, but the default (`retain_audio? => false`)
   still clears on every transition, so the menu bgm still stops on entering a
   demo (§7). No demo overrides the predicate.
3. **Clock behaviour is preserved.** `scene.clock` for a single always-top scene
   progresses identically to the old `game.clock` delegation (§8). The demos'
   `clock`-keyed orbit/swing are unchanged.
4. **Camera target rename is internal.** Only `camera.rb` reads the target name
   (§9); demos never reference the literal, so namespacing is transparent.
5. **Focus reset is unchanged for the no-stack path.** `perform_setup` still
   resets the focus globals on entry; snapshot/restore only engages on
   `push`/`pop`, which no current demo calls.

**Breaking-change candidate to flag in the changelog:** the *location* of
`audio.clear` moved. A game that relied on `super` inside its own
`perform_setup` to clear audio (rather than the default `change_scene` path) will
find the clear no longer happens in setup. The observable default is identical;
only the extension point moved.

No demo edits are required to land C1. The pause-menu demo (§11) is *new* code
that exercises `push`/`pop`; it does not modify existing scenes.

---

## 11. Demo (acceptance)

New demo, per the roadmap: a **pause menu pushed over the basic-camera scene**.

- `Esc` in `BasicCameraScene#input` → `push_scene(PauseScene.new(:pause))`.
- `PauseScene` is a translucent overlay (screen-space `outputs`, likely **no
  camera** — sidesteps §9 entirely for the demo) with a "Resume" button whose
  action calls `pop_scene`, and a "Quit to menu" button calling
  `change_scene(to: MenuScene.new(:main))`.
- `PauseScene` leaves `covers_below?` false so the frozen gameplay shows through,
  dimmed by a full-screen translucent pixel.
- **Observable acceptance:**
  - The orbiting follow-target and camera **visibly freeze** while paused
    (`scene.clock` frozen — no new plumbing).
  - The pause menu is keyboard/pad navigable above the frozen scene
    (`activate_navigation` in `PauseScene#setup`; gameplay's nav group is
    snapshotted and restored on resume).
  - Resume returns to gameplay with the camera HUD's selection intact.
  - Music (if any) keeps playing across push/pop (audio never cleared), and is
    cleared only by "Quit to menu" (`change_scene`).

---

## 12. Test plan

Mirrors the roadmap's test list, expressed against the doubles in
`test/support/`:

1. **Hook ordering across change/push/pop.** Record hook calls on stub scenes;
   assert the exact sequences in §4 (including top-down `on_exit` for a
   multi-element `change_scene`).
2. **Input/update isolation.** Only `stack.last` receives `perform_input` /
   `perform_update`; paused scenes receive neither.
3. **Bottom-up render order + opaque cutoff.** With `[A, B]` and default
   `covers_below?`, both render bottom-up; with `B.covers_below? => true`, `A` is
   skipped.
4. **Clock freeze while paused.** `A.clock` stops advancing after `push`, resumes
   after `pop`; unaffected scene-below stays frozen; hit-stop freezes the active
   scene's clock too.
5. **Focus globals reset on push, restored on pop.** Snapshot/restore round-trips
   `focused_node` / `active_navigation_group` / `focus_cursor` / `pressed_node`.
6. **Audio policy.** `change_scene` clears unless `retain_audio?`; `push`/`pop`
   never clear.
7. **Guards.** Pushing the same instance twice raises; popping the last scene is a
   no-op.
8. **Camera target namespacing.** Two scenes with same-named cameras resolve to
   distinct target names.

`script/test.sh` currently passes 133/133; C1 adds a `scene_stack_test.rb`
alongside these.

---

## 13. Open questions for the PR discussion

The decisions above are proposed answers. These are the few where a reviewer's
call could legitimately flip the recommendation:

1. **Audio predicate home.** `Scene#retain_audio?` (incoming scene decides,
   proposed) vs. a game-level policy object. Incoming-scene is lower ceremony;
   a game-level hook is more centralized. (§7)
2. **`covers_below?` naming.** `covers_below?` vs. `opaque?` vs. `blocks_render?`.
   Purely a naming call; semantics are fixed. (§5)
3. **`on_exit` on pop vs. a distinct `on_dismiss`.** Proposed: one `on_exit` for
   both removal paths. A reviewer may want to distinguish "changed away forever"
   from "popped, might be re-pushed". (§4)
4. **Render caching in v1.** Proposed: re-render frozen scenes, ship the cache
   later. A reviewer targeting a heavy scene may want the produce/present split in
   v1. (§6.8)
5. **Scene uid source.** `object_id` vs. an explicit incrementing counter with
   reuse. Affects only the popped-target memory note. (§9)

---

## 14. Divergences from the roadmap starting point

The roadmap's starting-point design is adopted almost wholesale. Three
clarifications/divergences worth calling out explicitly:

1. **`change_scene` replaces the *whole* stack, not just the top.** The roadmap
   comment says "replace top (current behaviour + exit hook)". Interpreted
   literally that would leave a paused scene underneath after a full transition.
   The recommendation makes `change_scene` drain the entire stack (§6.4);
   "replace top while keeping the rest" is `pop`+`push` or a future `replace_top`.
   For the only case that exists today (single scene) the two readings are
   identical, so this is a forward-looking clarification, not a behaviour change.
2. **Render caching is explicitly *not* in v1.** The roadmap poses "every frame
   vs. cached" as an open question; this doc decides **every frame for v1** with
   `covers_below?` as the cost escape hatch, because DR clears screen-space
   primitives each tick and a correct cache needs a produce/present split that is
   its own change (§6.8).
3. **A concrete render-target namespacing requirement is added.** The roadmap
   lists cameras/targets among the hard questions but doesn't prescribe a fix.
   This doc commits to per-scene-uid target names in `camera.rb` (§9) as a
   prerequisite for `push_scene` — without it, same-named cameras on a stack
   corrupt each other silently. Two smaller guards are also made explicit that the
   roadmap left implied: **same-instance double-push raises** (§6.3) and
   **popping the last scene is a no-op** (§6.9).
