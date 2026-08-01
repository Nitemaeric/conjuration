---
name: conjuration
description: Building or debugging a DragonRuby GTK game that uses the Conjuration framework — scenes and the scene stack, reactive UI/HUD views, layout and menu navigation, cameras, action-based input, cutscene sequences, and headless tests. Load whenever the project vendors Conjuration (a `Conjuration::Game` / `Conjuration::Scene` subclass, `mygame/vendor/conjuration`) or the task mentions Conjuration scenes, views, `camera.draw`, `play_sequence`, or the `:ui_*` actions.
---

# Conjuration

A DragonRuby GTK framework: a scene stack with per-scene clocks, a reactive
UI/layout/navigation system, cameras, timers/tweens/sequences, and action-based
input through [dragon_input](https://github.com/Nitemaeric/dragon_input).

drenv vendors it into `mygame/vendor/` (`drenv add github:Nitemaeric/conjuration`)
and generates a bundle you require at the top of `mygame/app/main.rb`. dragon_input
comes with it — never declare that yourself.

This file is the operating brief. The framework's own `docs/` is the human
reference; `references/` here is the API detail.

## Golden rules

These are the ones priors get wrong.

1. **Key every timing to the scene's `clock`, never `Kernel.tick_count`.**
   `clock` advances only on frames the scene actually updated, so a hit stop, a
   transition, or sitting paused under a pushed scene freezes every timer, tween,
   clip, and cutscene step at once. `Kernel.tick_count` skips ahead when the
   freeze ends. `game.clock` is the same counter at game scope.
2. **Query input as actions through `game.input_source`, never `inputs.keyboard`.**
   `game.input_source.just_pressed?(game.ui_pad, :attack)` and `pressed?` are the
   whole contract — rebindable, and the seam that makes menus testable without a
   device. Raw DR composites (`inputs.left_right`, `inputs.up_down`) are still the
   right read for analog *movement*.
3. **Nothing grows unless you ask.** Layout is fixed-size-by-default: a node keeps
   the size you gave it or the size its content implies. Growth is `grow:` (a
   share of leftover main-axis space), `justify: :stretch` (main axis), or
   `align: :stretch` (cross axis). This is what keeps a HUD stable when a label's
   text changes length.
4. **Overflow scrolls by default.** A container whose content escapes its box
   becomes a scroll pane and warns once. `overflow: :clip` and `overflow: :visible`
   are opt-in — pick one deliberately rather than discovering a scrollbar.
5. **Give siblings an `id:`.** Identity is the reconcile key; without it a list
   that changes length re-matches positionally and drags scroll offset, focus, and
   measurements onto the wrong node.
6. **Node keywords live outside the object hash.** `node({ ...render data... },
   align: :center)`. A keyword inside the hash becomes inert render data (the
   framework warns).
7. **The mouse never writes focus.** It writes `UI.hovered_node`; keyboard and pad
   write `UI.focused_node`. Reaching for the mouse mid-menu must not destroy the
   selection. Never assign `focused_node` from a hover handler.
8. **Navigation is off until the game turns it on** — `activate_navigation(:group)`.
   There is no built-in group switcher; the scene owns the order panes cycle in.
9. **A pause menu is intra-scene view state, not a pushed scene.** Stop updating,
   keep rendering, branch the view. Cheaper than a push, and it's the pattern
   unless the overlay is genuinely a different place.
10. **The stack is for state-preserving swaps** — walking into a house, where the
    overworld must keep its hero position, walk cycle, and camera focal point while
    a different scene owns the screen. `push_scene`/`pop_scene`, with
    `covers_below?` when the overlay is opaque.
11. **A scene must be reconstructible from (class, name, state).** `state` is keyed
    by the scene's name on the game, so `MenuScene.new(:main)` gets the same bag
    back every time. Nothing load-bearing may live only in instance variables —
    that is the contract a save file needs. Schedules, sequences, and clocks are
    transient by design.
12. **Never launch the DragonRuby window to verify.** See [Verification](#verification).

## mruby landmines

DragonRuby's mruby is not CRuby. These fail at *runtime*, so they survive review.

- **No `Range#step`.** `(0..10).step(2)` raises `NoMethodError`. Use
  `Array.new(count) { |i| i * spacing }`.
- **No `Enumerable#sum`.** Use `inject(0) { |acc, value| acc + value }`.
- **No `defined?`.** Use `Object.const_defined?(:Foo)` or `respond_to?`.
- **Splatting empty `**kwargs` forwards a stray `{}` positional.**
  `send(name, *args, **kwargs)` with no keywords calls the target with one extra
  argument. Guard it: `kwargs.empty? ? send(name, *args) : send(name, *args, **kwargs)`.
  Conjuration's own `Node.delegate` and `Sequence::Animate` both do this.
- **Bare `module_function` does not toggle.** Methods defined after it stay
  instance-only. Use `extend self`.
- **`Integer#/` returns a Float under DragonRuby** — `1 / 2` is `0.5`, not `0`.
  Plain CRuby (if you ever run a probe under `ruby`) returns `0`. Never rely on
  either: write `(a / b).to_i` when you mean floor division.
- **Asset paths must be lowercase snake_case.** Vendored art often ships camelCase
  (Kenney packs do); rename on import or the load silently misses.
- The headless test harness has no `Dir` and no `Regexp` (DragonRuby itself has
  Regexp). Harness-side code must scan strings by hand.

## A scene that runs

`mygame/app/main.rb`:

```ruby
require "app/drenv_bundle.rb"
require_relative "game"

def boot(args)
  $game = Game.new(args)
end

def tick(args)
  $game.args = args
  $game.perform_setup if Kernel.tick_count.zero?
  $game.tick
end
```

`mygame/app/game.rb`:

```ruby
require_relative "scenes/play_scene"

class Game < Conjuration::Game
  def setup
    DragonInput.setup do |c|
      c.action_set :gameplay do |s|
        s.digital :attack, controller: :b, keyboard: :space
      end
    end

    self.current_scene = PlayScene.new(:play)
  end
end
```

`mygame/app/scenes/play_scene.rb`:

```ruby
class PlayScene < Conjuration::Scene
  def setup
    self.virtual_w = self.virtual_h = 4000
    state[:hero] ||= { x: 400, y: 300 }
    state[:paused] = false

    camera = add_camera(:main, speed: 12)
    camera.ui.group = :hud
    camera.ui.view { hud(camera) }
    camera.follow(state[:hero])

    activate_navigation(:hud)
  end

  def input
    return unless game.input_source.just_pressed?(game.ui_pad, :attack)

    state[:paused] = !state[:paused]
  end

  def update
    return if state[:paused]

    state[:hero][:x] += inputs.left_right * 4
  end

  def draw_world(camera)
    hero = state[:hero]
    camera.draw({ x: hero[:x], y: hero[:y], w: 32, h: 32, path: :pixel, r: 220, g: 200, b: 120 }, z: -hero[:y])
  end

  # A camera HUD is viewport-relative: camera.from_top, not Numeric#from_top.
  def hud(camera)
    node({ x: 20, y: camera.from_top(20), w: 240, h: 40, anchor_y: 1, path: :pixel, r: 20, g: 22, b: 30 },
         id: :panel, direction: :row, align: :center, gap: 8, padding: 8) do
      node({ text: state[:paused] ? "Paused" : "Playing", r: 240, g: 240, b: 245 }, id: :status)

      node({ w: 96, h: 24, path: :pixel, r: 60, g: 64, b: 80,
             action: -> { change_scene(to: MenuScene.new(:main)) },
             hover: { r: 90, g: 96, b: 120 } },
           id: :quit, justify: :center, align: :center) do
        node({ text: "Quit", r: 255, g: 255, b: 255 }, id: :quit_label)
      end
    end
  end
end
```

`view` on the scene is the same thing in screen space. Both are re-run every
frame and reconciled onto a retained tree — never cache nodes yourself.

## The demo is the reference implementation

`demo/mygame/app/scenes/` in the Conjuration repo. Read the one that matches the
problem rather than inventing a pattern:

| Scene | Canonical example of |
| --- | --- |
| `menu_scene.rb` | routing, transitions, name-keyed persistent state, glyph `memo` |
| `reactive_scene.rb` | the reconciler — keyed create/remove/reorder, view components |
| `ui_scene.rb` | the full layout surface: nav groups, scroll, absolute, wrap, states |
| `basic_camera_scene.rb` | pan/follow/shake, `z:` sorting, `TileLayer` |
| `parallax_scene.rb` | `parallax:` layers, `Animation` clips, `push_scene` into a door |
| `interior_scene.rb` | the pop side of the stack, `covers_below?` |
| `zoom_scene.rb` | zoom, and `load_tick` / `loading_view` cooperative loading |
| `multiple_cameras_scene.rb` | split screen, minimaps, `focused_camera` |
| `hit_stop_scene.rb` | `game.hit_stop` + `camera.shake` impact frames |
| `cutscene_scene.rb` | `play_sequence`, the typewriter `sequence_confirm?` override |
| `isometric_scene.rb` | `Projection::Isometric`, elevation picking, draw-order dumps |
| `ecs_scene.rb` | Draco ECS ticked from `update` |

`views/button_view.rb` and `views/prompt_view.rb` are the reference view
components (custom focus visuals; device-following glyphs).

## Verification

**Never run `drenv run`, `dragonruby`, or anything else that opens a window.** A
GUI pass is the human's job. Yours is headless.

Verify game logic by preloading the framework into DragonRuby's mruby interpreter
and driving scenes by hand — no engine, no window. Conjuration's own
`script/test.sh` is the pattern to copy: shims for the DragonRuby surface, doubles
for `$game`, then `-r` every lib file in dependency order, then the tests.

```
scene = PlayScene.new(:test)
scene.send(:perform_setup)
scene.send(:perform_input)      # with a scripted input_source
scene.send(:perform_update)
assert scene.ui.find(:status).object.text == "Paused"
```

Then: `ruby -c` every file you touched, and grep the framework's `lib/` for any
API name you are not certain of. See [references/testing.md](references/testing.md)
for the full driver, the doubles, and the `extensions/hash` caveat.

## With the dragonruby-* skills

The generic DragonRuby skills (Nitemaeric/dragonruby-skills) cover the engine;
this one covers the framework. In a Conjuration project they mostly compose —
use `dragonruby` for engine idioms, `dragonruby-3d`, `-audio`, `-pathfinding`,
`-platformer` for their domains, `-yard` for editor setup. Two supersessions:

- Do NOT follow `dragonruby-ui`'s widget, menu, scroll-view, or input-remapping
  patterns here. Conjuration's reactive views, layout, navigation, and
  dragon_input replace all of them; hand-rolled widgets fight the reconciler
  and the focus model.
- Do NOT follow `dragonruby-rendering`'s camera-system or lowrez patterns.
  Conjuration cameras own world/screen conversion, z-ordering, and culling;
  hand-rolled cameras bypass the deferred draw path.

## Low resolution (canvas)

Fixed low resolution comes from the framework's canvas, never a hand-rolled
render target — UI, navigation, cameras, transitions, and the mouse all follow
it automatically:

```ruby
class Game < Conjuration::Game
  def setup
    self.canvas = { w: 64, h: 64 }   # whole-game default
  end
end

class BattleScene < Conjuration::Scene
  canvas w: 64, h: 64                # per-scene override; scene wins over game
end
```

Scene-space geometry is authored in canvas pixels; the frame letterboxes into
the window (`integer_scale: true` by default). A canvas is fixed for a scene's
lifetime — declare it, never mutate it. Debug tooling stays window-space.

Low-resolution landmines (each cost a real debugging session):

- A missing `font:` path falls back to the default font SILENTLY — it looks
  like "the pixel font is blurry", not like an error. Copy DragonRuby's
  bundled tiny.ttf into `mygame/fonts/` and reference `font: "fonts/tiny.ttf"`
  by game path; never rely on engine-root resolution.
- tiny.ttf's native size is 10px and it is crisp only at multiples of 10.
- Fractional positions rasterize as antialiased mush at low resolution. Flow
  centering can land text on a half pixel — pin canvas-scene text at integer
  offsets (`position: :absolute, left:/top:`) instead.
- Set `scale_quality=3` and `highdpi=true` in `metadata/game_metadata.txt` or
  the upscale (or macOS itself) blurs everything regardless.

See [references/canvas.md](references/canvas.md) for the API detail.

## References

Open the one you need; each is signatures and semantics, not tutorial.

- [references/scenes.md](references/scenes.md) — lifecycle phases and ordering, hooks, the stack, transitions, `load_tick`.
- [references/ui.md](references/ui.md) — `node()`, the keyword table, sizing, overflow, navigation, components, `memo`.
- [references/time.md](references/time.md) — `after`/`every`/`tween`, eases, `Animation` clips, the sequence DSL.
- [references/input.md](references/input.md) — actions, the reserved `:ui_*` set, the input-source contract, glyphs.
- [references/cameras.md](references/cameras.md) — spaces and conversions, `look_at`/`follow`, `z:`, `parallax:`, shake.
- [references/testing.md](references/testing.md) — the headless harness: preload order, doubles, driving a scene.
- [references/canvas.md](references/canvas.md) — virtual resolution: declaration, scaling, mouse mapping, text at low res.
