class UIScene < Conjuration::Scene
  TILE_SIZE = 40

  attr_reader :party, :skills, :minimap

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    add_camera(:main, x: 0, y: 0)

    state.cells = []

    (grid.w / TILE_SIZE).to_i.times do |column|
      (grid.h / TILE_SIZE).to_i.times do |row|
        state.cells << {
          x: column * TILE_SIZE,
          y: row * TILE_SIZE,
          w: TILE_SIZE,
          h: TILE_SIZE,
          r: (column + row) % 2 == 0 ? 93 : 83,
          g: (column + row) % 2 == 0 ? 95 : 85,
          b: (column + row) % 2 == 0 ? 99 : 89,
          path: :pixel
        }
      end
    end
  end

  def update
    @party = Conjuration::UI.build({ id: "root", **grid.rect, w: 240 + Math.sin(Kernel.tick_count.to_radians * 2)* 50, y: grid.h / 2, h: grid.h - 200, anchor_y: 0.5, primitive_marker: :border }, padding: 20, gap: 20) do
      node({ id: "section_1", primitive_marker: :border, h: 200 }, padding: 20) do
        node({
          id: "sub_section_1",
          text: "Hello, World!",
          primitive_marker: :label,
          r: 255,
          g: 255,
          b: 255,
          w: 100,
          h: 20
        })
      end

      node({
        id: "section_2",
        text: "Hello, World!",
        primitive_marker: :label,
        r: 255,
        g: 255,
        b: 255,
        w: 100,
        h: 20
      })

      node({
        id: "button",
        path: "sprites/button.png",
        primitive_marker: :sprite,
        h: 50
      }, alignment: :center, padding: 15) do
        node({
          id: "label",
          text: "Click me!",
          primitive_marker: :label,
          r: 255,
          g: 255,
          b: 255,
          w: gtk.calcstringbox("Click me!")[0]
        })
      end
    end

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
  end

  def render
    outputs.primitives << state.cells

    outputs.primitives << party.primitives
    # outputs.primitives << skills.primitives
    # outputs.primitives << minimap.primitives

    if debug?
      [*party.primitives, *skills.primitives, *minimap.primitives].each do |rect|
        outputs.debug << rect.to_s
      end
    end
  end
end
