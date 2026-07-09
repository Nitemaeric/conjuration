require_relative "menu_scene"

class TitleScene < Conjuration::Scene
  GLYPH_SIZE = 88

  def setup
    @background = { x: grid.allscreen_x, y: grid.allscreen_y, w: grid.allscreen_w, h: grid.allscreen_h, path: :pixel, r: 18, g: 20, b: 28 }

    @title = { x: grid.w / 2, y: grid.h / 2 + 150, text: "Conjuration Demo", size_enum: 6, r: 255, g: 255, b: 255, anchor_x: 0.5, anchor_y: 0.5 }

    @prompt = { x: grid.w / 2 - 12, y: grid.h / 2 - 10, text: "Press", size_enum: 5, r: 235, g: 235, b: 240, anchor_x: 1, anchor_y: 0.5 }

    @glyph_rect = { x: grid.w / 2 + 12, y: grid.h / 2 - 10 - GLYPH_SIZE / 2, w: GLYPH_SIZE, h: GLYPH_SIZE }
  end

  def input
    source = game.input_source
    pad = game.ui_pad
    return unless source.just_pressed?(pad, :start) || source.just_pressed?(pad, :ui_confirm)

    change_scene(to: MenuScene.new(:main))
  end

  def render
    outputs.primitives << @background
    outputs.primitives << @title
    outputs.primitives << @prompt

    DragonInput.render_glyph(game.args, game.ui_pad, :start, @glyph_rect)
  end
end
