module Conjuration
  # Default digital/analog bindings for UI navigation and confirm. Injected into
  # every action set that lacks them so menus work without game wiring.
  #
  # @return [Hash{Symbol => Hash}] reserved action names to controller/keyboard bindings
  # @note Single source of default UI bindings. Games may rebind any entry; injection
  #   is gaps-only, so a game's own binding always wins.
  # @note +:ui_*+ names are reserved. Unknown actions are never bootstrapped from this table.
  # @see Conjuration::UI_ANALOG_ACTIONS
  # @see Conjuration::DragonInputSource
  UI_ACTIONS = {
    # Space is intentionally unbound: games commonly use it (the hit-stop demo
    # swings with it), so confirming on it would double-fire.
    ui_confirm: { controller: :a,            keyboard: :enter },
    ui_up:      { controller: :dpad_up,      keyboard: :up },
    ui_down:    { controller: :dpad_down,    keyboard: :down },
    ui_left:    { controller: :dpad_left,    keyboard: :left },
    ui_right:   { controller: :dpad_right,   keyboard: :right },
    # Analog navigation: the right stick, read with flick semantics (see
    # DragonInputSource#navigation_flick). No keyboard side — the keys keep the
    # digital arrows above.
    ui_navigate: { controller: :right_analog }
  }.freeze

  # The analog members of UI_ACTIONS — injected via set.analog and read via
  # DragonInput.axis rather than the digital path.
  #
  # @return [Array<Symbol>] action names that use the analog injection path
  # @see Conjuration::UI_ACTIONS
  UI_ANALOG_ACTIONS = %i[ui_navigate].freeze

  # Default input source for Conjuration UI and gameplay queries. Wraps
  # DragonInput so reserved +:ui_*+ actions are injected on demand and unknown
  # actions read as inactive rather than raising.
  #
  # @note Contract: +just_pressed?+ / +pressed?+ take +(pad, action)+. +action+ may
  #   be a reserved +:ui_*+ name (injected from {UI_ACTIONS}) or a game-defined
  #   action. Unknown actions return inactive (all false).
  # @note DragonInput.setup bootstraps a +:ui+ set on the first reserved-name
  #   query if no config exists yet, so menus work without explicit wiring.
  # @example Game-defined actions (demo/mygame/app/game.rb)
  #   DragonInput.setup do |c|
  #     c.action_set :gameplay do |s|
  #       s.digital :attack, controller: :b, keyboard: :space
  #       s.digital :start, controller: :start, keyboard: :enter
  #       s.analog :pan, controller: :left_analog, keyboard: :wasd
  #     end
  #   end
  # @example Querying a game action (demo hit_stop_scene)
  #   start_swing if game.input_source.just_pressed?(game.ui_pad, :attack)
  # @see Conjuration::UI_ACTIONS
  class DragonInputSource
    INACTIVE = { down: false, held: false, up: false, active: false }.freeze

    # Flick thresholds for analog navigation: fire once when the deflection
    # crosses FLICK_ENGAGE, re-arm once it falls back below FLICK_RELEASE. The gap
    # is hysteresis so a stick hovering near the edge can't chatter.
    FLICK_ENGAGE = 0.5
    FLICK_RELEASE = 0.35

    # True on the frame the action transitions to pressed (down edge).
    #
    # @param pad [Symbol] gamepad identifier (e.g. +:one+, or +game.ui_pad+)
    # @param action [Symbol] reserved +:ui_*+ name or game-defined action
    # @return [Boolean] true only on the down edge
    # @note Unknown actions read as not pressed ({INACTIVE}).
    # @example (demo hit_stop_scene)
    #   start_swing if game.input_source.just_pressed?(game.ui_pad, :attack)
    def just_pressed?(pad, action)
      digital(pad, action)[:down]
    end

    # True while the action is held or on its down edge.
    #
    # @param pad [Symbol] gamepad identifier (e.g. +:one+, or +game.ui_pad+)
    # @param action [Symbol] reserved +:ui_*+ name or game-defined action
    # @return [Boolean] true while held or just pressed
    # @note Unknown actions read as not pressed ({INACTIVE}).
    def pressed?(pad, action)
      state = digital(pad, action)
      state[:held] || state[:down]
    end

    # One navigation step from the right stick, or nil. Flick semantics: a single
    # step per neutral->deflected crossing, in the dominant axis; the stick must
    # return to neutral to re-arm (no repeat-while-held in v1). @flick_armed is the
    # only state — nil/true means ready, false means already fired this deflection.
    #
    # @param pad [Symbol] gamepad identifier
    # @return [Hash{Symbol => Integer}, nil] +{x:, y:}+ with one axis ±1, or +nil+
    # @note Uses flick hysteresis: engage at {FLICK_ENGAGE}, re-arm below
    #   {FLICK_RELEASE}. Dominant axis only (no diagonals).
    def navigation_flick(pad)
      config = DragonInput.config
      config = bootstrap_config if config.nil?
      return nil unless config

      ensure_injected(config)
      axis = DragonInput.axis(pad, :ui_navigate)

      # active:false means a set was (re)built since our last injection —
      # re-inject and read once more, as the digital path does.
      unless axis[:active]
        inject(config)
        axis = DragonInput.axis(pad, :ui_navigate)
      end

      x = axis[:x]
      y = axis[:y]
      magnitude = x.abs > y.abs ? x.abs : y.abs

      @flick_armed = true if magnitude < FLICK_RELEASE
      return nil unless @flick_armed && magnitude >= FLICK_ENGAGE

      @flick_armed = false
      if x.abs >= y.abs
        { x: x > 0 ? 1 : -1, y: 0 }
      else
        { x: 0, y: y > 0 ? 1 : -1 }
      end
    end

    # Query a UI shortcut's down edge, injecting its digital action (gaps-only, so
    # a game can rebind it) the first time it's seen. `name` is deterministic per
    # node (:ui_shortcut_<id>); `bindings` is { keyboard:, controller: }.
    #
    # @param pad [Symbol] gamepad identifier
    # @param name [Symbol] deterministic shortcut action name (e.g. +:ui_shortcut_back+)
    # @param bindings [Hash] +{ keyboard:, controller: }+ device bindings
    # @return [Boolean] true on the down edge of the shortcut
    # @note Injection is gaps-only: a game binding for +name+ is never overwritten.
    def shortcut_just_pressed?(pad, name, bindings)
      config = DragonInput.config
      config = bootstrap_config if config.nil?
      return false unless config

      ensure_injected(config)
      inject_shortcut(config, name, bindings)
      DragonInput.digital(pad, name)[:down]
    end

    private

    # Inject a shortcut's digital action into every set that lacks it. Gaps-only —
    # runs each query but re-adds only where missing (a game's own binding, or a
    # freshly rebuilt set), so the steady state is one lookup per set.
    def inject_shortcut(config, name, bindings)
      config.action_sets.each_value do |set|
        set.digital(name, **bindings) unless set.action(name)
      end
    end

    def digital(pad, action)
      config = DragonInput.config

      # Bootstrap at query time (not load time) so a game's own later setup wins,
      # and only for reserved names so a game's own actions never get a config.
      config = bootstrap_config if config.nil? && UI_ACTIONS.key?(action)
      return INACTIVE unless config

      ensure_injected(config)
      result = DragonInput.digital(pad, action)

      # active:false on a reserved name means a set was (re)built since our last
      # injection: re-inject and read once more.
      if !result[:active] && UI_ACTIONS.key?(action)
        inject(config)
        result = DragonInput.digital(pad, action)
      end

      result
    end

    def bootstrap_config
      # setup returns the backend, not the config, so re-read the facade.
      DragonInput.setup { |c| c.action_set(:ui) }
      DragonInput.config
    end

    def ensure_injected(config)
      sets = config.action_sets
      return if @injected_sets_id == sets.object_id && @injected_sets_size == sets.size

      inject(config)
      @injected_sets_id = sets.object_id
      @injected_sets_size = sets.size
    end

    def inject(config)
      config.action_sets.each_value do |set|
        UI_ACTIONS.each do |name, bindings|
          next if set.action(name)

          if UI_ANALOG_ACTIONS.include?(name)
            set.analog(name, **bindings)
          else
            set.digital(name, **bindings)
          end
        end
      end
    end
  end
end
