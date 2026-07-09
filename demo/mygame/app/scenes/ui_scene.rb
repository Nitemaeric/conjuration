require "app/views/shortcut_badge_view.rb"

# The UI showcase, declared reactively: `view` re-derives the whole tree each
# frame (animated panel width, tooltip, nav hint included) and the reconciler
# updates the retained nodes in place — scroll offset, focus, and group
# membership survive re-renders.
class UIScene < Conjuration::Scene
  TILE_SIZE = 40

  # The scene owns the order panes cycle in — the framework doesn't switch groups.
  NAV_GROUPS = [:hud, :party, :skills, :list].freeze

  BACK_SHORTCUT = { keyboard: :escape, controller: :b }.freeze

  # Navigation turns on the moment the player uses the keyboard or pad (the mouse
  # works without it); Tab then cycles the panes in an order this scene defines.
  def input
    if Conjuration::UI.active_navigation_group.nil? && inputs.last_active != :mouse
      activate_navigation(:skills)
    elsif Conjuration::UI.active_navigation_group && (inputs.keyboard.key_down.tab || inputs.controller_one.key_down.r1)
      current = NAV_GROUPS.index(Conjuration::UI.active_navigation_group) || -1
      activate_navigation(NAV_GROUPS[(current + 1) % NAV_GROUPS.length])
    end
  end

  def view
    background
    hud_bar
    party_panel
    decoration
    skills_bar
    tooltip
    scroll_panel
    nav_hint
  end

  private

  # ~600 static nodes: memoized on a constant, so the subtree is built once and
  # the reconciler's identity short-circuit skips it every frame after.
  def background
    memo(:background, :static) do
      node(grid.rect, id: :background, direction: :row) do
        (grid.w / TILE_SIZE).to_i.times do |column|
          node({ w: TILE_SIZE }) do
            (grid.h / TILE_SIZE).to_i.times do |row|
              node({
                w: TILE_SIZE,
                h: TILE_SIZE,
                r: (column + row) % 2 == 0 ? 93 : 83,
                g: (column + row) % 2 == 0 ? 95 : 85,
                b: (column + row) % 2 == 0 ? 99 : 89,
                path: :pixel
              })
            end
          end
        end
      end
    end
  end

  def hud_bar
    node({ x: 20, y: 20.from_top, anchor_y: 1 }, id: :hud_bar, group: :hud) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) } }, id: :back, shortcut: BACK_SHORTCUT, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 }, id: :back_label)
        ShortcutBadgeView(id: :back_badge, shortcut: BACK_SHORTCUT, height: 50, pad: game.ui_pad)
      end
    end
  end

  # The width animates every frame — declared inline; the reconciler sees the
  # changed w and relayouts the subtree.
  def party_panel
    node({ x: 5, y: grid.h / 2, w: 240 + Math.sin(clock.to_radians * 2) * 40, h: grid.h - 200, anchor_y: 0.5, path: "sprites/sidebar-container-background.png", r: 222, g: 222, b: 222 }, id: :party, justify: :center, align: :stretch, padding: 20, gap: 20, group: :party) do
      node({ primitive_marker: :border, h: 200 }, id: :section_1, padding: 20, wrap: true) do
        node({ text: "Text wrapping breaks a long line onto multiple rows so it fits inside the panel." }, id: :sub_section_1)
      end

      node({ h: 20 }, id: :section_2, align: :end) do
        node({ text: "Hello, World!" }, id: :hello)
      end

      node({ path: "sprites/button.png", h: 50, action: -> { puts "Button clicked!" }, hover: { r: 220, g: 230, b: 255 }, pressed: { r: 160, g: 170, b: 210 } }, id: :button, align: :center, padding: 15) do
        node({ text: "Click me!", r: 255, g: 255, b: 255 }, id: :label)
      end
    end
  end

  def decoration
    node(
      {
        x: 20.from_right,
        y: 20.from_top,
        w: 192,
        h: 192,
        anchor_x: 1,
        anchor_y: 1,
        path: "sprites/ui.png",
        tile_x: 0,
        tile_y: 176,
        tile_w: 128,
        tile_h: 128
      },
      id: :deco,
      gap: 20
    )
  end

  def skills_bar
    memo(:skills, :static) do
      node(
        {
          x: grid.w / 2,
          y: 5,
          w: 640,
          h: 80,
          anchor_x: 0.5,
          path: "sprites/skills-container-background.png",
        },
        id: :skills,
        direction: :row,
        justify: :center,
        padding: 15,
        gap: 20,
        group: :skills
      ) do
        8.times do |i|
          node({
            path: "sprites/skill-background.png",
            w: 50,
            h: 50,
            action: -> { puts "skill #{i + 1}" },
            hover: { path: "sprites/selected-skill-background.png" },
            disabled: i == 3 ? { r: 90, g: 90, b: 90 } : nil
          }, id: "skill_#{i + 1}") do
            # Out-of-flow notification badge, pinned overhanging the slot's corner.
            node({ w: 14, h: 14, path: :pixel, r: 200, g: 50, b: 50 }, id: :notify, position: :absolute, top: -4, right: -4) if i.zero?
          end
        end
      end
    end
  end

  # Anchored to last frame's layout of the button (hidden on the very first
  # frame, before the button has a box).
  def tooltip
    button = ui.find(:button)
    shown = button ? button.hovered? || button.focused? : false

    node({ x: shown ? button.rect.right + 20 : grid.w, y: shown ? button.rect.center.y : grid.h, anchor_y: 0.5, path: :pixel, w: 700, h: 60, r: 0, g: 0, b: 0 }, id: :tooltip, visible: shown, padding: 20) do
      node({ text: "Clicking this button will print 'Button clicked!' to the console.", r: 255, g: 255, b: 255 }, id: :tooltip_text)
    end
  end

  # A fixed-height panel whose contents overflow and scroll with the wheel (or
  # the right stick once navigated to).
  def scroll_panel
    node({ x: 20.from_right, y: grid.h / 2 - 40, w: 230, h: 240, anchor_x: 1, anchor_y: 0.5, path: :pixel, r: 30, g: 34, b: 44 }, id: :scroll_list, overflow: :scroll, padding: 12, gap: 8, group: :list) do
      16.times do |i|
        node({ text: "Scrollable item #{i + 1}", r: 230, g: 230, b: 240 }, id: "item_#{i + 1}")
      end
    end
  end

  def nav_hint
    group = Conjuration::UI.active_navigation_group
    text = group ? "Keyboard nav: #{group}  -  arrows move, Tab switches panes" : "Keyboard nav: off  -  press a key or use the d-pad (mouse works too)"

    node({ x: grid.w / 2, y: 28, anchor_x: 0.5, text: text, r: 255, g: 255, b: 255 }, id: :nav_hint)
  end
end
