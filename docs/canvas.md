# Canvas — virtual resolution

A **canvas** is a fixed virtual resolution. Declare one and the whole frame is
composed into a canvas-sized render target, then blitted to the window centred
and letterboxed — a 64x64 LOWREZJAM entry, a 320x180 pixel-art game, a fixed
480x270 handheld look.

Everything in *scene space* moves to canvas pixels with it: scene `w`/`h`,
camera viewports and their defaults, world units, HUD layout, and the mouse the
framework hit-tests with. Nothing else in your code changes.

```ruby
class LowrezScene < Conjuration::Scene
  canvas w: 64, h: 64

  def setup
    add_camera(:main).follow(state.player) # 64x64 viewport, not 1280x720
  end

  def view
    node({ x: 2, y: 2, w: 24, h: 9, path: :pixel, action: -> { back! } }, id: :back)
  end
end
```

## Declaring one

| Where | How | Scope |
| --- | --- | --- |
| Game | `game.canvas = { w: 64, h: 64 }` (in `setup`) | every scene that doesn't override it |
| Scene | `canvas w: 64, h: 64` in the class body | that scene class (and its subclasses) |

The resolution chain is **scene override > game default > nil**, and `nil` means
the native window: with no canvas anywhere the framework emits exactly the
primitive stream it always did.

A canvas is **fixed for the life of the scene**. It is declared, never mutated —
there is deliberately no API for changing resolution mid-scene. Mixed
resolutions across a game are fine (the demo's menu is native, its LowRez scene
is 64x64), including a transition between them.

### `integer_scale`

`integer_scale: true` (the default) floors the zoom to a whole number, so every
canvas pixel is an identical square block — 64x64 in a 1280x720 window scales
11x to 704x704, with 288px bars left and right and 8px top and bottom. Pass
`integer_scale: false` for the maximum fractional fit (11.25x → 720x720) when
filling the short axis matters more than pixel evenness.

The letterbox bars are just the cleared window background, so
`outputs.background_color` sets their colour.

## Coordinate spaces

Two spaces, and the split is deliberate:

- **Scene space** — the canvas. Scene/camera geometry, world content, UI nodes,
  and `game.mouse`. This is where your game lives.
- **Window space** — the real 1280x720 grid. `grid.w`/`grid.h`, `inputs.mouse`,
  and everything drawn into `outputs.debug`.

`outputs.debug` bypasses the canvas entirely (only `render_output` is
rerouted), which is what you want from debug tooling: the game-state panel and
the UI inspector's hover readout stay crisp window-space chrome at 64x64
instead of being blown up 11x. The inspector still *resolves* which node you are
hovering with the canvas mouse — the nodes live there — and the interleaved
bounds/box-model layer rides the primitive stream into the canvas target, so it
scales with the art it annotates.

### The mouse

`game.mouse` is the pointer in scene space: `(window - offset) / zoom`, floored
to the canvas pixel it lands in, with click/held/wheel delegated untouched from
the device. Without a canvas it *is* `inputs.mouse`, the same object.

Framework hit-testing (UI hover/click/wheel, camera focus, `sequence_confirm?`)
reads `game.mouse`; use it for your own picking too. Points in the letterbox
bars map outside `0...w` / `0...h`, so they can never phantom-hover an edge
pixel. `inputs.mouse` remains the raw device pointer for window-space chrome.

## Framework dimensions

`view_w` / `view_h` are the scene-space dimensions — the canvas when one
resolves, `grid.w`/`grid.h` otherwise. Use them anywhere you would have reached
for `grid.w`:

```ruby
outputs.primitives << { x: 0, y: 0, w: view_w, h: view_h, path: :pixel, r: 18, g: 16, b: 26 }
```

Keep using `grid.w`/`grid.h` for things that are genuinely about the window:
debug overlays, and anything drawn into `outputs.debug`.

## Transitions

Transitions are resolution-agnostic and need no changes. The snapshot a
transition animates is the composed **window** frame — including the letterboxed
blit — so a transition from a native-resolution menu into a 64x64 scene works
like any other: the outgoing frame is blitted at window size while the incoming
canvas composes and blits underneath it.

## Crisp pixels

The canvas blit is scaled by the engine, so the engine's sprite filtering
decides whether pixels stay square. In `metadata/game_metadata.txt`:

```
scale_quality=3
highdpi=true
```

Without `scale_quality` the upscale can smear single-pixel detail into
gradients, and without `highdpi` a retina display lets the OS blur the whole
window regardless. DragonRuby's own lowrez samples set both.

## Text

A canvas cannot fix fonts — DragonRuby's default font has no legible size at
64x64. DragonRuby ships `tiny.ttf` at the engine root: a pixel font whose
native size is 10px, crisp only at multiples of 10 (its `lowrez_labels` sample
demonstrates 10/20/30/40; anything off-multiple rasterizes as antialiased
mush). At 64x64 that means text is chunky — 10px glyphs are a sixth of the
screen, the authentic lowrez look. For smaller text, ship a 3x5/4x6 bitmap
font or draw glyphs as sprites.

## See also

- [Scenes](scenes.md) — lifecycle, the stack, transitions.
- [Cameras](cameras.md) — viewports, world space, culling.
- `demo/mygame/app/scenes/lowrez_scene.rb` — the 64x64 demo scene.
