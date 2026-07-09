# A device-aware input prompt row: one keycap glyph per DragonInput action in
# keyboard style, or a single controller glyph, followed by a short label.
#
#   PromptView(id: :walk, actions: [:move_left, :move_right], controller: :left_analog, label: "walk", pad: pad)
#   PromptView(id: :swing, action: :attack, label: "swing now", pad: pad)
#
# action: is sugar for a one-element actions: list. controller: overrides the
# pad-style art — two digital actions (A/D) collapse to one stick glyph; without
# it, controller style shows the first action's own glyph.
#
# Keyed on DragonInput.glyph_style so only a device switch re-derives the art;
# an unchanged style reuses last frame's subtree (see #call's memo).
class PromptView < Conjuration::UI::View
  GLYPH = 24
  GAP = 6

  # Wide keys, as an ink width:height ratio. Every keycap PNG is a square 64x64
  # canvas — sprite metadata reads 1:1 for all keys — but the cap drawn inside is
  # wide for these, so a square node crushes the spacebar to an illegible strip.
  # Ratios are the measured opaque bounds of the bundled art; unlisted keys
  # render square.
  KEYCAP_ASPECT = {
    "space" => 1.7, "shift" => 1.5, "tab" => 1.35, "ctrl" => 1.35,
    "control" => 1.35, "alt" => 1.35, "arrows" => 1.5
  }.freeze

  # The controller: override names a raw button, which the action-level
  # DragonInput.glyph can't resolve — probe the library's own art roots for it.
  CONTROLLER_ART_ROOTS = [DragonInput::Glyphs::LOCAL_ROOT, DragonInput::Glyphs::VENDORED_ROOT].freeze

  # color tints the white-silhouette glyph art (and the label) so it reads on the
  # host panel: dark on a light panel, white over the gameplay view.
  def initialize(id:, label:, pad:, actions: nil, action: nil, controller: nil, color: { r: 92, g: 62, b: 30 })
    @id = id
    @actions = actions || [action]
    @controller = controller
    @label = label
    @pad = pad
    @color = color
  end

  def call
    style = DragonInput.glyph_style(@pad)

    memo(@id, style) do
      glyphs = resolve_glyphs(style)
      widths = glyphs.map { |(path, _)| glyph_width(path) }
      row_w = widths.inject(0) { |sum, w| sum + w } + glyphs.length * GAP + label_width

      # The row carries its real width: hosts centre or right-align these rows,
      # and both resolve child positions from the row's own box.
      node({ w: row_w, h: GLYPH }, id: @id, direction: :row, align: :center, gap: GAP) do
        glyphs.each_with_index { |(path, name), i| glyph_node(path, widths[i], name, i) }
        node({ text: @label, r: @color[:r], g: @color[:g], b: @color[:b] }, id: :"#{@id}_label")
      end
    end
  end

  private

  # [sprite path (nil = keycap fallback), display name] per rendered glyph.
  def resolve_glyphs(style)
    if style == :keyboard
      @actions.map { |action| [DragonInput.glyph(@pad, action), action] }
    elsif @controller
      [[controller_art_path(style), @controller]]
    else
      [[DragonInput.glyph(@pad, @actions.first), @actions.first]]
    end
  end

  def controller_art_path(style)
    rel = "#{style}/#{@controller}.png"
    root = CONTROLLER_ART_ROOTS.find { |r| $gtk.read_file("#{r}/#{rel}") }
    root && "#{root}/#{rel}"
  end

  def glyph_width(path)
    button = path && path.split("/").last.sub(".png", "")
    (GLYPH * (KEYCAP_ASPECT[button] || 1)).round
  end

  def label_width
    $gtk.calcstringbox(@label)[0]
  end

  def glyph_node(path, w, name, index)
    id = :"#{@id}_g#{index}"

    if path
      node({ w: w, h: GLYPH, path: path, r: @color[:r], g: @color[:g], b: @color[:b] }, id: id)
    else
      node({ w: w, h: GLYPH, path: :solid, r: @color[:r], g: @color[:g], b: @color[:b] }, id: id, justify: :center, align: :center) do
        node({ text: name.to_s.upcase, size_enum: -2, r: 245, g: 238, b: 220 }, id: :"#{id}_label")
      end
    end
  end
end
