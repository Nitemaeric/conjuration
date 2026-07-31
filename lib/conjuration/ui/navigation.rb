module Conjuration
  module UI
    # Keyboard/controller navigation focus. The mouse never writes this — it
    # tracks hovered_node instead — so focus survives a mouse interlude.
    def self.focused_node
      @focused_node
    end

    def self.focused_node=(node)
      @focused_node = node
    end

    # The interactive node under the mouse. Drives hover styling and click
    # targeting; independent of focused_node.
    def self.hovered_node
      @hovered_node
    end

    def self.hovered_node=(node)
      @hovered_node = node
    end

    def self.pressed_node
      @pressed_node
    end

    def self.pressed_node=(node)
      @pressed_node = node
    end

    # [path, hotspot_x, hotspot_y]; applied by the input loop on focus change.
    def self.hover_cursor
      @hover_cursor
    end

    def self.hover_cursor=(cursor)
      @hover_cursor = cursor
    end

    def self.default_cursor
      @default_cursor
    end

    def self.default_cursor=(cursor)
      @default_cursor = cursor
    end

    # Games that style focus themselves (per-state styles, custom cursors) turn
    # the built-in indicator off here; a scene can override focus_indicator_enabled?
    # to opt back in.
    def self.focus_indicator_default
      @focus_indicator_default.nil? ? true : @focus_indicator_default
    end

    def self.focus_indicator_default=(value)
      @focus_indicator_default = value
    end

    # Lerp state for the focus indicator (the highlight that trails focused_node).
    def self.focus_cursor
      @focus_cursor ||= { x: 0, y: 0, w: 0, h: 0 }
    end

    # The active navigation group (a node's `group:` id). The game owns this —
    # there is no built-in trigger to switch groups; you set it yourself. nil
    # disables UI navigation entirely: the input loop is inert until a group is
    # set, so menus stay dormant while gameplay owns the input.
    def self.active_navigation_group
      @active_navigation_group
    end

    def self.active_navigation_group=(group)
      @active_navigation_group = group
    end

    # Interactive-ness, focus/hover/press queries, navigation groups, and beam
    # spatial navigation. Mixed into Node — the caches (@interactive_nodes,
    # @navigation_index, @shortcut_nodes) and the shortcut attribute live there.
    module Navigation
      def interactive_nodes
        @interactive_nodes ||= nodes.select(&:interactive?)
      end

      # The nodes keyboard/pad navigation may land on. Narrower than
      # interactive_nodes, which hit-testing and hover still need in full.
      def navigable_nodes
        @navigable_nodes ||= nodes.select(&:navigable?)
      end

      # A scroll container is interactive so an empty pane can be focused and
      # stick-scrolled, but once it holds interactive items those items represent
      # it — otherwise focus lands on the pane itself partway down a list. A pane
      # with its own action is a real target and stays navigable.
      def navigable?
        return false unless interactive?
        return true if has_key?(:action)

        !(scroll? && interactive_descendant?)
      end

      def interactive_descendant?
        children.any? { |child| child.interactive? || child.interactive_descendant? }
      end

      # The interactive nodes carrying a shortcut, memoized on the root and rebuilt
      # only when the structure/interactive caches are — so the input loop iterates
      # a cached list each frame rather than rewalking the tree. Empty (and free)
      # when nothing in the ui declares a shortcut.
      def shortcut_nodes
        @shortcut_nodes ||= interactive_nodes.select(&:shortcut)
      end

      # Reconcilable like a plain opt, but a change to shortcut presence flips
      # membership in shortcut_nodes, so drop the interactive caches on any change.
      def shortcut=(value)
        return if @shortcut == value

        @shortcut = value
        clear_interactive_cache!
      end

      # Reconcilable: the flag is read off the group registry, so a change has to
      # drop it.
      def nav_wrap=(value)
        return if @nav_wrap == value

        @nav_wrap = value
        clear_interactive_cache!
      end

      # The injected action name backing this node's shortcut — deterministic by
      # id so a game can rebind it, and public so display code can resolve its
      # glyph (e.g. DragonInput.glyph(pad, node.shortcut_action_name)).
      def shortcut_action_name
        :"ui_shortcut_#{id || object_id}"
      end

      # Interactive nodes bucketed by their navigation group — the nearest
      # ancestor's `group:`. Ungrouped nodes are omitted: groups are explicit and
      # named, and the game decides which one is active.
      def navigation_groups
        navigation_index[:groups]
      end

      # The named group's wrap declaration — `nav_wrap:` on the node that declares
      # the group: true wraps both axes, :x only horizontal presses, :y only
      # vertical. nil/false unless declared.
      def navigation_group_wrap(id)
        navigation_index[:wraps][id]
      end

      def navigation_index
        @navigation_index ||= accumulate_navigation_groups(nil, { groups: {}, wraps: {} })
      end

      # The group id a given interactive node belongs to (or nil if ungrouped).
      def group_of(target)
        navigation_groups.each do |id, members|
          return id if members.any? { |member| member.equal?(target) }
        end
        nil
      end

      # Recursive helper for navigation_groups; threads the nearest enclosing
      # group down the tree so the innermost group wins. Wrapping is a property of
      # the declaration, so it is recorded against this node's own `group:`.
      def accumulate_navigation_groups(inherited, index)
        current = group || inherited
        index[:wraps][group] = nav_wrap if group && nav_wrap
        (index[:groups][current] ||= []) << self if navigable? && current
        children.each { |child| child.accumulate_navigation_groups(current, index) }
        index
      end

      # The interactive node `direction` leads to from `from`, among `candidates`
      # (default: all interactive nodes; the input loop passes the active group's
      # members to keep navigation inside a pane).
      #
      # A candidate whose cross-axis span overlaps the source's (the "beam")
      # categorically outranks every non-beam candidate, however near: this is what
      # makes an aligned neighbour win over a closer diagonal one. Only when the
      # beam is empty do we fall back to the nearest node in a 45-degree cone.
      #
      # `wrap` (the active group's nav_wrap) turns the dead end at an edge into a
      # jump to the far side instead of a stay-put.
      def spatial_navigate(from, direction, candidates: navigable_nodes, wrap: false)
        return candidates.first if from.nil?

        source = from.rect
        origin = source.center
        horizontal = direction.x != 0

        main_sign = horizontal ? direction.x : direction.y
        if horizontal
          src_main_lo, src_main_hi = source.left, source.right
          beam_lo, beam_hi = source.bottom, source.top
        else
          src_main_lo, src_main_hi = source.bottom, source.top
          beam_lo, beam_hi = source.left, source.right
        end

        beam_best = nil
        beam_gap = nil
        beam_offset = nil
        fallback_best = nil
        fallback_score = nil

        candidates.each do |node|
          next if node.equal?(from)

          rect = node.rect
          centre = rect.center
          dx = centre.x - origin.x
          dy = centre.y - origin.y

          # Eligibility: the centre must lie strictly beyond the source along the
          # direction axis (a permissive centre test — edge-based exclusion strands
          # focus in overlapping layouts).
          along = dx * direction.x + dy * direction.y
          next unless along > 0

          if horizontal
            cand_lo, cand_hi = rect.bottom, rect.top
            cand_main_lo, cand_main_hi = rect.left, rect.right
            cross_offset = dy.abs
          else
            cand_lo, cand_hi = rect.left, rect.right
            cand_main_lo, cand_main_hi = rect.bottom, rect.top
            cross_offset = dx.abs
          end

          if cand_hi > beam_lo && cand_lo < beam_hi
            gap = main_sign > 0 ? cand_main_lo - src_main_hi : src_main_lo - cand_main_hi
            gap = 0 if gap < 0
            if beam_gap.nil? || gap < beam_gap || (gap == beam_gap && cross_offset < beam_offset)
              beam_best = node
              beam_gap = gap
              beam_offset = cross_offset
            end
          else
            across = (dx * direction.y - dy * direction.x).abs
            next if along < across

            weighted = along + 2 * across
            if fallback_score.nil? || weighted < fallback_score
              fallback_best = node
              fallback_score = weighted
            end
          end
        end

        found = beam_best || fallback_best
        return found if found || !wrap_applies?(wrap, direction)

        wrap_navigate(from, direction, candidates)
      end

      # A row that wraps horizontally must still dead-end vertically — otherwise
      # a down press at a row's edge "wraps" onto the adjacent slot, the only
      # far-end candidate there is. :x/:y scope the wrap to one axis.
      def wrap_applies?(wrap, direction)
        return false unless wrap
        return true if wrap == true
        return direction.x != 0 if wrap == :x
        return direction.y != 0 if wrap == :y

        false
      end

      # The far-end candidate a press at the edge wraps onto: down at the bottom
      # lands on the topmost node, right at the right edge on the leftmost. Beam
      # alignment wins outright over distance, so a grid wraps within its own
      # column (or row), and only an unaligned wrap falls back to the candidate
      # nearest the source's axis.
      def wrap_navigate(from, direction, candidates)
        source = from.rect
        origin = source.center
        horizontal = direction.x != 0
        main_sign = horizontal ? direction.x : direction.y
        beam_lo, beam_hi = horizontal ? [source.bottom, source.top] : [source.left, source.right]

        aligned_best = nil
        aligned_reach = nil
        aligned_offset = nil
        any_best = nil
        any_reach = nil
        any_offset = nil

        candidates.each do |node|
          next if node.equal?(from)

          rect = node.rect
          centre = rect.center
          if horizontal
            cand_lo, cand_hi = rect.bottom, rect.top
            reach = centre.x * main_sign
            cross_offset = (centre.y - origin.y).abs
          else
            cand_lo, cand_hi = rect.left, rect.right
            reach = centre.y * main_sign
            cross_offset = (centre.x - origin.x).abs
          end

          # Smallest reach = furthest back against the pressed direction.
          if cand_hi > beam_lo && cand_lo < beam_hi
            if aligned_reach.nil? || reach < aligned_reach || (reach == aligned_reach && cross_offset < aligned_offset)
              aligned_best = node
              aligned_reach = reach
              aligned_offset = cross_offset
            end
          end

          if any_reach.nil? || reach < any_reach || (reach == any_reach && cross_offset < any_offset)
            any_best = node
            any_reach = reach
            any_offset = cross_offset
          end
        end

        aligned_best || any_best
      end

      def interactive?
        # Cheap checks first: most nodes have neither an action nor scroll, so
        # short-circuit before the visible_in_tree? parent walk (this runs over
        # every node, every tick). A scroll container is focusable too, so it can
        # be navigated to and scrolled with the right stick once focused.
        return false unless has_key?(:action) || scroll?

        !disabled? && visible_in_tree?
      end

      def disabled?
        !!object[:disabled]
      end

      def focused?
        UI.focused_node.equal?(self)
      end

      def hovered?
        UI.hovered_node.equal?(self)
      end

      def pressed?
        UI.pressed_node.equal?(self)
      end

      def interaction_state
        return :disabled if disabled?
        return :pressed if pressed?
        return :hover if hovered?
        return :focused if focused?

        :default
      end

      # Nodes declare per-state style overrides as hover:/focused:/pressed:/
      # disabled: hashes. Without a focused: override, focus falls back to the
      # hover: style so hover-only buttons still read as selected under nav.
      def styled_object
        state = interaction_state
        override = object[state]
        override = object[:hover] if override.nil? && state == :focused
        return object unless override.is_a?(Hash)

        { **object, **override }
      end
    end
  end
end
