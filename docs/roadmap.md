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

| PR | Item | Track | Size | Depends on |
|----|------|-------|------|------------|
| 1 | Tweens + timers on scene clocks | G | S | — |
| 2 | Frame animation + frame events | G | M | — |
| 3 | Sequences (cutscene primitive) | G | M | PR 1 |
| 4 | `ui.rb` modularisation + shared render path | E | M | best while UI is quiet |
| 5 | Camera + scene/stack debug overlays | H | S | — |
| 6 | UI tree inspector | H | S | PR 4 (navigates the split files) |
| 7 | Draw-order inspector | H | S | — |
| 8 | Docs refresh (ui/cameras/scenes + recipes) | F | M | after PRs 1–3 settle the new APIs |

PRs 1, 2, 4, 5, 7 are independent starting points. Every PR ships with tests
under `script/test.sh` and a demo touchpoint; the standing quality bar from
round one applies unchanged (hot-path discipline, strict comment policy).

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

### G2. Frame animation + events (PR 2)

Named clips over frame lists: loop / once / ping-pong, per-frame durations,
and **frame events** (`on_frame(3) { footstep }` — the feature that separates
an animation system from a modulo). Owned per entity, ticked by the scene.
Demo: the parallax hero's hand-rolled `clock.idiv(5) % 8` walk cycle migrates;
the iso knight gains a walk (its art permitting) or a bob.

### G3. Sequences (PR 3)

Chained steps with waits — `sequence { move(npc, to:); pan(camera, to:);
say("..."); wait_for_confirm }` — the minimal scripted-events primitive a
Pokémon-like needs. Composes G1's tweens/timers; input-locking during a
sequence is the scene's choice, not enforced. Demo: a short scripted moment in
an existing scene (parallax doorway greeting is a natural fit with #19's
interior).

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

### H2. UI tree inspector (PR 6)

The existing debug rects grown up: node bounds/ids, navigation groups,
focus/hover/pressed state highlighting. The hover/focus work would have been
half the effort with this.

### H3. Draw-order inspector (PR 7)

The iso dump promoted to core: freeze + dump a camera's deferred draw buffer
(z bands, emission order, culling verdicts) to a file, with the analyzer
shipped as a framework tool rather than a demo script.

## Track E — consolidation (carried from v1)

### E2+E3. `ui.rb` modularisation + shared render path (PR 4)

The file has only grown since v1 flagged it (hover, shortcuts, beam
navigation now live there). Mechanical, behaviour-free split into
node/layout/reconciler/view/text/scroll/navigation, `require` order preserved;
fold in the `NODE_KEYWORDS` four-places dedup and extract the ~25 duplicated
lines of Scene/Camera UI rendering into `UIManagement#render_ui`. Suite passes
unchanged; no public constant moves.

## Track F — docs refresh (PR 8)

- Rewrite `docs/ui.md` around the reactive path — now the *only* path in the
  demos — demoting imperative `ui.node` to the escape-hatch section.
- New `docs/cameras.md` (spaces, culling, z-ordering, parallax, shake,
  multi-camera) including the **camera-feel recipe** (deadzone + lookahead on
  `look_at` + `speed` — the documented answer to a deliberate non-feature).
- New `docs/scenes.md`: lifecycle, stack, transitions, loading, clocks,
  the intra-scene pause pattern, save-state contract.
- README checklist truth-up.

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
