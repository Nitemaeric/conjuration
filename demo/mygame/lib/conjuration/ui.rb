module Conjuration
  module UI
    def self.build(object_hash = nil, id: :root, justify: :start, direction: :column, alignment: :start, gap: 0, padding: 0, **object, &block)
      root = Node.new(object_hash, id: id, justify: justify, direction: direction, alignment: alignment, gap: gap, padding: padding, **object, &block)
      root.calculate_layout
      root
    end

    class Node < Conjuration::Node
      attr_accessor :id, :object, :children, :descendants
      attr_accessor :justify, :direction, :alignment, :gap, :padding

      delegate :first, :last, to: :children

      def initialize(object_hash = nil, id: nil, justify: :start, direction: :column, alignment: :start, gap: 0, padding: 0, **object, &block)
        @id = id.to_sym
        @object = object_hash || object
        @children = []

        @direction = direction
        @justify = justify
        @alignment = alignment
        @gap = gap
        @padding = padding

        instance_exec(&block) if block_given?
      end

      def node(object_hash = nil, id: nil, justify: :start, direction: :column, alignment: :start, gap: 0, padding: 0, **object, &block)
        children << Node.new(object_hash, id: id, justify: justify, direction: direction, alignment: alignment, gap: gap, padding: padding, **object, &block)
      end

      def find(id)
        descendants[id.to_sym]
      end

      def find_interactive_intersect(rect)
        Geometry.find_intersect_rect(rect, interactive_nodes.map(&:object))
      end

      def descendants
        @descendants ||= begin
          nodes.each_with_object({}) do |node, hash|
            hash[node.id] = node if node.id
          end
        end
      end

      def calculate_layout
        if object.has_key?(:text)
          object.w, object.h = gtk.calcstringbox(object.text)
        end

        children.each_with_index do |child, index|
          if direction == :row
            # index 0: Left side of parent + padding
            # index i: Right side of sibling + gap
            child.object.x = index.zero? ? object.left + padding : children[index - 1].object.right + gap

            # Top side of parent - padding
            child.object.y = case justify
                           when :start  then object.top + padding
                           when :center then object.top + (object.h - child.object.h) / 2
                           when :end    then object.bottom - child.object.h - padding
                           end

            child.object.h = object.h - padding * 2
            child.object.anchor_x = 1
          elsif direction == :column
            child.object.anchor_x = 0
            child.object.w = object.w - padding * 2 # stretch

            case alignment
            when :start
              child.object.y = index.zero? ? object.top - padding : children[index - 1].object.bottom - gap
              child.object.anchor_y = 1
            when :center
              child.object.y = object.center.y - (child.object.h ? child.object.h / 2 : 0)
              child.object.anchor_y = 0.5
            when :end     then object.right - child.object.w - padding
            when :stretch then object.left + padding
            when :between then object.left + padding
            end

            # index 0: Top side of parent - padding
            # index i: Bottom side of sibling - gap
            # child.object.y = index.zero? ? object.top - padding : children[index - 1].object.bottom - gap

            # child.object.anchor_y = 1

            case justify
            when :start
              child.object.x = object.left + padding
              child.object.anchor_x = 0
            when :center
              child.object.x = object.center.x
              child.object.anchor_x = 0.5
            when :end     then object.right - child.object.w - padding
            when :stretch then object.left + padding
            when :between then object.left + padding
            end
          end

          child.calculate_layout
        end
      end

      def nodes
        [self, *children.flat_map(&:nodes)].compact
      end

      def primitives
        nodes.select(&:renderable?).map(&:object)
      end

      def interactive_nodes
        nodes.select(&:interactive?)
      end

      def method_missing(method_name, *args, &block)
        if object.respond_to?(method_name, *args, &block)
          object.send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        object.respond_to?(method_name, include_private) || super
      end

      def has_key?(key)
        object.has_key?(key)
      end

      def to_s
        inspect
      end

      def inspect
        "#<#{self.class} id: #{id.inspect}, x: #{x.inspect}, y: #{y.inspect}, w: #{w.inspect}, h: #{h.inspect}, anchor_x: #{anchor_x.inspect}, anchor_y: #{anchor_y.inspect}>"
      end

      def to_xml
        if children.any?
          <<~XML
            <node id="#{id}" #{rect.keys.map { |key| "rect-#{key}=#{rect[key]}" }.join(' ')} direction="#{direction}" alignment="#{alignment}" gap="#{gap}" padding="#{padding}">
            #{children.map(&:to_xml).join("\n").indent(1)}</node>
          XML
        else
          <<~XML
            <node id="#{id}" rect="#{{ x: rect.x, y: rect.y, w: rect.w, h: rect.h }}" direction="#{direction}" alignment="#{alignment}" gap="#{gap}" padding="#{padding}" />
          XML
        end
      end

      def interactive?
        has_key?(:action)
      end

      def renderable?
        return %i[solid label sprite line border].include?(primitive_marker)
      end

      def primitive_marker
        return :sprite if has_key?(:path)
        return :label  if has_key?(:text)
        return :line   if has_key?(:x2) && has_key?(:y2)

        object.primitive_marker
      end

      private

      # def calculate_column_alignment()

      # end

      # def calculate_row_alignment()

      # end

      # def calculate_column_justify()

      # end

      # def calculate_row_justify()

      # end
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
