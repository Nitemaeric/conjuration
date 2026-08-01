# A LOWREZJAM-style scene: everything below is authored in 64x64 canvas pixels
# — camera viewport, world units, HUD layout, hit-testing — and the framework
# blits the finished frame to the window at an 11x integer zoom, letterboxed.
# The rest of the demo stays at native resolution, so opening this scene is also
# a cross-resolution transition.
#
# DragonRuby ships tiny.ttf at the engine root for exactly this — a pixel font
# whose native size is 10px, crisp only at multiples of 10 (see DR's lowrez_labels sample — scale with the canvas).
class LowrezScene < Conjuration::Scene
  canvas w: 64, h: 64

  WORLD = 128
  TILE = 16
  PLAYER = 4
  HUD_TEXT = 10

  FLOOR = [{ r: 38, g: 42, b: 58 }, { r: 30, g: 34, b: 48 }].freeze

  def setup
    self.virtual_w = WORLD
    self.virtual_h = WORLD

    state.player ||= { x: WORLD / 2, y: WORLD / 2, w: PLAYER, h: PLAYER }

    # No dimensions passed: the camera defaults to the canvas, not the window.
    add_camera(:main, speed: 1).follow(state.player)

    activate_navigation(:hud)
  end

  def update
    angle = clock * 0.015
    state.player[:x] = WORLD / 2 + Math.sin(angle) * 44
    state.player[:y] = WORLD / 2 + Math.sin(angle * 2) * 28
  end

  def draw_world(camera)
    tiles_per_side = WORLD / TILE
    tiles_per_side.to_i.times do |column|
      tiles_per_side.to_i.times do |row|
        camera.draw({
          x: column * TILE,
          y: row * TILE,
          w: TILE,
          h: TILE,
          path: :pixel,
          **FLOOR[(column + row) % 2]
        })
      end
    end

    player = state.player
    camera.draw({ **player, path: :pixel, r: 240, g: 196, b: 92 })
    camera.draw({ x: player[:x], y: player[:y] + PLAYER, w: PLAYER, h: 1, path: :pixel, r: 255, g: 240, b: 200 })
  end

  def view
    # y positions the 10px em box, whose glyphs carry ~2px top bearing — box top
    # flush with the canvas top reads as the intended 2px visual inset.
    node({ x: 2, y: 64, anchor_y: 1, text: position_label, size_px: HUD_TEXT, font: "fonts/tiny.ttf", r: 226, g: 226, b: 236 }, id: :hud_label)

    back_button
  end

  private

  def position_label
    "#{state.player[:x].to_i},#{state.player[:y].to_i}"
  end

  # Sized to hug the label: "Back" renders ~15x7 visual px in tiny.ttf at 10, so
  # 21x11 gives ~3px horizontal / ~2px vertical padding around the glyphs. Hover
  # and focus are plain fill swaps; a focus ring would swallow the button.
  def back_button
    tint = highlighted? ? { r: 236, g: 232, b: 220 } : { r: 150, g: 148, b: 160 }

    node({ x: 2, y: 2, w: 21, h: 11, path: :pixel, action: -> { change_scene(to: MenuScene.new(:main), transition: FadeTransition.new) }, **tint },
         id: :back, group: :hud, justify: :center, align: :center, overflow: :visible,
         shortcut: { keyboard: :escape, controller: :b }) do
      node({ text: "Back", size_px: HUD_TEXT, font: "fonts/tiny.ttf", r: 24, g: 22, b: 30 }, id: :back_label)
    end
  end

  def highlighted?
    [Conjuration::UI.hovered_node, Conjuration::UI.focused_node].any? { |node| node && node.id == :back }
  end
end
