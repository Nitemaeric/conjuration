class ControllerKeymap < Keymap
  private

  def input
    $game.inputs.send(name)
  end
end
