# Reactive UI (view reconciliation)

Status: **accepted** — implementation phased below.

## Problem

UI state lives in two places: game state and the node tree. The dev owns keeping
them in sync, and that sync code is pure noise:

```ruby
items.each do |item, index|
  item[:progress] += item[:rate] / 60
  item[:progress] = 0 if item[:progress] > 100
  ui.find("item_#{index}").w = ((grid.w - 40) * item[:progress] / 100) # ← shouldn't be needed
end
```

The line that shouldn't be needed exists because the tree is built once in
`setup` and mutated forever after. The fix is to let the dev **declare the tree
as a function of state**, and make the framework responsible for reconciling
that declaration against the retained tree.

## Model: React's, not Solid's

Re-run a `view` each frame → get a cheap **descriptor tree** (plain hashes, not
`Node`s) → **reconcile** it against the retained node tree by key → write
changed props through the existing change-aware `invalidate!`. No signals, no
`.value` ceremony — state is plain Ruby, reactivity comes from re-derivation
plus diffing.

Critically, this is a **front door on the existing engine, not a new engine**.
The retained tree, `layout_signature` change detection, `mark_dirty!` parent
propagation, dirty-gated `calculate_layout`, memoized text measurement, and
scroll targets are all reused unchanged. The reconciler's only job is to write
props and add/remove children; everything downstream is already built and
tested.

## Authoring API

A scene (or any UI owner) defines `view`. `update` mutates state; `view`
derives the tree. One-way data flow:

```ruby
class ClickerScene < Conjuration::Scene
  def setup
    state.items = 8.times.map { { progress: 0, rate: 10 + rand * 30 } }
  end

  def update
    state.items.each do |item|
      item[:progress] = (item[:progress] + item[:rate] / 60) % 100
    end
  end

  def view
    node({ x: 20, y: 20.from_top, w: grid.w - 40, anchor_y: 1 }, gap: 8) do
      state.items.each_with_index do |item, i|
        node({ h: 20, path: :pixel, r: 40, g: 44, b: 52 }, id: "item_#{i}") do
          node({ w: (grid.w - 40) * item[:progress] / 100, h: 20, path: :pixel, r: 120, g: 200, b: 120 })
        end
      end
    end
  end
end
```

No `find`, no `invalidate!`, no manual width write. Conditionals and lists are
plain Ruby — `if`, `each`:

```ruby
node({ ... }, id: :tooltip) if ui.find(:button)&.focused?
```

Underneath, the generic form is `ui.view { ... }` (a registered block on any UI
root), so camera HUDs get it too (`camera.ui.view { ... }`); `def view` on a
scene is sugar for the scene's root.

### Ownership

**Within a root, `view` replaces `setup`-time UI building** — one owner per
tree, no split-brain. A root either has a view (fully declarative) or it
doesn't (imperative, exactly as today). The feature is opt-in per root, and the
imperative API (`find` + `invalidate!`) remains as the escape hatch for
non-view roots. Manual mutations inside a view-owned root are overwritten on
the next frame — documented, by design.

## Frame pipeline

```
input → update → run view (descriptors) → reconcile → calculate_layout (dirty-gated) → primitives
```

## Reconciliation

Per parent, match descriptor children to retained children:

- **Keyed** (`id:` present): match by id, regardless of position. `id:` is
  already the identity concept in the framework — it doubles as the React key.
- **Unkeyed**: match by position among unkeyed siblings. Fine for static
  structure; dynamic lists should key (v1: warn in debug mode when an unkeyed
  sibling list changes length).
- **Unmatched descriptor** → create a `Node` (existing `Node.new`), insert,
  `clear_structure_cache!`, parent `mark_dirty!`.
- **Unmatched retained node** → remove; if it (or a descendant) is
  `UI.focused_node`, clear focus so it can't dangle.

### Diff against declared props, not the live object

Layout writes computed geometry back into `object` (measured `w`/`h`,
positioned `x`/`y`), so diffing descriptor-vs-object would see phantom changes
every frame and defeat the dirty engine entirely. Instead each reconciled node
keeps `@declared` — the previous frame's descriptor props. Diff the new
descriptor against `@declared`; write only changed keys into `object`; call
`invalidate!` only if a layout-relevant key changed (render-only keys like
colour just write — the renderer re-reads `object` anyway, no relayout). A
clean frame is therefore a hash-compare per node and **zero** layout work.

### Retained state survives

Nodes are reused, not rebuilt: `scroll_offset`, focus identity (the lerping
focus cursor keeps working), memoized text measurement, and memoized wrap lines
all persist across frames.

`action:` lambdas are recreated every view run and can't be meaningfully
compared — they're treated as render-only (overwrite, never dirty).

## Performance

Per-frame cost on a clean frame = one view run + one diff walk: roughly two
hash allocations and a small hash-compare per node. For UI/HUD scale (50–300
nodes) that should be sub-millisecond on desktop — but mruby allocation churn
and GC pressure are the real risk, so this is a **measured gate, not an
assumption**:

1. **Benchmark first**: extend the bench harness with a reconcile benchmark
   (300-node tree; clean frame / 1-node change / list churn) and set a budget —
   clean-frame reconcile ≤ 0.5 ms — before merging.
2. **`memo` as the relief valve** — skip descriptor building for a subtree when
   its inputs didn't change (the retained subtree is kept as-is):

   ```ruby
   memo(state.items.length, state.wave) do
     state.items.each_with_index { |item, i| ... }
   end
   ```

   This is `useMemo`: most of what signals buy, with zero ceremony on the rest
   of the game's state.
3. **Pooling later if needed**: descriptor hashes are uniform and short-lived —
   a per-frame arena/pool is a mechanical follow-up if the benchmark says GC
   hurts. Not built speculatively.
4. **Scope guard**: this is for UI/HUD. Non-UI game components are not expected
   users; the imperative path stays available for anything hotter.

Fallback position if the benchmark fails its budget even with memo:
prop-bindings only (`w: -> { ... }` lambdas, no structural reconcile) — much
cheaper, less expressive. Not expected to be needed.

## Phases (each a PR)

1. **Reconciler core** — `ui.view`, descriptor build, declared-props diffing,
   stable trees only (no add/remove). Golden tests: every existing demo scene
   converted must produce byte-identical primitives. Bench gate added.
2. **Structural reconcile** — keyed create/remove/reorder, conditional
   rendering, focus/scroll preservation, unkeyed-list warning. Clicker-style
   progress-bar demo scene (the acceptance test: the `update` loop touches only
   `item[:progress]`).
3. **`memo` + perf pass** — memo API, allocation measurement, pooling only if
   the numbers demand it.
4. **Later / out of scope**: extraction into a standalone UI lib (the
   reconciler deliberately lives under `lib/conjuration/ui/` with no scene
   dependencies, so this stays cheap), list virtualization, signals (only if a
   real workload defeats memo — doubtful).

## Decisions

- The scene hook is named **`view`** (`render` collides with the existing
  render hook).
- Within a root, `view` **replaces** `setup`-time building — one owner per
  tree.
- Reconciliation lands **before** Part 2 flex sizing: it changes authoring,
  flex changes layout math, and they barely overlap.
