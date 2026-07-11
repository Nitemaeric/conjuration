module Conjuration
  module UI
    def self.build(object_hash = nil, id: :root, **opts, &block)
      root = Node.new(object_hash, id: id, **opts, &block)
      root.calculate_layout
      root
    end

    # A layout node combining flexbox geometry, reconciliation, navigation, text wrapping,
    # and scroll clipping into one tree structure. Nodes are built via node() calls or UI.build,
    # laid out flexbox-style, and optionally reconciled frame-to-frame from a declarative view.
    # The retained node tree survives layout invalidation and reconciliation, preserving scroll
    # offset, focus, and measurement caches across re-renders.
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
      attr_writer :declared
      # The view component this node was mounted for (nil for a plain node) —
      # part of its reconcile identity, so a type swap at the same key remounts.
      attr_accessor :component_class

      delegate :first, :last, to: :children

      # Create a node with flexbox layout keywords and render/geometry data.
      #
      # Node keywords define layout and interactivity; anything else is render data (sprites, text,
      # colors, computed geometry). Both are stored in `object` so layout can compute geometry into
      # it. The reconciler snapshots declared-only state to diff frame-to-frame.
      #
      # @param object_hash [Hash, nil] render data; nil means create from **object keywords
      # @param id [Symbol, nil] unique identifier; nil = anonymous node
      # @param direction [Symbol] main axis: :column (default, vertical) or :row (horizontal)
      # @param justify [Symbol] main-axis distribution (default: :start):
      #   - :start — children at main-axis start
      #   - :center — children centered; requires resolved main-axis size (warns if unresolved)
      #   - :end — children at main-axis end; never requires size resolution
      #   - :between — space children to fill; first at start, last at end
      #   - :around — space children equally with half-spacing at edges
      #   - :evenly — equal space everywhere including edges
      # @param align [Symbol] cross-axis alignment (default: :start):
      #   - :start — children at cross-axis start
      #   - :center — children centered on cross-axis
      #   - :end — children at cross-axis end
      #   - :stretch — children span the container's cross-axis size
      # @param gap [Numeric] space between children (default: 0)
      # @param padding [Numeric, Array, Hash] space inside edges (default: 0); can be:
      #   - Single value: applies to all edges
      #   - Two-element Array [horizontal, vertical]
      #   - Hash {left:, right:, top:, bottom:} with defaults for missing keys
      # @param visible [Boolean] render and interact if true (and all ancestors visible); default true
      # @param position [Symbol] :static (default, in-flow) or :absolute (out-of-flow);
      #   absolute nodes positioned by insets, don't consume flow space
      # @param top [Numeric, nil] out-of-flow vertical position; inset from parent's padding-box top edge
      # @param right [Numeric, nil] out-of-flow horizontal position; inset from parent's padding-box right edge
      # @param bottom [Numeric, nil] out-of-flow vertical position; inset from parent's padding-box bottom edge
      # @param left [Numeric, nil] out-of-flow horizontal position; inset from parent's padding-box left edge
      # @param group [Symbol, nil] named navigation group; nil inherits nearest ancestor's group
      # @param overflow [Symbol, nil] :scroll clips children to this node's box and scrolls via scroll_offset;
      #   nil (default) lays out normally
      # @param wrap [Boolean, nil] text wrapper container; nil (default) is non-wrapping
      # @param text_break [Symbol, Boolean] text break mode when wrapped (default: :word):
      #   - :word — break on spaces
      #   - :letter — break anywhere (mid-word)
      #   - false — never wrap
      # @param shortcut [Hash, nil] accelerator trigger {keyboard: :key, controller: :button};
      #   nil (default) means no shortcut; fire queries shortcut_action_name
      # @param object [Hash] remaining keyword arguments become render data
      # @param block [Proc] nested node() calls to build children
      #
      # @note Out-of-flow insets are kept off the object hash to avoid shadowing computed
      #   geometry accessors (object.left, object.top) which would go stale across re-layouts.
      #
      # @note Retained-mode layout: nodes start dirty and are recomputed only when invalidate!
      #   marks them. Render-only changes (color, sprite path) don't force relayout.
      #
      # @see Node#node for a convenience wrapper
      # @see UI.build for the typical entry point
      def initialize(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, visible: true, position: :static, top: nil, right: nil, bottom: nil, left: nil, group: nil, overflow: nil, wrap: nil, text_break: :word, shortcut: nil, **object, &block)
        @id = id&.to_sym
        @object = object_hash || object
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

        # Retained-mode layout: a node starts dirty (needs its first layout) and
        # is recomputed only when invalidate! marks it — see calculate_layout.
        @dirty = true

        instance_exec(&block) if block_given?
      end

      # Create a child node and add it to this node's children.
      #
      # The child's keywords follow Node.new's contract (the single source of node-keyword defaults).
      #
      # @param object_hash [Hash, nil] render data
      # @param opts [Hash] node keywords (id, direction, justify, align, gap, padding, visible, position, etc.)
      # @param block [Proc] nested node() calls to build children
      # @return [Node] the new child node
      #
      # @note Adding a node calls clear_structure_cache! and invalidate!, rebuilding descendant
      #   maps and marking the tree for relayout.
      #
      # @see Node#initialize for keyword details
      #
      # @example Nested node tree
      #   node({ w: 100, h: 50, path: 'sprites/button.png', action: -> { puts 'clicked' } },
      #        id: :button, justify: :center, align: :center) do
      #     node({ text: 'Click me!', r: 255, g: 255, b: 255 }, id: :label)
      #   end
      def node(object_hash = nil, **opts, &block)
        element = Node.new(object_hash, **opts, &block)
        element.parent = self
        children << element
        clear_structure_cache!
        invalidate!
        element
      end

      # Find a descendant node by id.
      #
      # @param id [Symbol, String] node identifier (converted to symbol)
      # @return [Node, nil] the descendant node, or nil if not found
      #
      # @example
      #   button = ui.find(:my_button)
      #   button.visible = false if button
      def find(id)
        descendants[id.to_sym]
      end

      def intersect_rect?(rect)
        Geometry.intersect_rect?(rect, self.rect)
      end

      def find_interactive_intersect(rect)
        Geometry.find_intersect_rect(rect, interactive_nodes)
      end

      # All descendants keyed by id, memoized and invalidated on structural changes.
      #
      # @return [Hash[Symbol => Node]] id -> node map; empty entries for nil ids skipped
      #
      # @note This hash is rebuilt on every clear_structure_cache! (node added/removed).
      def descendants
        @descendants ||= begin
          nodes.each_with_object({}) do |node, hash|
            hash[node.id] = node if node.id
          end
        end
      end

      # All nodes in this subtree (self and all descendants), memoized.
      #
      # @return [Array<Node>] depth-first traversal including self
      #
      # @note Cleared on structural change (node added/removed).
      def nodes
        @nodes ||= [self, *children.flat_map(&:nodes)].compact
      end

      # Clear all memoized structure (nodes, descendants, interactive_nodes).
      #
      # Called when children are added/removed; propagates up to every ancestor so they rebuild
      # their memos on next access.
      #
      # @return [nil]
      def clear_structure_cache!
        @nodes = nil
        @descendants = nil
        @interactive_nodes = nil
        @navigation_groups = nil
        @shortcut_nodes = nil
        parent&.clear_structure_cache!
      end

      # Clear interactive-ness caches (interactive_nodes, navigation_groups, shortcut_nodes).
      #
      # Called when a node's visibility, disabled state, or shortcut changes; propagates up to
      # every ancestor. Keeps nodes/descendants memos alive.
      #
      # @return [nil]
      def clear_interactive_cache!
        @interactive_nodes = nil
        @navigation_groups = nil
        @shortcut_nodes = nil
        parent&.clear_interactive_cache!
      end

      # All styled objects emitted by this subtree (flat, render-order list).
      #
      # Scroll containers emit their render targets + scrollbars instead of recursing, so
      # overflowing children don't leak. Text nodes emit wrapped primitives.
      #
      # @return [Array<Object>] renderable primitive objects
      def primitives
        collect_primitives([])
      end

      # Walk the tree emitting each renderable node's styled object.
      #
      # Scroll containers emit a sprite of their clipped render target plus scrollbar instead of
      # recursing, so children stay clipped. Wrapped text emits its lines.
      #
      # @param acc [Array<Object>] accumulator for primitives
      # @return [Array<Object>] same as acc, mutated with this subtree's primitives
      #
      # @private Used internally; prefer primitives().
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

      # Mutate the visibility flag without forcing layout recalculation.
      #
      # Visibility is baked into the layout signature, so invalidate! would trigger a relayout
      # anyway. This method just clears interactive caches and returns the value.
      #
      # @param value [Boolean] new visibility state
      # @return [Boolean] the value assigned
      #
      # @note Setting visible: false hides this node and all descendants from rendering,
      #   interaction, and navigation.
      def visible=(value)
        return if @visible == value

        @visible = value
        clear_interactive_cache!
      end

      # Test whether this node and all ancestors are visible.
      #
      # @return [Boolean] true only if this node and every ancestor is visible
      #
      # @note Effective visibility is computed here rather than assigned down the tree, so
      #   per-frame relayout can't clobber a node's own `visible` setting.
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
