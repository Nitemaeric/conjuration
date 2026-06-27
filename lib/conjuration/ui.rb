module Conjuration
  module UI
    def self.build(object_hash = nil, id: :root, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, visible: true, **object, &block)
      root = Node.new(object_hash, id: id, direction: direction, justify: justify, align: align, gap: gap, padding: padding, visible: visible, **object, &block)
      root.calculate_layout
      root
    end

    def self.focused_node
      @focused_node
    end

    def self.focused_node=(node)
      @focused_node = node
    end

    def self.pressed_node
      @pressed_node
    end

    def self.pressed_node=(node)
      @pressed_node = node
    end

    # [path, hotspot_x, hotspot_y]; applied by the input loop on focus change.
    def self.hover_cursor
      @hover_cursor
    end

    def self.hover_cursor=(cursor)
      @hover_cursor = cursor
    end

    def self.default_cursor
      @default_cursor
    end

    def self.default_cursor=(cursor)
      @default_cursor = cursor
    end

    # Lerp state for the focus indicator (the highlight that trails focused_node).
    def self.focus_cursor
      @focus_cursor ||= { x: 0, y: 0, w: 0, h: 0 }
    end

    class Node < Conjuration::Node
      attr_accessor :id, :object, :children, :descendants
      attr_accessor :justify, :direction, :align, :gap, :padding, :visible
      attr_reader :focus_index

      delegate :first, :last, to: :children

      def initialize(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, visible: true, focus_index: nil, **object, &block)
        @id = id&.to_sym
        @object = object_hash || object
        @children = []

        @direction = direction
        @justify = justify
        @align = align
        @gap = gap
        @padding = padding
        @visible = visible

        # Optional explicit tab-order: nodes with one tab first (ascending), then
        # the rest in tree order — mirroring CSS tabindex.
        @focus_index = focus_index

        instance_exec(&block) if block_given?
      end

      def node(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, focus_index: nil, **object, &block)
        element = Node.new(object_hash, id: id, direction: direction, justify: justify, align: align, gap: gap, padding: padding, focus_index: focus_index, **object, &block)
        children << element
        element
      end

      def find(id)
        descendants[id.to_sym]
      end

      def intersect_rect?(rect)
        Geometry.intersect_rect?(rect, self.rect)
      end

      def find_interactive_intersect(rect)
        Geometry.find_intersect_rect(rect, interactive_nodes)
      end

      def descendants
        @descendants ||= begin
          nodes.each_with_object({}) do |node, hash|
            hash[node.id] = node if node.id
          end
        end
      end

      def calculate_layout
        # Per-pass caches for centered layouts; cleared each call so a
        # re-layout after children change size doesn't reuse stale totals.
        @children_width_with_gaps = nil
        @children_height_with_gaps = nil

        if object.has_key?(:text)
          object.w, object.h = gtk.calcstringbox(object.text)
        end

        if justify == :end
          children = @children.reverse
        else
          children = @children
        end

        children.each_with_index do |child, index|
          if id != :root
            case direction
            when :row
              calculate_row_justify(child, children, index)
              calculate_row_align(child)
            when :column
              calculate_column_justify(child, children, index)
              calculate_column_align(child)
            end
          end

          child.visible = visible
          child.calculate_layout
        end
      end

      def nodes
        [self, *children.flat_map(&:nodes)].compact
      end

      def primitives
        nodes.select(&:renderable?).map(&:styled_object)
      end

      def interactive_nodes
        nodes.select(&:interactive?)
      end

      # Interactive nodes in tab-traversal order: those with an explicit
      # focus_index first (ascending), then the rest in tree order.
      def tab_order
        indexed, unindexed = interactive_nodes.partition(&:focus_index)
        indexed.sort_by(&:focus_index) + unindexed
      end

      # The nearest interactive node within a 45-degree cone of `direction`. For
      # true row/column grids, DR's grid-based Geometry.rect_navigate is the tool;
      # it's global, so call it directly rather than wrapping it here.
      def spatial_navigate(from, direction)
        return interactive_nodes.first if from.nil?

        origin = from.rect.center
        best = nil
        best_distance = nil

        interactive_nodes.each do |node|
          next if node.equal?(from)

          centre = node.rect.center
          dx = centre.x - origin.x
          dy = centre.y - origin.y

          # Inside a 45-degree cone of the direction: the projection along it must
          # be positive and at least as large as the perpendicular offset.
          along = dx * direction.x + dy * direction.y
          next unless along > 0
          across = (dx * direction.y - dy * direction.x).abs
          next if along < across

          distance = dx * dx + dy * dy
          if best_distance.nil? || distance < best_distance
            best = node
            best_distance = distance
          end
        end

        best
      end

      def method_missing(method_name, *args, &block)
        if object.respond_to?(method_name)
          object.send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        object.respond_to?(method_name, include_private) || super
      end

      # These are required, as `Geometry.find_intersect_rect` seems to check for method definitions,
      # not if the instance responds to anchor_x and anchor_y.
      def anchor_x
        object.anchor_x
      end

      def anchor_y
        object.anchor_y
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
        visible && has_key?(:action) && !disabled?
      end

      def renderable?
        return false unless visible
        return %i[solid label sprite line border].include?(primitive_marker)
      end

      def primitive_marker
        return :sprite if has_key?(:path)
        return :label  if has_key?(:text)
        return :line   if has_key?(:x2) && has_key?(:y2)

        object.primitive_marker
      end

      def disabled?
        !!object[:disabled]
      end

      def focused?
        UI.focused_node.equal?(self)
      end

      def pressed?
        UI.pressed_node.equal?(self)
      end

      def interaction_state
        return :disabled if disabled?
        return :pressed if pressed?
        return :hover if focused?

        :default
      end

      # Nodes declare per-state style overrides as hover:/pressed:/disabled: hashes.
      def styled_object
        override = object[interaction_state]
        return object unless override.is_a?(Hash)

        { **object, **override }
      end

      private

      def calculate_column_justify(child, children, index)
        case justify
        when :start
          child.object.anchor_y = 1
          child.object.y = index.zero? ? object.top - padding_top : children[index - 1].object.bottom - gap
        when :center
          if children.count == 1
            child.object.anchor_y = 0.5
            child.object.y = object.center.y
          else
            @children_height_with_gaps ||= (children.count - 1) * gap + sum_main_size(children, :h)

            child.object.anchor_y = 1
            child.object.y = index.zero? ? object.top - object.h / 2 + @children_height_with_gaps / 2 : children[index - 1].object.bottom - gap
          end
        when :end
          child.object.anchor_y = 0
          child.object.y = index.zero? ? object.bottom + padding_bottom : children[index - 1].object.top + gap
        when :between, :around, :evenly
          inner = object.h - padding_top - padding_bottom
          free = inner - sum_main_size(children, :h)
          spacing, leading = free_space_distribution(free, children.count)

          child.object.anchor_y = 1
          child.object.y = index.zero? ? object.top - padding_top - leading : children[index - 1].object.bottom - spacing
        end
      end

      def calculate_column_align(child)
        case align
        when :start
          child.object.anchor_x = 0
          child.object.x = object.left + padding_left
        when :center
          child.object.anchor_x = 0.5
          child.object.x = object.center.x
        when :end
          child.object.anchor_x = 1
          child.object.x = object.right - padding_right
        when :stretch
          child.object.anchor_x = 0.5
          child.object.x = object.center.x
          child.object.w = object.w - padding_left - padding_right
        end
      end

      def calculate_row_justify(child, children, index)
        case justify
        when :start
          child.object.anchor_x = 0
          child.object.x = index.zero? ? object.left + padding_left : children[index - 1].object.right + gap
        when :center
          if children.count == 1
            child.object.anchor_x = 0.5
            child.object.x = object.center.x
          else
            @children_width_with_gaps ||= (children.count - 1) * gap + sum_main_size(children, :w)

            child.object.anchor_x = 0
            child.object.x = index.zero? ? object.left + object.w / 2 - @children_width_with_gaps / 2 : children[index - 1].object.right + gap
          end
        when :end
          child.object.anchor_x = 1
          child.object.x = index.zero? ? object.right - padding_right : children[index - 1].object.left - gap
        when :between, :around, :evenly
          inner = object.w - padding_left - padding_right
          free = inner - sum_main_size(children, :w)
          spacing, leading = free_space_distribution(free, children.count)

          child.object.anchor_x = 0
          child.object.x = index.zero? ? object.left + padding_left + leading : children[index - 1].object.right + spacing
        end
      end

      def calculate_row_align(child)
        case align
        when :start
          child.object.anchor_y = 1
          child.object.y = object.top - padding_top
        when :center
          child.object.anchor_y = 0.5
          child.object.y = object.center.y
        when :end
          child.object.anchor_y = 0
          child.object.y = object.bottom + padding_bottom
        when :stretch
          child.object.anchor_y = 0.5
          child.object.y = object.center.y
          child.object.h = object.h - padding_top - padding_bottom
        end
      end

      def free_space_distribution(free, count)
        case justify
        when :between then [count > 1 ? free / (count - 1) : 0, 0]
        when :around
          spacing = free / count
          [spacing, spacing / 2]
        when :evenly
          spacing = free / (count + 1)
          [spacing, spacing]
        end
      end

      # Folded explicitly: the mruby build the tests run under has no Enumerable#sum.
      def sum_main_size(children, axis)
        children.inject(0) { |total, child| total + child.object[axis] }
      end

      def normalized_padding
        case padding
        when Array then { left: padding[0], right: padding[0], top: padding[1], bottom: padding[1] }
        when Hash  then { left: padding[:left] || 0, right: padding[:right] || 0, top: padding[:top] || 0, bottom: padding[:bottom] || 0 }
        else            { left: padding, right: padding, top: padding, bottom: padding }
        end
      end

      def padding_left
        normalized_padding[:left]
      end

      def padding_right
        normalized_padding[:right]
      end

      def padding_top
        normalized_padding[:top]
      end

      def padding_bottom
        normalized_padding[:bottom]
      end
    end
  end
end
