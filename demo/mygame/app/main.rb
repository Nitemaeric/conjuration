require "app/drenv_bundle.rb"

require_relative "game"

$frame_timer = FrameTimer.new

def boot args
  $game = Game.new(args)
end

def tick args
  $frame_timer.start_tick(args)
  $game.args = args
  $game.perform_setup if Kernel.tick_count.zero?
  $game.tick
  $frame_timer.end_tick(args)
end

def current_scene
  $game.current_scene
end
