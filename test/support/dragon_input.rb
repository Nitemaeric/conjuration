# A minimal double of the dragon_input surface Conjuration touches — not the real
# library (https://github.com/Nitemaeric/dragon_input).
module DragonInput
  class FakeActionSet
    attr_reader :name, :digitals

    def initialize(name)
      @name = name
      @digitals = {}
    end

    def digital(name, controller: nil, keyboard: nil, mouse: nil, glyph: nil)
      @digitals[name] = { controller: controller, keyboard: keyboard, mouse: mouse }
    end

    def action(name)
      @digitals[name]
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
    end

    def press!(pad, action)
      (@pressed ||= {})["#{pad}/#{action}"] = true
    end

    def digital(pad, action)
      raise "DragonInput.setup must be called before use" unless @config

      set = @config.action_sets[@config.default_set]
      return { down: false, held: false, up: false, active: false } unless set && set.action(action)

      down = @pressed && @pressed["#{pad}/#{action}"] ? true : false
      { down: down, held: false, up: false, active: true }
    end

    def just_pressed?(pad, action)
      digital(pad, action)[:down]
    end

    def pressed?(pad, action)
      state = digital(pad, action)
      state[:held] || state[:down]
    end
  end
end
