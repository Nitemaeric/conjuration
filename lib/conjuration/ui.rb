# Declarative flexbox-style UI layout, reconciliation, and navigation.
module Conjuration
  module UI
    # Build a node tree, measure all text, calculate flexbox layout, and return the root.
    #
    # @param object_hash [Hash, nil] render data (sprites, text, colors, etc.) at the root
    # @param id [Symbol] unique node identifier (default: :root)
    # @param opts [Hash] node layout keywords (see Node#initialize for all keywords)
    # @param block [Proc] nested node() calls to build children
    # @return [Node] the laid-out root node
    #
    # @see Node#initialize for keyword documentation (canonical site)
    #
    # @example Create a simple button with text label
    #   UI.build(id: :root, direction: :row, justify: :center, padding: 20, gap: 15) do
    #     node({ path: 'sprites/button.png', w: 100, h: 50, action: -> { puts 'clicked' } },
    #          id: :button, justify: :center, align: :center) do
    #       node({ text: 'Click me!', r: 255, g: 255, b: 255 }, id: :label)
    #     end
    #   end
    #
    # @example Build a scrollable panel with text items
    #   UI.build(id: :root, padding: 10) do
    #     node({ w: 300, h: 400, path: :pixel, r: 30, g: 34, b: 44 },
    #          id: :scroll_list, overflow: :scroll, gap: 8) do
    #       16.times do |i|
    #         node({ text: "Item #{i + 1}", r: 230, g: 230, b: 240 }, id: "item_#{i + 1}")
    #       end
    #     end
    #   end
    def self.build(object_hash = nil, id: :root, **opts, &block)
      root = Node.new(object_hash, id: id, **opts, &block)
      root.calculate_layout
      root
    end
  end
end

require_relative "ui/reconciler"
require_relative "ui/navigation"
require_relative "ui/layout"
require_relative "ui/text"
require_relative "ui/scroll"
require_relative "ui/view"
require_relative "ui/node"
