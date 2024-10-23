class Keymap
  DIRECTIONAL_MAPPING = {
    [true, true] => 0,
    [true, false] => -1,
    [false, true] => 1,
    [false, false] => 0,
  }

  attr_accessor :name, :config

  def initialize(name, config)
    @name = name
    @config = config
  end

  def self.load_keymap(key, name: key)
    self.new(name, keymaps_json[key.to_s])
  end

  def method_missing(method_name, *args, &block)
    if config[method_name.to_s]
      ![nil, false].any? { _1 == input.send(config[method_name.to_s]) }
    else
      super
    end
  end

  def up_down
    DIRECTIONAL_MAPPING.fetch([up, down]) * -1
  end

  def left_right
    DIRECTIONAL_MAPPING.fetch([left, right])
  end

  def directional_vector
    Vector.new(x: left_right, y: up_down)
  end

  def key_down(action)
    input.key_down.send(config[action.to_s])
  end

  def key_up(action)
    input.key_up.send(config[action.to_s])
  end

  def inputs
    default_hash = { "directional_vector" => directional_vector }

    config.except("up", "down", "left", "right").each_with_object(default_hash) do |(key, value), hash|
      hash[key] = send(key)
    end
  end

  private

  def self.keymaps_json
    @keymaps_json ||= $game.gtk.parse_json_file("config/keymaps.json")
  end
end

require_relative "keymaps/keyboard_keymap"
require_relative "keymaps/controller_keymap"
