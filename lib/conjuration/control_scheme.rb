module Conjuration
  # The one seam through which framework UI reads raw input; scenes and games may
  # still read `inputs` directly.
  class ControlScheme
    def initialize(inputs)
      # DragonRuby's `inputs` is mutated in place each tick, so holding the
      # reference reads live state — no need to re-fetch per frame.
      @inputs = inputs
    end

    # Space is intentionally NOT bound: games commonly use it (the hit-stop demo
    # swings with it), so confirming on it would double-fire.
    def confirm_down?
      @inputs.keyboard.key_down.enter || @inputs.controller_one.key_down.a
    end

    def confirm_held?
      @inputs.keyboard.key_held.enter || @inputs.controller_one.key_held.a
    end

    def navigation_vector
      @inputs.key_down.directional_vector
    end
  end
end
