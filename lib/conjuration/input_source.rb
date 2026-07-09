module Conjuration
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
  UI_ANALOG_ACTIONS = %i[ui_navigate].freeze

  class DragonInputSource
    INACTIVE = { down: false, held: false, up: false, active: false }.freeze

    # Flick thresholds for analog navigation: fire once when the deflection
    # crosses FLICK_ENGAGE, re-arm once it falls back below FLICK_RELEASE. The gap
    # is hysteresis so a stick hovering near the edge can't chatter.
    FLICK_ENGAGE = 0.5
    FLICK_RELEASE = 0.35

    def just_pressed?(pad, action)
      digital(pad, action)[:down]
    end

    def pressed?(pad, action)
      state = digital(pad, action)
      state[:held] || state[:down]
    end

    # One navigation step from the right stick, or nil. Flick semantics: a single
    # step per neutral->deflected crossing, in the dominant axis; the stick must
    # return to neutral to re-arm (no repeat-while-held in v1). @flick_armed is the
    # only state — nil/true means ready, false means already fired this deflection.
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
