# Headless testing reference

**Never launch the DragonRuby window to verify.** `drenv run` and `dragonruby`
open a window on someone's desktop. A GUI pass is the human's job; yours is
headless.

Everything except pixels is testable without the engine. DragonRuby's mruby is
open source (`DragonRuby/mruby-patched`, MIT) — the exact language runtime DR
ships, minus the proprietary GTK engine. Build it once, shim the DR surface,
preload the framework, and drive scenes by hand.

Conjuration's own `script/test.sh` + `test/support/` is the reference
implementation of everything below.

## The interpreter

Clone `https://github.com/DragonRuby/mruby-patched` at a pinned SHA, build with
`MRUBY_CONFIG=default rake`, and copy `build/host/bin/mruby`. The stock default
gembox pulls what the framework needs (enum-ext, numeric-ext, struct, metaprog).

Pin the SHA. The runtime is part of your test contract.

## Preload order

The standalone `mruby` CLI has **no `require` / `require_relative`** — DragonRuby
provides those in its engine. So preload every file with `-r`, in dependency
order, and never load the vendored `conjuration.rb` entrypoint itself (its
`require_relative`s would raise).

```bash
VENDOR=mygame/vendor/conjuration

preload=(
  test/support/shims.rb          # DR surface: Kernel.tick_count, AttrGTK, Hash-as-object, Geometry
  test/support/dragon_input.rb   # the DragonInput constant — lib touches it
  $VENDOR/conjuration/extensions/hash.rb
  $VENDOR/conjuration/extensions/array.rb
  $VENDOR/conjuration/base_lifecycle_methods.rb
  $VENDOR/conjuration/node.rb
  $VENDOR/conjuration/vector.rb
  $VENDOR/conjuration/input_source.rb
  $VENDOR/conjuration/ui/reconciler.rb
  $VENDOR/conjuration/ui/navigation.rb
  $VENDOR/conjuration/ui/layout.rb
  $VENDOR/conjuration/ui/text.rb
  $VENDOR/conjuration/ui/scroll.rb
  $VENDOR/conjuration/ui/view.rb
  $VENDOR/conjuration/ui/node.rb
  $VENDOR/conjuration/ui/inspector.rb
  $VENDOR/conjuration/ui_management.rb
  $VENDOR/conjuration/camera.rb
  $VENDOR/conjuration/camera_management.rb
  $VENDOR/conjuration/tile_layer.rb
  $VENDOR/conjuration/projection.rb
  $VENDOR/conjuration/scheduler.rb
  $VENDOR/conjuration/animation.rb
  $VENDOR/conjuration/sequence.rb
  $VENDOR/conjuration/scene.rb
  $VENDOR/conjuration/scene_management.rb
  $VENDOR/conjuration/game.rb
  test/support/doubles.rb        # $game, GridDouble, GtkDouble, OutputsDouble, Assert
  # then your own game files, then each test/*_test.rb
)

args=()
for file in "${preload[@]}"; do args+=(-r "$file"); done
exec tmp/mruby/bin/mruby "${args[@]}" test/run.rb
```

Mirror the order of the framework's `lib/conjuration.rb` (and `lib/conjuration/ui.rb`
for the `ui/*` block) whenever you re-derive this list — that file is the source of
truth for load order.

Your own game files load after the doubles. mruby has no `Kernel#require`, so
stub it (`def require(_path); end`) and let `-r` do the work.

## Shims — the DragonRuby surface

The three that matter, all in `test/support/shims.rb`:

1. **`Kernel.tick_count`** as a plain settable counter. DR's never stops (that is
   the point — UI key-repeat keeps timing while a scene is paused), so tests
   advance it by hand: `Kernel.tick_count = 30`.
2. **Hash-as-object** — DragonRuby exposes hash values as methods (`h.x` reads
   `h[:x]`, `h.x = v` writes it), via `method_missing` + `respond_to_missing?`.
   The framework leans on this everywhere: rects, primitives, the `object` a
   `UI::Node` wraps.
3. **`Geometry`** — `intersect_rect?`, `find_intersect_rect`, `vec2_normalize`.
   The first two are native (C) in DR with no Ruby source to vendor, so they are
   reimplemented as plain AABB overlap.

`AttrGTK` (an `args` accessor plus `outputs`) is needed because `game.rb` does
`include AttrGTK` at load time.

**The `extensions/hash` caveat.** `Hash#left/right/top/bottom/center` are
Conjuration's, in `extensions/hash.rb`. If a probe script loads the shims but
forgets that file, `method_missing` answers `rect.right` with `self[:right]` —
`nil` — instead of the computed edge. Nothing raises; the geometry is just
silently wrong. **Always load `extensions/hash.rb` first**, in a one-off probe as
much as in the suite.

## Doubles

`$game` is a global (`Conjuration::Node#game` returns `$game`), so a `GameDouble`
answering `grid`, `gtk`, `outputs`, `render_output`, `events`, `state`, `audio`,
`debug?`, `inputs`, `input_source`, `ui_pad` is the whole seam.

- **`GtkDouble#calcstringbox(text, *)`** must be deterministic and
  font-independent — `[text.to_s.length * 8, 22]` — or text layout isn't
  reproducible. `read_file` returning nil makes every art probe miss, which
  exercises the fallback paths; return a string to exercise the hit paths.
- **`OutputsDouble#[](name)`** vends `RenderTargetDouble`s so scroll panes and
  camera viewports have somewhere to render.
- **`inputs`** is just a Hash — the Hash-as-object shim makes
  `inputs.mouse.click` work:

  ```ruby
  $game.inputs = {
    last_active: :controller,
    mouse: { x: -100, y: -100, w: 1, h: 1, wheel: nil, click: false, held: false },
    keyboard: { key_down: { tab: nil } },
    controller_one: { key_down: { r1: nil }, right_analog_y_perc: 0 }
  }
  ```

- **A scripted input source** is the cleanest way to drive menus — implement
  `just_pressed?(pad, action)` / `pressed?(pad, action)` (plus
  `shortcut_just_pressed?` if you test accelerators) and assign it to
  `$game.input_source`. See [input.md](input.md).

## Driving a scene

The lifecycle methods are private, but mruby does not enforce visibility on an
explicit receiver; use `send` anyway so the intent is obvious.

```ruby
def test_pause_freezes_the_clock(args, assert)
  scene = PlayScene.new(:test)
  $game.current_scene = scene
  scene.send(:perform_setup)

  $game.input_source = ScriptedInput.new(edges: [:attack])
  scene.send(:perform_input)
  scene.send(:perform_update)

  assert.true!(scene.state[:paused], "attack toggles pause")

  before = scene.clock
  10.times { scene.send(:perform_update) }
  assert.equal!(scene.state[:hero][:x], hero_x_before, "a paused scene doesn't simulate")
ensure
  $game.input_source = nil
  $game.inputs = nil
end
```

For a UI-only assertion you don't need a scene at all:

```ruby
ui = Conjuration::UI.build({ x: 0, y: 0, w: 1280, h: 720 }, id: :root)
ui.view { my_view }
ui.render_view
ui.calculate_layout

assert.equal!(ui.find(:fill).object.w, 120)
```

`Conjuration::UI.render_component(BadgeView, label: "gold", count: 2)` renders one
component to descriptors with no scene involved.

Assert on `Conjuration::UI.warnings` (a bounded ring) rather than parsing stdout —
that is how the suite catches a justified node whose main-axis size never resolved.

## Discipline

- **Reset globals in `ensure`.** `UI.focused_node`, `UI.hovered_node`,
  `UI.active_navigation_group`, `$game.inputs`, `$game.input_source`,
  `DragonInput.reset!`. They are process-wide; a leak makes an unrelated test fail
  later and much more confusingly.
- **Test files are flat.** Each defines top-level `def test_*(args, assert)`; the
  runner discovers them via `private_methods` and runs each. That is DragonRuby's
  own `--test` signature, so the same files run under `dragonruby --test` — as long
  as you stick to DR's assertion surface (`equal! true! false! not_equal! nil! ok!`).
  `close!` and `raises!` are harness-only extensions.
- **The harness is not CRuby and not quite DR.** It has no `Dir` and no `Regexp`
  (DragonRuby itself has Regexp), so harness-side helpers must scan strings by
  hand. See the mruby landmines in `SKILL.md`.

## What is still the human's job

Pixel-accurate appearance, font metrics, real controller behaviour, audio,
performance under load, and anything requiring a window. Report what you verified
headlessly and say plainly that the visual pass is outstanding.
