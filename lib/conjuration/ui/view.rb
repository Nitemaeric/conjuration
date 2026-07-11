module Conjuration
  module UI
    # Mixed into scene/camera (and later view components) so node() is available
    # wherever a view block runs, emitting into the descriptor build context.
    module Builder
      # Emit a node into the current descriptor build context.
      #
      # The object hash becomes the node's renderable/layout payload; keyword
      # opts (id:, group:, overflow:, shortcut:, etc.) configure the node.
      # Nested node/memo/component calls inside the block become children.
      #
      # @param object_hash [Hash, nil] renderable/layout props (text:, path:,
      #   action:, w:, h:, etc.)
      # @param opts [Hash] node configuration (id:, group:, justify:, align:,
      #   gap:, padding:, overflow:, shortcut:, wrap:, etc.)
      # @yield optional child-building block
      # @return [void]
      # @example Button with nested label (from ButtonView)
      #   node(object, id: @id, justify: :center, align: :center, shortcut: @shortcut) do
      #     node({ text: @label, r: 255, g: 255, b: 255 }, id: "#{@id}_label")
      #   end
      # @example Navigation group and scroll container (from UIScene)
      #   node({}, id: :skills, group: :skills) do
      #     8.times { |i| node({ action: -> { puts "skill #{i + 1}" } }, id: "skill_#{i + 1}") }
      #   end
      #   node({}, id: :scroll_list, overflow: :scroll, padding: 12, gap: 8, group: :list) do
      #     16.times { |i| node({ text: "Item #{i + 1}" }, id: "item_#{i + 1}") }
      #   end
      def node(object_hash = nil, **opts, &block)
        UI.emit(object_hash, opts, &block)
      end

      # Memoize a subtree by a stable key plus dependency values — the block is
      # skipped (and its subtree reused as-is) while the deps compare equal.
      #
      # @param key [Object] stable identity for this memo slot (e.g. a component id)
      # @param deps [Array] dependency values; any change re-runs the block
      # @yield builds the subtree when deps change (or on first build)
      # @return [void]
      # @example Device-aware prompt row (from PromptView)
      #   memo(@id, style) do
      #     glyphs = resolve_glyphs(style)
      #     # ... build UI ...
      #   end
      def memo(key, *deps, &block)
        UI.memo(key, deps, &block)
      end
    end

    # Base class for view components (ViewComponent-inspired): subclass, take
    # props in initialize, and define #call to emit nodes. Subclassing defines a
    # builder method named after the class, so components read as function calls
    # in a view:
    #
    #   class MenuView < Conjuration::UI::View
    #     def initialize(items:)  = (@items = items)
    #     def render?             = @items.any?
    #     def call
    #       node({ ... }, id: :menu) do
    #         @items.each { |item| node({ text: item.name }, id: item.id) }
    #         content   # the caller's block children, placed here
    #       end
    #     end
    #   end
    #
    #   MenuView(items: state.items)    # invoke with parens (bareword = the class)
    #   Panel(title: "x") { node(...) } # a block becomes the component's content
    #
    # @example ButtonView subclass (from demo)
    #   class ButtonView < Conjuration::UI::View
    #     def initialize(id:, label:, action:, width: 100, height: 44, shortcut: nil, pad: nil)
    #       @id = id
    #       @label = label
    #       @action = action
    #       @width = width
    #       @height = height
    #       @shortcut = shortcut
    #       @pad = pad
    #     end
    #
    #     def call
    #       object = { h: @height, path: "sprites/button.png", action: @action }
    #       object[:w] = @width if @width
    #       node(object, id: @id, justify: :center, align: :center, shortcut: @shortcut) do
    #         node({ text: @label, r: 255, g: 255, b: 255 }, id: "#{@id}_label")
    #       end
    #     end
    #   end
    #
    #   ButtonView(id: :play, label: "Play", action: -> { change_scene(...) })
    class View
      include Builder

      attr_writer :content_block

      # Default props contract — subclasses override with their own keywords. This
      # also lets a propless component be constructed with an empty kwargs splat.
      #
      # @param _props [Hash] keyword props accepted by the subclass
      # @return [Conjuration::UI::View]
      # @example (from ButtonView)
      #   def initialize(id:, label:, action:, width: 100, height: 44, shortcut: nil, pad: nil)
      #     @id = id
      #     @label = label
      #     @action = action
      #     @width = width
      #     @height = height
      #     @shortcut = shortcut
      #     @pad = pad
      #   end
      def initialize(**_props); end

      # Define a builder method named after each subclass (demodulised) so
      # SomeView(**props) reads as a call — uppercase method names are legal Ruby
      # when invoked with parens.
      def self.inherited(subclass)
        name = subclass.name
        return unless name

        method_name = name.split("::").last
        UI.warn(nil, "component builder #{method_name} is already defined — namespaced components share a demodulised name") if Builder.method_defined?(method_name)

        Builder.send(:define_method, method_name) do |**props, &content|
          UI.component(subclass, props, &content)
        end
      end

      # Opt into props-equality memoization: while a keyed component's props
      # compare equal, its #call is skipped and last frame's subtree reused.
      #
      # @return [void]
      def self.memoize_props!
        @memoize_props = true
      end

      # Whether this component class opted into props-equality memoization via
      # {memoize_props!}.
      #
      # @return [Boolean]
      def self.memoize_props?
        @memoize_props ? true : false
      end

      # Emit nothing when false — conditional rendering owned by the component
      # rather than repeated at every call site.
      #
      # @return [Boolean] false to skip emitting this component entirely
      def render?
        true
      end

      # The caller's block children, emitted wherever the component places this.
      #
      # @return [Object, nil] the result of the caller's content block, if any
      def content
        @content_block&.call
      end
    end
  end
end
