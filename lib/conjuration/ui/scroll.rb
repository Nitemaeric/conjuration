module Conjuration
  module UI
    # overflow: :scroll containers — clipping children into a render target,
    # offsetting by scroll_offset, and drawing a scrollbar. Mixed into Node.
    module Scroll
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
    end
  end
end
