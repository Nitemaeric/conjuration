class DebugManager < Node
  delegate :state, :inputs, :outputs, :grid, :gtk, to: :game

  attr_accessor :debug_strings

  def setup
    state.debug ||= false
  end

  def input
    return if gtk.production?

    state.debug = !state.debug if inputs.keyboard.key_down.f1
  end

  def render
    build_debug_strings
    render_debug_strings
    render_scene_with_cameras

    current_scene.debug if current_scene.respond_to?(:debug)
  end

  def update
    @debug_strings = []
  end

  private

  def build_debug_strings
    gtk.framerate_diagnostics_primitives.select { _1[:primitive_marker] == :label }.map(&:text).each do |text|
      debug_strings << text
    end

    debug_strings << "current_scene: #{current_scene.debug_inspect}"

    current_scene.camera_manager.cameras.each_with_index do |camera, index|
      rect = "[#{camera.x.to_i},#{camera.y.to_i},#{camera.w.to_i},#{camera.h.to_i}]"
      focus = "(#{camera.focus_x.to_i},#{camera.focus_y.to_i}@#{camera.zoom.to_sf})"
      debug_strings << "camera[#{index}]: #{rect} #{focus}"
    end

    current_scene.debug_strings.each { |string| debug_strings << string } if current_scene.respond_to?(:debug_strings)
  end

  def render_debug_strings
    string_w, _ = gtk.calcstringbox debug_strings.max_by(&:length), -2, "font.ttf"

    outputs.primitives << { x: 0.from_right, y: 0, w: string_w + 20, h: grid.h, primitive_marker: :solid, r: 0, g: 0, b: 0, a: 128, anchor_x: 1 }

    outputs.debug << debug_strings.map_with_index do |text, index|
      { text: text, x: 10.from_right, y: (10 + 20 * index).from_top, size_enum: -2, alignment_enum: 2, primitive_marker: :label, r: 255, g: 255, b: 255 }
    end
  end

  def render_scene_with_cameras
    outputs[:scene_with_cameras].transient!
    outputs[:scene_with_cameras].width = current_scene.width
    outputs[:scene_with_cameras].height = current_scene.height

    outputs[:scene_with_cameras].primitives << {
      x: 0,
      y: 0,
      w: current_scene.width,
      h: current_scene.height,
      path: :scene,
    }

    outputs[:scene_with_cameras].primitives << current_scene.camera_manager.cameras.map_with_index do |camera, index|
      [
        {
          x: camera.focus_x,
          y: camera.focus_y,
          w: camera.w / camera.zoom,
          h: camera.h / camera.zoom,
          anchor_x: 0.5,
          anchor_y: 0.5,
          a: 128,
          primitive_marker: :solid
        },
        {
          x: camera.focus_x,
          y: camera.focus_y,
          text: index,
          size_enum: 100,
          alignment_enum: 1,
          vertical_alignment_enum: 1,
          primitive_marker: :label
        }
      ]
    end

    scene_aspect_ratio = current_scene.width / current_scene.height
    max_size = grid.w / 4

    outputs.primitives << [{ path: :scene_with_cameras }, { primitive_marker: :border }].map do |options|
      {
        x: 10,
        y: 10.from_top,
        w: scene_aspect_ratio < 1 ? max_size * scene_aspect_ratio : max_size,
        h: scene_aspect_ratio > 1 ? max_size / scene_aspect_ratio : max_size,
        a: 196,
        anchor_y: 1
      }.merge(options)
    end
  end

  def perform_render?
    state.debug
  end

  def perform_update?
    state.debug
  end

  def game
    $game
  end

  def current_scene
    game.scene_manager.current_scene
  end
end
