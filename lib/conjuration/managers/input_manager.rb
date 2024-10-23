class InputManager
  def register_keymap(name, keymap)
    keymaps[name] = keymap
  end

  def get_keymap(keymap)
    keymaps[keymap]
  end

  def keymaps
    @keymaps ||= {}
  end
end
