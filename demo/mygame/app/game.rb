require_relative "scenes/menu_scene"

class Game < Conjuration::Game
  def setup
    self.current_scene = MenuScene.new(:main)
  end

  def input
    if inputs.keyboard.key_held?(:meta) && inputs.keyboard.key_up?(:d)
      self.debug = !debug
    end
  end

  def render
    outputs.background_color = [0, 0, 0]

    if debug?
      outputs.primitives << {
        x: 5.from_right,
        y: 5.from_top,
        text: gtk.current_framerate.to_s,
        anchor_x: 1,
        anchor_y: 1
      }
    end
  end
end
