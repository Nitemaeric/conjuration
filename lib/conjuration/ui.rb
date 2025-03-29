module Conjuration
  module UI
    def self.build(object_hash = nil, id: :root, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, **object, &block)
      root = Node.new(object_hash, id: id, direction: direction, justify: justify, align: align, gap: gap, padding: padding, **object, &block)
      root.calculate_layout
      root
    end

    class Node < Conjuration::Node
      attr_accessor :id, :object, :children, :descendants
      attr_accessor :justify, :direction, :align, :gap, :padding

      delegate :first, :last, to: :children

      def initialize(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, **object, &block)
        @id = id.to_sym
        @object = object_hash || object
        @children = []

        @direction = direction
        @justify = justify
        @align = align
        @gap = gap
        @padding = padding

        instance_exec(&block) if block_given?
      end

      def node(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, **object, &block)
        children << Node.new(object_hash, id: id, direction: direction, justify: justify, align: align, gap: gap, padding: padding, **object, &block)
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

        if justify == :end
          children = @children.reverse
        else
          children = @children
        end

        children.each_with_index do |child, index|
          case direction
          when :row
            calculate_row_justify(child, children, index)
            calculate_row_align(child)
          when :column
            calculate_column_justify(child, children, index)
            calculate_column_align(child)
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
            <node id="#{id}" #{object.keys.map { |key| "object-#{key}=\"#{object[key]}\"" }.join(' ')} direction="#{direction}" align="#{align}" gap="#{gap}" padding="#{padding}">
            #{children.map(&:to_xml).join("\n").indent(1)}</node>
          XML
        else
          <<~XML
            <node id="#{id}" object="#{{ x: object.x, y: object.y, w: object.w, h: object.h }}" direction="#{direction}" align="#{align}" gap="#{gap}" padding="#{padding}" />
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

      # Top to Bottom of vertical children
      def calculate_column_justify(child, children, index)
        case justify
        when :start
          child.object.anchor_y = 1
          child.object.y = index.zero? ? object.top - padding : children[index - 1].object.bottom - gap
        when :center
          child.object.anchor_y = 0.5
          child.object.y = object.center.y
          # I need to know the total height of all children
        when :end
          child.object.anchor_y = 0
          child.object.y = index.zero? ? object.bottom + padding : children[index - 1].object.top + gap
        when :between
          # I need to know the total height of all children
        when :around
          # I need to know the total height of all children
        when :evenly
          # I need to know the total height of all children
        end
      end

      # Left to Right align of vertical children
      def calculate_column_align(child)
        case align
        when :start
          child.object.anchor_x = 0
          child.object.x = object.left + padding
        when :center
          child.object.anchor_x = 0.5
          child.object.x = object.center.x
        when :end
          child.object.anchor_x = 1
          child.object.x = object.right - padding
        when :stretch
          child.object.anchor_x = 0.5
          child.object.x = object.center.x
          child.object.w = object.w - 2 * padding
        end
      end

      # Left to Right of horizontal children
      def calculate_row_justify(child, children, index)
        case justify
        when :start
          child.object.anchor_x = 0
          child.object.x = index.zero? ? object.left + padding : children[index - 1].object.right + gap
        when :center
          child.object.anchor_x = 0.5
          child.object.x = object.center.x
        when :end
          child.object.anchor_x = 1
          child.object.x = index.zero? ? object.right - padding : children[index - 1].object.left - gap
        when :between

        when :around

        end
      end

      # Top to Bottom align of horizontal children
      def calculate_row_align(child)
        case align
        when :start
          child.object.anchor_y = 1
          child.object.y = object.top - padding
        when :center
          child.object.anchor_y = 0.5
          child.object.y = object.center.y
        when :end
          child.object.anchor_y = 0
          child.object.y = object.bottom + padding
        when :stretch
          child.object.anchor_y = 0.5
          child.object.y = object.center.y
          child.object.h = object.h - 2 * padding
        end
      end
    end
  end
end
