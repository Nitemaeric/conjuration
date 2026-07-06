# A view component for one progress-bar row. Invoked as
# BarView(item:, width:, on_remove:) from a scene's view; #call emits the row's
# nodes and clicking the row calls back into the scene via the on_remove prop.
class BarView < Conjuration::UI::View
  BAR_MAX = 340

  def initialize(item:, width:, on_remove:)
    @item = item
    @width = width
    @on_remove = on_remove
  end

  def call
    id = @item[:id]
    progress = @item[:progress]
    remove = @on_remove

    node({ w: @width, h: 26, direction: :row, gap: 12, align: :center, action: -> { remove.call(id) } }, id: "row_#{id}") do
      node({ w: 48, h: 26, justify: :center, align: :center }, id: "pct_#{id}") do
        node({ text: "#{progress.to_i}%", r: 210, g: 210, b: 220 })
      end
      node({ w: BAR_MAX * progress / 100, h: 18, path: :pixel, r: 120, g: 200, b: 120 }, id: "fill_#{id}")
    end
  end
end
