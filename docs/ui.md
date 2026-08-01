# UI & HUD

`Conjuration::UI` is a layout, reconciliation, and navigation system — not a
widget library. It positions boxes, keeps a retained node tree in sync with a
function of your state, and moves a selection around with keyboard and pad.
Buttons, sliders, and text inputs are game code (or an external library); the
demo's `ButtonView` and `PromptView` are the reference patterns, not framework
types.

Every scene and every camera owns a UI root: `scene.ui` draws in screen space,
`camera.ui` draws into that camera's viewport target.

- [The reactive path](#the-reactive-path)
- [Nodes](#nodes)
- [Layout](#layout)
- [Overflow and scrolling](#overflow-and-scrolling)
- [Navigation](#navigation)
- [Interaction state](#interaction-state)
- [The debug inspector](#the-debug-inspector)
- [The imperative escape hatch](#the-imperative-escape-hatch)

## The reactive path

A scene that defines `view` opts into the reactive path: the block is re-run
every frame, and the result is reconciled onto the retained tree rather than
rebuilt.

```ruby
class PauseScene < Conjuration::Scene
  def setup
    activate_navigation(:menu)
  end

  def view
    node({ x: 0, y: 0, w: grid.w, h: grid.h }, id: :screen, justify: :center, align: :center, gap: 12, group: :menu) do
      node({ text: "Paused", r: 255, g: 255, b: 255 }, id: :title)

      node({ w: 220, h: 48, path: :pixel, r: 60, g: 64, b: 80, action: -> { state[:paused] = false },
             hover: { r: 90, g: 96, b: 120 } }, id: :resume, justify: :center, align: :center) do
        node({ text: "Resume", r: 255, g: 255, b: 255 })
      end
    end
  end
end
```

`view` is a plain method — `self` is the scene, so `state`, `grid`, and your own
helpers resolve normally. Split it into as many private builder methods as you
like; `MenuScene#view` is one line (`state[:started] ? menu : press_prompt`).

A camera registers its own view in `setup`:

```ruby
def setup
  camera = add_camera(:main)
  camera.ui.group = :hud
  camera.ui.view { hud(camera) }
end
```

Camera HUD coordinates are viewport-relative, so use `camera.from_top(20)` /
`camera.from_right(20)` rather than DR's grid-relative `Numeric#from_top`.

**The root is an absolute canvas.** `calculate_layout` positions a node's
children only when that node isn't the root, so top-level nodes place themselves
with explicit `x`/`y` (usually a full-screen box, as above) and flex layout takes
over inside them. `padding:`/`justify:` on the root are ignored.

### Reconciliation

Each frame the view builds a tree of lightweight descriptors, then diffs them
against the retained nodes. Only changed props are written, and a node whose
declaration is unchanged is not re-laid-out. Colour and sprite changes never
trigger layout at all — they're excluded from the layout signature.

**Give siblings an `id:`.** Identity is the reconcile key. When the sibling list
is stable, matching is positional; when a conditional toggles or a list reorders,
keyed nodes are matched by id regardless of position, so retained state (scroll
offset, text measurements, focus) rides along with the right node. An unkeyed
sibling list that changes length warns:

```
unkeyed sibling list changed length under :list — give these nodes an id: so they reconcile by key, not position
```

Ids may be strings; they are symbolised (`"row_#{item.id}"` becomes
`:"row_3"`). A node removed from the tree drops any focus, hover, or press that
pointed at it, so a stale global can never dangle.

### `memo`

`memo(key, *deps) { … }` skips building a subtree while its deps compare equal —
the block never runs, so there are no fresh hashes or interpolated strings, and
the reconciler's identity check skips the subtree entirely.

```ruby
def background
  memo(:background, :static) do
    node({ x: 0, y: 0, w: grid.w, h: grid.h, path: "sprites/panel.png" }, id: :bg)
  end
end
```

Deps must be scalars or version counters. A Hash or Array dep compares against
itself and always looks unchanged; passing one warns in debug. `:static` (as
above) is the idiom for a subtree with no inputs at all — the demo's UI scene
memoizes ~600 static nodes that way.

### View components

`Conjuration::UI::View` is a ViewComponent-style class: take props in
`initialize`, emit nodes in `call`. Subclassing defines a builder method named
after the class, so components read as function calls.

```ruby
class BadgeView < Conjuration::UI::View
  def initialize(label:, count: 0)
    @label = label
    @count = count
  end

  def render?
    @count > 0
  end

  def call
    node({ w: 90, h: 24, path: :pixel, r: 40, g: 40, b: 52 }, id: :"badge_#{@label}", direction: :row, gap: 4, align: :center) do
      node({ text: @label, r: 230, g: 230, b: 240 })
      node({ text: @count.to_s, r: 255, g: 210, b: 120 })
      content
    end
  end
end

# in a view:
BadgeView(label: "gold", count: state.gold)
BadgeView(label: "keys", count: state.keys) { node({ text: "!" }) }
```

- Invoke with parentheses — the bareword is the class constant.
- `render?` (default `true`) gates emission, so callers pass props
  unconditionally.
- `content` places the caller's block children.
- `memoize_props!` on the class opts into props-equality memoization for keyed,
  block-less invocations: while props compare equal, `call` is skipped.
- A same-`id:` node whose component class changed remounts rather than
  prop-morphing, so swapping component types at one key is safe.

Components are the unit of isolated testing: `UI.render_component(BadgeView,
label: "gold", count: 2)` returns descriptors with no scene involved.

## Nodes

```ruby
node(object_hash, **node_keywords, &children)
```

The **object hash** is DragonRuby primitive data — `x`, `y`, `w`, `h`, `path`,
`text`, `r`/`g`/`b`/`a`, `angle`, `anchor_x`, and so on — plus two keys the UI
system reads: `action:` (a lambda; its presence makes the node interactive) and
`disabled:`. The primitive kind is derived: `path` → sprite, `text` → label,
`x2`/`y2` → line, otherwise whatever `primitive_marker` you set.

The **node keywords** are layout and behaviour, and live outside the object hash:

| Keyword | Default | Meaning |
| --- | --- | --- |
| `id:` | `nil` | Reconcile key and `find` handle |
| `direction:` | `:column` | Main axis: `:row` or `:column` |
| `justify:` | `:start` | Main-axis distribution |
| `align:` | `:start` | Cross-axis alignment |
| `gap:` | `0` | Space between in-flow children |
| `padding:` | `0` | Scalar, `[horizontal, vertical]`, or `{ left:, right:, top:, bottom: }` |
| `visible:` | `true` | Hidden nodes render nothing and are not interactive |
| `position:` | `:static` | `:absolute` takes the node out of flow |
| `top:`/`right:`/`bottom:`/`left:` | `nil` | Insets for an out-of-flow node |
| `grow:` | `nil` | Main-axis growth factor |
| `max_w:`/`max_h:` | `nil` | Size caps |
| `overflow:` | `nil` | See [Overflow](#overflow-and-scrolling) |
| `wrap:` | `nil` | This container wraps its text children to its content width |
| `text_break:` | `:word` | `:word`, `:letter`, or `false` to opt out |
| `group:` | `nil` | Navigation group name |
| `nav_wrap:` | `false` | Wrap navigation at this group's edges |
| `shortcut:` | `nil` | `{ keyboard:, controller: }` accelerator |

Putting a node keyword *inside* the object hash silently makes it render data, so
it is flagged:

```
node keyword(s) align are inside the object hash and will be ignored — pass them as keyword arguments: node({ ... }, align: ...)
```

Most keywords are reconcilable — change them frame to frame and the node
updates. `overflow:`, `wrap:`, `text_break:`, and the insets are fixed at
creation; to change one, change the node's `id:` so it remounts.

## Layout

Flexbox semantics, with one deliberate difference: **nothing grows unless you
ask it to.** A node keeps the size you gave it, or the size its content implies.
Growth is opt-in via `grow:`, which keeps a HUD stable when a label's text
changes length.

`direction:` picks the main axis. `justify:` distributes along it (`:start`,
`:end`, `:center`, `:between`, `:around`, `:evenly`, `:stretch`); `align:`
positions across it (`:start`, `:center`, `:end`, `:stretch`).

```ruby
node({ x: 20, y: 20.from_top, w: 400, h: 60, path: :pixel, r: 30, g: 34, b: 44 },
     id: :toolbar, direction: :row, justify: :between, align: :center, padding: 8) do
  node({ text: "Party", r: 255, g: 255, b: 255 }, id: :label)
  node({ w: 80, h: 32, path: :pixel, r: 70, g: 90, b: 140, action: -> { open_party } }, id: :open)
end
```

A `justify:` other than `:start`/`:end` needs a resolved size on that axis to
divide; without one it degrades to `:start` and says so.

### Where a size comes from

1. **Explicit** — the `w:`/`h:` you declared. Always wins.
2. **Assigned** — handed down by a parent: `align: :stretch`, a `grow:` share,
   or an out-of-flow node pinned by insets on both sides of an axis.
3. **Auto** — derived from content.

A container with no declared size on an axis, and children to measure, derives
it: the main axis is the sum of in-flow children plus gaps, the cross axis is the
largest in-flow child, each plus that container's padding. Out-of-flow children
count for neither. Text nodes size from their string, and the root and `wrap:`
containers are excluded (a wrap container's width comes from its parent, and its
children then wrap to it — the opposite resolution order).

`max_w:` / `max_h:` clamp whatever the size ended up being, from any of the three
sources. A cap never enlarges.

### Growing

`grow:` expands a node into the leftover main-axis space of its parent, in
proportion to the factors of all its growing siblings.

```ruby
node({ w: 240, h: 18 }, id: :track, direction: :row) do
  node({ w: 0, h: 18, path: :pixel, r: 120, g: 200, b: 120 }, id: :fill, grow: progress)
  node({ h: 18 }, id: :rest, grow: 100 - progress)
end
```

Factors need not sum to anything in particular — they're shares. Each grower
restarts from its authored size (or 0) before leftover is measured, so
re-rendering with a different factor can't compound. There is no shrinking: when
leftover is zero or negative, nothing moves. `grow:` on a parent with no resolved
main size warns and is ignored.

`justify: :stretch` is the main-axis mirror of `align: :stretch`: sugar for
`grow: 1` on every in-flow child that has no authored main size. Children with
their own `grow:` keep their factor, and text children — intrinsically sized —
never stretch.

```ruby
# three equal columns, whatever the container's width
node({ w: 600, h: 40 }, id: :tabs, direction: :row, justify: :stretch, gap: 4) do
  node({ h: 40, path: :pixel, r: 50, g: 50, b: 60 }, id: :tab_a)
  node({ h: 40, path: :pixel, r: 50, g: 50, b: 60 }, id: :tab_b)
  node({ h: 40, path: :pixel, r: 50, g: 50, b: 60 }, id: :tab_c)
end
```

### Out of flow

`position: :absolute` takes a node out of the flow: it consumes no space, shifts
no siblings, and counts toward neither auto-sizing nor overflow. It is placed
against its parent's padding box by CSS-style insets. Both insets on an axis
stretch it between them; a single inset pins that edge and leaves its size alone.

```ruby
node({ w: 24, h: 24, path: "sprites/star.png" }, id: :badge, position: :absolute, top: -8, right: -8)
```

Overhangs are the point: a badge pinned outside its parent's corner is
deliberate, so it must never make the parent scroll.

### Wrapped text

A container with `wrap: true` breaks its text children to its own content width,
and each text node sizes to the wrapped block. `text_break:` chooses `:word`
(default), `:letter`, or `false` to opt one child out.

```ruby
node({ w: 420, h: 96, path: :pixel, r: 20, g: 20, b: 28 }, id: :dialogue, wrap: true, padding: 12, overflow: :visible) do
  node({ text: state.line, r: 240, g: 240, b: 245 }, id: :line)
end
```

A wrap container needs an explicit height: its width comes from the parent and
its content height isn't known until after the break, so it can't auto-size on
either axis.

## Overflow and scrolling

When in-flow content extends past a container's resolved height, `overflow:`
decides what happens. It defaults to scrolling, materialized only on demand —
so a pane that grows past its box stays usable instead of silently clipping, and
you find out in dev rather than in a bug report.

- `overflow: nil` (default) — a fitting container costs nothing; the first time
  content overflows it becomes a scroll container (render target, scrollbar,
  scroll input, focusable) and warns once.
- `overflow: :scroll` — always a scroll container, from the first frame.
- `overflow: :clip` — clips to the box once content overflows: same render
  target, no scrollbar, no scroll interaction.
- `overflow: :visible` — content spills; never scrolls or clips.

```ruby
node({ x: 20.from_right, y: 200, w: 230, h: 240, anchor_x: 1, path: :pixel, r: 30, g: 34, b: 44 },
     id: :quest_list, overflow: :scroll, padding: 12, gap: 8, group: :list, nav_wrap: :y) do
  state.quests.each { |quest| node({ text: quest.title, action: -> { open(quest) } }, id: "quest_#{quest.id}") }
end
```

Scrolling is vertical. The container's children are painted into a render target
keyed by its `id` (`ui_scroll_<id>`), so give a scroll container a stable id.
The mouse wheel scrolls the innermost pane under the cursor, and the right stick
scrolls the pane holding focus.

A scroll container is itself focusable, so an empty one — a pane of prose — can
be navigated to and stick-scrolled. Once it holds interactive nodes those become
the navigation targets and the pane drops out of the candidate list, so focus
never lands on the pane partway down a list.

Out-of-flow children never count toward overflow.

## Navigation

Navigation is off until the game turns it on. `activate_navigation(:group)` sets
the active pane; `deactivate_navigation` turns it off and drops the highlight.
There is no built-in group switcher — the scene owns the order panes cycle in,
because only the game knows whether Tab should move between panes or do
something else.

```ruby
NAV_GROUPS = [:hud, :party, :list].freeze

def input
  return if Conjuration::UI.active_navigation_group.nil? && inputs.last_active == :mouse

  if Conjuration::UI.active_navigation_group.nil?
    activate_navigation(:list)
  elsif inputs.keyboard.key_down.tab
    current = NAV_GROUPS.index(Conjuration::UI.active_navigation_group) || -1
    activate_navigation(NAV_GROUPS[(current + 1) % NAV_GROUPS.length])
  end
end
```

`group:` names a pane. Interactive nodes belong to the nearest enclosing group,
so the keyword usually sits on the panel, not on each item. Ungrouped
interactive nodes are never navigation targets (they still hover and click).
Setting `camera.ui.group = :hud` groups a whole camera HUD in one line.

When a group is activated, focus is seeded onto its first member if it isn't
already inside — so there is always a visible selection.

### Hover and focus are separate

The mouse never writes focus. It drives `UI.hovered_node`, which styles and
targets clicks; keyboard and pad drive `UI.focused_node`. So reaching for the
mouse mid-menu doesn't destroy the selection, and going back to the pad resumes
exactly where it was. Navigation input is only read when
`inputs.last_active != :mouse`.

Confirm (`:ui_confirm`) fires the focused node's action; a mouse click fires the
hovered node's.

### Spatial navigation

A direction press moves focus to the interactive node that way within the active
group, resolved in two tiers. Any candidate whose cross-axis span overlaps the
source's — the *beam* — categorically outranks every non-beam candidate, however
near; among beam candidates the smallest main-axis gap wins. Only when the beam
is empty does it fall back to the nearest node in a 45-degree cone. That is what
makes an aligned neighbour beat a closer diagonal one, which is what players
expect from a grid.

A press with nothing ahead of it stays put, unless the group wraps.

### `nav_wrap:`

`nav_wrap:`, declared alongside `group:`, makes that group loop: pressing down at
the bottom lands on the topmost member, up at the top on the bottommost, and the
same horizontally. A wrap prefers a member aligned with the source, so a grid
wraps within its own column or row rather than jumping across. Off unless
declared.

The value scopes the wrap to an axis: `true` wraps both, `:x` only horizontal
presses, `:y` only vertical. A single row wants `:x` — with `true`, a down press
at a row's edge has nowhere to go and would "wrap" onto the adjacent slot, the
only far-end candidate there is.

### Scroll into view

Navigating onto an item scrolls its pane to bring the item into view along with
the next one in the direction of travel, so you can always see what you are about
to move onto. Nested panes are adjusted innermost-first.

### Hold to repeat

Holding a direction keeps moving focus: the press edge steps immediately, then
after `UI.nav_repeat_delay` ticks the step repeats every
`UI.nav_repeat_interval` ticks (18 and 6 by default — 300ms then 100ms at
60fps). Both are writable; `UI.nav_repeat_delay = nil` switches repeat off and
leaves the edge-only behaviour.

Releasing resets it, and changing direction starts a fresh hold rather than
inheriting the old one's cadence. The timing runs off `Kernel.tick_count`, not a
scene clock, because a menu is exactly what you navigate while the scene behind
it is paused or in hit stop. The right stick keeps its one-step-per-flick
behaviour; repeat is for the held digital directions.

### Shortcuts

`shortcut: { keyboard:, controller: }` fires a node's action from anywhere —
regardless of focus, and even with no navigation group active.

```ruby
BACK = { keyboard: :escape, controller: :b }.freeze

node({ w: 120, h: 40, path: :pixel, r: 60, g: 60, b: 70, action: -> { change_scene(to: MenuScene.new(:main)) } },
     id: :back, shortcut: BACK) do
  node({ text: "Back", r: 255, g: 255, b: 255 })
end
```

The framework injects a deterministic action per node (`:ui_shortcut_<id>`, so a
game can rebind it) and fires the action on its down edge. **Drawing the badge is
game code** — read `node.shortcut_action_name` and hand it to
`DragonInput.glyph`. The demo's `ShortcutBadgeView` is the reference pattern; see
[input.md](input.md) for glyphs.

## Interaction state

Nodes answer `focused?`, `hovered?`, `pressed?`, `disabled?`, and
`interaction_state` (`:disabled`, `:pressed`, `:hover`, `:focused`, or
`:default`, in that precedence). Per-state style overrides go in the object hash
and are merged over it at render time:

```ruby
node({ w: 200, h: 44, path: :pixel, r: 60, g: 64, b: 80, action: -> { confirm },
       hover:    { r: 90, g: 96, b: 120 },
       pressed:  { r: 40, g: 44, b: 56 },
       disabled: state.locked ? { r: 90, g: 90, b: 90 } : nil }, id: :confirm)
```

Without a `focused:` override, focus falls back to the `hover:` style, so
hover-only buttons still read as selected under pad navigation.

The built-in focus ring is a two-tone border that lerps toward the focused node,
hidden (but retained) while the mouse is the active device. Games that style
focus themselves turn it off globally and opt back in per scene:

```ruby
Conjuration::UI.focus_indicator_default = false   # in Game#setup

def focus_indicator_enabled?   # in a scene that wants it back
  true
end
```

Mouse cursors are global: `UI.default_cursor` and `UI.hover_cursor` each take
`[path, hotspot_x, hotspot_y]`, applied as hover changes.

## The debug inspector

The inspector is on whenever `game.debug?` is — the demo toggles it with Meta+D —
and builds nothing when it's off.

**Bounds ride the primitive stream**, interleaved right after each node's own
primitives rather than collected into `outputs.debug`. So a foreground panel
covers the background's outlines exactly as it covers the background, and a
scroll pane's children decorate *inside* its render target and clip with the
content. Outlines are colour-coded: blue containers, green leaves, orange scroll
panes, grey out-of-flow nodes. Nodes with an `id:` get a label; a container whose
content spills gets a `+Npx` badge.

**Hovering reads out the box model** — DevTools-style translucent fills for the
content area, the padding band (as non-overlapping edge strips, so alphas never
stack), and the gap strips between consecutive in-flow children, derived from
where layout actually put the boxes. The readout panel next to the cursor gives
the node's identity (nearest id plus a child-index path when the node itself has
none), rect, per-axis size provenance (`explicit`, `grow`, `auto`, `assigned`,
plus `max-clamped`), padding, gap, overflow mode, and spill. Hit resolution uses
the same paint-order walk as clicks and the wheel, so the readout always agrees
with what you'd actually hit.

**Unresolved geometry is flagged loudly**, in `outputs.debug` rather than the
stream: a red crosshair and a `w=nil h=nil` label at whatever position is known.
An error marker must never be buried under a later-painted sibling, and a
container that collapsed to `h=nil` is otherwise invisible.

## The imperative escape hatch

`ui.node(...)` builds the tree directly, without a view. It is still supported —
the reconciler is opt-in — but a root is either view-driven or imperative, not
both. Mutating an imperative node means writing to its object and invalidating
it by hand:

```ruby
label = camera.ui.find(:hover_label)
label.object.text = hovered_label
label.invalidate!
```

Reach for this only where a view genuinely doesn't fit; every demo scene is
reactive.

## See also

- [scenes.md](scenes.md) — where `view`, `loading_view`, and the UI roots sit in
  the lifecycle.
- [input.md](input.md) — the reserved `:ui_*` actions menus read, and glyphs.
- [time.md](time.md) — animating UI state on a scene clock.
