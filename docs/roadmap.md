# Roadmap — foundation follow-up

An execution plan for the gaps identified in the 2026-07 foundation review, shaped
by the constraints agreed in that discussion. Each work item states its design,
API surface, files touched, test/demo expectations, and acceptance criteria, so
any item can be picked up independently where dependencies allow.

## Guiding constraints

These are decisions, not suggestions — every item below conforms to them:

- **Opt-in, zero-cost-when-unused.** New capabilities must not change the
  behaviour or performance of code that doesn't use them. No enforcement, no
  mandatory registries, no required base classes.
- **drenv is the plugin system.** Core ships contracts and extension points,
  never format- or vendor-specific integrations (Tiled, LDtk, Steam). Those live
  in separate drenv packages, extracted from real use rather than designed up
  front.
- **No ECS in core.** Entity composition belongs to the game (or to draco).
  Core may own update dispatch and culled/ordered drawing — performance
  concerns — but nothing about what an entity *is*.
- **Input management is a standalone library** (SteamInput-backed, base Ruby
  backend, pending). Core's job is to expose one seam it can plug into.
- **Raw DR APIs stay reachable.** Nothing here walls off `outputs`, `inputs`,
  `grid`, or `audio`.

## Sequencing at a glance

| PR | Item | Track | Size | Depends on |
|----|------|-------|------|------------|
| 1 | Game clock (hit-stop aware) + deferred z-ordering | A | S | — |
| 2 | Control-scheme seam | B | XS | — |
| 3 | Hot-path allocation fixes + small bug fixes | E | S | — |
| 4 | Parallax in `Camera#draw` | A | S | PR 1 (shares `draw` changes) |
| 5 | draco compatibility demo (investigation) | D | S | PR 1 (z-ordering makes the demo honest) |
| 6 | Scene lifecycle: hooks + stack + audio policy | C | M | — (design pass first) |
| 7 | Projection helpers + isometric demo | D | M | PR 1 |
| 8 | `TileLayer` contract: remove/invalidate + docs | D | S | — |
| 9 | Entity registry (only if PR 5 shows the need) | D | S | PR 5 |
| 10 | `ui.rb` modularisation split | E | M | best after 1–4 land (avoid rebase churn) |
| 11 | Shared UI render path (Scene/Camera dedup) | E | XS | PR 10 (or standalone before it) |
| 12 | Docs refresh: rewrite `docs/ui.md`, add guides | F | M | after 1–8 stabilise APIs |
| 13 | Input-library compatibility layer | B | ? | PR 2 + the standalone library existing |

Sizes: XS ≤ half day, S ≈ a day, M ≈ a few days. PRs 1–3 are independent and can
land in any order; they are first because everything later builds on or rebases
over them.

---

## Track A — timing & rendering core

### A1. Game clock (PR 1, with A2)

**Problem.** `Kernel.tick_count` advances during `Game#hit_stop`, so any DR
easing (`Easing.ease`, `Numeric#ease`) or hand-rolled timer keyed to it silently
jumps forward when the game thaws — the freeze that should *hold* an animation
skips it instead. The hit-stop demo only avoids this by decrementing counters
inside `update`. This is a bug class Conjuration created by adding hit stop, so
Conjuration owns the fix. It also becomes the foundation for pause semantics in
the scene stack (C1).

**Design.** A frame counter owned by the game and incremented in
`perform_update` — therefore frozen during hit stop, and later frozen for paused
scenes. Not a tween system: DR already provides the easing math; the framework
provides the *correct clock* to key it to.

```ruby
game.clock          # Integer, +1 per un-frozen update
scene.clock         # delegates to game (until C1 gives scenes their own)
```

- Convention documented in README + docs: *key easings and timers to
  `game.clock`, not `Kernel.tick_count`*.
- Migrate the framework's own `tick_count` uses where semantically "game time"
  (none in lib today — the demo scenes' orbit/swing animations migrate as the
  worked example).

**Files.** `lib/conjuration/game.rb`, demo scenes, README.
**Tests.** Clock advances per `tick`; does not advance across a `hit_stop(n)`
window; resumes after.
**Acceptance.** Hit-stop demo's crate flash/debris hold identically when driven
off `clock`-based easing instead of manual counters.

### A2. Deferred z-ordering in `Camera#draw` (PR 1, with A1)

**Problem.** `camera.draw` emits in call order; there is no way to interleave
entities with tiles (player behind a tree, iso depth) without the scene manually
ordering every draw call. This is the most load-bearing missing primitive — iso
(D2) and the draco demo (D1) both sit on it.

**Design.** Fully opt-in keyword; the default path is byte-for-byte today's
behaviour:

```ruby
camera.draw(sprite)                    # immediate emit — unchanged fast path
camera.draw(sprite, z: 3)              # deferred; sorted flush after draw_world
camera.draw(sprite, z: -sprite[:y])    # y-sort is a convention, not a feature
```

- `Camera#draw` pushes `[z, emission_index, primitive]` onto a per-frame buffer
  when `z:` is given; `perform_render` flushes it sorted after
  `scene.draw_world(self)` and before the UI pass.
- The emission index makes the sort stable (mruby `sort_by!` is not), so
  equal-`z` primitives never flicker.
- Semantics documented: unordered draws render **under** all ordered draws
  (they were emitted first). Tiles/backgrounds stay on the fast path; only
  interleaving entities pay for sorting.
- `TileLayer#draw` stays unordered (static content is under everything by
  definition).

**Files.** `lib/conjuration/camera.rb`, `docs/` (new rendering doc or README
section).
**Tests.** No-`z:` path emits immediately in call order; mixed `z:` values emit
sorted after unordered ones; equal `z:` preserves call order; buffer clears
between frames.
**Demo.** Extend the hit-stop or basic-camera scene: knight y-sorted against a
couple of world props.
**Acceptance.** A frame using only the no-`z:` path allocates nothing new and
produces an identical primitives sequence to before the change.

### A3. Parallax (PR 4)

**Problem.** Hand-rolling parallax against the current API is *incorrectly
culled*: `visible?` tests the real `view_rect` while a parallax layer's
effective view is the camera position scaled by the factor — sprites near the
view edge cull wrongly. Doing it right means reimplementing
`to_viewport` + `visible?`, i.e. rebuilding the pipeline the framework exists to
provide. Trivial to do wrong, fiddly to do right → belongs in core.

**Design.**

```ruby
camera.draw(far_hills, parallax: 0.3)          # scrolls at 30% of camera speed
camera.draw(clouds,    parallax: 0.5, z: -100) # composes with z-ordering
```

- `view_rect(parallax: 1.0)`: same computation with `current.x/y` scaled by the
  factor; memoized per factor per frame (a small hash keyed by factor, cleared
  with `@view_rect` in `perform_render`).
- `draw`/`visible?`/`to_viewport` take the factor and cull/transform against the
  derived view. All extra work guarded behind `parallax != 1.0`.
- Zoom applies un-scaled (only translation parallaxes); document this.

**Files.** `lib/conjuration/camera.rb`.
**Tests.** Culling correctness at factor 0.5 near view edges (the exact bug the
DIY version has); factor 1.0 hits the memoized default path; transforms match
`to_viewport` at factor 1.0.
**Demo.** Side-scrolling scene with 2–3 background layers (also the first
side-scroller demo, which the stated goal currently lacks).

---

## Track B — input seam

### B1. Control-scheme seam (PR 2)

**Problem.** The framework reads raw input in exactly three places, all in
`ui_management.rb`: `confirm_pressed?`, `pressing?`, and the
`directional_vector` read in `update_focus_by_navigation`. Each hard-codes
bindings (Enter/A, with Space deliberately excluded). Every additional raw read
makes the future input library a retrofit instead of an adapter — cut the seam
now while it's three methods.

**Design.**

```ruby
class Conjuration::ControlScheme
  def initialize(inputs) = (@inputs = inputs)
  def confirm_down?  = @inputs.keyboard.key_down.enter || @inputs.controller_one.key_down.a
  def confirm_held?  = @inputs.keyboard.key_held.enter || @inputs.controller_one.key_held.a
  def navigation_vector = @inputs.key_down.directional_vector
end

game.control_scheme          # defaults to the above; user- or library-replaceable
```

- `UIManagement` routes its three reads through `game.control_scheme`.
  Behaviour is identical by default.
- The future standalone input library ships its own `ControlScheme`
  implementation — that *is* the compatibility layer (B2), no core changes
  needed beyond this.
- Rule going forward (documented): framework code never reads
  `inputs.keyboard`/`controller` directly; scenes/games still can, freely.

**Files.** new `lib/conjuration/control_scheme.rb`, `lib/conjuration/ui_management.rb`,
`lib/conjuration/game.rb`.
**Tests.** A test double scheme drives UI navigation/confirm end-to-end;
default scheme preserves current bindings.
**Acceptance.** Replacing the scheme requires zero changes to UIManagement.

### B2. Input-library compatibility layer (PR 13 — deferred)

Blocked on the standalone library breaking ground. Expected shape: that library
ships a `Conjuration::ControlScheme` adapter (or core ships a tiny
`conjuration-<lib>` bridge package per the drenv-as-plugin-system principle).
Revisit when the library's API exists; no core work scheduled.

---

## Track C — scene lifecycle

### C1. Lifecycle hooks + scene stack + audio policy (PR 6)

**Problem.** Setup has no symmetric teardown: `change_scene` never notifies the
outgoing scene (nowhere to persist state, stop loops, release targets). There is
no scene stack, so a pause menu over gameplay — the most common scene need in
all three target genres — forces replace-and-rebuild. Two framework policies are
also mislocated: incoming `perform_setup` calls `audio.clear` (silently kills
cross-scene music), and per-name `state` persistence has no place for the game
to decide what survives.

**Design.** (This item warrants a short design doc/PR discussion before code —
it's the one place semantics can paint us into a corner.)

```ruby
change_scene(to: scene)    # replace top (current behaviour + exit hook)
push_scene(scene)          # overlay: previous scene pauses
pop_scene                  # resume what's underneath
```

Hooks, all optional: `on_enter` (after setup), `on_exit` (before removal),
`on_pause` (another scene pushed above), `on_resume` (returned to top).

Stack semantics:

- Only the top scene receives `perform_input` / `perform_update`.
- The stack renders bottom-up by default so overlays composite over gameplay;
  a scene can declare itself opaque (`covers_below? => true`) to skip rendering
  beneath it.
- Paused scenes' clocks freeze (rides on A1: each scene gets `scene.clock`,
  advanced only while active).
- `audio.clear` moves out of `Scene#perform_setup` into an overridable policy —
  default preserved for `change_scene` (documented as a breaking-change
  candidate), never applied on `push_scene`/`pop_scene`.

**Files.** `lib/conjuration/scene_management.rb`, `lib/conjuration/scene.rb`,
`lib/conjuration/game.rb`.
**Tests.** Hook ordering across change/push/pop; input/update isolation to the
top scene; bottom-up render order; clock freeze while paused; focus/navigation
globals reset correctly on push and restored on pop.
**Demo.** Pause menu pushed over the basic-camera scene (Esc to push, Resume
button to pop) — gameplay visibly frozen underneath, UI navigable above.
**Acceptance.** Existing demos run unmodified through `change_scene`.

---

## Track D — world layer

### D1. draco compatibility demo (PR 5 — investigation first)

**Problem/decision.** No ECS in core; draco is the designated external answer
but untested against Conjuration. Before designing any registry, prove the
integration and find the real friction.

**Work.** A demo scene vendoring draco (via drenv): a draco `World` ticked from
`Scene#update`, systems mutating components, rendering via `camera.draw(..., z:)`
from `draw_world`. Document findings in `docs/ecs.md`: what worked, what
required glue, whether iteration cost per camera per frame demands a registry
(D3).

**Acceptance.** A written compatibility statement (works / works-with-glue /
needs-core-changes) and a runnable demo. This PR is allowed to conclude "no
core changes needed."

### D2. Projection helpers + isometric demo (PR 7)

**Problem.** Isometric is in the project's goal statement and nothing supports
it. Key insight from review: iso is **not a camera concern** — the camera
already works in continuous world space. What's iso is grid→world mapping plus
draw order (A2).

**Design.** Pure, stateless math helpers; the camera and TileLayer are
untouched:

```ruby
iso = Conjuration::Projection::Isometric.new(tile_w: 64, tile_h: 32)
iso.to_world(col, row)   # => { x:, y: }   tile sprite anchor in world space
iso.to_grid(x, y)        # => { col:, row: } picking, via camera.to_world(mouse)
```

Plus `Projection::TopDown` (identity) so it reads as a family, not a special
case. Depth is `camera.draw(tile, z: col + row)` — a documented convention
riding on A2, not a feature.

**Files.** new `lib/conjuration/projection.rb`.
**Tests.** Round-trip `to_world`/`to_grid`; picking at tile edges/corners;
`TileLayer` chunking of iso-projected sprites (they're still axis-aligned world
rects — assert the assumption holds).
**Demo.** `IsometricScene`: diamond grid via `TileLayer`, mouse picking
highlight, an entity walking behind/in front of a raised tile (proves A2+D2
together).
**Acceptance.** The demo is genre-proof for "isometric" in the README's goal.

### D3. Entity registry (PR 9 — conditional on D1 findings)

**Scope guard.** Only if the draco demo (or profiling of hand-iterated scenes)
shows per-camera iteration is a real cost. Core owns only update dispatch and
culled, ordered drawing — nothing structural:

```ruby
scene.entities.add(crate)               # anything with #draw(camera) and/or #update(scene),
scene.entities.add(crate, tag: :crates) # or a hash with a rect (drawn via camera.draw)
scene.entities.remove(crate)
scene.entities[:crates]                 # tagged subsets for game logic
```

`perform_update` ticks registered entities; a default `draw_world` drains them
through `camera.draw(entity, z: ...)`. No base class, no components — a draco
world coexists (draco owns composition; the registry owns the render path).

**Acceptance.** Registry-free scenes are untouched; the hit-stop demo rewritten
onto the registry is a net LOC reduction, not an abstraction tax.

### D4. TileLayer contract + extension-package story (PR 8)

**Decision from discussion.** No plugin *system* — drenv already is one. Core's
job is a **documented contract**: a tilemap importer is anything that calls
`TileLayer#add` with world-space primitives. Format packages
(`conjuration-tiled`, `conjuration-ldtk`) live as separate drenv packages,
extracted when they exist; a plugin API, if ever needed, gets extracted from the
second or third real package, not designed up front.

**Core work now.**

- `TileLayer#remove(rect)` / chunk invalidation (drop the chunk's primitives in
  the region, clear its `@rendered` flag) — one destructible wall currently
  means rebuilding the whole layer. Keep it chunk-granular; document that
  dynamic content still belongs in `camera.draw`.
- `docs/tile_layer.md`: the contract (world-space primitives in, chunking
  behaviour, static-content assumption, invalidation), written as the interface
  an importer package targets.

**Tests.** Remove/invalidate re-renders only affected chunks; primitives
spanning chunk borders removed from all of them.

---

## Track E — code health

### E1. Hot-path allocations + small bugs (PR 3)

All findings from the review's performance/quality sections; behaviour-neutral:

- Cache `"camera_#{name}"` in `Camera#initialize` — currently interpolated per
  `outputs` call, i.e. once per drawn primitive (`camera.rb:145`). Same for
  `Scene#state`'s `"scene_#{name}"` key and `scroll_target_path`.
- Memoize `normalized_padding` keyed on the `padding` value (`ui.rb:1198`) —
  fresh hash per `padding_*` call, several calls per child per layout.
- Cache `interactive_nodes` (and `navigation_groups`) with invalidation via
  `clear_structure_cache!` — currently up to ~5 uncached full-tree
  `select`+parent-walk passes per frame per UI root. Visibility changes must
  also invalidate (add to the `visible=` path).
- `Node.delegate` forwards `**kwargs, &block` (`node.rb:4`) — currently drops
  both; `change_scene(to:)` survives only by mruby's kwarg leniency.
- `Vector#magnitude` memoizes while `x`/`y` are mutable (`vector.rb:27`) —
  drop the memo (or invalidate in the writers).
- `FocalPoint#zoom=` re-clamps `x`/`y` (`camera.rb:287`) — zooming out at a
  world edge currently shows out-of-bounds space until the next pan.
- Name the `speed: 1_000_000` snap default (`Camera::SNAP`), and fix the
  "eases toward" comment (it's constant-speed approach, not easing).
- `focused_camera`: define the overlap rule (topmost = last added wins,
  documented) and clear it when the mouse leaves all cameras
  (`camera_management.rb:34`).

**Tests.** Existing suite guards behaviour; add regression tests for the vector
memo, zoom re-clamp, and delegate kwargs.

### E2. `ui.rb` modularisation (PR 10)

**Problem.** 1,223 lines, one file; `UI::Node` (~900 lines) is simultaneously
layout engine, text wrapper, scroll renderer, reconciler target, spatial-nav
engine, primitive collector, and group indexer. Against the project's
clean-modular-code value this is the main debt.

**Design.** Mechanical, behaviour-free split — no API changes, `require` order
preserved in `lib/conjuration.rb`:

```
lib/conjuration/ui/node.rb         tree, props, identity, method_missing bridge
lib/conjuration/ui/layout.rb       justify/align/padding/measure/absolute insets
lib/conjuration/ui/reconciler.rb   Descriptor, build stack, memo, diffing (ui.rb:76–235 + Node's reconcile_*)
lib/conjuration/ui/view.rb         View base + builder-method registration
lib/conjuration/ui/text.rb         wrapping, break modes, measurement
lib/conjuration/ui/scroll.rb       scroll targets, scrollbar, content extent
lib/conjuration/ui/navigation.rb   groups, spatial_navigate, focus queries
```

Layout/text/scroll/navigation become modules included into `Node` (state stays
on the node; the split is by concern, not by object). The reconciler especially
earns its own file — it is the most intricate code in the repo.

Also fold in: derive the `node()` keyword handling from `NODE_KEYWORDS` (today
the list is maintained in four places — `UI.build`, `Node#initialize`,
`Node#node`, `NODE_KEYWORDS` — with nothing enforcing agreement).

**Acceptance.** Test suite passes unchanged; `git log --follow` traces each
extraction; no public constant moves (`Conjuration::UI::Node` et al. keep their
names).

### E3. Shared UI render path (PR 11, or folded into E2)

`Scene#perform_render` and `Camera#perform_render` duplicate ~25 lines verbatim
(render_view / calculate_layout / render_scroll_targets / primitives / focus
indicator / debug overlays — `scene.rb:78–101` vs `camera.rb:216–240`). Extract
`UIManagement#render_ui(outputs)`; both call it. Easiest DRY win in the repo.

### E4. Hash monkey-patch containment (backlog — decide, don't drift)

`extensions/hash.rb` patches core `Hash` with `left/right/top/bottom/center`;
it has already collided with DR internals once (the `:center` fallback). For a
framework loaded into user games, patched `Hash` is a liability (any user hash
with a `:left` key changes meaning). Plan: introduce `Conjuration::Rect.left(h)`
module functions as the internal implementation, make the `Hash` patch a thin
opt-in sugar layer over them, and migrate lib internals to the module calls.
Not scheduled into a PR yet — needs a decision on whether the sugar stays
default-on (DR culture says probably yes).

---

## Track F — documentation

### F1. Docs refresh (PR 12 — after the API dust settles)

`docs/ui.md` documents the pre-reactive API (`UI.build(grid.rect)` +
`state.ui`) and none of the headline features. The conventions currently live
only in code comments and demo source — fatal for a framework whose pitch is
convention.

- Rewrite `docs/ui.md` around the reactive path (`view`, components, `memo`,
  keys, groups, scroll, wrapping, per-state styles), demoting imperative
  `ui.node` to an "escape hatch" section. Lead every example with `view`.
- New: `docs/cameras.md` (world/screen/viewport spaces, culling, z-ordering,
  parallax, shake, multi-camera), `docs/scenes.md` (lifecycle, stack, state,
  clock), `docs/tile_layer.md` (from D4), `docs/ecs.md` (from D1).
- README: update the feature checklist (several shipped items still unchecked),
  add the clock convention, link the docs.
- Explicitly document the object-hash vs node-keyword rule in `node()` — and
  open a design issue on collapsing the split (the runtime warning at
  `ui.rb:206` treats a symptom; since `UI.emit` already partitions kwargs by
  `NODE_KEYWORDS`, an all-keywords call style may be achievable
  backwards-compatibly. Exploration, not committed scope.)

---

## Standing quality bar

Applies to every PR above:

- Tests run under the pinned mruby-patched build (`script/test.sh`) and stay
  DR-`--test`-compatible in signature; new features land with tests in the same
  PR.
- Every new capability gets a demo scene (or extends one) — the demo app is the
  living documentation.
- Hot paths follow the established discipline: no per-frame string
  interpolation or hash allocation in per-primitive code; bracket access over
  `method_missing`; memoize with explicit invalidation.
- Comments explain *why* (constraints, DR quirks), not *what*.
