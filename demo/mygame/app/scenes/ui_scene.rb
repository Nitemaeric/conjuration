class UIScene < Conjuration::Scene
  TILE_SIZE = 40

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    add_camera(:main)

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

    ui.node({ x: 20, y: 20.from_top, anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    ui.node({ x: 5, y: grid.h / 2, w: 240, h: grid.h - 200, anchor_y: 0.5, path: "sprites/sidebar-container-background.png", r: 222, g: 222, b: 222 }, id: :party, justify: :center, align: :stretch, padding: 20, gap: 20) do
      node({ primitive_marker: :border, h: 200 }, id: :section_1, padding: 20) do
        node({ text: "Hello, World!" }, id: :sub_section_1)
      end

      node({ h: 20 }, id: :section_2, align: :end) do
        node({ text: "Hello, World!" })
      end

      node({ path: "sprites/button.png", h: 50, action: -> { puts "Button clicked!" } }, id: :button, align: :center, padding: 15) do
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
      gap: 20
    ) do
      8.times do |i|
        node({
          path: "sprites/skill-background.png",
          w: 50,
          h: 50,
          action: -> { ui.find(:skills).interactive_nodes.each { |node| node.object.path = "sprites/skill-background.png" }; ui.find("skill_#{i + 1}").object.path = "sprites/selected-skill-background.png" }
        }, id: "skill_#{i + 1}")
      end
    end

    ui.node({ x: grid.w, y: grid.h, path: :pixel, w: 700, h: 60, r: 0, g: 0, b: 0 }, id: :tooltip, padding: 20) do
      node({ text: "Clicking this button will print 'Button clicked!' to the console.", r: 255, g: 255, b: 255 })
    end
  end

  def update
    ui.find(:party).object.w = 240 + Math.sin(Kernel.tick_count.to_radians * 2) * 40
    ui.find(:party).calculate_layout

    tooltip = ui.find(:tooltip)
    tooltip.x, tooltip.y = inputs.mouse.x + 20, inputs.mouse.y + 20
    tooltip.visible = inputs.mouse.inside_rect?(ui.find(:button).object)
    tooltip.calculate_layout
  end
end
