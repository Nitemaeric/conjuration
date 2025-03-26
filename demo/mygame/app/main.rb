require "lib/conjuration"

require_relative "game"

def boot args
  $game = Game.new(args)
end

def tick args
  $game.args = args
  $game.perform_setup if Kernel.tick_count.zero?
  $game.tick
end
