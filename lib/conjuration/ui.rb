module Conjuration
  module UI
    def self.build(rect, direction: :column, alignment: :start, gap: 0, padding: 0, &block)
      Node.new(rect, direction: direction, alignment: alignment, gap: gap, padding: padding, &block)
    end

    class Node < Conjuration::Node
      attr_accessor :rect, :children
      attr_accessor :direction, :alignment, :gap, :padding

      def initialize(rect, direction: :column, alignment: :start, gap: 0, padding: 0, &block)
        @rect = rect
        @children = []
        @direction = direction
        @alignment = alignment
        @gap = gap
        @padding = padding
        @ids = {}

        instance_exec(&block) if block_given?
      end

      def node(rect = {}, direction: :column, alignment: :start, gap: 0, padding: 0, &block)
        children << Node.new(rect, direction: direction, alignment: alignment, gap: gap, padding: padding, &block)
      end

      def [](id)
        @ids[id]
      end

      def calculate_layout
        # Things I need to know
        # - direction
        # - alignment
        # - gap
        # - padding
        # - prior sibling (children[index - 1])

        children.each_with_index do |child, index|
          if direction == :row
            # index 0: Left side of parent + padding
            # index i: Right side of sibling + gap
            child.rect.x = index.zero? ? rect.left + padding : children[index - 1].rect.right + gap

            # Top side of parent - padding
            child.rect.y = rect.top + padding

            child.rect.h ||= rect.h - padding * 2
            child.rect.anchor_x = 1
          elsif direction == :column
            child.rect.w ||= rect.w - padding * 2 # stretch

            # Left side of parent + padding
            child.rect.x = case alignment
                           when :start  then rect.left + padding
                           when :center then rect.left + (rect.w - child.rect.w) / 2
                           when :end    then rect.right - child.rect.w - padding
                           end

            # index 0: Top side of parent - padding
            # index i: Bottom side of sibling - gap
            child.rect.y = index.zero? ? rect.top - padding : children[index - 1].rect.bottom - gap

            child.rect.anchor_y = 1
          else
            raise "Invalid direction: #{direction}"
          end

          child.calculate_layout
        end
      end

      def primitives
        calculate_layout
        deep_children.map { |child| child.rect }.select { |rect| rect.has_key?(:primitive_marker) }
      end

      def deep_children
        [self, *children.flat_map(&:deep_children)].compact
      end

      def inspect
        if children.any?
          <<~XML
            <node id="#{id}" rect="#{{ x: rect.x, y: rect.y, w: rect.w, h: rect.h }}" direction="#{direction}" alignment="#{alignment}" gap="#{gap}" padding="#{padding}">
            #{children.map(&:inspect).join("\n").indent(1)}</node>
          XML
        else
          <<~XML
            <node id="#{id}" rect="#{{ x: rect.x, y: rect.y, w: rect.w, h: rect.h }}" direction="#{direction}" alignment="#{alignment}" gap="#{gap}" padding="#{padding}" />
          XML
        end
      end
    end
  end
end

# Container
# attributes (flexbox inspired)
# - direction: row or column
# - alignment: start, center, end, stretch, between
# - gap: space between children
# - padding: space around children

# node(children = nil, **attributes, &block)
# node([{}, {}], direction: :row)
#
# build(
#   { left: grid.left + 20, top: grid.top - 200, bottom: grid.bottom + 200, w: 200 },
#   [
#     { text: "Hello" },
#     { path: "sprites/ui.png", tile_x: 320, tile_y: 256, tile_w: 64, tile_h: 64 }
#   ],
#   gap: 10,
#   padding: 10
# )
#
# => [
#   {
#     text: "Hello",
#     x: container.left + 10,
#     y: container.top + 10,
#     w: container.w - 20,
#     h: node.h
#   },
#   {
#     path: "sprites/ui.png",
#     tile_x: 320,
#     tile_y: 256,
#     tile_w: 64,
#     tile_h: 64,
#     x: container.left + 10,
#     y: sibling.bottom + gap,
#     w: container.w - 20,
#     h: node.h
#   },
# ]
