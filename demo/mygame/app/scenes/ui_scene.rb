class UIScene < Conjuration::Scene
  TILE_SIZE = 40

  # The scene owns the order panes cycle in — the framework doesn't switch groups.
  NAV_GROUPS = [:hud, :party, :skills].freeze

  def setup
    ui.node(grid.rect, id: :background, direction: :row) do
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

    ui.node({ x: 20, y: 20.from_top, anchor_y: 1 }, group: :hud) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    ui.node({ x: 5, y: grid.h / 2, w: 240, h: grid.h - 200, anchor_y: 0.5, path: "sprites/sidebar-container-background.png", r: 222, g: 222, b: 222 }, id: :party, justify: :center, align: :stretch, padding: 20, gap: 20, group: :party) do
      node({ primitive_marker: :border, h: 200 }, id: :section_1, padding: 20) do
        node({ text: "Hello, World!" }, id: :sub_section_1)
      end

      node({ h: 20 }, id: :section_2, align: :end) do
        node({ text: "Hello, World!" })
      end

      node({ path: "sprites/button.png", h: 50, action: -> { puts "Button clicked!" }, hover: { r: 220, g: 230, b: 255 }, pressed: { r: 160, g: 170, b: 210 } }, id: :button, align: :center, padding: 15) do
        node(
          {
            text: "Click me!",
            r: 255,
            g: 255,
            b: 255
          },
          id: :label
        )
      end
    end

    ui.node(
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
      gap: 20
    )

    ui.node(
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
          node({ w: 14, h: 14, path: :pixel, r: 200, g: 50, b: 50 }, position: :absolute, top: -4, right: -4) if i.zero?
        end
      end
    end

    ui.node({ x: grid.w, y: grid.h, path: :pixel, w: 700, h: 60, r: 0, g: 0, b: 0 }, id: :tooltip, padding: 20) do
      node({ text: "Clicking this button will print 'Button clicked!' to the console.", r: 255, g: 255, b: 255 })
    end

    ui.node({ x: grid.w / 2, y: 28, anchor_x: 0.5, text: "Press N to enable keyboard navigation", r: 255, g: 255, b: 255 }, id: :nav_hint)
  end

  # The game drives navigation: N toggles keyboard nav on/off, Tab cycles the
  # panes in an order this scene defines. The mouse works regardless.
  def input
    if inputs.keyboard.key_down.n || inputs.controller_one.key_down.start
      Conjuration::UI.active_navigation_group ? deactivate_navigation : activate_navigation(:skills)
    elsif Conjuration::UI.active_navigation_group && (inputs.keyboard.key_down.tab || inputs.controller_one.key_down.r1)
      current = NAV_GROUPS.index(Conjuration::UI.active_navigation_group) || -1
      activate_navigation(NAV_GROUPS[(current + 1) % NAV_GROUPS.length])
    end
  end

  def update
    party = ui.find(:party)
    party.object.w = 240 + Math.sin(Kernel.tick_count.to_radians * 2) * 40
    party.invalidate!

    button = ui.find(:button)
    tooltip = ui.find(:tooltip)
    tooltip.visible = button.focused?
    tooltip.object.merge!(x: button.rect.right + 20, y: button.rect.center.y, anchor_y: 0.5)
    tooltip.invalidate!

    group = Conjuration::UI.active_navigation_group
    hint = ui.find(:nav_hint)
    hint.text = group ? "Keyboard nav: #{group}  -  arrows move, Tab switches panes, N disables" : "Keyboard nav: OFF (mouse still works)  -  press N to enable"
    hint.invalidate!
  end
end
