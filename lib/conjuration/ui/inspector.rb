module Conjuration
  module UI
    # Read-only debug overlay for the mounted UI tree (roadmap H2), emitted into
    # outputs.debug after layout. It only reads geometry and the layout signals
    # the tree already stores — it never writes layout state, caches, or the
    # focus/hover globals, and never recomputes layout. Annotation (annotate,
    # node_at_point) is kept separate from emission so it is testable off-pixel.
    module Inspector
      extend self

      CONTAINER   = { r: 80,  g: 150, b: 245 }.freeze
      LEAF        = { r: 90,  g: 200, b: 120 }.freeze
      SCROLL      = { r: 235, g: 150, b: 45  }.freeze
      OUT_OF_FLOW = { r: 120, g: 120, b: 150 }.freeze
      UNRESOLVED  = { r: 240, g: 45,  b: 45  }.freeze

      # DevTools-style box model for the hover highlight: translucent blue content
      # area, translucent green padding band, translucent purple gap strips. Low
      # alpha so the UI underneath stays visible.
      CONTENT_FILL = { r: 100, g: 160, b: 240, a: 80 }.freeze
      PADDING_FILL = { r: 130, g: 200, b: 120, a: 80 }.freeze
      GAP_FILL     = { r: 175, g: 120, b: 220, a: 80 }.freeze

      SCREEN_W = 1280
      SCREEN_H = 720

      # Entry point (gated on game.debug? at the call site, mirrored by the caller
      # doing zero work when debug is off). Emits the bounds layer for every
      # mounted node, then the hover readout for the deepest node under the mouse.
      def render(root, outputs, mouse = nil)
        # Guarded here as well as at the call site (render_ui) so the overlay
        # builds nothing when debug is off — the whole walk is a no-op then.
        return unless root.debug?

        root.nodes.each { |node| emit_node(node, outputs) }

        return unless mouse

        hovered = node_at_point(root, mouse.x, mouse.y)
        emit_hover(hovered, outputs, mouse) if hovered && hovered.id != :root
      end

      # The read-only annotation for a single node: its resolved rect, identity,
      # per-axis size provenance, whether geometry is unresolved, and any content
      # overflow past the box. Derived from what layout actually did.
      def annotate(node)
        obj = node.object
        {
          id: node.id,
          kind: kind(node),
          rect: { x: obj.x, y: obj.y, w: obj.w, h: obj.h },
          unresolved: unresolved?(node),
          provenance: {
            w: axis_provenance(node, :w),
            h: axis_provenance(node, :h),
            w_max_clamped: max_clamped?(node, :w),
            h_max_clamped: max_clamped?(node, :h)
          },
          overflow: node.overflow,
          overflow_amount: overflow_amount(node)
        }
      end

      # DevTools-style box model for a node, computed without emission: its
      # deanchored bounds, the content area inset by resolved padding, the padding
      # band as 4 non-overlapping strips (top/bottom span the full width, left/right
      # fill only the middle so alphas never stack), and the gap strips between
      # consecutive in-flow children. Returns nil when geometry is unresolved.
      def box_model(node)
        bounds = draw_bounds(node)
        return nil unless bounds

        pad = node.padding_edges
        content = {
          x: bounds[:x] + pad[:left],
          y: bounds[:y] + pad[:bottom],
          w: bounds[:w] - pad[:left] - pad[:right],
          h: bounds[:h] - pad[:top] - pad[:bottom]
        }

        {
          bounds: bounds,
          content: content,
          padding: pad,
          strips: padding_strips(bounds, content, pad),
          gaps: gap_strips(node, content)
        }
      end

      # The padding band as up-to-4 edge strips. Zero-padding sides emit no strip
      # (not a zero-size one), so a node with no padding yields an empty band and a
      # full-rect content area.
      def padding_strips(bounds, content, pad)
        strips = []
        strips << { x: bounds[:x], y: bounds[:y] + bounds[:h] - pad[:top], w: bounds[:w], h: pad[:top], edge: :top } if pad[:top] > 0
        strips << { x: bounds[:x], y: bounds[:y], w: bounds[:w], h: pad[:bottom], edge: :bottom } if pad[:bottom] > 0
        strips << { x: bounds[:x], y: content[:y], w: pad[:left], h: content[:h], edge: :left } if pad[:left] > 0
        strips << { x: bounds[:x] + bounds[:w] - pad[:right], y: content[:y], w: pad[:right], h: content[:h], edge: :right } if pad[:right] > 0
        strips
      end

      # The gaps between consecutive in-flow children, derived from their laid-out
      # rects (the space layout actually left between the boxes), not recomputed gap
      # math. Only for a container with gap > 0 and 2+ in-flow children; out-of-flow
      # (absolute) children are excluded from the pairing, mirroring the flow. Each
      # strip spans the content box on the cross axis.
      def gap_strips(node, content)
        return [] unless node.gap && node.gap > 0

        flow = node.children.reject(&:absolute?)
        boxes = flow.map { |child| draw_bounds(child) }.compact
        return [] if boxes.length < 2

        if node.direction == :row
          ordered = boxes.sort_by { |box| box[:x] }
          adjacent_gaps(ordered) do |a, b|
            edge = a[:x] + a[:w]
            span = b[:x] - edge
            span > 0 ? { x: edge, y: content[:y], w: span, h: content[:h] } : nil
          end
        else
          ordered = boxes.sort_by { |box| -(box[:y] + box[:h]) }
          adjacent_gaps(ordered) do |upper, lower|
            top = lower[:y] + lower[:h]
            span = upper[:y] - top
            span > 0 ? { x: content[:x], y: top, w: content[:w], h: span } : nil
          end
        end
      end

      def adjacent_gaps(boxes)
        strips = []
        index = 0
        while index < boxes.length - 1
          strip = yield(boxes[index], boxes[index + 1])
          strips << strip if strip
          index += 1
        end
        strips
      end

      # The smallest/deepest node whose resolved box contains the point. Ties in
      # depth break toward the smaller area, so a child inside a same-depth sibling
      # stack still resolves to the tightest enclosing node.
      def node_at_point(root, x, y)
        best = nil
        best_depth = -1

        walk(root, 0) do |node, depth|
          next unless contains?(node, x, y)

          if depth > best_depth || (depth == best_depth && area(node) < area(best))
            best = node
            best_depth = depth
          end
        end

        best
      end

      def kind(node)
        return :unresolved  if unresolved?(node)
        return :out_of_flow if node.absolute?
        return :scroll      if node.render_target?
        return :container   if node.children.any?

        :leaf
      end

      def unresolved?(node)
        node.object.w.nil? || node.object.h.nil?
      end

      # Per-axis size provenance, read from the tree's own layout signals rather
      # than re-inferred: explicit (author declared w/h), grow (a grow factor grew
      # this axis, which is the parent's main axis), auto (content-derived —
      # auto_w?/auto_h?, or a text node measured from its string), else assigned
      # (an external size handed down, e.g. align: :stretch or an absolute inset).
      def axis_provenance(node, axis)
        return :explicit unless node.authored_main_size(axis).nil?
        return :grow      if grows_on?(node, axis)
        return :auto      if content_sized?(node, axis)

        :assigned
      end

      def max_clamped?(node, axis)
        cap  = axis == :w ? node.max_w : node.max_h
        size = axis == :w ? node.object.w : node.object.h
        !cap.nil? && !size.nil? && size == cap
      end

      # The amount in-flow content spills past this container's box on the layout
      # axis, or nil when it fits. Reuses the extent the scroll/overflow code
      # already computes (content_span); never recomputes layout.
      def overflow_amount(node)
        return nil if node.children.empty?

        box = node.object.h
        return nil if box.nil?

        span = node.content_span
        return nil if span.nil?

        over = span - box
        over > 0 ? over : nil
      end

      # The nearest identity: this node's id, or the closest ancestor that has one
      # plus the child-index path down to this node.
      def nearest_identity(node)
        path = []
        current = node

        while current
          return { id: current.id, path: path } if current.id

          parent = current.parent
          break unless parent

          path.unshift(parent.children.index(current))
          current = parent
        end

        { id: nil, path: path }
      end

      # --- emission -------------------------------------------------------------

      def emit_node(node, outputs)
        return if node.id == :root

        annotation = annotate(node)

        if annotation[:unresolved]
          emit_unresolved(node, outputs)
          return
        end

        color = color_for(annotation[:kind])
        box = draw_bounds(node)

        outputs.debug << { **box, **color, primitive_marker: :border }
        emit_id_label(node, box, color, outputs) if node.id
        emit_overflow_badge(annotation, box, outputs) if annotation[:overflow_amount]
      end

      def color_for(kind)
        case kind
        when :out_of_flow then OUT_OF_FLOW
        when :scroll      then SCROLL
        when :leaf        then LEAF
        else                   CONTAINER
        end
      end

      def emit_id_label(node, box, color, outputs)
        outputs.debug << {
          x: box[:x], y: box[:y] + box[:h], text: node.id.inspect,
          size_px: 12, anchor_x: 0, anchor_y: 1, **color
        }
      end

      def emit_overflow_badge(annotation, box, outputs)
        outputs.debug << {
          x: box[:x] + box[:w], y: box[:y] + box[:h],
          text: "+#{fmt(annotation[:overflow_amount])}px",
          size_px: 12, anchor_x: 1, anchor_y: 1, **SCROLL
        }
      end

      # The loud case: a node whose w or h never resolved. Draw a red crosshair
      # and a label at whatever position IS known (x/y), so a wrap container that
      # collapsed to h=nil is visible rather than silently absent.
      def emit_unresolved(node, outputs)
        obj = node.object
        x = obj.x || 0
        y = obj.y || 0

        outputs.debug << { x: x - 8, y: y, x2: x + 8, y2: y, **UNRESOLVED, primitive_marker: :line }
        outputs.debug << { x: x, y: y - 8, x2: x, y2: y + 8, **UNRESOLVED, primitive_marker: :line }
        outputs.debug << {
          x: x + 6, y: y, text: "#{node.id.inspect} #{unresolved_label(node)}".strip,
          size_px: 12, anchor_x: 0, anchor_y: 1, **UNRESOLVED
        }
      end

      def unresolved_label(node)
        parts = []
        parts << "w=nil" if node.object.w.nil?
        parts << "h=nil" if node.object.h.nil?
        parts.join(" ")
      end

      def emit_hover(node, outputs, mouse)
        model = box_model(node)

        if model
          content = model[:content]
          outputs.debug << { **content, anchor_x: 0, anchor_y: 0, **CONTENT_FILL, primitive_marker: :solid }
          model[:strips].each do |strip|
            outputs.debug << { x: strip[:x], y: strip[:y], w: strip[:w], h: strip[:h], anchor_x: 0, anchor_y: 0, **PADDING_FILL, primitive_marker: :solid }
          end
          model[:gaps].each do |strip|
            outputs.debug << { x: strip[:x], y: strip[:y], w: strip[:w], h: strip[:h], anchor_x: 0, anchor_y: 0, **GAP_FILL, primitive_marker: :solid }
          end
        end

        emit_readout(node, outputs, mouse)
      end

      def emit_readout(node, outputs, mouse)
        lines = readout_lines(node)

        line_h = 16
        pad = 6
        w = 220
        h = lines.length * line_h + pad * 2

        x = clamp(mouse.x + 16, 0, SCREEN_W - w)
        y = clamp(mouse.y - 16, h, SCREEN_H)

        outputs.debug << { x: x, y: y, w: w, h: h, anchor_x: 0, anchor_y: 1, r: 15, g: 15, b: 22, a: 225, primitive_marker: :solid }

        lines.each_with_index do |text, index|
          outputs.debug << {
            x: x + pad, y: y - pad - index * line_h, text: text,
            size_px: 12, anchor_x: 0, anchor_y: 1, r: 235, g: 235, b: 242
          }
        end
      end

      def readout_lines(node)
        annotation = annotate(node)
        rect = annotation[:rect]
        ident = nearest_identity(node)

        lines = [identity_label(ident)]
        lines << "x=#{fmt(rect[:x])} y=#{fmt(rect[:y])}"
        lines << "w=#{fmt(rect[:w])} h=#{fmt(rect[:h])}"
        lines << "w: #{provenance_label(annotation, :w)}"
        lines << "h: #{provenance_label(annotation, :h)}"
        lines << padding_readout(node)
        lines << "gap: #{fmt(node.gap)}"
        lines << "overflow: #{annotation[:overflow] || :auto}" if node.children.any?
        lines << "spill: +#{fmt(annotation[:overflow_amount])}px" if annotation[:overflow_amount]
        lines
      end

      def padding_readout(node)
        pad = node.padding_edges
        if pad[:top] == pad[:right] && pad[:right] == pad[:bottom] && pad[:bottom] == pad[:left]
          "padding: #{fmt(pad[:top])}"
        else
          "padding: t#{fmt(pad[:top])} r#{fmt(pad[:right])} b#{fmt(pad[:bottom])} l#{fmt(pad[:left])}"
        end
      end

      def identity_label(ident)
        return "(no id)" if ident[:id].nil?

        label = ident[:id].inspect
        label += " > #{ident[:path].join('.')}" unless ident[:path].empty?
        label
      end

      def provenance_label(annotation, axis)
        label = annotation[:provenance][axis].to_s
        label += " max-clamped" if annotation[:provenance][:"#{axis}_max_clamped"]
        label
      end

      # --- helpers --------------------------------------------------------------

      def grows_on?(node, axis)
        return false unless node.grow
        return false if node.absolute?

        parent = node.parent
        return false unless parent

        main = parent.direction == :row ? :w : :h
        axis == main
      end

      def content_sized?(node, axis)
        return true if node.object.has_key?(:text)

        axis == :w ? node.auto_w? : node.auto_h?
      end

      def draw_bounds(node)
        obj = node.object
        return nil if obj.w.nil? || obj.h.nil? || obj.x.nil? || obj.y.nil?

        ax = obj.anchor_x || 0
        ay = obj.anchor_y || 0
        { x: obj.x - ax * obj.w, y: obj.y - ay * obj.h, w: obj.w, h: obj.h }
      end

      def contains?(node, x, y)
        bounds = draw_bounds(node)
        return false unless bounds

        x >= bounds[:x] && x <= bounds[:x] + bounds[:w] &&
          y >= bounds[:y] && y <= bounds[:y] + bounds[:h]
      end

      def area(node)
        bounds = draw_bounds(node)
        return nil unless bounds

        bounds[:w] * bounds[:h]
      end

      def walk(node, depth, &block)
        block.call(node, depth)
        node.children.each { |child| walk(child, depth + 1, &block) }
      end

      def clamp(value, low, high)
        return low if value < low
        return high if value > high

        value
      end

      def fmt(value)
        return "nil" if value.nil?

        value.is_a?(Float) ? value.round : value
      end
    end
  end
end
