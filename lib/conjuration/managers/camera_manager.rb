class CameraManager < Node
  CAMERA_LAYOUTS = {
    1 => [
      [0]
    ],
    2 => [
      [0, 1]
    ],
    3 => [
      [0, 1, 2]
    ],
    4 => [
      [0, 1],
      [2, 3]
    ],
  }

  attr_accessor :scene, :cameras

  def initialize(scene, camera_count: 1)
    @scene = scene
    @cameras = camera_count.times.map do
      Camera.new(scene)
    end
  end

  def add_camera(x:, y:, zoom: 1)
    camera = Camera.new(scene, x: x, y: y, zoom: zoom)
    cameras << camera
    calculate_camera_dimensions
    camera
  end

  def perform_setup
    calculate_camera_dimensions
  end

  def perform_render
    cameras.each_with_index do |camera, index|
      camera.perform(:render)

      $game.outputs.primitives << { x: camera.x, y: camera.y, w: camera.w, h: camera.h, primitive_marker: :border }
    end
  end

  def perform_update
    cameras.each do |camera|
      camera.perform(:update)
    end
  end

  private

  def calculate_camera_dimensions
    rows = CAMERA_LAYOUTS.fetch(cameras.length)
    camera_h = $game.grid.h / rows.length

    rows.each_with_index do |columns, row_index|
      camera_w = $game.grid.w / columns.length

      columns.each_with_index do |index, column_index|
        next if index.nil?

        cameras[index].merge!(
          x: camera_w * column_index,
          y: camera_h * (rows.length - 1 - row_index),
          w: camera_w,
          h: camera_h
        )
      end
    end
  end
end
