require "app/views/prompt_view.rb"
require "app/views/button_view.rb"

class BasicCameraScene < Conjuration::Scene
  TILE_SIZE = 40

  # Two pillars on the orbit's vertical crossings. The follow target weaves
  # behind the far one and in front of the near one purely from z-ordering
  # (z: -y), no manual layering — see #draw_world.
  PILLARS = [
    { x: 1000, y: 1240, w: 72, h: 190 },
    { x: 1000, y: 760,  w: 72, h: 190 }
  ].freeze

  def setup
    self.virtual_w = self.virtual_h = 2000

    add_camera(:main, speed: 30)
    # No activate_navigation: the arrows pan the camera; activating would let
    # ensure_focus_in_active_group steal them to focus the HUD.
    cameras[:main].ui.group = :hud

    @tiles = Conjuration::TileLayer.new(name: :grid, chunk_size: 400)

    (virtual_w / TILE_SIZE).to_i.times do |row|
      (virtual_h / TILE_SIZE).to_i.times do |column|
        cell = { x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE }

        @tiles.add({ **cell, path: :pixel, r: 192, g: 192, b: 192, a: 192 })
        @tiles.add({ **cell, primitive_marker: :border, r: 255, g: 255, b: 255, a: 192 })
      end
    end

    # A target that orbits the world for the camera to follow.
    state.target = { x: 1000, y: 1000, w: 80, h: 80 }

    camera = cameras[:main]
    camera.ui.view { hud(camera) }
  end

  def hud(camera)
    node({ x: 20, y: camera.from_top(20), anchor_y: 1 }) do
      ButtonView(id: :back, label: "Back", action: -> { scene.change_scene(to: MenuScene.new(:main)) }, height: 50, shortcut: { keyboard: :escape, controller: :b }, pad: game.ui_pad)
    end

    node({ x: 0, y: grid.h / 2, w: 256, h: 420, anchor_y: 0.5, path: "sprites/menu-container-background.png", tile_x: 32, tile_w: 480 - 32 }, id: :panel, align: :stretch, padding: 20, gap: 20) do
      node({ h: 84 }, gap: 6, align: :center) do
        PromptView(id: :pan, action: :pan, label: "pan", pad: game.ui_pad)
        PromptView(id: :shake, action: :attack, label: "shake", pad: game.ui_pad)
        node({ text: "RMB to destroy tile" })
      end

      ButtonView(id: :point_a, label: "Point A", action: -> { scene.cameras[:main].look_at(x: 1200, y: 1600) }, width: nil, height: 50)

      ButtonView(id: :point_b, label: "Point B", action: -> { scene.cameras[:main].look_at(x: 640, y: 600) }, width: nil, height: 50)

      ButtonView(id: :point_c, label: "Point C", action: -> { scene.cameras[:main].look_at(x: 1200, y: 400) }, width: nil, height: 50)

      ButtonView(id: :follow, label: "Follow", action: -> { camera = scene.cameras[:main]; camera.following ? camera.unfollow : camera.follow(scene.state.target) }, width: nil, height: 50)
    end

    node({ x: camera.from_right(20), y: 20, anchor_x: 1, anchor_y: 0, text: camera_readout(camera) }, id: :camera_label)
  end

  def input
    # WASD/arrows pan as before; when they're neutral the :pan action's analog
    # side pans with the left stick (the right stick stays on HUD selection).
    pan_x = inputs.left_right
    pan_y = inputs.up_down

    if pan_x.zero? && pan_y.zero?
      stick = DragonInput.axis(game.ui_pad, :pan)
      pan_x = stick[:x]
      pan_y = stick[:y]
    end

    if focused_camera && (!pan_x.zero? || !pan_y.zero?)
      focused_camera.look_at(x: focused_camera.current.x + pan_x * 10, y: focused_camera.current.y + pan_y * 10)
    end

    if focused_camera && inputs.mouse.button_right
      point = focused_camera.to_world(**inputs.mouse.rect)
      column = (point.x / TILE_SIZE).floor
      row = (point.y / TILE_SIZE).floor

      if column.between?(0, (virtual_w / TILE_SIZE).to_i - 1) && row.between?(0, (virtual_h / TILE_SIZE).to_i - 1)
        @tiles.remove({ x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE })
      end
    end

    if focused_camera && game.input_source.just_pressed?(game.ui_pad, :attack)
      # Shake along the target's orbital velocity, for a directional impact.
      angle = clock * 0.02
      focused_camera.shake(0.8, direction: { x: -Math.sin(angle), y: Math.cos(angle) })
    end
  end

  def update
    # Key the orbit to game.clock, not Kernel.tick_count: clock holds still
    # during a hit stop / pause, so the animation freezes with the game instead
    # of skipping ahead when it thaws.
    angle = clock * 0.02
    state.target.x = 1000 + Math.cos(angle) * 400
    state.target.y = 1000 + Math.sin(angle) * 400
  end

  # Re-derived each frame by the camera HUD view.
  def camera_readout(camera)
    camera.following ? "Following target" : "Camera: #{camera.current.x.round}, #{camera.current.y.round}"
  end

  def draw_world(camera)
    # Static grid: drawn from cached chunk textures, so the 2000x2000 world stays
    # cheap even fully zoomed out and across multiple cameras.
    @tiles.draw(camera)

    # Dynamic hover highlight: an immediate (no-z) draw, so it stays on the floor
    # under the y-sorted entities below.
    if camera == focused_camera
      point = camera.to_world(**inputs.mouse.rect)
      column = (point.x / TILE_SIZE).floor
      row = (point.y / TILE_SIZE).floor

      if column.between?(0, (virtual_w / TILE_SIZE).to_i - 1) && row.between?(0, (virtual_h / TILE_SIZE).to_i - 1)
        camera.draw({ x: column * TILE_SIZE, y: row * TILE_SIZE, w: TILE_SIZE, h: TILE_SIZE, path: :pixel, r: 255, g: 0, b: 0, a: 128 })
      end
    end

    # Pillars + the follow target, y-sorted with z: -y (lower on screen draws in
    # front). The orbiting target passes behind the far pillar and in front of
    # the near one with no manual layering — depth falls out of the z buffer.
    PILLARS.each do |pillar|
      camera.draw({ **pillar, path: :pixel, r: 120, g: 90, b: 200 }, z: -pillar[:y])
    end

    camera.draw({ **state.target, path: :pixel, r: 255, g: 140, b: 0 }, z: -state.target.y)
  end
end
