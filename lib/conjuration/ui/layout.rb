module Conjuration
  module UI
    # Flexbox-style layout: dirty tracking, justify/align distribution, padding,
    # and absolute positioning. Mixed into Node — the geometry it computes lands
    # on each node's object hash.
    module Layout
      # Test whether this node needs layout calculation.
      #
      # @return [Boolean] true if marked dirty or has never been laid out
      #
      # @see Node#invalidate!
      # @see Node#calculate_layout
      def dirty?
        @dirty
      end

      # Mark this node for relayout — but only if a layout-relevant input actually
      # changed since it was last laid out.
      #
      # A no-op write (same value) or a render-only change (color, sprite) leaves the
      # node clean. When the node is marked dirty, the mark propagates up so the
      # per-frame relay reaches it (a child's size change reflows its parent).
      #
      # @return [nil]
      #
      # @note invalidate! is change-aware via layout_signature comparison, so a
      #   render-only change (color, path) doesn't force relayout. Structural changes
      #   (visible: true→false, text content, children added/removed) do mark dirty.
      #
      # @see Node#mark_dirty!
      # @see Node#layout_signature
      def invalidate!
        return if @dirty
        return if layout_signature == @laid_out_signature

        mark_dirty!
      end

      # Set this node and its ancestors dirty so the relay traverses to it,
      # short-circuiting at the first already-dirty node.
      #
      # Unlike invalidate! it doesn't re-test the signature — ancestors just need
      # to be reachable. Used when structure changes and signature is ambiguous.
      #
      # @return [nil]
      #
      # @note Used internally after structural changes (node added/removed).
      #
      # @see Node#invalidate!
      def mark_dirty!
        return if @dirty

        @dirty = true
        parent&.mark_dirty!
      end

      # The layout-relevant inputs: geometry, layout properties, text, and child count.
      #
      # Render-only fields (color, path, alpha) are deliberately excluded, so changing
      # them never forces a relayout.
      #
      # @return [Array] signature tuple compared by value
      #
      # @private Used internally by invalidate!.
      #
      # @see Node#invalidate!
      def layout_signature
        [
          object.x, object.y, object.w, object.h, object.anchor_x, object.anchor_y, object.text,
          justify, direction, align, gap, padding, position,
          inset_top, inset_right, inset_bottom, inset_left,
          visible, children.length
        ]
      end

      # Force the entire subtree dirty — used on orientation change or other
      # global reflows where every grid-relative value must be recomputed.
      #
      # @return [nil]
      #
      # @note Heavier than invalidate!; use sparingly.
      #
      # @see Node#invalidate!
      def invalidate_subtree!
        @dirty = true
        children.each(&:invalidate_subtree!)
      end

      # Resolve this node's intrinsic size from its text, if any.
      #
      # When the parent opted into wrapping (wrap: true), the text breaks across lines
      # to the parent's content width and the node sizes to the wrapped block.
      #
      # @return [nil]
      #
      # @note Called early in calculate_layout, before children are positioned.
      #
      # @see Node#inner_width
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

      # This node's content width — its box width minus left/right padding.
      #
      # Used to constrain text wrapping and child layouts.
      #
      # @return [Numeric] inner width in pixels
      #
      # @see Node#padding
      def inner_width
        object.w - padding_left - padding_right
      end

      # Calculate flexbox layout for this node and all descendants.
      #
      # Measures text, distributes flow children, positions absolute children,
      # and recurses to set up the retained-mode layout tree. Skipped if not dirty
      # unless force: true.
      #
      # @param force [Boolean] recalculate even if not dirty (default: false)
      # @return [nil]
      #
      # @note Layout computes into object (x, y, w, h, anchor_x, anchor_y); each
      #   node's declared state is preserved in @declared for reconciliation diffing.
      #
      # @note The root (id: :root) is skipped—its children are laid out without
      #   repositioning (they use their own computed positions).
      #
      # @note When justify uses :center, :between, :around, or :evenly, the main-axis
      #   size must be resolved (non-nil), or the method falls back to :start and warns.
      #   :start and :end never need size resolution.
      #
      # @see Node#dirty?
      # @see Node#invalidate!
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

      # Test whether this node is out-of-flow positioned.
      #
      # @return [Boolean] true if position == :absolute
      #
      # @see Node#position
      def absolute?
        position == :absolute
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

      # :center/:between/:around/:evenly divide by the node's main-axis size; when
      # that size is unresolved (nil) mruby dies with an opaque "non float value"
      # TypeError, so degrade to :start and record why. :start and :end never
      # touch the size (:end anchors off the trailing edge), so they pass through.
      def effective_justify(size, axis, index)
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
        children.inject(0) { |total, child| total + child.object[axis] }
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
