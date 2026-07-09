require "app/views/shortcut_badge_view.rb"

# A reusable wooden sprite button with a centred label and a distinct read per
# interaction state: mouse hover brightens the face (an additive sheen — sprite
# tints can only darken), pressing dims it, and keyboard/pad focus draws corner
# brackets that breathe on the game clock, so the pulse freezes under hit-stop.
# Invoked as ButtonView(id:, label:, action:); nest it inside a `group:`
# container to make it keyboard/pad-navigable. A shortcut: fires the action
# from anywhere and shows a corner glyph badge.
class ButtonView < Conjuration::UI::View
  HEIGHT = 44
  PRESSED_TINT = { r: 170, g: 160, b: 145 }.freeze

  BRACKET_ARM = 12
  BRACKET_THICKNESS = 3
  BRACKET_REACH = 5
  BRACKET_INK = { path: :pixel, r: 245, g: 238, b: 220 }.freeze

  def initialize(id:, label:, action:, width: 100, height: HEIGHT, shortcut: nil, pad: nil)
    @id = id
    @label = label
    @action = action
    @width = width
    @height = height
    @shortcut = shortcut
    @pad = pad
  end

  # width: nil leaves the main-axis size to the parent (align: :stretch panels).
  def call
    object = { h: @height, path: "sprites/button.png", action: @action, pressed: PRESSED_TINT }
    object[:w] = @width if @width

    node(object, id: @id, justify: :center, align: :center, shortcut: @shortcut) do
      node({ text: @label, r: 255, g: 255, b: 255 }, id: "#{@id}_label")
      ShortcutBadgeView(id: :"#{@id}_badge", shortcut: @shortcut, height: @height, pad: @pad || $game.ui_pad)
      hover_sheen if targets_self?(Conjuration::UI.hovered_node)
      focus_brackets if focus_visible?
    end
  end

  private

  def targets_self?(node)
    node && node.id == @id.to_sym
  end

  # Focus visuals follow the framework rule: hidden (but retained) while the
  # mouse is the active device.
  def focus_visible?
    targets_self?(Conjuration::UI.focused_node) && $game.inputs.last_active != :mouse
  end

  def hover_sheen
    node({ path: "sprites/button.png", a: 64, blendmode_enum: 2 }, id: "#{@id}_sheen", position: :absolute, top: 0, right: 0, bottom: 0, left: 0)
  end

  # Alpha-pulsed rather than position-pulsed: alpha is a render-only prop, so
  # the breathe costs no relayout (and insets aren't reconcilable anyway).
  def focus_brackets
    glow = (195 + Math.sin($game.clock * 0.1) * 60).to_i

    { tl: [:top, :left], tr: [:top, :right], bl: [:bottom, :left], br: [:bottom, :right] }.each do |corner, (vertical, horizontal)|
      insets = { vertical => -BRACKET_REACH, horizontal => -BRACKET_REACH }
      node({ **BRACKET_INK, w: BRACKET_ARM, h: BRACKET_THICKNESS, a: glow }, id: "#{@id}_fb_#{corner}_h", position: :absolute, **insets)
      node({ **BRACKET_INK, w: BRACKET_THICKNESS, h: BRACKET_ARM, a: glow }, id: "#{@id}_fb_#{corner}_v", position: :absolute, **insets)
    end
  end
end
