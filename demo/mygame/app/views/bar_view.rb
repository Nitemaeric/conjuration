# A view component for one progress-bar row. Invoked as BarView(item:, on_remove:)
# from a scene's view; #call emits the row's nodes and clicking the row calls
# back into the scene via the on_remove prop. The row sizes to its content
# (label + gap + full bar) so its click target matches the bar's extent.
#
# Note: direction/align/gap/justify are node KEYWORDS (outside the object hash);
# geometry and render props (w, h, path, text, colours, action) go inside it.
class BarView < Conjuration::UI::View
  BAR_MAX = 340
  LABEL_WIDTH = 48
  GAP = 12

  def initialize(item:, on_remove:)
    @item = item
    @on_remove = on_remove
  end

  def call
    id = @item[:id]
    progress = @item[:progress]
    remove = @on_remove

    node({ w: LABEL_WIDTH + GAP + BAR_MAX, h: 26, action: -> { remove.call(id) } }, id: "row_#{id}", direction: :row, gap: GAP, align: :center) do
      node({ w: LABEL_WIDTH, h: 26 }, id: "pct_#{id}", justify: :center, align: :center) do
        node({ text: "#{progress.to_i}%", r: 210, g: 210, b: 220 })
      end
      # Factors needn't sum to 1: progress vs its remainder splits the track.
      node({ w: BAR_MAX, h: 18 }, id: "track_#{id}", direction: :row) do
        node({ w: 0, h: 18, path: :pixel, r: 120, g: 200, b: 120 }, id: "fill_#{id}", grow: progress)
        node({ h: 18 }, id: "space_#{id}", grow: 100 - progress)
      end
    end
  end
end
