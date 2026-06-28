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

    # The active navigation group (a node's `group:` id). The game owns this —
    # there is no built-in trigger to switch groups; you set it yourself. nil
    # disables UI navigation entirely: the input loop is inert until a group is
    # set, so menus stay dormant while gameplay owns the input.
    def self.active_navigation_group
      @active_navigation_group
    end

    def self.active_navigation_group=(group)
      @active_navigation_group = group
    end

    class Node < Conjuration::Node
      attr_accessor :id, :object, :children, :descendants
      attr_accessor :justify, :direction, :align, :gap, :padding, :visible, :position, :parent
      attr_reader :inset_top, :inset_right, :inset_bottom, :inset_left
      attr_accessor :group
      attr_reader :overflow
      attr_accessor :scroll_offset
      attr_reader :wrap

      delegate :first, :last, to: :children

      def initialize(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, visible: true, position: :static, top: nil, right: nil, bottom: nil, left: nil, group: nil, overflow: nil, wrap: nil, **object, &block)
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

        # wrap: a max width that breaks this node's text across multiple lines.
        @wrap = wrap

        # Retained-mode layout: a node starts dirty (needs its first layout) and
        # is recomputed only when invalidate! marks it — see calculate_layout.
        @dirty = true

        instance_exec(&block) if block_given?
      end

      def node(object_hash = nil, id: nil, direction: :column, justify: :start, align: :start, gap: 0, padding: 0, position: :static, top: nil, right: nil, bottom: nil, left: nil, group: nil, overflow: nil, wrap: nil, **object, &block)
        element = Node.new(object_hash, id: id, direction: direction, justify: justify, align: align, gap: gap, padding: padding, position: position, top: top, right: right, bottom: bottom, left: left, group: group, overflow: overflow, wrap: wrap, **object, &block)
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

      def dirty?
        @dirty
      end

      # Mark this node for relayout — but only if a layout-relevant input actually
      # changed since it was last laid out. A no-op write (same value) or a
      # render-only change (colour, sprite) leaves it clean. Then propagate up so
      # the per-frame relay reaches it (a child's size change reflows its parent).
      def invalidate!
        return if @dirty
        return if layout_signature == @laid_out_signature

        mark_dirty!
      end

      # Set this node and its ancestors dirty so the relay traverses to it,
      # short-circuiting at the first already-dirty node. Unlike invalidate! it
      # doesn't re-test the signature — ancestors just need to be reachable.
      def mark_dirty!
        return if @dirty

        @dirty = true
        parent&.mark_dirty!
      end

      # The layout-relevant inputs: geometry, layout properties, text, and child
      # count. Render-only fields (colour, path, alpha) are deliberately excluded,
      # so changing them never forces a relayout.
      def layout_signature
        [
          object.x, object.y, object.w, object.h, object.anchor_x, object.anchor_y, object.text,
          justify, direction, align, gap, padding, position,
          inset_top, inset_right, inset_bottom, inset_left,
          visible, children.length
        ]
      end

      # Force the whole subtree dirty — e.g. on orientation change, where every
      # grid-relative value has to be recomputed.
      def invalidate_subtree!
        @dirty = true
        children.each(&:invalidate_subtree!)
      end

      # Memoized text measurement: re-measure only when the string changes, so a
      # relayout that merely repositions a label doesn't re-run calcstringbox.
      def measure_text
        if @measured_text != object.text
          @measured_text = object.text
          @measured_size = gtk.calcstringbox(object.text)
        end

        @measured_size
      end

      # Resolve this node's own intrinsic size from its text, if any. When the
      # parent opted into wrapping (wrap: true), the text breaks across lines to
      # the parent's content width and the node sizes to the wrapped block.
      def measure!
        return unless object.has_key?(:text)

        width = wrap_width
        if width
          object.w = width
          object.h = wrap_lines.length * measure_text[1]
        else
          object.w, object.h = measure_text
        end
      end

      def wrapped?
        !wrap_width.nil?
      end

      # The width this text node wraps to — its parent's content width when the
      # parent set wrap: true, else nil. Coupling to the parent's width means the
      # text reflows when the container resizes, instead of a fixed magic number.
      def wrap_width
        return nil unless object.has_key?(:text) && parent&.wrap

        parent.inner_width
      end

      # This node's content width — its box minus left/right padding.
      def inner_width
        object.w - padding_left - padding_right
      end

      # Greedily break the text into lines no wider than the wrap width, on word
      # boundaries (a word wider than the width takes its own line). Memoized.
      def wrap_lines
        width = wrap_width
        return [] unless width

        key = [object.text, width]
        return @wrapped_lines if @wrapped_key == key

        @wrapped_key = key
        @wrapped_lines = build_wrapped_lines(width)
      end

      def build_wrapped_lines(width)
        lines = []
        line = ""

        object.text.to_s.split(" ").each do |word|
          candidate = line.empty? ? word : "#{line} #{word}"
          if line.empty? || gtk.calcstringbox(candidate)[0] <= width
            line = candidate
          else
            lines << line
            line = word
          end
        end

        lines << line unless line.empty?
        lines
      end

      # One label primitive per wrapped line, stacked down from the node's top.
      def wrapped_text_primitives
        line_height = measure_text[1]

        wrap_lines.each_with_index.map do |line, index|
          { **styled_object, text: line, x: object.left, y: object.top - index * line_height, anchor_x: 0, anchor_y: 1 }
        end
      end

      def calculate_layout(force: false)
        return unless @dirty || force

        # Per-pass caches for centered layouts; cleared each call so a
        # re-layout after children change size doesn't reuse stale totals.
        @children_width_with_gaps = nil
        @children_height_with_gaps = nil

        measure!

        # A child's intrinsic (text) size must be known before we position it, or
        # a sibling stacks against an unmeasured height of zero and they overlap.
        @children.each(&:measure!)

        # Absolutely-positioned children are out of flow: they don't consume
        # space, shift siblings, or count toward justify/align distribution.
        flow_children = @children.reject(&:absolute?)
        flow_children = flow_children.reverse if justify == :end

        unless id == :root
          flow_children.each_with_index do |child, index|
            case direction
            when :row
              calculate_row_justify(child, flow_children, index)
              calculate_row_align(child)
            when :column
              calculate_column_justify(child, flow_children, index)
              calculate_column_align(child)
            end
          end

          @children.each { |child| position_absolute(child) if child.absolute? }
        end

        @dirty = false
        @laid_out_signature = layout_signature

        # We just repositioned our children (everywhere but the root canvas), so
        # they moved and must relay; the root leaves children to their own state.
        cascade = id != :root
        @children.each { |child| child.calculate_layout(force: cascade) }
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
        parent&.clear_structure_cache!
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

      def scroll?
        overflow == :scroll
      end

      # Render each scroll container's children into its render target, translated
      # to target-local space and shifted by scroll_offset. Call once per frame,
      # before emitting primitives.
      def render_scroll_targets
        nodes.each { |node| node.render_scroll_target if node.scroll? }
      end

      def render_scroll_target
        target = game.outputs[scroll_target_path]
        target.width = object.w
        target.height = object.h

        # Fill with the container's own background first, then the children
        # translated to target-local space and shifted by scroll_offset.
        target.primitives << scroll_background if renderable?

        dx = -object.left
        dy = -object.bottom + scroll_offset
        children.flat_map { |child| child.collect_primitives([]) }.each do |source|
          primitive = source.dup
          primitive[:x]  += dx if primitive[:x]
          primitive[:y]  += dy if primitive[:y]
          primitive[:x2] += dx if primitive[:x2]
          primitive[:y2] += dy if primitive[:y2]
          target.primitives << primitive
        end
      end

      # The blit of a scroll container's render target at its on-screen box.
      def scroll_sprite
        { x: object.left, y: object.bottom, w: object.w, h: object.h, path: scroll_target_path }
      end

      def scroll_target_path
        "ui_scroll_#{id || object_id}"
      end

      # The container's own background, sized to fill its render target.
      def scroll_background
        { **styled_object, x: 0, y: 0, w: object.w, h: object.h, anchor_x: 0, anchor_y: 0 }
      end

      # The total height the content occupies — the children's span plus the
      # container's top and bottom padding — the basis for how far it scrolls.
      def content_height
        return 0 if children.empty?

        span = children.map { |child| child.object.top }.max - children.map { |child| child.object.bottom }.min
        span + padding_top + padding_bottom
      end

      # How far the content can scroll past the box (0 when it already fits).
      def max_scroll
        [content_height - object.h, 0].max
      end

      # A thin thumb on the right edge, sized and placed by the scroll position.
      def scrollbar_primitives
        return [] if max_scroll <= 0

        track = object.h
        thumb = [track * object.h / content_height, 16].max
        thumb_top = object.top - (scroll_offset / max_scroll) * (track - thumb)

        [{ x: object.right - 6, y: thumb_top - thumb, w: 4, h: thumb, path: :pixel, r: 70, g: 70, b: 70, a: 200 }]
      end

      def interactive_nodes
        nodes.select(&:interactive?)
      end

      # Interactive nodes bucketed by their navigation group — the nearest
      # ancestor's `group:`. Ungrouped nodes are omitted: groups are explicit and
      # named, and the game decides which one is active.
      def navigation_groups
        accumulate_navigation_groups(nil, {})
      end

      # The group id a given interactive node belongs to (or nil if ungrouped).
      def group_of(target)
        navigation_groups.each do |id, members|
          return id if members.any? { |member| member.equal?(target) }
        end
        nil
      end

      # Recursive helper for navigation_groups; threads the nearest enclosing
      # group down the tree so the innermost group wins.
      def accumulate_navigation_groups(inherited, groups)
        current = group || inherited
        (groups[current] ||= []) << self if interactive? && current
        children.each { |child| child.accumulate_navigation_groups(current, groups) }
        groups
      end

      # The nearest interactive node to `from` within a 45-degree cone of
      # `direction`, among `candidates` (default: all interactive nodes; the input
      # loop passes the active group's members to keep navigation inside a pane).
      def spatial_navigate(from, direction, candidates: interactive_nodes)
        return candidates.first if from.nil?

        origin = from.rect.center
        best = nil
        best_distance = nil

        candidates.each do |node|
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
        # Cheap checks first: most nodes have neither an action nor scroll, so
        # short-circuit before the visible_in_tree? parent walk (this runs over
        # every node, every tick). A scroll container is focusable too, so it can
        # be navigated to and scrolled with the right stick once focused.
        return false unless has_key?(:action) || scroll?

        !disabled? && visible_in_tree?
      end

      def renderable?
        return false unless visible_in_tree?
        return %i[solid label sprite line border].include?(primitive_marker)
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

      def absolute?
        position == :absolute
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

      # Place an out-of-flow child against this node's padding box using its
      # CSS-style insets. Both insets on an axis stretch the child to span between
      # them; a single inset pins that edge and leaves the child's size as-is.
      def position_absolute(child)
        inner_left   = object.left   + padding_left
        inner_right  = object.right  - padding_right
        inner_top    = object.top    - padding_top
        inner_bottom = object.bottom + padding_bottom

        if child.inset_left && child.inset_right
          child.object.anchor_x = 0
          child.object.x = inner_left + child.inset_left
          child.object.w = inner_right - child.inset_right - (inner_left + child.inset_left)
        elsif child.inset_left
          child.object.anchor_x = 0
          child.object.x = inner_left + child.inset_left
        elsif child.inset_right
          child.object.anchor_x = 1
          child.object.x = inner_right - child.inset_right
        end

        if child.inset_top && child.inset_bottom
          child.object.anchor_y = 1
          child.object.y = inner_top - child.inset_top
          child.object.h = inner_top - child.inset_top - (inner_bottom + child.inset_bottom)
        elsif child.inset_top
          child.object.anchor_y = 1
          child.object.y = inner_top - child.inset_top
        elsif child.inset_bottom
          child.object.anchor_y = 0
          child.object.y = inner_bottom + child.inset_bottom
        end
      end

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
