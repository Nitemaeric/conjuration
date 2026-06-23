# Game-level hit stop: input and update freeze for N ticks while rendering keeps
# running. Uses a scene double that just counts the lifecycle calls Game delegates.

class HitStopSceneDouble
  attr_reader :inputs, :updates, :renders

  def initialize
    @inputs = 0
    @updates = 0
    @renders = 0
  end

  def perform_input;  @inputs  += 1; end
  def perform_update; @updates += 1; end
  def perform_render; @renders += 1; end
end

def hit_stop_game
  game = Conjuration::Game.new(nil)
  game.current_scene = HitStopSceneDouble.new
  game
end

def test_hit_stop_freezes_input_and_update_but_keeps_rendering(args, assert)
  game = hit_stop_game
  scene = game.current_scene
  game.hit_stop(2)

  game.tick
  game.tick

  assert.equal!(scene.updates, 0, "update is frozen during the hit stop")
  assert.equal!(scene.inputs, 0, "input is frozen during the hit stop")
  assert.equal!(scene.renders, 2, "rendering continues during the hit stop")
end

def test_update_resumes_after_hit_stop(args, assert)
  game = hit_stop_game
  scene = game.current_scene
  game.hit_stop(1)

  game.tick # consumes the one frozen frame
  game.tick # resumes

  assert.equal!(scene.updates, 1, "update resumes once the freeze ends")
end

def test_runs_normally_without_a_hit_stop(args, assert)
  game = hit_stop_game
  scene = game.current_scene

  game.tick

  assert.equal!(scene.updates, 1, "update runs with no hit stop")
  assert.equal!(scene.inputs, 1, "input runs with no hit stop")
end
