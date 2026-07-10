# The lifecycle never touches audio, but the host mirrors Game's surface;
# the spy doubles as the regression guard (clears must stay 0).
class AudioSpy
  attr_reader :clears

  def initialize
    @clears = 0
  end

  def clear
    @clears += 1
  end
end

class SceneManagementHost
  include Conjuration::SceneManagement

  def audio
    @audio ||= AudioSpy.new
  end
end

class SetupCountingScene
  attr_reader :setups

  def initialize
    @setups = 0
  end

  def perform_setup
    @setups += 1
  end
end

class NavActivatingScene < SetupCountingScene
  def perform_setup
    super
    Conjuration::UI.active_navigation_group = :menu
  end
end

def test_change_scene_resets_focus_globals(args, assert)
  node = Object.new
  Conjuration::UI.focused_node = node
  Conjuration::UI.pressed_node = node
  Conjuration::UI.active_navigation_group = :hud

  scene = SetupCountingScene.new
  SceneManagementHost.new.change_scene(to: scene)

  assert.equal!(scene.setups, 1, "incoming scene set up once")
  assert.nil!(Conjuration::UI.focused_node, "focused node cleared")
  assert.nil!(Conjuration::UI.pressed_node, "pressed node cleared")
  assert.nil!(Conjuration::UI.active_navigation_group, "active group cleared")
end

def test_change_scene_reset_precedes_setup_activation(args, assert)
  Conjuration::UI.active_navigation_group = :hud

  host = SceneManagementHost.new
  host.change_scene(to: NavActivatingScene.new)

  assert.equal!(Conjuration::UI.active_navigation_group, :menu,
                "a scene activating navigation in setup wins over the reset")

  Conjuration::UI.active_navigation_group = nil
end
