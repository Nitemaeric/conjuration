require_relative "scenes/menu_scene"
require_relative "device_toast"

class Game < Conjuration::Game
  def setup
    # No ui_* actions here on purpose: Conjuration injects them on the first menu
    # query, so navigation works without the game wiring them.
    DragonInput.setup do |c|
      c.action_set :gameplay do |s|
        s.digital :attack, controller: :b, keyboard: :space
        s.digital :start, controller: :start, keyboard: :enter
      end
    end

    Conjuration::UI.default_cursor = ["sprites/cursor-none.png", 9, 4]
    Conjuration::UI.hover_cursor = ["sprites/hand-point.png", 6, 4]

    @device_toast = DeviceToast.new
    self.current_scene = MenuScene.new(:main)
  end

  def update
    @device_toast.poll(DragonInput.glyph_style(ui_pad), clock)
  end

  def input
    if inputs.keyboard.key_held?(:meta) && inputs.keyboard.key_up?(:d)
      self.debug = !debug
    end
  end

  def render
    outputs.background_color = [0, 0, 0]

    @device_toast.draw(outputs, clock)

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
