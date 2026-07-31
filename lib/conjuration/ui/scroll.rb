module Conjuration
  module UI
    # overflow: :scroll containers — clipping children into a render target,
    # offsetting by scroll_offset, and drawing a scrollbar. Mixed into Node.
    module Scroll
      # A scroll container: explicit overflow: :scroll, or the default mode once
      # its content is found to overflow (detect_overflow! sets @overflowing).
      # Scroll containers clip into a render target, draw a scrollbar, take scroll
      # input, and are focusable.
      def scroll?
        overflow == :scroll || (overflow.nil? && @overflowing)
      end

      # A clip container: overflow: :clip once content overflows. Clips into a
      # render target like scroll, but with no scrollbar and no scroll interaction.
      def clip?
        overflow == :clip && @overflowing
      end

      # Either mode needs the render target materialized and blitted; a fitting
      # container needs neither, so nothing is allocated until overflow occurs.
      def render_target?
        scroll? || clip?
      end

      # Render each render-target container's children into its target, translated
      # to target-local space and shifted by scroll_offset. Call once per frame,
      # before emitting primitives.
      def render_scroll_targets
        nodes.each { |node| node.render_scroll_target if node.render_target? }
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

      # The vertical extent of the in-flow content — the span from the topmost
      # child's top to the bottommost child's bottom. This is the overflow test's
      # metric (compared against the box height): content is deemed to overflow
      # only when it escapes the drawn bounds, not merely the nominal padding.
      # Out-of-flow (absolute) children are excluded, so a deliberate overhang
      # never counts. nil when there is nothing in flow. A single scalar scan (no
      # intermediate arrays), since detect_overflow! calls it each relayout.
      def content_span
        top = nil
        bottom = nil

        children.each do |child|
          next if child.absolute?

          child_top = child.object.top
          child_bottom = child.object.bottom
          next if child_top.nil? || child_bottom.nil?

          top = child_top if top.nil? || child_top > top
          bottom = child_bottom if bottom.nil? || child_bottom < bottom
        end

        top && (top - bottom)
      end

      # The total height the in-flow content occupies including the container's
      # top and bottom padding — the basis for how far a scroll container scrolls.
      def content_height
        span = content_span
        return 0 if span.nil?

        span + padding_top + padding_bottom
      end

      # How far the content can scroll past the box (0 when it already fits).
      def max_scroll
        [content_height - object.h, 0].max
      end

      # The nearest enclosing scroll container, if any — what the right stick
      # scrolls while one of its items holds focus.
      def enclosing_scroll_pane
        ancestor = parent
        ancestor = ancestor.parent until ancestor.nil? || ancestor.scroll?
        ancestor
      end

      # A node's layout rect is its UNSHIFTED position: panes shift their content
      # at emission only (render_scroll_target). This is what to add to reach the
      # position it is actually drawn at.
      def ancestor_scroll_offset
        offset = 0
        ancestor = parent
        while ancestor
          offset += ancestor.scroll_offset if ancestor.render_target?
          ancestor = ancestor.parent
        end
        offset
      end

      # Scroll every enclosing pane so this node's box sits inside it, and — given
      # a direction of travel — so the neighbour that way is revealed too, so the
      # player can see what they are about to navigate onto. Innermost pane first:
      # each adjustment moves this node within the panes above it, which is what
      # the accumulated `inner` offset carries.
      def scroll_into_view(direction = nil)
        inner = 0
        ancestor = parent
        while ancestor
          if ancestor.render_target?
            ancestor.reveal_child(self, inner, direction) if ancestor.scroll?
            inner += ancestor.scroll_offset
          end
          ancestor = ancestor.parent
        end
      end

      # Pick the offset that brings `node` fully inside this pane, then extend it
      # toward revealing the lookahead neighbour as far as the node itself allows.
      def reveal_child(node, inner, direction)
        box_top = object.top
        box_bottom = object.bottom
        node_top = node.object.top
        node_bottom = node.object.bottom
        return if box_top.nil? || box_bottom.nil? || node_top.nil? || node_bottom.nil?

        # Screen y = layout y + scroll_offset, so a larger offset raises content.
        low = box_bottom - node_bottom - inner
        high = box_top - node_top - inner

        offset = scroll_offset
        offset = low if offset < low
        offset = high if offset > high # a node taller than the box aligns to its top

        neighbour = lookahead_neighbour(node, direction)
        if neighbour
          if direction.y < 0
            want = box_bottom - neighbour.object.bottom - inner
            want = high if want > high
            offset = want if want > offset
          else
            want = box_top - neighbour.object.top - inner
            want = low if want < low
            offset = want if want < offset
          end
        end

        self.scroll_offset = offset.clamp(0, max_scroll)
      end

      # The in-flow sibling the travel direction leads to. Vertical only — that is
      # the axis a pane scrolls on.
      def lookahead_neighbour(node, direction)
        return nil if direction.nil? || direction.y == 0

        best = nil
        node.parent.children.each do |sibling|
          next if sibling.equal?(node) || sibling.absolute? || !sibling.visible_in_tree?

          top = sibling.object.top
          bottom = sibling.object.bottom
          next if top.nil? || bottom.nil?

          if direction.y < 0
            next unless top <= node.object.bottom
            best = sibling if best.nil? || top > best.object.top
          else
            next unless bottom >= node.object.top
            best = sibling if best.nil? || bottom < best.object.bottom
          end
        end
        best
      end

      # A thin thumb on the right edge, sized and placed by the scroll position.
      def scrollbar_primitives
        return [] if max_scroll <= 0

        track = object.h
        thumb = [track * object.h / content_height, 16].max
        thumb_top = object.top - (scroll_offset / max_scroll) * (track - thumb)

        [{ x: object.right - 6, y: thumb_top - thumb, w: 4, h: thumb, path: :pixel, r: 70, g: 70, b: 70, a: 200 }]
      end
    end
  end
end
