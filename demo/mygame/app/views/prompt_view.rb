# A device-aware input prompt row: keycap glyph(s) for the named keyboard keys,
# or the controller equivalent's glyph, followed by a short label. Each prompt
# names both sides explicitly (keys: for keyboard, controller: for the pad) —
# there's no reliable keyboard->controller inference to lean on.
#
#   PromptView(id: :walk, keys: [:a, :d], controller: :left_analog, label: "walk", pad: pad)
#
# Keyed on DragonInput.glyph_style so only a device switch re-derives the art;
# an unchanged style reuses last frame's subtree (see #call's memo).
class PromptView < Conjuration::UI::View
  GLYPH = 24

  # Reuses DragonInput's own glyph roots and per-file probe to resolve a
  # <style>/<button>.png sprite. The library exposes only the action-level
  # DragonInput.glyph, so key-level lookup is rebuilt here; coupled to Glyphs'
  # root constants, which it references directly to stay in sync.
  module Glyphs
    ROOTS = [DragonInput::Glyphs::LOCAL_ROOT, DragonInput::Glyphs::VENDORED_ROOT].freeze

    def self.path(style, button)
      rel = "#{style}/#{button}.png"
      root = ROOTS.find { |r| $gtk.read_file("#{r}/#{rel}") }
      root && "#{root}/#{rel}"
    end
  end

  # color tints the white-silhouette glyph art (and the label) so it reads on the
  # host panel: dark on a light panel, white over the gameplay view.
  def initialize(id:, keys:, controller:, label:, pad:, color: { r: 92, g: 62, b: 30 })
    @id = id
    @keys = keys
    @controller = controller
    @label = label
    @pad = pad
    @color = color
  end

  def call
    style = DragonInput.glyph_style(@pad)

    memo(@id, style) do
      node({ h: GLYPH }, id: @id, direction: :row, align: :center, gap: 6) do
        glyphs(style).each_with_index { |(glyph_style, button), i| glyph_node("#{@id}_g#{i}", glyph_style, button) }
        node({ text: @label, r: @color[:r], g: @color[:g], b: @color[:b] }, id: "#{@id}_label")
      end
    end
  end

  private

  def glyphs(style)
    style == :keyboard ? @keys.map { |key| [:keyboard, key] } : [[style, @controller]]
  end

  def glyph_node(id, style, button)
    path = Glyphs.path(style, button)

    if path
      node({ w: GLYPH, h: GLYPH, path: path, r: @color[:r], g: @color[:g], b: @color[:b] }, id: id)
    else
      node({ w: GLYPH, h: GLYPH, path: :solid, r: @color[:r], g: @color[:g], b: @color[:b] }, id: id, justify: :center, align: :center) do
        node({ text: button.to_s.upcase, size_enum: -2, r: 245, g: 238, b: 220 }, id: "#{id}_label")
      end
    end
  end
end
