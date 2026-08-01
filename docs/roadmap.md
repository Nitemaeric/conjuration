# Roadmap v2 — time, introspection, and consolidation

The successor to the 2026-07 foundation-review roadmap. Round one is complete
(outcomes below); this round was scoped by an engine-comparison gap analysis
(what Godot/Unity/GameMaker-class engines provide that DR + Conjuration don't)
followed by an item-by-item scope review. Most candidates were deliberately
deferred — the decisions and their reasons are recorded here so they stay
decisions rather than drift.

## Guiding constraints

Round one's constraints stand (opt-in and zero-cost-when-unused; drenv is the
plugin system; no ECS in core; raw DR APIs stay reachable). This round adds
three that emerged from practice:

- **The admission test.** If a feature is hand-rollable on existing seams with
  no hidden correctness trap, it becomes documentation, not API. Parallax
  earned core status because the DIY version mis-culled; a camera deadzone is
  eight honest lines on `look_at` + `speed` and earns a recipe instead.
- **Layout, not widgets.** The UI system's job is layout, reconciliation, and
  navigation. Interactive components (text inputs, sliders, themes) are
  external libraries or game code — `dr-input` already exists for text entry,
  and the demo's ButtonView/PromptView model the pattern.
- **Standalone libraries over core modules.** Cross-cutting capabilities take
  the dragon_input shape: a library that depends on nothing, which Conjuration
  may depend on or expose a seam for. (This is the designated shape for audio,
  when a real game demands it.)

## Round-one outcomes

| v1 item | Outcome |
|---|---|
| 1. Game clock + z-ordering | Merged (#17) |
| 2+13. Input seam + library layer | Merged as one (#18): action-query contract, dragon_input hard dep, injection, bootstrap |
| 3. Hot-path fixes | Merged (#20) |
| 4. Parallax | Merged (#21), + Kenney art, animated hero |
| 5. draco investigation | Merged (#23): works-with-glue; conventions in docs/ecs.md |
| 6. Scene lifecycle | PR #19: hooks, stack, per-scene clocks, **transitions**, **loading protocol**, audio policy, save-state constraints |
| 7. Projection + isometric | Merged (#24): elevation, Sketch Desert art, feet-gated unit depth |
| 8. TileLayer remove/invalidate | Merged (#22) |
| 9. Entity registry | **Killed** — draco benchmark showed a 3-line scene-level cache absorbs the cost |
| 10/11. ui.rb split + shared render path | Carried into this round (below) |
| 12. Docs refresh | Carried into this round (below) |

Unplanned work that also landed: controller parity (`shortcut:` + stick
navigation, #32), hover/focus split + focus polish (#33), beam-tier spatial
navigation (#30), fully reactive demos (zero imperative `ui.node` call sites),
two-column menu (#27), navigation-conflict fixes (#25), justify hardening
(#28/#31).

## Sequencing at a glance

| PR | Item | Track | Size | Depends on | Status |
|----|------|-------|------|------------|--------|
| 1 | Tweens + timers on scene clocks | G | S | — | Shipped |
| 2 | Frame animation + frame events | G | M | — | Shipped |
| 3 | Sequences (cutscene primitive) | G | M | PR 1 | Shipped |
| 4 | `ui.rb` modularisation + shared render path | E | M | best while UI is quiet | Shipped |
| 5 | Camera + scene/stack debug overlays | H | S | — | Shipped |
| 6 | UI tree inspector | H | S | PR 4 (navigates the split files) | Shipped |
| 7 | Draw-order inspector | H | S | — | Shipped |
| 8 | Docs refresh (ui/cameras/scenes + recipes) | F | M | after PRs 1–3 settle the new APIs | Shipped |

PRs 1, 2, 4, 5, 7 were the independent starting points. Every PR shipped with
tests under `script/test.sh` and a demo touchpoint; the standing quality bar from
round one applied unchanged (hot-path discipline, strict comment policy).

**Round two is complete.** What remains below the tracks is the deferred list —
decisions, not backlog.

---

## Track G — time & motion

The structural foundations (scenes, cameras, UI, input) are strong; the *time*
axis is bare. Every piece keys to `scene.clock`, so pause, hit-stop, and the
scene stack freeze animation correctly for free — that clock correctness is
the framework's value-add over hand-rolled `tick_count` math.

### G1. Tweens + timers (PR 1)

`after(ticks) { }`, `every(ticks) { }`, and
`tween(target, attr, to:, over:, ease: :smooth_stop)` applying DR's existing
easing math over the owning scene's clock, cancelled/paused with the scene.
Not a new easing library — a scheduler for the one DR already has. The
transition machinery (#19) wants this internally; UI micro-animation and
camera moves consume it next. Demo: replace at least one hand-rolled counter
(hit-stop flash timing is the natural candidate).

**As shipped** (`lib/conjuration/scheduler.rb`). `after`/`every`/`tween` on the
scene's own clock, with four eases carried inline (`:identity`,
`:smooth_start`, `:smooth_stop`, `:smooth_step`) and any callable accepted as a
custom curve. Timer boundaries are absolute, so a frozen clock never produces a
catch-up burst; a tween's last frame writes the exact endpoint. Transient and
lazily allocated, like sequences. Documented in `docs/time.md`.

### G2. Frame animation + events (PR 2)

Named clips over frame lists: loop / once / ping-pong, per-frame durations,
and **frame events** (`on_frame(3) { footstep }` — the feature that separates
an animation system from a modulo). Owned per entity, ticked by the scene.
Demo: the parallax hero's hand-rolled `clock.idiv(5) % 8` walk cycle migrates;
the iso knight gains a walk (its art permitting) or a bob.

**As shipped** (`lib/conjuration/animation.rb`). Named clips with `:loop`,
`:once`, and `:ping_pong` modes, per-frame durations, and `on(clip, frame:)`
events that fire for every boundary crossed since the last poll (so a slow frame
plays each in sequence). The frame is *derived* from `clock - started_at` rather
than incremented, so a freeze holds it and resumes mid-clip. Players are plain
objects owned by game code — no registry. Documented in `docs/time.md`.

### G3. Sequences (PR 3)

Chained steps with waits — `sequence { move(npc, to:); pan(camera, to:);
say("..."); wait_for_confirm }` — the minimal scripted-events primitive a
Pokémon-like needs. Composes G1's tweens/timers; input-locking during a
sequence is the scene's choice, not enforced.

**Demo (the G3 acceptance): a dialogue cutscene.** Two characters on screen
talking in turns; a large portrait face shows whoever is speaking (swapping
sides/highlight as turns pass); dialogue advances on confirm; the character
models move subtly throughout (idle bob, a step toward each other, a gesture
on emphasis — all G1 tweens keyed to the scene clock, so pausing freezes the
whole performance). Needs a second character + face art (Kenney Toon
Characters ships per-part PNGs including heads — same CC0 sourcing as the
parallax hero). This one demo exercises sequences, tweens, portrait/UI
composition, and confirm-gated waits together — if it reads like a scene from
a real game, Track G is done.

**As shipped** (`lib/conjuration/sequence.rb`). A scene-owned `play_sequence do
… end` builds an ordered queue of steps, ticked one at a time against the scene
clock (so pause/hit-stop/stack freeze the whole performance and resume
mid-step). Coroutine-free — mruby fibers are unreliable, so the block runs once
as a *builder*; it never suspends. Steps:

- `act { … }` — runs once, completes immediately. A run of `act`s resolves in a
  single tick, so synchronous state changes chain without burning frames.
- `wait(ticks)` / `wait_until { predicate }` — block on the clock or a
  predicate (checked from the tick after entry, so entry-frame state can't
  satisfy it prematurely).
- `wait_confirm` (alias `wait_input`) — advances on the framework confirm edge
  (`input_source.just_pressed?(ui_pad, :ui_confirm)`) **or** a mouse/touch
  click, mirroring the tappable Press-Start prompt (#49) so touch-only players
  are never stranded. Override `sequence_confirm?` to redefine "advance".
- `animate(target, attrs, over:, ease:)` — kicks a real G1 `tween` and blocks
  for `over` ticks, so the sequence waits for the motion.
- `parallel { … }` — runs its sub-steps concurrently, completing only when all
  do (simultaneous character moves).

Design calls: **one active sequence per scene** (a cutscene is one linear
performance; concurrency lives *inside* via `parallel`, and `play_sequence`
cancels any in flight). **Input-locking is the scene's choice**, not enforced —
gate the scene's own `input` on `sequence_playing?`. **Zero-cost when unused**:
no Sequence is allocated until `play_sequence`, the tick site is a bare nil
check, and a finished sequence is released. **Transient**, like schedules: a
sequence lives on the scene instance, never in save state
(`docs/design/scene-lifecycle.md` §17); a mid-play sequence is not serialized.
Cancel with `stop_sequence` or the handle `play_sequence` returns.

The `CutsceneScene` demo is the living doc: `say`/portrait swap/movement are all
steps in one sequence, every motion a scene-clock tween.

Particles were considered and left as a **demo convention** — first game that
wants them hand-rolls a pooled emitter on G1/G2 primitives; extraction to core
needs recurrence, per the draco rule.

## Track H — introspection

Five rounds of isometric-knight forensics were done with hand-built dump
tooling; the lifecycle demo grew an ad-hoc hook feed. These are the debug
interfaces earning core status — all behind `debug?`, zero cost when off.

### H1. Camera + scene overlays (PR 5)

Per camera: view rect, focal current/target, follow state, world bounds.
Per game: scene stack with per-scene clocks, transition/loading phase, hook
trace. The "why is the camera doing that / what state is the stack in" panels.

**As shipped.** `Camera#render_debug_overlay` draws the cull frame, focal
current/target crosshairs (linked when they differ), the follow marker, world
bounds, and a per-camera readout into the camera's own viewport;
`Game#render_game_debug_panel` draws the scene/clock/hit-stop/camera/UI-focus
panel, draggable and corner-cyclable. Both guard on `debug?` at the call site
*and* internally, so nothing is built when it's off.

### H2. UI tree inspector (PR 6)

The existing debug rects grown up: node bounds/ids, navigation groups,
focus/hover/pressed state highlighting. The hover/focus work would have been
half the effort with this.

**As shipped** (`lib/conjuration/ui/inspector.rb`). Bounds, ids, and overflow
badges are interleaved into the *primitive stream* via `UI.debug_decorator`
rather than collected into `outputs.debug`, so a foreground panel occludes them
exactly as it occludes the nodes themselves and a scroll pane's decorations clip
with its content. Hover gives a DevTools box model (content / padding strips /
gap strips) plus a readout with per-axis size provenance
(explicit/grow/auto/assigned, max-clamped); unresolved geometry is flagged in
`outputs.debug` so an error marker can't be buried. Hit resolution reuses core's
`deepest_hit`, so the readout can't disagree with where clicks land.

### H3. Draw-order inspector (PR 7)

The iso dump promoted to core: freeze + dump a camera's deferred draw buffer
(z bands, emission order, culling verdicts) to a file, with the analyzer
shipped as a framework tool rather than a demo script.

**As shipped.** `Camera#dump_draw_order` serialises the buffer in post-sort
flush order through `each_ordered_draw` — the same code path the real flush uses,
so a dump can't drift from what DragonRuby composites. The `dbg:` tag convention
rides free on any primitive; `tools/analyze_draw_order.rb` reads the dump back.

## Track E — consolidation (carried from v1)

### E2+E3. `ui.rb` modularisation + shared render path (PR 4)

The file has only grown since v1 flagged it (hover, shortcuts, beam
navigation now live there). Mechanical, behaviour-free split into
node/layout/reconciler/view/text/scroll/navigation, `require` order preserved;
fold in the `NODE_KEYWORDS` four-places dedup and extract the ~25 duplicated
lines of Scene/Camera UI rendering into `UIManagement#render_ui`. Suite passes
unchanged; no public constant moves.

**As shipped.** `lib/conjuration/ui/` holds reconciler, navigation, layout, text,
scroll, view, node, and inspector; `lib/conjuration/ui.rb` is the require list.
`NODE_KEYWORDS` has one home, and `UIManagement#render_ui` is the single
scene/camera render path.

## Track F — docs refresh (PR 8)

- Rewrite `docs/ui.md` around the reactive path — now the *only* path in the
  demos — demoting imperative `ui.node` to the escape-hatch section.
- New `docs/cameras.md` (spaces, culling, z-ordering, parallax, shake,
  multi-camera) including the **camera-feel recipe** (deadzone + lookahead on
  `look_at` + `speed` — the documented answer to a deliberate non-feature).
- New `docs/scenes.md`: lifecycle, stack, transitions, loading, clocks,
  the intra-scene pause pattern, save-state contract.
- README checklist truth-up.

**As shipped.** `docs/ui.md` rewritten (reactive path, layout and sizing,
overflow, navigation, the inspector, imperative escape hatch); new
`docs/scenes.md`, `docs/cameras.md`, and `docs/input.md`; and a fourth page the
plan didn't anticipate — `docs/time.md`, since Track G landed three APIs
(scheduler, animation, sequences) that share one rationale and belonged
together rather than scattered across the other pages. README checklist and docs
index trued up.

---

## Deferred — decisions, with reasons

- **Audio**: the lifecycle deliberately never touches audio (no clears, no
  policy hooks) — the situation matrix (persist-across-change, per-area themes,
  transition stings, sfx tails, overlay ducking) must be enumerated before any
  structure is designed. When a real game forces it, the shape is a standalone
  `dragon_audio` (buses, crossfade, sfx pooling), not scene plumbing.
- **Camera feel (deadzone/lookahead/regions)**: fails the admission test —
  hand-rollable on existing seams. Ships as the docs recipe (Track F).
- **World tooling** (Tiled importer, trigger zones, darkness/post hook):
  deferred until a concrete game hits the wall. The D4 importer contract
  (`docs/tile_layer.md`) stands ready for `conjuration-tiled` when it comes.
- **UI widgets** (text input, slider, theme, rich text): external-library
  territory per the layout-not-widgets principle (`dr-input` exists).
- **Utilities** (seeded RNG streams, transform attachments): no demo evidence
  yet; both hand-rollable.
- **Hash monkey-patch containment** (v1 E4): still on the backlog awaiting the
  default-on/off decision — deliberately not scheduled.
- **Transition v2** (cross-fade / slide-in needing both scenes live, nested
  transitions, paused-scene render caching): revisit with evidence, per the
  gaps list in #19.
- **Platform ceilings**, named so nobody mistakes them for framework gaps:
  no user shaders in standard DR (post effects = render-target composition
  only), single-threaded loading (`load_tick` is cooperative), no networking
  ambitions.

Pending outside this roadmap: save/load state implementation (tracked task;
constraints in `docs/design/scene-lifecycle.md` §17), dragon_input `key_glyph`
PR upstream, dr-frame-timer upstream fix (overlay currently debug-gated).
