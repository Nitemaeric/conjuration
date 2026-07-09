# A minimal double of the dragon_input surface Conjuration (and the demo's
# PromptView) touches — not the real library
# (https://github.com/Nitemaeric/dragon_input).
module DragonInput
  # Real root constants (glyphs.rb in the library); PromptView's controller:
  # override references them at load.
  class Glyphs
    VENDORED_ROOT = "vendor/dragon_input/sprites/dragon_input/glyphs".freeze
    LOCAL_ROOT = "sprites/dragon_input/glyphs".freeze
  end

  class FakeActionSet
    attr_reader :name, :digitals, :analogs

    def initialize(name)
      @name = name
      @digitals = {}
      @analogs = {}
    end

    def digital(name, controller: nil, keyboard: nil, mouse: nil, glyph: nil)
      @digitals[name] = { controller: controller, keyboard: keyboard, mouse: mouse }
    end

    def analog(name, controller: nil, keyboard: nil, mouse: nil, glyph: nil)
      @analogs[name] = { controller: controller, keyboard: keyboard, mouse: mouse }
    end

    def action(name)
      @digitals[name] || @analogs[name]
    end
  end

  class FakeConfig
    attr_reader :action_sets, :default_set

    def initialize
      @action_sets = {}
      @default_set = nil
    end

    def action_set(name)
      set = (@action_sets[name] ||= FakeActionSet.new(name))
      yield set if block_given?
      @default_set ||= name
      set
    end
  end

  class << self
    attr_reader :config

    def setup(&block)
      @config = FakeConfig.new
      @pressed = {}
      block.call(@config) if block
      @config
    end

    def tick(_args)
      raise "DragonInput.setup must be called before use" unless @config
    end

    def reset!
      @config = nil
      @pressed = {}
      @axes = {}
      @glyph_style = nil
    end

    def press!(pad, action)
      (@pressed ||= {})["#{pad}/#{action}"] = true
    end

    # Set an analog axis reading for a pad/action, for the flick-navigation tests.
    def deflect!(pad, action, x, y)
      (@axes ||= {})["#{pad}/#{action}"] = { x: x, y: y }
    end

    def digital(pad, action)
      raise "DragonInput.setup must be called before use" unless @config

      set = @config.action_sets[@config.default_set]
      return { down: false, held: false, up: false, active: false } unless set && set.action(action)

      down = @pressed && @pressed["#{pad}/#{action}"] ? true : false
      { down: down, held: false, up: false, active: true }
    end

    def axis(pad, action)
      raise "DragonInput.setup must be called before use" unless @config

      set = @config.action_sets[@config.default_set]
      return { x: 0.0, y: 0.0, active: false } unless set && set.action(action)

      vec = (@axes ||= {})["#{pad}/#{action}"] || { x: 0.0, y: 0.0 }
      { x: vec[:x], y: vec[:y], active: true }
    end

    def glyph_style(_pad)
      @glyph_style || :keyboard
    end

    def glyph_style=(style)
      @glyph_style = style
    end

    # Action-level glyph, mirroring the real resolution shape: the action's
    # binding for the current style names a <style>/<button>.png path.
    def glyph(pad, action)
      raise "DragonInput.setup must be called before use" unless @config

      set = @config.action_sets[@config.default_set]
      binding = set && set.action(action)
      return nil unless binding

      style = glyph_style(pad)
      button = style == :keyboard ? binding[:keyboard] : binding[:controller]
      button && "sprites/dragon_input/glyphs/#{style}/#{button}.png"
    end

    def just_pressed?(pad, action)
      digital(pad, action)[:down]
    end

    def pressed?(pad, action)
      state = digital(pad, action)
      state[:held] || state[:down]
    end

    # Keyboard unless a test forces a controller style via glyph_style=.
    attr_writer :glyph_style

    def glyph_style(_pad)
      @glyph_style || :keyboard
    end

    # Keyboard-style resolution like the real Ruby backend's: the action's
    # keyboard binding names the art file, with the library's wasd->arrows
    # cluster alias. nil (the keycap fallback) without setup or a binding.
    def glyph(_pad, action_name)
      return nil unless @config

      set = @config.action_sets[@config.default_set]
      binding = set && set.action(action_name)
      button = binding && binding[:keyboard]
      return nil unless button

      button = :arrows if button == :wasd
      "sprites/dragon_input/glyphs/keyboard/#{button}.png"
    end
  end
end
