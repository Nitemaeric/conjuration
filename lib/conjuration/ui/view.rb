module Conjuration
  module UI
    # Mixed into scene/camera (and later view components) so node() is available
    # wherever a view block runs, emitting into the descriptor build context.
    module Builder
      def node(object_hash = nil, **opts, &block)
        UI.emit(object_hash, opts, &block)
      end

      # Memoize a subtree by a stable key plus dependency values — the block is
      # skipped (and its subtree reused as-is) while the deps compare equal.
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
    class View
      include Builder

      attr_writer :content_block

      # Default props contract — subclasses override with their own keywords. This
      # also lets a propless component be constructed with an empty kwargs splat.
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
      def self.memoize_props!
        @memoize_props = true
      end

      def self.memoize_props?
        @memoize_props ? true : false
      end

      # Emit nothing when false — conditional rendering owned by the component
      # rather than repeated at every call site.
      def render?
        true
      end

      # The caller's block children, emitted wherever the component places this.
      def content
        @content_block&.call
      end
    end
  end
end
