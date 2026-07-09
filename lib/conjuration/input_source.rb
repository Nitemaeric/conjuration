module Conjuration
  # The reserved UI actions the framework listens for, and their default
  # bindings. Single source of truth: the dragon_input integration injects these
  # entries into the game's action sets (see DragonInputSource). Each entry's
  # shape matches dragon_input's ActionSet#digital keyword args, so it splats
  # straight in.
  #
  # Bindings degrade gracefully: querying any action not listed here is defined to
  # read as "not pressed", so future reserved names stay safe on old games.
  UI_ACTIONS = {
    # Space is intentionally NOT bound: games commonly use it (the hit-stop demo
    # swings with it), so confirming on it would double-fire.
    ui_confirm: { controller: :a,          keyboard: :enter },
    ui_up:      { controller: :dpad_up,    keyboard: :up },
    ui_down:    { controller: :dpad_down,  keyboard: :down },
    ui_left:    { controller: :dpad_left,  keyboard: :left },
    ui_right:   { controller: :dpad_right, keyboard: :right }
  }.freeze

  # The default input source (see Game#input_source): dragon_input is a hard
  # dependency, so this reads through the DragonInput facade. Because Conjuration
  # can't control when the game calls DragonInput.setup, it LAZILY injects the
  # reserved UI actions from UI_ACTIONS into every action set — filling only gaps,
  # so a game's own :ui_* binding always wins. Injected actions are ordinary
  # config entries, so rebinding and IGA export pick them up for free.
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
      # setup may not have run yet — the game owns that timing. Until a config
      # exists there is nothing to inject into or query, so read as "not pressed".
      config = DragonInput.config
      return INACTIVE unless config

      ensure_injected(config)
      result = DragonInput.digital(pad, action)

      # active:false means the action isn't in the pad's set. A reserved name
      # should be; a miss means a set was (re)built since our last injection, so
      # re-inject and read once more.
      if !result[:active] && UI_ACTIONS.key?(action)
        inject(config)
        result = DragonInput.digital(pad, action)
      end

      result
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
