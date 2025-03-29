class UIScene < Conjuration::Scene
  TILE_SIZE = 40

  attr_reader :background, :tooltip, :party, :skills, :minimap

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    add_camera(:main, x: 0, y: 0)

    @background = Conjuration::UI.build(grid.rect, direction: :row) do
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

    @back_button = Conjuration::UI.build({ x: 20, y: 20.from_top, anchor_y: 1 }) do
      node({ w: 100, h: 50, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) }}, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    @tooltip = Conjuration::UI.build({ x: grid.w, y: grid.h, path: :pixel, w: 200, h: 100, r: 0, g: 0, b: 0 }, padding: 20) do
      node({ text: "Tooltip", r: 255, g: 255, b: 255 })
    end

    @party = Conjuration::UI.build({ x: 0, y: grid.h / 2, w: 240, h: grid.h - 200, anchor_y: 0.5, path: "sprites/sidebar-container-background.png", r: 222, g: 222, b: 222 }, align: :stretch) do
      node({ primitive_marker: :border, h: grid.h - 200 }, justify: :end, align: :stretch, padding: 20, gap: 20) do
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
    end
  end

  def input
    focused_button = @back_button.find_interactive_intersect(inputs.mouse) || @party.find_interactive_intersect(inputs.mouse)

    if focused_button
      gtk.set_cursor "sprites/hand-point.png", 6, 4

      instance_exec(&focused_button.action) if inputs.mouse.click
    else
      gtk.set_cursor "sprites/cursor-none.png", 9, 4
    end
  end

  def update
    @party.object.w = 240 + Math.sin(Kernel.tick_count.to_radians * 2) * 40
    @party.calculate_layout

    @skills = Conjuration::UI::Node.new(
      {
        id: "root",
        x: grid.w / 2,
        y: 0,
        w: 640,
        h: 80,
        anchor_x: 0.5,
        r: 255,
        primitive_marker: :border
      },
      direction: :row,
      gap: 20
    ) do
      node({
        primitive_marker: :solid,
        r: 255,
        g: 255,
        b: 255,
        w: 60,
        h: 60
      })

      node({
        primitive_marker: :solid,
        r: 255,
        g: 255,
        b: 255,
        w: 60,
        h: 60
      })
    end

    @minimap = Conjuration::UI::Node.new(
      {
        id: "root",
        x: 20.from_right,
        y: 20.from_top,
        w: 192,
        h: 192,
        anchor_x: 1,
        anchor_y: 1,
        r: 255,
        path: "sprites/ui.png",
        primitive_marker: :sprite,
        tile_x: 0,
        tile_y: 176,
        tile_w: 128,
        tile_h: 128
      },
      direction: :column,
      gap: 20
    )

    tooltip.x, tooltip.y = inputs.mouse.x + 20, inputs.mouse.y + 20
    if inputs.mouse.x > grid.w - tooltip.w
      tooltip.object.anchor_x = 1
    else
      tooltip.object.anchor_x = 0
    end
    tooltip.calculate_layout
  end

  def render
    outputs.primitives << background.primitives
    outputs.primitives << @back_button.primitives
    outputs.primitives << party.primitives
    outputs.primitives << tooltip.primitives
    # outputs.primitives << skills.primitives
    # outputs.primitives << minimap.primitives

    if debug?
      outputs.primitives << [*party.interactive_nodes].map do |node|
        {
          **node.object,
          r: 0,
          g: 255,
          b: 0
        }.border!
      end
    end
  end
end
