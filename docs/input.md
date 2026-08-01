# Input

Conjuration reads input through
[dragon_input](https://github.com/Nitemaeric/dragon_input): action-based
bindings over keyboard, mouse, and controller, with user remapping and
device-following glyphs. It is a **hard dependency** — drenv vendors it
automatically when you add Conjuration, so you never declare it yourself:

```toml
# drenv.toml
[dependencies.dragon_input]
github = "Nitemaeric/dragon_input"
```

Framework UI needs no setup at all. If you never call `DragonInput.setup`, the
first menu query bootstraps a minimal config; either way the reserved UI actions
are injected the first time a menu reads input.

- [Actions](#actions)
- [The reserved `:ui_*` actions](#the-reserved-ui_-actions)
- [The action-query contract](#the-action-query-contract)
- [Glyphs](#glyphs)
- [Which device is the player using?](#which-device-is-the-player-using)

## Actions

Declare your own bindings once, in `Game#setup`:

```ruby
class Game < Conjuration::Game
  def setup
    DragonInput.setup do |c|
      c.action_set :gameplay do |s|
        s.digital :attack,     controller: :b,            keyboard: :space
        s.digital :move_left,  controller: :dpad_left,    keyboard: :a
        s.digital :move_right, controller: :dpad_right,   keyboard: :d
        s.analog  :pan,        controller: :left_analog,  keyboard: :wasd
      end
    end

    self.current_scene = MenuScene.new(:main)
  end
end
```

Then query them anywhere:

```ruby
game.input_source.just_pressed?(game.ui_pad, :attack)   # down edge
game.input_source.pressed?(game.ui_pad, :attack)        # held
DragonInput.axis(game.ui_pad, :pan)                     # => { x:, y:, active: }
```

`game.ui_pad` (default `:one`) is the logical pad the framework UI listens to.

**Don't pump manually.** Conjuration calls `DragonInput.tick` once per frame
inside `Game#tick`. The pump is gated on `DragonInput.config`, so a game that
never uses input pays a nil check per tick.

For analog *movement*, raw DragonRuby composites are often the better read:
`inputs.left_right` and `inputs.up_down` keep the stick analog and the arrows
live at once, where a digital binding is a single key.

## The reserved `:ui_*` actions

Menus need input before your game has configured any. Conjuration reserves six
action names and injects them:

| Action | Controller | Keyboard |
| --- | --- | --- |
| `:ui_confirm` | `a` | `enter` |
| `:ui_up` / `:ui_down` | `dpad_up` / `dpad_down` | `up` / `down` |
| `:ui_left` / `:ui_right` | `dpad_left` / `dpad_right` | `left` / `right` |
| `:ui_navigate` (analog) | `right_analog` | — |

Space is deliberately unbound: games commonly use it, and confirming on it would
double-fire.

**Injection fills gaps only.** The reserved actions are added to every action
set that lacks them, so a set that already binds `:ui_confirm` keeps its own
binding and your rebinds always win. Injection happens at *query* time, not load
time, so your own `DragonInput.setup` — whenever it runs — takes precedence; and
if a set is rebuilt later, the next query notices and re-injects.

`:ui_navigate` is the right stick, read with flick semantics: one step per
neutral-to-deflected crossing, with hysteresis (engage at 0.5, re-arm below
0.35) so a stick resting near the edge can't chatter. The digital directions
handle [hold-to-repeat](ui.md#hold-to-repeat) instead.

Node `shortcut:` declarations get the same treatment: each is injected as
`:ui_shortcut_<node id>`, gaps-only, so a game can rebind an accelerator like any
other action. See [ui.md](ui.md#shortcuts).

## The action-query contract

The framework never touches `inputs.keyboard` for UI. It goes through
`game.input_source`, and the whole contract is two methods:

```ruby
just_pressed?(pad, action)   # down edge this frame
pressed?(pad, action)        # held (or newly down)
```

Two more are optional and feature-detected: `navigation_flick(pad)` (the right
stick step) and `shortcut_just_pressed?(pad, name, bindings)`. A source that
implements neither simply doesn't get those features.

Assign your own source to bypass dragon_input entirely — the seam that makes
menu behaviour testable without a device:

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

The default is `Conjuration::DragonInputSource`, which wraps dragon_input and
adds the injection and flick handling above. Assigning your own replaces it for
good — there is no fallback back to the default.

## Glyphs

Prompts should show the button the player will actually press, on the device they
are actually holding. dragon_input resolves both:

```ruby
DragonInput.glyph_style(pad)      # => :keyboard, or a controller art style
DragonInput.glyph(pad, action)    # => sprite path for that action, or nil
```

`glyph` is **action-based**: ask for `:ui_confirm` and you get the key or button
currently bound to it, including after a remap. It follows the last-used device,
so a prompt swaps art the moment the player picks up a pad.

Because the art is a white silhouette, tint it to match your UI. And because the
style is a scalar, it makes a perfect memo key — a prompt rebuilds only when the
device changes:

```ruby
def press_prompt
  memo(:press_prompt, DragonInput.glyph_style(game.ui_pad)) do
    node({ x: grid.w / 2, y: 200, w: 48, h: 48, anchor_x: 0.5,
           path: DragonInput.glyph(game.ui_pad, :ui_confirm), r: 240, g: 240, b: 240 }, id: :confirm_glyph)
  end
end
```

A nil glyph means there's no art for that binding — draw a text chip as the
fallback rather than an empty sprite. The demo's `PromptView` and
`ShortcutBadgeView` show both paths, including probing the raw button art when
an accelerator names a button rather than an action.

## Which device is the player using?

`inputs.last_active` is DragonRuby's own answer, and the framework leans on it in
two places: navigation input is only read when it isn't `:mouse`, and the focus
ring is hidden (but retained) while the mouse is active. Follow the same rule in
your own focus visuals:

```ruby
def focus_visible?
  Conjuration::UI.focused_node.equal?(my_node) && $game.inputs.last_active != :mouse
end
```

A device *change* is worth announcing. The demo polls `DragonInput.glyph_style`
each frame, buckets it into keyboard vs. controller, ignores the first
observation (that's just startup, not a switch), and on a change shows a toast
that holds for 40 ticks then fades over 80 — all keyed to `game.clock`, so it
freezes with the game.

## See also

- [ui.md](ui.md#navigation) — what the reserved actions actually drive.
- [time.md](time.md#sequences) — `sequence_confirm?`, the confirm seam for
  cutscenes.
