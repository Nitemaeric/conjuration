module Conjuration
  # The single seam between the framework's UI layer and raw input. Framework
  # code (UIManagement) asks the active scheme "confirm?"/"which way?" instead of
  # reading `inputs.keyboard`/`inputs.controller_one` itself — so a future input
  # library drops in as an adapter here rather than being retrofitted across
  # UIManagement. Scenes and games are free to read raw inputs directly; this
  # rule binds framework code only.
  #
  # Reachable and swappable as `game.control_scheme`; assign your own before the
  # first read to rebind everything the UI reacts to.
  class ControlScheme
    def initialize(inputs)
      # DragonRuby's `inputs` is a stable object mutated in place each tick, so
      # holding the reference reads live state — no need to re-fetch per frame.
      @inputs = inputs
    end

    # A fresh confirm press this tick (edge). Space is intentionally NOT bound:
    # games commonly use it (the hit-stop demo swings with it), so confirming on
    # it would double-fire.
    def confirm_down?
      @inputs.keyboard.key_down.enter || @inputs.controller_one.key_down.a
    end

    # Confirm held down (level) — drives the UI's :pressed state.
    def confirm_held?
      @inputs.keyboard.key_held.enter || @inputs.controller_one.key_held.a
    end

    # Directional intent for spatial UI navigation, as a { x:, y: } vector (y-up).
    def navigation_vector
      @inputs.key_down.directional_vector
    end
  end
end
