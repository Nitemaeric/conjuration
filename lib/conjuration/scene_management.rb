module Conjuration
  # Redirects screen-space output into a render target while a snapshot is
  # captured: scene HUD primitives and camera blits (which go through
  # game.render_output) land in the target; named camera targets and debug stay
  # on the real outputs.
  class ScreenRedirect
    def initialize(real, target)
      @real = real
      @target = target
    end

    def primitives
      @target.primitives
    end

    def [](name)
      @real[name]
    end

    def debug
      @real.debug
    end
  end

  module SceneManagement
    SNAPSHOT_KEY = "transition_snapshot".freeze

    def current_scene
      scene_stack.last
    end

    # Bootstrap seat (Game#setup, tests): make `scene` the sole stack entry
    # without firing any hook or the audio policy. perform_setup still runs
    # through the normal tick/super chain.
    def current_scene=(scene)
      scene_stack.clear
      scene_stack.push(scene)
    end

    # The screen target scenes and camera blits render into. Normally the real
    # outputs; temporarily a redirect while a transition snapshot is captured.
    def render_output
      @render_output || outputs
    end

    # Full transition: drain the ENTIRE stack and replace it with `to`. A
    # transition (optional, duck-typed) animates the swap over several frames;
    # nil transition is the instant swap (byte-identical to pre-transition C1).
    def change_scene(to:, transition: nil)
      begin_handover(:change, to, transition)
    end

    # Overlay: the current top pauses, `scene` becomes the new top. The
    # state-preserving swap (enter a house; the overworld survives underneath).
    # Never clears audio.
    def push_scene(scene, transition: nil)
      raise ArgumentError, "scene already on the stack" if scene_stack.any? { |entry| entry.equal?(scene) }

      begin_handover(:push, scene, transition)
    end

    # Remove the top and resume whatever is underneath. A no-op on a single-entry
    # stack — the game must always have a top scene.
    def pop_scene(transition: nil)
      return if scene_stack.size <= 1

      begin_handover(:pop, nil, transition)
    end

    # True while a transition/loading handover is mid-flight. Game#tick suspends
    # input/update (and thus every clock) until it clears.
    def transitioning?
      !@handover.nil?
    end

    # Drive the active handover one frame: load, then advance the transition
    # phases (out -> hold-while-loading -> in). Called by Game#tick instead of
    # input/update while transitioning?.
    def advance_handover
      handover = @handover
      return unless handover

      unless handover[:loaded]
        progress = tick_load(handover[:incoming])
        if progress == :done
          handover[:loaded] = true
          handover[:load_progress] = 1.0
        else
          handover[:load_progress] = progress
        end
      end

      transition = handover[:transition]

      if transition.nil?
        finish_handover(handover) if handover[:loaded]
        return
      end

      handover[:clock] += 1

      case handover[:phase]
      when :out
        if handover[:clock] >= transition.out_duration
          handover[:loaded] ? enter_in_phase(handover) : hold(handover)
        end
      when :hold
        enter_in_phase(handover) if handover[:loaded]
      when :in
        finish_handover(handover) if handover[:clock] >= transition.in_duration
      end
    end

    private

    def scene_stack
      @scene_stack ||= []
    end

    # --- handover orchestration ---------------------------------------------

    def begin_handover(mode, scene, transition)
      # Capture the outgoing frame BEFORE teardown, so a transition animates the
      # scene it is leaving even though teardown happens immediately after.
      capture_snapshot if transition

      apply_teardown(mode, scene)

      incoming = current_scene
      incoming.perform_setup if mode == :change || mode == :push

      loaded = mode == :pop || !incoming.respond_to?(:load_tick)

      # Fast path: no transition and nothing to load — resolve synchronously,
      # exactly as change/push/pop did before transitions existed.
      if transition.nil? && loaded
        finish_enter(mode, incoming)
        return
      end

      @handover = {
        mode: mode,
        incoming: incoming,
        transition: transition,
        phase: transition ? :out : :load,
        clock: 0,
        loaded: loaded,
        load_progress: loaded ? 1.0 : 0.0
      }
    end

    def apply_teardown(mode, scene)
      case mode
      when :change
        scene_stack.reverse_each { |entry| entry.on_exit if entry.respond_to?(:on_exit) }
        scene_stack.clear
        reset_focus_globals
        scene_stack.push(scene)
      when :push
        paused = current_scene
        paused.on_pause if paused.respond_to?(:on_pause)
        snapshot_focus_into(paused) # after on_pause so hook focus edits are captured
        scene_stack.push(scene)
      when :pop
        leaving = scene_stack.last
        leaving.on_exit if leaving.respond_to?(:on_exit)
        scene_stack.pop
        restore_focus_into(current_scene) # before on_resume so the hook sees real focus
      end
    end

    # on_enter (change/push) or on_resume (pop) — the "incoming is now live" edge.
    # With a transition it fires at the in-phase boundary (after load); without,
    # synchronously at handover start.
    def finish_enter(mode, incoming)
      if mode == :pop
        incoming.on_resume if incoming.respond_to?(:on_resume)
      else
        incoming.on_enter if incoming.respond_to?(:on_enter)
      end
    end

    def hold(handover)
      handover[:phase] = :hold
      handover[:clock] = 0
    end

    def enter_in_phase(handover)
      finish_enter(handover[:mode], handover[:incoming])
      handover[:phase] = :in
      handover[:clock] = 0
    end

    def finish_handover(handover)
      finish_enter(handover[:mode], handover[:incoming]) if handover[:transition].nil?
      release_snapshot
      @handover = nil
    end

    # Call load_tick until it reports :done, never after (absent load_tick reads
    # as instantly ready and is never a handover).
    def tick_load(incoming)
      return :done unless incoming.respond_to?(:load_tick)

      incoming.load_tick
    end

    # --- focus snapshot / restore -------------------------------------------

    def reset_focus_globals
      UI.focused_node = nil
      UI.hovered_node = nil
      UI.pressed_node = nil
      UI.active_navigation_group = nil
    end

    def snapshot_focus_into(scene)
      scene.saved_focus = {
        focused_node: UI.focused_node,
        active_navigation_group: UI.active_navigation_group,
        pressed_node: UI.pressed_node,
        hovered_node: UI.hovered_node,
        focus_cursor: UI.focus_cursor.dup # a mutated singleton hash
      }
    end

    def restore_focus_into(scene)
      saved = scene.respond_to?(:saved_focus) && scene.saved_focus
      return unless saved

      UI.focused_node = saved[:focused_node]
      UI.active_navigation_group = saved[:active_navigation_group]
      UI.pressed_node = saved[:pressed_node]
      UI.hovered_node = saved[:hovered_node]

      cursor = UI.focus_cursor
      saved_cursor = saved[:focus_cursor]
      cursor[:x] = saved_cursor[:x]
      cursor[:y] = saved_cursor[:y]
      cursor[:w] = saved_cursor[:w]
      cursor[:h] = saved_cursor[:h]
    end

    # --- snapshot render target ---------------------------------------------

    def capture_snapshot
      target = outputs[SNAPSHOT_KEY]
      target.width = grid.w if target.respond_to?(:width=)
      target.height = grid.h if target.respond_to?(:height=)
      target.primitives.clear

      previous = @render_output
      @render_output = ScreenRedirect.new(outputs, target)
      render_stack
      @render_output = previous
    end

    def release_snapshot
      target = outputs[SNAPSHOT_KEY]
      target.primitives.clear if target.respond_to?(:primitives)
    end

    def blit_snapshot
      outputs.primitives << { x: 0, y: 0, w: grid.w, h: grid.h, path: SNAPSHOT_KEY }
    end

    # --- lifecycle forwarders (called by Game#tick) --------------------------

    def perform_setup
      current_scene.perform_setup
    end

    # Input and update reach the top scene only; paused scenes freeze (no update
    # means their scene.clock stops, so paused gameplay holds).
    def perform_input
      current_scene.perform_input
    end

    def perform_update
      current_scene.perform_update
    end

    def perform_render
      if @handover
        render_handover(@handover)
      else
        render_stack
      end
    end

    # Render bottom-up so overlays composite over what they pause. Start at the
    # highest opaque scene (covers_below?) — everything beneath it is skipped.
    def render_stack
      index = render_floor
      while index < scene_stack.length
        scene_stack[index].perform_render
        index += 1
      end
    end

    def render_floor
      index = scene_stack.length - 1
      while index > 0
        entry = scene_stack[index]
        return index if entry.respond_to?(:covers_below?) && entry.covers_below?

        index -= 1
      end
      0
    end

    def render_handover(handover)
      transition = handover[:transition]

      if transition.nil?
        # Loading with no transition: a black backdrop plus the scene's own
        # loading_view (a progress bar), or just black if it defines none.
        outputs.primitives << { x: 0, y: 0, w: grid.w, h: grid.h, path: :pixel, r: 0, g: 0, b: 0 }
        draw_loading_view(handover)
        return
      end

      case handover[:phase]
      when :out
        blit_snapshot
        transition.draw(outputs, phase: :out, progress: phase_progress(handover, transition.out_duration), snapshot_key: SNAPSHOT_KEY, grid: grid)
      when :hold
        # Fully obscured by the transition; the loading_view (progress bar) reads
        # on top of it while the incoming scene builds.
        blit_snapshot
        transition.draw(outputs, phase: :hold, progress: 1.0, snapshot_key: SNAPSHOT_KEY, grid: grid)
        draw_loading_view(handover)
      when :in
        render_stack
        transition.draw(outputs, phase: :in, progress: phase_progress(handover, transition.in_duration), snapshot_key: SNAPSHOT_KEY, grid: grid)
      end
    end

    def draw_loading_view(handover)
      incoming = handover[:incoming]
      incoming.loading_view(handover[:load_progress]) if incoming.respond_to?(:loading_view)
    end

    def phase_progress(handover, duration)
      return 1.0 if duration.nil? || duration <= 0

      progress = handover[:clock].to_f / duration
      progress > 1.0 ? 1.0 : progress
    end
  end
end
