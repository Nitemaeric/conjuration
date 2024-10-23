require_relative "managers/debug_manager"
require_relative "managers/scene_manager"
require_relative "managers/input_manager"

module Conjuration
  class Game < Node
    attr_gtk

    attr_accessor :debug_manager, :scene_manager, :input_manager

    def initialize(args)
      super(
        args: args,
        debug_manager: DebugManager.new,
        scene_manager: SceneManager.new,
        input_manager: InputManager.new
      )
    end

    def tick
      perform(:setup)
      perform(:input)
      perform(:update)
      perform(:render)
    end

    private

    def perform_setup
      [scene_manager, debug_manager].each do |manager|
        manager.perform(:setup)
      end
    end

    def perform_input
      [scene_manager, debug_manager].each do |manager|
        manager.perform(:input)
      end
    end

    def perform_update
      [scene_manager, debug_manager].each do |manager|
        manager.perform(:update)
      end
    end

    def perform_render
      [scene_manager, debug_manager].each do |manager|
        manager.perform(:render)
      end
    end
  end
end
