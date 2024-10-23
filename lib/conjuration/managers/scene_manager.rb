class SceneManager < Node
  attr_reader :current_scene

  def register_scene(key, scene_class)
    scenes[key] = scene_class
  end

  def initial_scene(key, **config)
    @current_scene ||= scenes[key].new(key, **config)
    setup
  end

  def set_scene(key, **config)
    @current_scene = scenes[key].new(key, **config)
    setup
  end

  def setup
    return unless current_scene

    current_scene.perform(:setup)
    current_scene.camera_manager.perform(:setup)
  end

  def input
    return unless current_scene

    current_scene.perform(:input)
    current_scene.camera_manager.perform(:input)
  end

  def update
    return unless current_scene

    current_scene.perform(:update)
    current_scene.camera_manager.perform(:update)
  end

  def render
    return unless current_scene

    current_scene.perform(:render)
    current_scene.camera_manager.perform(:render)
  end

  private

  def scenes
    @scenes ||= {}
  end
end
