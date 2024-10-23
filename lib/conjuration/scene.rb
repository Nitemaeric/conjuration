require_relative "managers/camera_manager"

class Scene < Node
  attr_accessor :key, :camera_manager, :config, :width, :height

  delegate :inputs, :grid, :layout, :geometry, :scene_manager, :input_manager, :debug_manager, to: :game

  def initialize(key, camera_count: 1, **config)
    super(
      key: key,
      config: config,
      width: grid.w,
      height: grid.h
    )

    self.camera_manager = CameraManager.new(scene: self, camera_count: camera_count)
  end

  def state
    $game.state[key.to_sym]
  end

  def outputs
    $game.outputs[:scene]
  end

  def debug_inspect
    "#<#{self.class.name}:0x#{object_id.to_s(16)} size: #{width}x#{height}>"
  end

  private

  def perform_render?
    !setup_at.nil?
  end

  def perform_update?
    !setup_at.nil?
  end

  def perform_update
    outputs.transient!
    outputs.w = width
    outputs.h = height
  end

  def game
    $game
  end
end
