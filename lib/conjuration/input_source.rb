module Conjuration
  UI_ACTIONS = {
    # Space is intentionally unbound: games commonly use it (the hit-stop demo
    # swings with it), so confirming on it would double-fire.
    ui_confirm: { controller: :a,          keyboard: :enter },
    ui_up:      { controller: :dpad_up,    keyboard: :up },
    ui_down:    { controller: :dpad_down,  keyboard: :down },
    ui_left:    { controller: :dpad_left,  keyboard: :left },
    ui_right:   { controller: :dpad_right, keyboard: :right }
  }.freeze

  class DragonInputSource
    INACTIVE = { down: false, held: false, up: false, active: false }.freeze

    def just_pressed?(pad, action)
      digital(pad, action)[:down]
    end

    def pressed?(pad, action)
      state = digital(pad, action)
      state[:held] || state[:down]
    end

    private

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
          set.digital(name, **bindings) unless set.action(name)
        end
      end
    end
  end
end
