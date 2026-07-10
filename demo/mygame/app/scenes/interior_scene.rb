require "app/views/button_view.rb"
require "app/transitions/fade_transition.rb"

# The "house" case for the scene stack: parallax push_scenes this over the
# overworld, so the overworld keeps its state (hero position, camera) while this
# is on top and gets it all back verbatim on pop. Opaque (covers_below?), so the
# overworld isn't drawn underneath — a different room entirely, not an overlay.
class InteriorScene < Conjuration::Scene
  def covers_below?
    true
  end

  def setup
    activate_navigation(:interior)
  end

  def view
    node({ x: grid.w / 2, y: grid.h / 2, w: 380, h: 220, anchor_x: 0.5, anchor_y: 0.5 }, id: :room, direction: :column, align: :center, justify: :center, gap: 24, group: :interior) do
      node({ text: "Inside the house", size_enum: 2, r: 245, g: 235, b: 220 }, id: :room_label)
      ButtonView(id: :exit, label: "Exit", action: -> { pop_scene(transition: FadeTransition.new) }, width: 200, height: 52, shortcut: { keyboard: :escape, controller: :b }, pad: game.ui_pad)
    end
  end

  def render
    outputs.primitives << { x: 0, y: 0, w: grid.w, h: grid.h, path: :pixel, r: 58, g: 42, b: 58 }
    # A rug of floorboards so the room reads as a distinct place, not a menu.
    8.times do |i|
      outputs.primitives << { x: 0, y: i * 90, w: grid.w, h: 4, path: :pixel, r: 40, g: 28, b: 40 }
    end
  end
end
