require "app/views/shortcut_badge_view.rb"

# A reusable sprite button with a centred label. Invoked as
# ButtonView(id:, label:, action:); nest it inside a `group:` container to make
# it keyboard/pad-navigable (the group is inherited from the nearest ancestor).
# A shortcut: fires the action from anywhere and shows a corner glyph badge.
class ButtonView < Conjuration::UI::View
  HEIGHT = 44

  def initialize(id:, label:, action:, width: 100, shortcut: nil, pad: nil)
    @id = id
    @label = label
    @action = action
    @width = width
    @shortcut = shortcut
    @pad = pad
  end

  def call
    node({ w: @width, h: HEIGHT, path: "sprites/button.png", action: @action }, id: @id, justify: :center, align: :center, shortcut: @shortcut) do
      node({ text: @label, r: 255, g: 255, b: 255 }, id: "#{@id}_label")
      ShortcutBadgeView(id: :"#{@id}_badge", shortcut: @shortcut, height: HEIGHT, pad: @pad || $game.ui_pad)
    end
  end
end
