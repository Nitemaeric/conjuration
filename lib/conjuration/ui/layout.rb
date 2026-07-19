module Conjuration
  module UI
    # Flexbox-style layout: dirty tracking, justify/align distribution, padding,
    # and absolute positioning. Mixed into Node — the geometry it computes lands
    # on each node's object hash.
    module Layout
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
          justify, direction, align, gap, padding, position, grow, max_w, max_h,
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

      # This node's content width — its box minus left/right padding.
      def inner_width
        object.w - padding_left - padding_right
      end

      # Two-pass layout. First a bottom-up measure pass resolves every auto-sized
      # container (and applies max caps) over the dirty region, so a parent's
      # size is known before it positions its children. Then the existing
      # top-down positioning pass runs. Fully-sized trees skip the measure pass
      # entirely (see needs_measure?), taking the same single-pass path as before.
      def calculate_layout(force: false)
        return unless @dirty || force

        measure_pass
        position_pass(force: force)
      end

      def position_pass(force: false)
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
          mark_stretch_growers(flow_children) if justify == :stretch
          distribute_grow(flow_children)

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

          detect_overflow!
        end

        @dirty = false
        @laid_out_signature = layout_signature

        # We just repositioned our children (everywhere but the root canvas), so
        # they moved and must relay; the root leaves children to their own state.
        cascade = id != :root
        @children.each { |child| child.position_pass(force: cascade) }
      end

      def absolute?
        position == :absolute
      end

      # Whether this node — or anything in its subtree — needs the measure pass:
      # an auto-sized container (deriving a size from content) or a node with a
      # max cap to clamp. Memoized; dropped on structure or declared-size change.
      # A fully-sized subtree returns false, so the pass never descends into it.
      def needs_measure?
        return @needs_measure unless @needs_measure.nil?

        @needs_measure = self_needs_measure? || @children.any?(&:needs_measure?)
      end

      # Bottom-up: resolve nested auto sizes before this node's, so summing/maxing
      # children reads their final intrinsic sizes. Dirty- and needs_measure-gated,
      # so clean or fully-sized subtrees do no work. Public because the recursion
      # reaches it through Symbol#to_proc (an explicit receiver).
      def measure_pass
        return unless @dirty
        return unless needs_measure?

        @children.each(&:measure_pass)
        # Only resolve this node's own size when it itself auto-sizes or is capped;
        # a fixed ancestor merely relays the pass down to a deeper auto descendant.
        resolve_content_size! if self_needs_measure?
      end

      # A container derives its size on an axis when the author declared none and
      # it has children to derive from. Text nodes size from their string
      # (measure!), and the root is the fixed screen canvas — neither auto-sizes.
      # A wrap: container is excluded too: its width comes from its parent, and its
      # children then wrap to that width — a width-first resolution that can't be
      # derived from content in this single bottom-up pass, so it keeps the
      # existing parent-driven sizing. Public so the debug inspector can read each
      # axis's size provenance without re-deriving the auto-size rule.
      def auto_w?
        return false if id == :root || wrap

        @authored_w.nil? && !object.has_key?(:text) && !@children.empty?
      end

      def auto_h?
        return false if id == :root || wrap

        @authored_h.nil? && !object.has_key?(:text) && !@children.empty?
      end

      # The resolved per-side padding layout actually applied, as
      # { left:, right:, top:, bottom: }. Public so the debug inspector's box-model
      # overlay reads the same insets rather than re-normalizing raw `padding`.
      def padding_edges
        normalized_padding
      end

      private

      # justify: :stretch marks children without an AUTHORED main size (grow and
      # stretch themselves write sizes back, so current values can't be trusted)
      # as grow: 1; text children are intrinsically sized and never stretch.
      def mark_stretch_growers(flow_children)
        main_key = direction == :row ? :w : :h

        flow_children.each do |child|
          next if child.grow
          next if child.object[:text]
          next if child.declared_main_size?(main_key)

          child.grow = 1
        end
      end

      # Expand in-flow children with grow > 0 into leftover main-axis free space
      # (basis + share of leftover). No shrink when leftover is non-positive.
      def distribute_grow(flow_children)
        growers = flow_children.select { |child| child.grow && child.grow > 0 }
        return if growers.empty?

        row = direction == :row
        main_size = row ? object.w : object.h
        axis = row ? "width" : "height"
        main_key = row ? :w : :h

        unless main_size
          UI.warn(self, "grow: on #{id.inspect} needs a #{axis}; ignoring")
          return
        end

        # Re-rendering with a different factor must not compound: every grower
        # restarts from its authored size (or 0) before leftover is measured.
        growers.each do |child|
          basis = child.authored_main_size(main_key) || 0
          next if child.object[main_key] == basis

          child.object[main_key] = basis
          child.invalidate!
        end

        inner = row ? inner_width : (object.h - padding_top - padding_bottom)
        used = sum_main_size(flow_children, main_key) + (flow_children.length > 1 ? (flow_children.length - 1) * gap : 0)
        leftover = inner - used
        return if leftover <= 0

        sum_factors = growers.inject(0) { |total, child| total + child.grow }
        growers.each do |child|
          child.object[main_key] = (child.object[main_key] || 0) + leftover * (child.grow / sum_factors)
          child.invalidate!
        end
      end

      def resolve_content_size!
        measure!
        @children.each(&:measure!)
        apply_auto_size!
        apply_max_clamp!
      end

      def self_needs_measure?
        auto_w? || auto_h? || !max_w.nil? || !max_h.nil?
      end

      # Derive an unset axis from the in-flow children: main axis = Σ sizes + gaps,
      # cross axis = the largest child, each plus this node's padding on that axis.
      # Out-of-flow (absolute) children are excluded from both.
      def apply_auto_size!
        return if id == :root

        flow = @children.reject(&:absolute?)

        if auto_w?
          content = direction == :row ? auto_main_size(flow, :w) : auto_cross_size(flow, :w)
          object.w = content + padding_left + padding_right
        end

        if auto_h?
          content = direction == :column ? auto_main_size(flow, :h) : auto_cross_size(flow, :h)
          object.h = content + padding_top + padding_bottom
        end
      end

      def auto_main_size(flow, axis)
        total = flow.inject(0) { |sum, child| sum + (child.object[axis] || 0) }
        total += (flow.length - 1) * gap if flow.length > 1
        total
      end

      def auto_cross_size(flow, axis)
        max = 0
        flow.each do |child|
          size = child.object[axis] || 0
          max = size if size > max
        end
        max
      end

      # Clamp the resolved size (from any source) down to its max cap. A cap never
      # enlarges, so a node already within its cap is untouched.
      def apply_max_clamp!
        object.w = max_w if max_w && object.w && object.w > max_w
        object.h = max_h if max_h && object.h && object.h > max_h
      end

      # After positioning, flag whether the in-flow content spills past this
      # container's resolved height. In the default (nil) mode that lazily turns
      # it into a scroll container (materializing the render target only now) and
      # warns once; :clip clips to the same target without a scrollbar. Explicit
      # :scroll and :visible are left to their own fixed behaviour. Out-of-flow
      # children never count, protecting deliberate overhangs.
      def detect_overflow!
        return if overflow == :scroll || overflow == :visible
        return unless object.h

        span = content_span
        over = !span.nil? && span > object.h
        changed = over != @overflowing
        @overflowing = over

        if over && overflow.nil? && !@overflow_warned
          @overflow_warned = true
          UI.warn(self, "content overflows #{id.inspect} (#{span} > #{object.h}); scrolling")
        end

        # Becoming (or ceasing to be) a scroll container flips interactive-ness,
        # which is cached on ancestors — drop it so the change is seen.
        clear_interactive_cache! if changed
      end

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

      # :center/:between/:around/:evenly divide by the node's main-axis size; when
      # that size is unresolved (nil) mruby dies with an opaque "non float value"
      # TypeError, so degrade to :start and record why. :start and :end never
      # touch the size (:end anchors off the trailing edge), so they pass through.
      def effective_justify(size, axis, index)
        return :start if justify == :stretch && size
        return justify if justify == :start || justify == :end || size

        UI.warn(self, "justify: #{justify.inspect} on #{id.inspect} needs a #{axis}; falling back to :start") if index.zero?
        :start
      end

      def calculate_column_justify(child, children, index)
        case effective_justify(object.h, "height", index)
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
        case effective_justify(object.w, "width", index)
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
        children.inject(0) { |total, child| total + (child.object[axis] || 0) }
      end

      def normalized_padding
        return @normalized_padding if @normalized_padding && @normalized_padding_key == padding

        @normalized_padding_key = padding
        @normalized_padding =
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
