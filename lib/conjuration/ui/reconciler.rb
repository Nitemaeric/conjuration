module Conjuration
  module UI
    # Node-keyword arguments to node()/Node.new — everything else in a node()
    # call is object (render/geometry) data. The descriptor builder uses this to
    # split a call's keywords from its object props.
    #
    # @see Node#initialize for keyword documentation (canonical site)
    NODE_KEYWORDS = %i[
      id direction justify align gap padding visible position
      top right bottom left group overflow wrap text_break shortcut
    ].freeze

    # Node keywords that map to a writable attribute and can therefore change
    # frame-to-frame under reconciliation. Structural keywords fixed at creation
    # (overflow, wrap, text_break, the insets) are intentionally excluded.
    RECONCILABLE_OPTS = %i[direction justify align gap padding visible position group shortcut].freeze

    # A lightweight snapshot of one node() call: the resolved object hash, its
    # node-keyword options, and child descriptors. The reconciler diffs these
    # against the retained node tree instead of rebuilding Node objects, so a
    # frame that changes nothing costs a hash compare per node and no layout.
    #
    # @!attribute object [rw]
    #   @return [Hash] the render/geometry data at this node
    #
    # @!attribute opts [rw]
    #   @return [Hash] node keyword options (subset of NODE_KEYWORDS)
    #
    # @!attribute children [rw]
    #   @return [Array<Descriptor>] child descriptors
    #
    # @!attribute component_class [rw]
    #   @return [Class, nil] the view component class, if this descriptor came from one;
    #     part of reconcile identity for type-aware remounting
    class Descriptor
      attr_reader :object, :opts, :children
      # The view component that emitted this descriptor (nil for a plain node).
      # Part of the reconcile identity so swapping component types at the same
      # key remounts rather than prop-morphs.
      attr_accessor :component_class

      def initialize(object, opts)
        @object = object
        @opts = opts
        @children = []
      end
    end

    # Build a descriptor tree by running `block`. The block keeps its own self
    # (a scene or component), so node() reaches the current parent through this
    # stack rather than instance_exec — which would hide the caller's own methods
    # (state, grid, helpers). `owner` (the view root) holds the memo cache that
    # survives across frames. Cleared on the way out even if the block raises, so
    # a failed view can't strand the builder.
    #
    # @param owner [Node, nil] view root holding the memo cache; nil for descriptor-only builds
    # @param block [Proc] emits node() and component() calls
    # @return [Descriptor] the root descriptor holding child descriptors
    #
    # @note A failed block leaves no state behind; the builder stack and memo owner are
    #   cleared in an ensure clause.
    #
    # @see UI.memo
    # @see UI.component
    def self.build_tree(owner = nil, &block)
      @builder_stack = [Descriptor.new(nil, {})]
      @memo_owner = owner
      begin
        block.call
        @builder_stack.first
      ensure
        @builder_stack = nil
        @memo_owner = nil
      end
    end

    # Skip building a subtree when its inputs are unchanged: on a dep match the
    # cached descriptors (the same objects as last frame) are re-emitted, so the
    # block never runs — no fresh hashes, no string interpolation — and the
    # reconciler's identity short-circuit skips the subtree entirely. `deps` must
    # be scalars or explicitly-snapshotted values: a mutable collection compared
    # against itself always looks unchanged (see the debug warning).
    #
    # @param key [Object] cache key (typically a symbol or string)
    # @param deps [Array<Object>] dependency list; compared by value on next call
    # @param block [Proc] emits node() and component() calls
    # @return [nil]
    #
    # @note Dependencies must be scalars or explicitly-snapshotted values. Mutable
    #   collections (Hash, Array) compared against themselves always look unchanged
    #   if mutated in place; pass a version counter or immutable copy instead.
    #
    # @example Cache a large static subtree
    #   memo(:background, :static) do
    #     node(grid.rect, id: :background, direction: :row) do
    #       # 600+ nodes, built once and reused every frame
    #     end
    #   end
    #
    # @example Cache with a version counter
    #   memo(:inventory, [@inventory_version]) do
    #     inventory_list.each { |item| ItemRow(id: item.id, item: item) }
    #   end
    def self.memo(key, deps, &block)
      warn(@memo_owner, "memo(#{key.inspect}) dep #{mutable_dep(deps).inspect} is a mutable collection — memo compares it by value, so in-place mutation looks unchanged; pass a scalar or a version counter") if mutable_dep(deps)

      cache = @memo_owner.memo_cache
      entry = cache[key]
      parent = @builder_stack.last

      if entry && entry[:deps] == deps
        parent.children.concat(entry[:descriptors])
      else
        start = parent.children.length
        block.call
        cache[key] = { deps: deps, descriptors: parent.children[start..-1] }
      end
    end

    # The first mutable-collection dep (Hash/Array), or nil — memo deps should be
    # scalars or version counters, never a live collection.
    #
    # @private
    # @param deps [Array]
    # @return [Object, nil]
    def self.mutable_dep(deps)
      deps.find { |dep| dep.is_a?(Hash) || dep.is_a?(Array) }
    end

    # Debug-mode reconciliation warnings (unkeyed structural changes, mutable memo deps).
    #
    # Stored in a bounded ring (max 100 entries) so tests can assert on warnings
    # without depending on game console output. Printed to console only when the owning
    # node is in debug mode.
    #
    # @return [Array<String>] warning messages
    #
    # @see UI.warn
    def self.warnings
      @warnings ||= []
    end

    # Record a reconciliation warning for debug inspection.
    #
    # @param node [Node, nil] the node to check for debug mode; nil disables printing
    # @param message [String] warning text
    # @return [nil]
    #
    # @see UI.warnings
    def self.warn(node, message)
      warnings << message
      warnings.shift while warnings.length > 100
      puts "[conjuration] #{message}" if node&.debug?
    end

    # Emit a view component: instantiate it, check render?, run its #call, and tag
    # descriptors with the component class for type-aware reconciliation.
    #
    # Memoized components (those with memoize_props! + a keyed prop, no content block)
    # reuse their cached expansion while props compare equal—the block never runs.
    #
    # @param klass [Class] component class (must respond to #new, #render?, #call)
    # @param props [Hash] component props (passed as keyword arguments to #new)
    # @param content [Proc, nil] optional content block for the component
    # @return [nil]
    #
    # @note A component type swap at the same key remounts instead of prop-morphing.
    #   Components track their class in component_class for this identity check.
    #
    # @see UI.render_component
    #
    # @example Emit a reusable button component
    #   component(ButtonView, { id: :my_button, label: 'Click me', action: -> { handle_click } })
    #
    # @example Emit a component with content
    #   component(CardView, { id: :card, title: 'Inventory' }) do
    #     InventoryListView(items: @inventory)
    #   end
    def self.component(klass, props, &content)
      parent = @builder_stack.last
      start = parent.children.length

      if klass.memoize_props? && props.key?(:id) && content.nil? && @memo_owner
        warn(@memo_owner, "#{klass}(#{props[:id].inspect}) memoizes on a mutable prop #{mutable_dep(props.values).inspect} — pass a scalar or a version counter") if mutable_dep(props.values)
        expand_memoized_component(klass, props, parent)
      else
        expand_component(klass, props, &content)
      end

      parent.children[start..-1].each { |descriptor| descriptor.component_class = klass }
    end

    def self.expand_component(klass, props, &content)
      instance = klass.new(**props)
      instance.content_block = content
      instance.call if instance.render?
    end

    def self.expand_memoized_component(klass, props, parent)
      key = [:component, props[:id]]
      cache = @memo_owner.memo_cache
      entry = cache[key]

      if entry && entry[:props] == props
        parent.children.concat(entry[:descriptors])
      else
        start = parent.children.length
        expand_component(klass, props)
        cache[key] = { props: props, descriptors: parent.children[start..-1] }
      end
    end

    # Render a component to its descriptor children in isolation (no view root or memo).
    #
    # The basis for unit testing components without a full scene setup.
    #
    # @param klass [Class] component class
    # @param props [Hash] component props
    # @param content [Proc, nil] optional content block
    # @return [Array<Descriptor>] child descriptors emitted by the component
    #
    # @see UI.component
    def self.render_component(klass, props = {}, &content)
      build_tree { component(klass, props, &content) }.children
    end

    # Emit one node() call as a descriptor under the current parent, then (when
    # the call has a block) descend so nested node() calls attach beneath it.
    #
    # @private
    def self.emit(object_hash, opts, &block)
      object = object_hash || opts.reject { |key, _| NODE_KEYWORDS.include?(key) }
      node_opts = opts.select { |key, _| NODE_KEYWORDS.include?(key) }

      # A node keyword (direction, align, group, ...) placed inside the object
      # hash is silently ignored — it's a render prop there, not layout. This is
      # an easy mistake, so flag it. (Only when passed positionally; as a kwarg
      # it's correctly extracted into node_opts above.)
      if object_hash
        stray = object_hash.keys.select { |key| NODE_KEYWORDS.include?(key) }
        warn(@memo_owner, "node keyword(s) #{stray.join(', ')} are inside the object hash and will be ignored — pass them as keyword arguments: node({ ... }, #{stray.first}: ...)") if stray.any?
      end

      descriptor = Descriptor.new(object, node_opts)
      @builder_stack.last.children << descriptor

      if block
        @builder_stack.push(descriptor)
        begin
          block.call
        ensure
          @builder_stack.pop
        end
      end

      descriptor
    end

    # Node-side reconciliation: turning a freshly built descriptor tree into
    # writes on the retained node tree. Mixed into Node — the state it diffs
    # (@declared, children, memo_cache) lives on the node.
    module Reconciler
      # Register a declarative view: a block that emits this root's children via
      # node() each frame.
      #
      # render_view rebuilds a descriptor tree and reconciles it against the retained nodes.
      # A root is either view-driven (has a view block) or built imperatively via node()—
      # not both.
      #
      # @param block [Proc] emits node() and component() calls; runs every frame
      # @return [self]
      #
      # @see Node#render_view
      #
      # @example Register a reactive view
      #   ui.view do
      #     node({ w: 100, h: 50 }, id: :button) do
      #       node({ text: @label }, id: :label)
      #     end
      #   end
      def view(&block)
        @view_block = block
        self
      end

      # Test whether this node has a registered view block.
      #
      # @return [Boolean] true if view() was called
      #
      # @see Node#view
      def view?
        !@view_block.nil?
      end

      # Run the view into a fresh descriptor tree, then reconcile onto this root's children.
      #
      # Two-phase: the descriptor build completes before any node is touched, so an
      # exception mid-view leaves last frame's tree intact. Reconciliation then updates
      # the retained nodes based on descriptor diffs.
      #
      # @return [nil]
      #
      # @note Called automatically by the scene lifecycle; not typically called manually.
      #
      # @see Node#view
      def render_view
        return unless @view_block

        reconcile_children(UI.build_tree(self, &@view_block))
      end

      # Per-root, per-frame-surviving cache of memoized subtrees.
      #
      # Keyed by the dep array passed to memo(), or [:component, props[:id]] for
      # memoized components. Survives across reconciliations so the same memo key
      # with matching deps re-emits cached descriptors without re-rendering.
      #
      # @return [Hash] memo cache
      #
      # @see UI.memo
      # @see UI.component
      #
      # @note This is an internal cache; not typically accessed directly.
      def memo_cache
        @memo_cache ||= {}
      end

      # Reconcile one descriptor onto this node.
      #
      # The identity short-circuit makes memoized (and any other reused) subtree free:
      # if this is the very descriptor object we reconciled last frame, nothing in it
      # can have changed, so apply + recursion are skipped entirely.
      #
      # @param descriptor [Descriptor] the descriptor to reconcile
      # @return [nil]
      #
      # @private Used internally by render_view and reconcile_children.
      #
      # @note This is the core reconciliation entry point; it diffs the descriptor's
      #   props against @declared and applies changes, then recurses to children.
      def reconcile(descriptor)
        return if descriptor.equal?(@reconciled_descriptor)

        @reconciled_descriptor = descriptor
        apply_descriptor(descriptor)
        reconcile_children(descriptor)
      end

      # Reconcile a descriptor's children onto this node's children.
      #
      # The common case — same keys in the same order — takes a positional fast path.
      # When structure changes (a key added/removed, a conditional toggled, a reorder)
      # the keyed path matches by id regardless of position: creating the new,
      # discarding the gone (clearing focus so it can't dangle), and preserving
      # retained state (scroll offset, measurement caches) on everything reused.
      #
      # @param descriptor [Descriptor] the descriptor whose children to reconcile
      # @return [nil]
      #
      # @private Used internally by reconcile.
      #
      # @note Warns when unkeyed children change length (structural churn is likely).
      def reconcile_children(descriptor)
        descriptors = descriptor.children

        if aligned?(descriptors)
          descriptors.each_with_index { |child_descriptor, index| children[index].reconcile(child_descriptor) }
          return
        end

        keyed = {}
        unkeyed = []
        children.each { |child| child.id ? keyed[child.id] = child : unkeyed << child }

        new_children = []
        cursor = 0
        created_unkeyed = 0

        descriptors.each do |child_descriptor|
          key = descriptor_key(child_descriptor)

          child =
            if key
              candidate = keyed[key]
              # A same-key node of a different component type is a type swap, not
              # a reuse: leave it in the pool to be discarded, and mount fresh.
              if candidate && candidate.component_class == child_descriptor.component_class
                keyed.delete(key)
                candidate
              end
            else
              match = unkeyed[cursor]
              cursor += 1
              match
            end

          if child.nil?
            child = create_child(child_descriptor)
            created_unkeyed += 1 unless key
          end

          child.reconcile(child_descriptor)
          new_children << child
        end

        (keyed.values + unkeyed[cursor..-1].to_a).each { |orphan| discard_node!(orphan) }

        if created_unkeyed.positive? || cursor < unkeyed.length
          UI.warn(self, "unkeyed sibling list changed length under #{id.inspect} — give these nodes an id: so they reconcile by key, not position")
        end

        replace_children!(new_children)
      end

      # Write this frame's declared props onto the node, diffing against last frame's
      # declaration (@declared) — never against object, which layout has polluted with
      # computed geometry.
      #
      # Only a real change re-dirties the node; invalidate! is change-aware, so a
      # render-only tweak like color costs no layout—the next primitives pass reads
      # it off object for free.
      #
      # @param descriptor [Descriptor] the descriptor to apply
      # @return [nil]
      #
      # @private Used internally by reconcile.
      #
      # @note Action lambdas are fresh objects each frame and can't be compared; they're
      #   written unconditionally but excluded from the change test so a node whose only
      #   "change" is its recreated action stays clean.
      def apply_descriptor(descriptor)
        declared = @declared || {}
        incoming = descriptor.object

        # action presence and `disabled` aren't in the layout signature, so invalidate!
        # won't drop the interactive/navigation caches on a flip — do it here.
        if declared.key?(:action) != incoming.key?(:action) || declared[:disabled] != incoming[:disabled]
          clear_interactive_cache!
        end

        # An action lambda is a fresh object every frame and can't be compared —
        # write it through unconditionally but keep it out of the change test, so
        # a node whose only "change" is its recreated action stays clean.
        object[:action] = incoming[:action] if incoming.key?(:action)

        unless objects_equal?(incoming, declared)
          (declared.keys - incoming.keys).each { |key| object.delete(key) }
          incoming.each { |key, value| object[key] = value unless key == :action || declared[key] == value }
          @declared = incoming.dup
          invalidate!
        end

        descriptor.opts.each do |key, value|
          next unless RECONCILABLE_OPTS.include?(key)
          next if send(key) == value

          send("#{key}=", value)
          invalidate!
        end
      end

      # Whether two declared-object hashes are equal ignoring :action (which holds
      # an incomparable fresh lambda). Both directions so an added or removed key
      # counts as a change.
      #
      # @private
      def objects_equal?(a, b)
        a.each { |key, value| next if key == :action; return false unless b.key?(key) && b[key] == value }
        b.each_key { |key| next if key == :action; return false unless a.key?(key) }
        true
      end

      # Create a retained node for a descriptor with no match.
      #
      # A fresh copy of the object means layout's computed geometry pollutes the node's
      # own hash, not the descriptor's (which we diff against next frame); @declared
      # seeds the pure declaration. Not appended here—reconcile_children assembles the
      # final child order and replace_children! commits it.
      #
      # @param descriptor [Descriptor]
      # @return [Node] the new child node
      #
      # @private Used internally by reconcile_children.
      def create_child(descriptor)
        child = Node.new(descriptor.object.dup, **descriptor.opts)
        child.parent = self
        child.declared = descriptor.object.dup
        child.component_class = descriptor.component_class
        child
      end

      # Commit a reconciled child list.
      #
      # A no-op when the set and order are unchanged (the clean-frame path); otherwise
      # it rebuilds the structure caches and forces relayout. It must force (mark_dirty!,
      # not the change-aware invalidate!): swapping a child for a different one—or
      # reordering—leaves the layout_signature untouched (child count is the same), so
      # a signature check would wrongly skip the relayout and the new children would
      # never be positioned.
      #
      # @param new_children [Array<Node>]
      # @return [nil]
      #
      # @private Used internally by reconcile_children.
      def replace_children!(new_children)
        return if new_children == children

        @children = new_children
        clear_structure_cache!
        mark_dirty!
      end

      # A removed node leaves the tree: drop any focus/press pointing at it or a
      # descendant so a stale global can't dangle. (Scroll offset and measurement
      # caches ride along on reused nodes; a discarded node is simply dropped.)
      #
      # @param node [Node] the node being discarded
      # @return [nil]
      #
      # @private Used internally by reconcile_children.
      def discard_node!(node)
        node.nodes.each do |gone|
          UI.focused_node = nil if UI.focused_node.equal?(gone)
          UI.hovered_node = nil if UI.hovered_node.equal?(gone)
          UI.pressed_node = nil if UI.pressed_node.equal?(gone)
        end
      end

      # Whether the descriptors line up 1:1 with the current children by id and
      # order — the stable-tree case, reconciled positionally with no keyed maps.
      #
      # @param descriptors [Array<Descriptor>]
      # @return [Boolean]
      #
      # @private Used internally by reconcile_children.
      def aligned?(descriptors)
        return false unless descriptors.length == children.length

        descriptors.each_with_index do |child_descriptor, index|
          child = children[index]
          return false unless child.id == descriptor_key(child_descriptor) && child.component_class == child_descriptor.component_class
        end
        true
      end

      # A descriptor's reconcile key: its id (symbolised to match Node#id), or nil
      # when unkeyed.
      #
      # @param descriptor [Descriptor]
      # @return [Symbol, nil]
      #
      # @private Used internally by reconcile_children.
      def descriptor_key(descriptor)
        key = descriptor.opts[:id]
        key && key.to_sym
      end
    end
  end
end
