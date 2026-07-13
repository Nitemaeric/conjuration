# Corner glyph badge for a node that declares a `shortcut:` — the reference
# pattern for displaying shortcuts. Conjuration only injects and fires the
# action (queryable as node.shortcut_action_name); drawing it is game code.
#
#   node({ ..., action: -> { back } }, shortcut: BACK) do
#     node({ text: "Back" })
#     ShortcutBadgeView(id: :back_badge, shortcut: BACK, height: 50, pad: game.ui_pad)
#   end
#
# Device-following via glyph_style: the keyboard side shows the key's art, the
# controller side the button's, swapping live. ~40% of the host button's
# height, pinned 4px inside its bottom-right corner; a drawn keycap chip when
# no art exists. Keyed on glyph_style, so only a device switch re-derives it.
class ShortcutBadgeView < Conjuration::UI::View
  ART_ROOTS = [DragonInput::Glyphs::LOCAL_ROOT, DragonInput::Glyphs::VENDORED_ROOT].freeze
  INSET = 4

  def self.size_for(height)
    (height * 0.4).clamp(16, 40)
  end

  # The shortcut names raw buttons, so art is probed key-level from the
  # library's roots (the same approach as PromptView's controller: override).
  def self.art_path(style, button)
    rel = "#{style}/#{button}.png"
    root = ART_ROOTS.find { |candidate| $gtk.read_file("#{candidate}/#{rel}") }
    root && "#{root}/#{rel}"
  end

  def initialize(id:, shortcut:, height:, pad:)
    @id = id
    @shortcut = shortcut
    @height = height
    @pad = pad
  end

  # Emits nothing without a shortcut, so hosts (ButtonView) pass the prop
  # through unconditionally.
  def render?
    !@shortcut.nil?
  end

  def call
    style = DragonInput.glyph_style(@pad)
    button = style == :keyboard ? @shortcut[:keyboard] : @shortcut[:controller]
    return if button.nil?

    memo(@id, style, button, @height) do
      size = self.class.size_for(@height)
      path = self.class.art_path(style, button)

      if path
        node({ w: size, h: size, path: path }, id: @id, position: :absolute, right: INSET, bottom: INSET)
      else
        # overflow: :visible — a fixed decorative chip whose small centred label
        # is meant to sit inside it; it must never turn into a scroll region.
        node({ w: size, h: size, path: :solid, r: 40, g: 40, b: 48 }, id: @id, position: :absolute, right: INSET, bottom: INSET, justify: :center, align: :center, overflow: :visible) do
          node({ text: button.to_s.upcase, size_enum: -3, r: 235, g: 235, b: 240 }, id: :"#{@id}_label")
        end
      end
    end
  end
end
