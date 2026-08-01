# UI reference

`Conjuration::UI` is layout, reconciliation, and navigation — not a widget
library. Buttons and sliders are game code. Rationale lives in the framework's
`docs/ui.md`.

Every scene and camera owns a root: `scene.ui` draws in screen space,
`camera.ui` into that camera's viewport target.

## Declaring a tree

```ruby
node(object_hash = nil, **node_keywords, &children)
```

A scene that defines `view` opts into the reactive path — the method is re-run
every frame and reconciled onto the retained tree. `self` is the scene, so
`state`, `grid`, and your own helpers resolve. A camera registers its own in
`setup`:

```ruby
camera.ui.group = :hud
camera.ui.view { hud(camera) }
```

The root is an absolute canvas: top-level nodes place themselves with explicit
`x`/`y` (usually a full-screen box), and `padding:`/`justify:` on the root are
ignored.

`ui.node(...)` builds imperatively without a view; a root is one or the other,
never both. Mutating an imperative node is `node.object.text = "x"` then
`node.invalidate!`.

### The object hash

DragonRuby primitive data — `x`, `y`, `w`, `h`, `path`, `text`, `r`/`g`/`b`/`a`,
`angle`, `anchor_x`, `anchor_y`, `primitive_marker`, … — plus two keys the UI
reads:

- `action:` — a lambda. Its presence makes the node interactive. Fired with
  `instance_exec` against the owning scene/camera.
- `disabled:` — truthy suppresses interaction.

Primitive kind is derived: `path` → sprite, `text` → label, `x2`+`y2` → line,
otherwise `primitive_marker`.

Per-state style overrides also go in the object hash and are merged over it at
render time: `hover:`, `pressed:`, `focused:`, `disabled:`, each a Hash.

### Node keywords

| Keyword | Default | Meaning |
| --- | --- | --- |
| `id:` | `nil` | Reconcile key and `find` handle. Symbolised. |
| `direction:` | `:column` | Main axis: `:row` or `:column` |
| `justify:` | `:start` | Main-axis distribution: `:start :end :center :between :around :evenly :stretch` |
| `align:` | `:start` | Cross-axis: `:start :center :end :stretch` |
| `gap:` | `0` | Space between in-flow children |
| `padding:` | `0` | Scalar, `[horizontal, vertical]`, or `{ left:, right:, top:, bottom: }` |
| `visible:` | `true` | Hidden nodes render nothing and are not interactive |
| `position:` | `:static` | `:absolute` takes the node out of flow |
| `top:` `right:` `bottom:` `left:` | `nil` | Insets for an out-of-flow node |
| `grow:` | `nil` | Main-axis growth factor |
| `max_w:` `max_h:` | `nil` | Size caps; never enlarge |
| `overflow:` | `nil` | `nil` (lazy scroll), `:scroll`, `:clip`, `:visible` |
| `wrap:` | `nil` | This container wraps its text children to its content width |
| `text_break:` | `:word` | `:word`, `:letter`, or `false` |
| `group:` | `nil` | Navigation group name |
| `nav_wrap:` | `false` | `true`, `:x`, or `:y` — wrap navigation at this group's edges |
| `shortcut:` | `nil` | `{ keyboard:, controller: }` accelerator |

Reconcilable frame-to-frame: `direction justify align gap padding visible
position group nav_wrap shortcut grow max_w max_h`. Fixed at creation:
`overflow`, `wrap`, `text_break`, the insets — change the `id:` to remount.

A node keyword placed *inside* the object hash is inert render data; the
framework warns.

## Sizing

Three sources, in precedence order:

1. **Explicit** — the `w:`/`h:` you declared. Always wins.
2. **Assigned** — `align: :stretch`, a `grow:` share, or an out-of-flow node
   pinned by insets on both sides of an axis.
3. **Auto** — main axis = sum of in-flow children plus gaps; cross axis = largest
   in-flow child; each plus this container's padding. Text sizes from its string.

Out-of-flow children count toward neither auto-size nor overflow. The root and
`wrap:` containers never auto-size. `max_w:`/`max_h:` clamp whatever the result
was.

`grow:` factors are shares of leftover main-axis space; each grower restarts from
its authored size, so re-rendering with a different factor cannot compound. There
is no shrinking. `grow:` on a parent with no resolved main size warns and is
ignored. `justify: :stretch` is sugar for `grow: 1` on every in-flow child with
no authored main size; text children never stretch.

A `justify:` other than `:start`/`:end` needs a resolved size on that axis;
without one it degrades to `:start` and warns.

A `wrap: true` container needs an explicit height — its width comes from the
parent and its content height isn't known until after the break.

## Overflow and scrolling

| `overflow:` | Behaviour |
| --- | --- |
| `nil` (default) | Free while it fits; the first time content overflows it becomes a scroll container and warns once |
| `:scroll` | Scroll container from the first frame |
| `:clip` | Clips once content overflows: same render target, no scrollbar, no scroll input |
| `:visible` | Content spills; never scrolls or clips |

Scrolling is vertical only. Children are painted into a render target keyed
`ui_scroll_<id>`, so give a scroll container a stable `id:`. Mouse wheel scrolls
the innermost pane under the cursor; the right stick scrolls the pane holding
focus.

Layout rects are **unshifted** — the `scroll_offset` shift happens at emission.
To reach a node's drawn position, add `node.ancestor_scroll_offset`.

A scroll container is itself focusable so an empty pane of prose can be navigated
to and stick-scrolled; once it holds interactive nodes those become the targets
and the pane drops out of the candidate list.

Useful members: `scroll?`, `clip?`, `render_target?`, `scroll_offset` (writable),
`max_scroll`, `content_height`, `enclosing_scroll_pane`, `scroll_into_view`.

## Navigation

```ruby
activate_navigation(:group)     # sets UI.active_navigation_group
deactivate_navigation           # off, and drops the highlight
```

Off until the game turns it on; nil group means the whole nav input path is
inert. There is no built-in group switcher — read
`Conjuration::UI.active_navigation_group` and reassign it yourself.

`group:` names a pane; interactive nodes belong to the nearest enclosing group,
so the keyword sits on the panel, not each item. Ungrouped interactive nodes are
never navigation targets (they still hover and click). `camera.ui.group = :hud`
groups a whole camera HUD.

On activation, focus seeds onto the group's first member if it isn't already
inside.

**Spatial resolution.** A candidate whose cross-axis span overlaps the source's —
the *beam* — categorically outranks every non-beam candidate, however near; among
beam candidates the smallest main-axis gap wins. Only when the beam is empty does
it fall back to the nearest node in a 45-degree cone.

**`nav_wrap:`** makes a group loop at its edges, preferring a member aligned with
the source. `true` wraps both axes, `:x` horizontal presses only, `:y` vertical
only. A single row wants `:x` — with `true`, a down press at the row's edge
"wraps" onto the adjacent slot.

**Hold to repeat.** The press edge steps immediately, then after
`UI.nav_repeat_delay` ticks repeats every `UI.nav_repeat_interval` ticks (18 and
6 — 300ms then 100ms at 60fps). Both writable; `UI.nav_repeat_delay = nil`
disables repeat. This timing runs off `Kernel.tick_count`, not a scene clock,
because a menu is what you navigate while the scene behind it is frozen — the one
sanctioned exception to golden rule 1.

**Scroll into view** brings the focused item *and the next one in the direction
of travel* into the pane, innermost pane first.

**Shortcuts.** `shortcut: { keyboard:, controller: }` fires a node's action from
anywhere, regardless of focus and with no group active. The framework injects
`:ui_shortcut_<id>` so a game can rebind it. Drawing the badge is game code —
read `node.shortcut_action_name` and hand it to `DragonInput.glyph`.

## Interaction state

Nodes answer `focused?`, `hovered?`, `pressed?`, `disabled?`, `interactive?`,
`navigable?`, and `interaction_state` (`:disabled`, `:pressed`, `:hover`,
`:focused`, `:default`, in that precedence).

Without a `focused:` override, focus falls back to the `hover:` style.

Globals — assign, don't guess:

```ruby
Conjuration::UI.focused_node            # keyboard/pad only
Conjuration::UI.hovered_node            # mouse only
Conjuration::UI.pressed_node
Conjuration::UI.active_navigation_group
Conjuration::UI.focus_indicator_default = false   # in Game#setup
Conjuration::UI.default_cursor = ["sprites/cursor.png", 9, 4]
Conjuration::UI.hover_cursor   = ["sprites/hand.png", 6, 4]
```

A scene overriding `focus_indicator_enabled?` opts back into the built-in ring.
The ring is hidden (but retained) while `inputs.last_active == :mouse`; follow
the same rule in your own focus visuals.

Confirm (`:ui_confirm`) fires the **focused** node's action; a mouse click fires
the **hovered** node's.

## Reconciliation

Each frame the view builds descriptors and diffs them against retained nodes.
Only changed props are written; colour and sprite changes never trigger layout.

Matching is positional while the sibling list is stable; when a conditional
toggles or a list reorders, keyed nodes match by `id:` regardless of position, so
scroll offset, text measurements, and focus ride along with the right node. An
unkeyed sibling list that changes length warns. A removed node drops any focus,
hover, or press pointing at it.

### `memo`

```ruby
memo(key, *deps) { }
```

Skips building a subtree while deps compare equal — the block never runs, so no
fresh hashes or interpolated strings, and the reconciler's identity check skips
the subtree. Deps must be scalars or version counters; a Hash or Array dep
compares against itself and always looks unchanged (warns in debug). `:static` is
the idiom for a subtree with no inputs.

`DragonInput.glyph_style(pad)` is a scalar and therefore a perfect memo key for a
device-following prompt.

### View components

`Conjuration::UI::View` — props in `initialize`, nodes in `call`. Subclassing
defines a builder method named after the class, so components read as calls:

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
      node({ text: @label, r: 230, g: 230, b: 240 }, id: :"badge_#{@label}_label")
      content
    end
  end
end

BadgeView(label: "gold", count: state[:gold])
```

- Invoke with parentheses — the bareword is the class constant.
- `render?` (default true) gates emission, so callers pass props unconditionally.
- `content` places the caller's block children.
- `memoize_props!` on the class memoizes keyed, block-less invocations while props
  compare equal.
- A same-`id:` node whose component class changed remounts rather than
  prop-morphing.
- `UI.render_component(BadgeView, label: "gold", count: 2)` returns descriptors
  with no scene — the unit of isolated testing.

Namespaced components share a demodulised builder name; a collision warns.

## Debug inspector

On whenever `game.debug?` is; builds nothing when off. Bounds ride the primitive
stream (so a foreground panel covers background outlines exactly as it covers the
background); hovering reads out the box model, rect, per-axis size provenance
(`explicit`/`grow`/`auto`/`assigned`, plus `max-clamped`), padding, gap, overflow
mode, and spill. Unresolved geometry (`w=nil h=nil`) is flagged loudly in
`outputs.debug`.

`Conjuration::UI.warnings` is a bounded ring of the reconciler/layout warnings —
assert on it in tests rather than parsing stdout.
