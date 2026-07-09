require "app/drenv_bundle.rb"

require_relative "game"

# Upstream start_tick re-`set`s both buffers' w/h every tick, which recreates
# their textures on current DR builds — the history buffer is wiped each frame
# and renders as the missing-texture checkerboard. Size them once instead.
class FrameTimer
  def start_tick(args)
    @frame_start_time = Time.now
    @frame_spans[@frame_index] = { children: {} }
    @span_collecter_stack = [@frame_spans[@frame_index]]

    return if @disabled || @buffers_sized

    @buffers_sized = true
    args.outputs[@buffers[0]].set(clear_before_render: false, w: @graph_width, h: @graph_height)
    args.outputs[@buffers[1]].set(clear_before_render: false, w: @graph_width, h: @graph_height)
  end
end

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
