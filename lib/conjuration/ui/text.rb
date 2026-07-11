module Conjuration
  module UI
    # Text measurement and wrapping. Mixed into Node — the memo caches
    # (@measured_text, @wrapped_lines) live on the node, keyed off its text.
    #
    # Public knobs (via node declarations):
    # - +wrap: true+ on a parent enables wrapping for text children
    # - +text_break: false+ on a text node opts out of wrapping
    # - +text_break: :letter+ breaks anywhere; default +:word+ breaks on word boundaries
    #
    # @example Enable wrapping on a panel (from UIScene)
    #   node({ primitive_marker: :border, h: 200 }, id: :section_1, padding: 20, wrap: true) do
    #     node({ text: "Text wrapping breaks a long line onto multiple rows so it fits inside the panel." }, id: :sub_section_1)
    #   end
    module Text
      # Memoized text measurement: re-measure only when the string changes, so a
      # relayout that merely repositions a label doesn't re-run calcstringbox.
      #
      # @return [Array<Numeric>] +[width, height]+ from +gtk.calcstringbox+
      def measure_text
        if @measured_text != object.text
          @measured_text = object.text
          @measured_size = gtk.calcstringbox(object.text)
        end

        @measured_size
      end

      # Whether this text node wraps to a constrained width.
      #
      # @return [Boolean] true when {#wrap_width} is non-nil
      def wrapped?
        !wrap_width.nil?
      end

      # The width this text node wraps to — its parent's content width when the
      # parent set wrap: true (and this text doesn't opt out with text_break:
      # false), else nil. Coupling to the parent's width reflows it on resize.
      #
      # @return [Numeric, nil] wrap width in pixels, or nil when wrapping is off
      # @note Wrapping requires +wrap: true+ on the parent and a text-bearing
      #   object. Pass +text_break: false+ on the text node to opt out.
      def wrap_width
        return nil if text_break == false
        return nil unless object.has_key?(:text) && parent&.wrap

        parent.inner_width
      end

      # The text wrapped to width, per text_break. Memoized per [text, width, mode].
      #
      # @return [Array<String>] lines of text fitting {#wrap_width}, or +[]+ when
      #   wrapping is not active
      def wrap_lines
        width = wrap_width
        return [] unless width

        key = [object.text, width, text_break]
        return @wrapped_lines if @wrapped_key == key

        @wrapped_key = key
        @wrapped_lines = text_break == :letter ? break_by_letter(width) : break_by_word(width)
      end

      # Greedy break on word boundaries; a word wider than the width takes its own
      # line (and overflows rather than splitting).
      def break_by_word(width)
        accumulate_lines(object.text.to_s.split(" "), width) { |line, word| line.empty? ? word : "#{line} #{word}" }
      end

      # Greedy break anywhere — characters are packed until the line overflows.
      def break_by_letter(width)
        accumulate_lines(object.text.to_s.chars, width) { |line, char| line + char }
      end

      # Greedily pack tokens into lines no wider than width: each token joins the
      # current line (via the block) if it fits, else it starts a new line.
      def accumulate_lines(tokens, width)
        lines = []
        line = ""

        tokens.each do |token|
          candidate = yield(line, token)
          if line.empty? || gtk.calcstringbox(candidate)[0] <= width
            line = candidate
          else
            lines << line
            line = token
          end
        end

        lines << line unless line.empty?
        lines
      end

      # One label primitive per wrapped line, stacked down from the node's top.
      #
      # @return [Array<Hash>] label primitives ready for +outputs.primitives+
      def wrapped_text_primitives
        line_height = measure_text[1]

        wrap_lines.each_with_index.map do |line, index|
          { **styled_object, text: line, x: object.left, y: object.top - index * line_height, anchor_x: 0, anchor_y: 1 }
        end
      end
    end
  end
end