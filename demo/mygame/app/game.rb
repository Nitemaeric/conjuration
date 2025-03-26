require_relative "scenes/menu_scene"

class Game < Conjuration::Game
  def setup
    self.current_scene = MenuScene.new(:main)
  end

  def render
    outputs.background_color = [0, 0, 0]
  end
end
