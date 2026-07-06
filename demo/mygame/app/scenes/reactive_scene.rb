# A reactive scene: the HUD is declared once as `view`, a pure function of
# state, and animated purely by mutating state in `update`. There is no
# `ui.find`, no `invalidate!`, and no manual geometry write — the reconciler
# turns each frame's declaration into prop updates on the retained nodes.
class ReactiveScene < Conjuration::Scene
  BAR_COUNT = 6
  PANEL_WIDTH = 560
  BAR_MAX = 400

  def setup
    # The only state the view reads. update() mutates bar[:progress]; everything
    # the player sees is derived from it.
    state.bars = BAR_COUNT.times.map do |i|
      { id: i, rate: 18 + i * 9, progress: (i * 15) % 100 }
    end
  end

  def update
    state.bars.each do |bar|
      bar[:progress] = (bar[:progress] + bar[:rate] / 60) % 100
    end
  end

  def input
    activate_navigation(:hud) if Conjuration::UI.active_navigation_group.nil? && inputs.last_active != :mouse
  end

  # Declarative tree. Re-run every frame; the reconciler diffs it against the
  # retained nodes and only touches what changed (bar widths and percentages).
  def view
    node({ x: 20, y: 20.from_top, anchor_y: 1 }, group: :hud) do
      node({ w: 100, h: 44, path: "sprites/button.png", action: -> { change_scene(to: MenuScene.new(:main)) } }, id: :back, justify: :center, align: :center) do
        node({ text: "Back", r: 255, g: 255, b: 255 })
      end
    end

    node({ x: grid.w / 2, y: grid.h / 2, w: PANEL_WIDTH, h: 340, anchor_x: 0.5, anchor_y: 0.5, path: :pixel, r: 24, g: 26, b: 34 }, id: :panel, gap: 16, padding: 24, justify: :center) do
      node({ text: "Reactive progress bars", r: 255, g: 255, b: 255 }, id: :title)

      state.bars.each do |bar|
        node({ w: PANEL_WIDTH - 48, h: 26, direction: :row, gap: 12, align: :center }, id: "row_#{bar[:id]}") do
          node({ w: 56, h: 26, justify: :center, align: :center }, id: "pct_#{bar[:id]}") do
            node({ text: "#{bar[:progress].to_i}%", r: 210, g: 210, b: 220 })
          end
          node({ w: BAR_MAX * bar[:progress] / 100, h: 20, path: :pixel, r: 120, g: 200, b: 120 }, id: "fill_#{bar[:id]}")
        end
      end
    end
  end

  def render
    outputs.primitives << { x: grid.allscreen_x, y: grid.allscreen_y, w: grid.allscreen_w, h: grid.allscreen_h, path: :pixel, r: 30, g: 30, b: 40 }
  end
end
