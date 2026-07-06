# A reusable sprite button with a centred label. Invoked as
# ButtonView(id:, label:, action:); nest it inside a `group:` container to make
# it keyboard/pad-navigable (the group is inherited from the nearest ancestor).
class ButtonView < Conjuration::UI::View
  def initialize(id:, label:, action:, width: 100)
    @id = id
    @label = label
    @action = action
    @width = width
  end

  def call
    node({ w: @width, h: 44, path: "sprites/button.png", action: @action }, id: @id, justify: :center, align: :center) do
      node({ text: @label, r: 255, g: 255, b: 255 }, id: "#{@id}_label")
    end
  end
end
