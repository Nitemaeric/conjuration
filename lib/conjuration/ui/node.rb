module Conjuration
  module UI
    def self.build(object_hash = nil, id: :root, **opts, &block)
      root = Node.new(object_hash, id: id, **opts, &block)
      root.calculate_layout
      root
    end

    class Node < Conjuration::Node
      include Reconciler
      include Layout
      include Text
      include Scroll
      include Navigation

      attr_accessor :id, :object, :children, :descendants
      attr_accessor :justify, :direction, :align, :gap, :padding, :position, :parent
      attr_reader :visible
      attr_reader :inset_top, :inset_right, :inset_bottom, :inset_left
      attr_accessor :group
      attr_reader :overflow
      attr_accessor :scroll_offset
      attr_reader :wrap, :text_break
      attr_reader :shortcut
      attr_reader :grow

      def authored_main_size(main_key)
        main_key == :w ? @authored_w : @authored_h
      end

      def declared_main_size?(main_key)
        !authored_main_size(main_key).nil?
      end
      attr_writer :declared
      # The view component this node was mounted for (nil for a plain node) —
      # part of its reconcile identity, so a type swap at the same key remounts.
      attr_accessor :component_class

      delegate :first, :last, to: :children

      # @param grow [Numeric, nil] flex grow factor; nil (default) = no growth
      # justify: :stretch — main-axis analog of align: :stretch; children without
      # an authored main size grow equally (explicit grow: factors still compose).
      def initialize(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, visible: true, position: :static, top: nil, right: nil, bottom: nil, left: nil, group: nil, overflow: nil, wrap: nil, text_break: :word, shortcut: nil, grow: nil, **object, &block)
        @id = id&.to_sym
        @object = object_hash || object
        # Authored-at-build sizes: grow/stretch write w/h back into object each
        # layout, so basis and declaredness must come from what the author gave.
        @authored_w = @object[:w]
        @authored_h = @object[:h]
        @children = []
        @parent = nil

        @direction = direction
        @justify = justify
        @align = align
        @gap = gap
        @padding = padding
        @visible = visible

        # Out-of-flow nodes are placed by their parent against its box using these
        # CSS-style insets, rather than flowing alongside their siblings. They're
        # kept off the object hash so they don't shadow object.left/top (computed
        # geometry accessors) — which would also go stale across re-layouts.
        @position = position
        @inset_top = top
        @inset_right = right
        @inset_bottom = bottom
        @inset_left = left

        # A named navigation group: this node's interactive descendants form one
        # pane for UI.active_navigation_group. nil inherits the nearest ancestor's.
        @group = group

        # overflow: :scroll clips this node's children to its box and offsets them
        # by scroll_offset; nil (the default) lays out normally.
        @overflow = overflow
        @scroll_offset = 0

        # wrap: this container wraps its text children to its content width.
        @wrap = wrap

        # text_break: how this text node breaks when wrapped — :word (default,
        # on spaces), :letter (anywhere, mid-word), or false (never wrap).
        @text_break = text_break

        # shortcut: { keyboard:, controller: } — an accelerator that fires this
        # node's action from anywhere (see UIManagement#trigger_shortcuts). Core
        # draws nothing for it — display is game code, keyed off the injected
        # action's name (shortcut_action_name). nil (default) means no work.
        @shortcut = shortcut

        @grow = grow

        # Retained-mode layout: a node starts dirty (needs its first layout) and
        # is recomputed only when invalidate! marks it — see calculate_layout.
        @dirty = true

        instance_exec(&block) if block_given?
      end

      # node()'s keyword contract is Node.new's (the single source of node-keyword
      # defaults); forward through rather than restate every keyword here.
      def node(object_hash = nil, **opts, &block)
        element = Node.new(object_hash, **opts, &block)
        element.parent = self
        children << element
        clear_structure_cache!
        invalidate!
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

      def nodes
        @nodes ||= [self, *children.flat_map(&:nodes)].compact
      end

      # A structural change (a node added/removed) invalidates the memoized node
      # and descendant lists here and in every ancestor that contains this
      # subtree, so they rebuild on next access.
      def clear_structure_cache!
        @nodes = nil
        @descendants = nil
        @interactive_nodes = nil
        @navigation_groups = nil
        @shortcut_nodes = nil
        parent&.clear_structure_cache!
      end

      # Like clear_structure_cache! but keeps the @nodes/@descendants memos — only
      # the interactive-ness caches go stale on a visible/disabled/shortcut flip.
      def clear_interactive_cache!
        @interactive_nodes = nil
        @navigation_groups = nil
        @shortcut_nodes = nil
        parent&.clear_interactive_cache!
      end

      def primitives
        collect_primitives([])
      end

      # Walk the tree emitting each renderable node's styled object — but a scroll
      # container emits a sprite of its (clipped) render target plus its scrollbar
      # instead of recursing, so overflowing children don't leak into the flat
      # list. render_scroll_targets fills those targets before this is emitted.
      def collect_primitives(acc)
        if scroll?
          # The container's background + children are painted into its render
          # target (see render_scroll_target); the flat list gets the blit + bar.
          acc << scroll_sprite
          acc.concat(scrollbar_primitives)
        elsif wrapped? && renderable?
          acc.concat(wrapped_text_primitives)
        else
          acc << styled_object if renderable?
          children.each { |child| child.collect_primitives(acc) }
        end

        acc
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

      def renderable?
        return false unless visible_in_tree?
        return %i[solid label sprite line border].include?(primitive_marker)
      end

      # No layout clear: `visible` is in the layout signature, so invalidate! relayouts.
      def visible=(value)
        return if @visible == value

        @visible = value
        clear_interactive_cache!
      end

      def grow=(value)
        return if @grow == value

        @grow = value
        invalidate!
      end

      # Visible only if this node and every ancestor is visible. Effective
      # visibility is read here rather than assigned down the tree, so the
      # per-frame relayout can't clobber a node's own `visible` setting.
      def visible_in_tree?
        node = self
        while node
          return false unless node.visible
          node = node.parent
        end
        true
      end

      def primitive_marker
        return :sprite if has_key?(:path)
        return :label  if has_key?(:text)
        return :line   if has_key?(:x2) && has_key?(:y2)

        object.primitive_marker
      end
    end
  end
end
