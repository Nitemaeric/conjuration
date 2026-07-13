module Conjuration
  module UI
    # Node-keyword arguments to node()/Node.new — everything else in a node()
    # call is object (render/geometry) data. The descriptor builder uses this to
    # split a call's keywords from its object props.
    NODE_KEYWORDS = %i[
      id direction justify align gap padding visible position
      top right bottom left group overflow wrap text_break shortcut grow max_w max_h
    ].freeze

    # Node keywords that map to a writable attribute and can therefore change
    # frame-to-frame under reconciliation. Structural keywords fixed at creation
    # (overflow, wrap, text_break, the insets) are intentionally excluded.
    RECONCILABLE_OPTS = %i[direction justify align gap padding visible position group shortcut grow max_w max_h].freeze

    # A lightweight snapshot of one node() call: the resolved object hash, its
    # node-keyword options, and child descriptors. The reconciler diffs these
    # against the retained node tree instead of rebuilding Node objects, so a
    # frame that changes nothing costs a hash compare per node and no layout.
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
    def self.mutable_dep(deps)
      deps.find { |dep| dep.is_a?(Hash) || dep.is_a?(Array) }
    end

    # Debug-mode reconciliation warnings (unkeyed structural churn, mutable memo
    # deps). Collected into a bounded ring so tests can assert on them without a
    # debug game; printed only when the owning node is in debug mode.
    def self.warnings
      @warnings ||= []
    end

    def self.warn(node, message)
      warnings << message
      warnings.shift while warnings.length > 100
      puts "[conjuration] #{message}" if node&.debug?
    end

    # Emit a view component: instantiate it, gate on render?, run its #call to
    # produce node descriptors, and tag those descriptors with the component
    # class so a type swap at the same key remounts instead of prop-morphing.
    # Memoized components (memoize_props! + a keyed prop, no content block) reuse
    # their cached expansion while props compare equal — the block never runs.
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

    # Render a component to its descriptor children, no scene required — the
    # basis for isolated component tests.
    def self.render_component(klass, props = {}, &content)
      build_tree { component(klass, props, &content) }.children
    end

    # Emit one node() call as a descriptor under the current parent, then (when
    # the call has a block) descend so nested node() calls attach beneath it.
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
      # node() each frame. render_view rebuilds a descriptor tree and reconciles
      # it against the retained nodes. A root is either view-driven or built
      # imperatively via node() — not both.
      def view(&block)
        @view_block = block
        self
      end

      def view?
        !@view_block.nil?
      end

      # Run the view into a fresh descriptor tree, then reconcile onto this root's
      # children. Two-phase: the descriptor build completes before any node is
      # touched, so an exception mid-view leaves last frame's tree intact.
      def render_view
        return unless @view_block

        reconcile_children(UI.build_tree(self, &@view_block))
      end

      # Per-root, per-frame-surviving cache of memoized subtrees (see UI.memo).
      def memo_cache
        @memo_cache ||= {}
      end

      # Reconcile one descriptor onto this node. The identity short-circuit makes
      # memoized (and any other reused) subtree free: if this is the very
      # descriptor object we reconciled last frame, nothing in it can have
      # changed, so apply + recursion are skipped entirely.
      def reconcile(descriptor)
        return if descriptor.equal?(@reconciled_descriptor)

        @reconciled_descriptor = descriptor
        apply_descriptor(descriptor)
        reconcile_children(descriptor)
      end

      # Reconcile a descriptor's children onto this node's children. The common
      # case — same keys in the same order — takes a positional fast path. When
      # structure changes (a key added/removed, a conditional toggled, a reorder)
      # the keyed path matches by id regardless of position: creating the new,
      # discarding the gone (clearing focus so it can't dangle), and preserving
      # retained state (scroll offset, measurement caches) on everything reused.
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

      # Write this frame's declared props onto the node, diffing against last
      # frame's declaration (@declared) — never against object, which layout has
      # polluted with computed geometry. Only a real change re-dirties the node
      # (invalidate! is change-aware, so a render-only tweak like colour costs no
      # layout — the next primitives pass reads it off object for free).
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

          # Re-snapshot authored sizes (grow/stretch basis + declaredness) and, if a
          # size appeared or vanished, drop the measure cache: the node just crossed
          # between fixed and auto-sized.
          auto_before = [@authored_w.nil?, @authored_h.nil?]
          @authored_w = incoming[:w]
          @authored_h = incoming[:h]
          clear_measure_cache! if auto_before != [@authored_w.nil?, @authored_h.nil?]

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
      def objects_equal?(a, b)
        a.each { |key, value| next if key == :action; return false unless b.key?(key) && b[key] == value }
        b.each_key { |key| next if key == :action; return false unless a.key?(key) }
        true
      end

      # Create a retained node for a descriptor with no match. A fresh copy of the
      # object means layout's computed geometry pollutes the node's own hash, not
      # the descriptor's (which we diff against next frame); @declared seeds the
      # pure declaration. Not appended here — reconcile_children assembles the
      # final child order and replace_children! commits it.
      def create_child(descriptor)
        child = Node.new(descriptor.object.dup, **descriptor.opts)
        child.parent = self
        child.declared = descriptor.object.dup
        child.component_class = descriptor.component_class
        child
      end

      # Commit a reconciled child list. A no-op when the set and order are
      # unchanged (the clean-frame path); otherwise it rebuilds the structure
      # caches and forces relayout. It must force (mark_dirty!, not the
      # change-aware invalidate!): swapping a child for a different one — or
      # reordering — leaves the layout_signature untouched (child count is the
      # same), so a signature check would wrongly skip the relayout and the new
      # children would never be positioned.
      def replace_children!(new_children)
        return if new_children == children

        @children = new_children
        clear_structure_cache!
        mark_dirty!
      end

      # A removed node leaves the tree: drop any focus/press pointing at it or a
      # descendant so a stale global can't dangle. (Scroll offset and measurement
      # caches ride along on reused nodes; a discarded node is simply dropped.)
      def discard_node!(node)
        node.nodes.each do |gone|
          UI.focused_node = nil if UI.focused_node.equal?(gone)
          UI.hovered_node = nil if UI.hovered_node.equal?(gone)
          UI.pressed_node = nil if UI.pressed_node.equal?(gone)
        end
      end

      # Whether the descriptors line up 1:1 with the current children by id and
      # order — the stable-tree case, reconciled positionally with no keyed maps.
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
      def descriptor_key(descriptor)
        key = descriptor.opts[:id]
        key && key.to_sym
      end
    end
  end
end
