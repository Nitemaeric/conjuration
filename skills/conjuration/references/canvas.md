# Canvas (virtual resolution)

Full guide: `docs/canvas.md`. This is the API and the traps.

## Declaration

```ruby
game.canvas = { w: 64, h: 64 }                        # game-level default
game.canvas = { w: 320, h: 180, integer_scale: false }  # max fractional fit

class BattleScene < Conjuration::Scene
  canvas w: 64, h: 64                                  # scene override, wins
end
```

Resolution chain: scene's declaration, else the game's, else native 1280x720
(byte-identical to no canvas at all). Fixed per scene instance — declared,
never mutated; a "resolution change" is a scene swap. Different resolutions
across scenes are fine; transitions composite the letterboxed frames in
window space, so cross-resolution handovers need nothing special.

`integer_scale: true` (default) floors the zoom to whole pixels: 64x64 in a
1280x720 window renders 11x as 704x704, letterboxed. `false` fills the max
fractional fit.

## What follows the canvas

Everything scene-space, automatically: scene w/h, UI layout and hit-testing,
navigation, cameras and their viewports, transition snapshots, and the mouse
(framework consumers read a canvas-space mouse; letterbox-bar points map
outside the canvas and can never phantom-hover). Author all scene geometry in
canvas pixels.

Window-space, deliberately: `outputs.debug`, the game debug panel and its
drag, the inspector's hover readout. The inspector's interleaved bounds ride
the primitive stream and scale with the canvas.

## Crisp pixels checklist

- `metadata/game_metadata.txt`: `scale_quality=3` and `highdpi=true`. Without
  them the upscale — or macOS itself — blurs the whole frame.
- Text: copy DragonRuby's bundled tiny.ttf into `mygame/fonts/` and reference
  `font: "fonts/tiny.ttf"` BY GAME PATH. A missing font path falls back to
  the default font silently, which presents as "blurry pixel font", not as an
  error. tiny.ttf is crisp only at `size_px` multiples of 10.
- Integer positions only. Flow centering can resolve to half pixels, and any
  fractional position rasterizes as antialiased mush at canvas scale — pin
  text with `position: :absolute, left:/top:` in canvas scenes. A TTF label's
  box is its em box, not its ink: tiny.ttf carries ~2px top bearing, so tight
  vertical fits use negative `top:` overhang to place the ink.
- At 64x64, 10px glyphs are a sixth of the screen — the authentic lowrez
  look. Smaller text means shipping a 3x5/4x6 bitmap font.

## Demo

`demo/mygame/app/scenes/lowrez_scene.rb` — scene-level 64x64 with camera
follow, HUD, an ink-fitted button, and a cross-resolution fade from the
native-res menu. Start a LOWREZJAM-style game from it.
