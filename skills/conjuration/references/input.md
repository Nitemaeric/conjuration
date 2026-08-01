# Input reference

Conjuration reads input through
[dragon_input](https://github.com/Nitemaeric/dragon_input): action-based bindings
over keyboard, mouse, and controller, with user remapping and device-following
glyphs. It is a hard dependency — drenv vendors it when you add Conjuration, so
never declare it yourself. Rationale lives in the framework's `docs/input.md`.

Framework UI needs no setup at all. If you never call `DragonInput.setup`, the
first menu query bootstraps a minimal config.

## Declaring actions

Once, in `Game#setup`:

```ruby
DragonInput.setup do |c|
  c.action_set :gameplay do |s|
    s.digital :attack,     controller: :b,           keyboard: :space
    s.digital :move_left,  controller: :dpad_left,   keyboard: :a
    s.digital :move_right, controller: :dpad_right,  keyboard: :d
    s.analog  :pan,        controller: :left_analog, keyboard: :wasd
  end
end
```

Query anywhere:

```ruby
game.input_source.just_pressed?(game.ui_pad, :attack)   # down edge
game.input_source.pressed?(game.ui_pad, :attack)        # held (or newly down)
DragonInput.axis(game.ui_pad, :pan)                     # => { x:, y:, active: }
```

`game.ui_pad` (default `:one`, writable) is the logical pad the framework UI
listens to.

**Don't pump manually.** Conjuration calls `DragonInput.tick(args)` once per frame
inside `Game#tick`, gated on `DragonInput.config`.

For analog *movement*, raw DragonRuby composites are usually the better read:
`inputs.left_right` and `inputs.up_down` keep the stick analog and the arrows live
at once, where a digital binding is a single key.

## The reserved `:ui_*` actions

| Action | Controller | Keyboard |
| --- | --- | --- |
| `:ui_confirm` | `a` | `enter` |
| `:ui_up` / `:ui_down` | `dpad_up` / `dpad_down` | `up` / `down` |
| `:ui_left` / `:ui_right` | `dpad_left` / `dpad_right` | `left` / `right` |
| `:ui_navigate` (analog) | `right_analog` | — |

Space is deliberately unbound — games commonly use it, and confirming on it would
double-fire.

**Injection fills gaps only**, into every action set that lacks them, at *query*
time rather than load time. So your own `DragonInput.setup` always wins whenever
it runs, and a set rebuilt later is re-injected on the next query.

`:ui_navigate` is the right stick read with flick semantics: one step per
neutral-to-deflected crossing, hysteresis at 0.5 engage / 0.35 re-arm. The digital
directions handle hold-to-repeat instead.

Node `shortcut:` declarations get the same treatment, injected as
`:ui_shortcut_<node id>` (`node.shortcut_action_name`), gaps-only.

## The action-query contract

The framework never touches `inputs.keyboard` for UI. It goes through
`game.input_source`, and the whole required contract is two methods:

```ruby
just_pressed?(pad, action)   # down edge this frame
pressed?(pad, action)        # held (or newly down)
```

Two more are optional and feature-detected: `navigation_flick(pad)` (the right
stick step) and `shortcut_just_pressed?(pad, name, bindings)`. A source
implementing neither simply doesn't get those features.

The default is `Conjuration::DragonInputSource`, which wraps dragon_input and adds
the injection and flick handling. **Assigning your own replaces it for good** —
there is no fallback:

```ruby
class ScriptedInput
  attr_accessor :edges, :held

  def initialize
    @edges = []
    @held = []
  end

  def just_pressed?(_pad, action)
    @edges.include?(action)
  end

  def pressed?(_pad, action)
    @held.include?(action) || just_pressed?(_pad, action)
  end
end

source = ScriptedInput.new
game.input_source = source
source.edges = [:ui_down]     # drive a frame, then assert on UI.focused_node
```

This is the seam that makes menu behaviour testable without a device — see
[testing.md](testing.md).

## Glyphs

```ruby
DragonInput.glyph_style(pad)      # => :keyboard, or a controller art style
DragonInput.glyph(pad, action)    # => sprite path for that action, or nil
```

`glyph` is **action-based**: ask for `:ui_confirm` and you get the key or button
currently bound to it, including after a remap. It follows the last-used device.

The art is a white silhouette — tint it. The style is a scalar, so it makes a
perfect memo key:

```ruby
def press_prompt
  memo(:press_prompt, DragonInput.glyph_style(game.ui_pad)) do
    node({ x: grid.w / 2, y: 200, w: 48, h: 48, anchor_x: 0.5,
           path: DragonInput.glyph(game.ui_pad, :ui_confirm), r: 240, g: 240, b: 240 }, id: :confirm_glyph)
  end
end
```

A nil glyph means there is no art for that binding — draw a text chip rather than
an empty sprite. The demo's `PromptView` and `ShortcutBadgeView` show both paths.

## Which device is the player using?

`inputs.last_active` is DragonRuby's answer, and the framework leans on it twice:
navigation input is read only when it isn't `:mouse`, and the focus ring is hidden
(but retained) while the mouse is active. Follow the same rule in your own focus
visuals:

```ruby
def focus_visible?
  Conjuration::UI.focused_node.equal?(my_node) && $game.inputs.last_active != :mouse
end
```
