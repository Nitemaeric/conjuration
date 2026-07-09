require "app/drenv_bundle.rb"

require_relative "game"

$frame_timer = FrameTimer.new

def boot args
  $game = Game.new(args)
end

def tick args
  $frame_timer.start_tick(args)
  if Kernel.tick_count.zero?
    # frame-timer presents its double buffers as sprites before anything renders
    # into them; an untouched target paints as DR's missing-texture checkerboard
    # and the buffer copy-swap then bakes it in. Render both once, empty.
    [:graph1, :graph2].each do |buffer|
      args.outputs[buffer].clear_before_render = true
      args.outputs[buffer].primitives << { x: 0, y: 0, w: 0, h: 0, path: :pixel, a: 0 }
    end
  end
  $game.args = args
  $game.perform_setup if Kernel.tick_count.zero?
  $game.tick
  $frame_timer.end_tick(args)
end

def current_scene
  $game.current_scene
end
