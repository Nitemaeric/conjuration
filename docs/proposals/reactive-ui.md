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

## Composition: nested views

Complex UIs compose in two tiers.

**Tier 1 — method extraction (free, day one).** `view` is just Ruby, so a
"component" is just a method that emits nodes:

```ruby
def view
  hud_view
  state.nested ? nested_menu_view : menu_view
end
```

**Tier 2 — formal view classes.** Swapping whole views through a conditional
exposes an identity problem: if `MenuView` and `NestedMenuView` both emit a
root with `id: :menu`, key-only matching would *prop-morph* one into the other
when the conditional flips — reusing the retained node and its state, so
`NestedMenuView` would wake up wearing `MenuView`'s leftover scroll offset.
React's rule fixes this: **the component type is part of the identity** —
different type → unmount and remount, fresh subtree, state reset.

The class anatomy borrows deliberately from GitHub's ViewComponent (components
as plain Ruby classes; logic beside markup; no template compiler):

```ruby
class MenuView < Conjuration::UI::View
  def initialize(items:, title: "Menu")   # the props contract
    @items = items
    @title = title
  end

  def render? = @items.any?               # self-gating conditional rendering

  def call
    node({ ... }, id: :menu) do
      node({ text: @title })
      @items.each { |item| menu_row(item) }
      content                              # caller's block children, if given
    end
  end

  private

  def menu_row(item) = node({ text: item.name }, id: item.id)
end

def view
  state.nested ? NestedMenuView(items: state.items) : MenuView(items: state.items)
end
```

Borrowed from ViewComponent:

- **`initialize` is the props contract.** Props become ivars, visible to every
  helper method without argument threading; the signature documents the
  component's API. Instances are ephemeral — constructed fresh each time the
  component runs (stateless v1 holds).
- **`#call` is the render method** (not `view`). `call` is Ruby's universal
  invocation interface — procs, lambdas, and `Method` objects all respond to
  it — and it disambiguates the two concepts: a scene *has* a `view` (the
  hook); a component *is* a view, and `call` runs it. Consequence of the duck
  type (`call` + optional `render?`): a bare lambda can serve as a stateless
  anonymous component (`Divider = -> { node({ ... }) }`), with the caveat that
  procs have no stable class identity — positional matching only; class
  components remain the tool where `[key, component_class]` identity matters.
- **`render?`** — the component self-gates. `render?` → false means emit
  nothing (unmount if previously mounted), so a common conditional-rendering
  pattern lives in the component instead of at every call site.
- **Content blocks.** `MenuView(items:) do ... end` — the caller's block
  children become `content`, placed wherever the component's `call` wants.
  This is what makes wrapper components (panels, cards, modals) possible.
  Named slots (`renders_one` / `renders_many`) are the natural extension —
  later phase; single `content` covers most game UI.
- **Isolated testing.** A component is `props → descriptors` with no scene
  coupling, so tests can instantiate one directly and assert on its descriptor
  tree — no scene boot, no reconciler.

Not borrowed: ViewComponent's `render(MenuView.new(...))` invocation style.
The view DSL collects children by side effect — `node(...)` emits into the
enclosing builder context — not by return value (return values must be
droppable, e.g. inside `each` blocks). A bare `.new` constructs an object that
nothing ever emits; a call site is a method on the builder, and the builder is
exactly the thing that knows where to emit.

The call syntax is automatic: `View.inherited(klass)` defines a builder method
named after the class (uppercase method names are legal Ruby when called with
parens — the `Kernel#Integer()` trick; verified working in DR's mruby) on the
shared builder module, which emits a component descriptor
`[key, component_class, props, block]` into the current context — the
reconciler instantiates lazily, so props-equality memo can skip a subtree
before `initialize` ever runs. The reconciler matches on
`[key, component_class]`; flipping the class tears the subtree down cleanly
(focus cleared, scroll reset) and remounts.

Caveats:

- Namespaced components (`Menus::ItemView`) can't be invoked as `Foo::Bar(...)`
  — the auto-defined method uses the demodulized name (`ItemView(...)`), with a
  debug-mode warning on name collision. Flat component names are the expected
  common case in game code.
- **Content blocks weaken memo.** A block captures its environment and can't
  be compared frame-to-frame, so a component invoked with a block can't be
  skipped by props equality alone — its children must re-run. Leaf components
  without blocks memo cleanly.

Consequences:

- **Component boundaries are natural memo boundaries.** Props are explicit at
  the call site, so `React.memo` comes almost free: props `==` last frame →
  skip running the component's `call` and keep the retained subtree. This may end
  up the primary memo API, with bare `memo(deps)` as the low-level tool.
- **Components are stateless in v1**: pure `props → descriptors`. State lives
  in the scene (`state.*`) — no `useState`, no retained component instances
  across frames. Component-local state is a real feature but a separate one;
  pure views keep the reconciler simple and the data flow one-way.
- View classes with no scene coupling are exactly the shape a standalone-lib
  extraction wants.

## Frame pipeline

```
input → update → run view (descriptors) → reconcile → calculate_layout (dirty-gated) → primitives
```

## Reconciliation

Per parent, match descriptor children to retained children:

- **Keyed** (`id:` present): match by id, regardless of position. `id:` is
  already the identity concept in the framework — it doubles as the React key.
  Where a formal view class is in play, identity is `[key, component_class]` —
  a type change never prop-morphs (see Composition).
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
3. **Composition + `memo` + perf pass** — formal view classes
   (`SomeView(**props)` call syntax via `inherited`-defined builder methods,
   ViewComponent-style anatomy: `initialize` props contract, `#call` as the
   render method, `render?`, `content` blocks; `[key, component_class]`
   identity, unmount/remount on type change), props-equality component memo,
   lambda-as-component duck typing, bare `memo(deps)`, isolated
   component tests, allocation measurement, pooling only if the numbers demand
   it. (Method-extraction composition needs nothing and works from Phase 1.)
4. **Later / out of scope**: named slots (`renders_one` / `renders_many`),
   component-local state, extraction into a standalone UI lib (the reconciler
   deliberately lives under `lib/conjuration/ui/` with no scene dependencies,
   so this stays cheap), list virtualization, signals (only if a real workload
   defeats memo — doubtful).

## Decisions

- The scene hook is named **`view`** (`render` collides with the existing
  render hook).
- Within a root, `view` **replaces** `setup`-time building — one owner per
  tree.
- Reconciliation lands **before** Part 2 flex sizing: it changes authoring,
  flex changes layout math, and they barely overlap.
