require_relative "basic_camera_scene"
require_relative "multiple_cameras_scene"
require_relative "ui_scene"

class MenuScene < Conjuration::Scene
  attr_accessor :buttons

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    audio[:bgm] = { input: "sounds/bgm.mp3", looping: true, gain: 0.5 }

    add_camera(:main, x: 0, y: 0)

    @buttons = Conjuration::UI.build({
      x: grid.w / 2,
      y:  grid.h / 2 + 140,
      w: 256,
      h: 400,
      anchor_x: 0.5,
      anchor_y: 1
    }, gap: 20) do
      node(
        {
          h: 64,
          action: -> { change_scene(to: BasicCameraScene.new(:basic_camera)) },
          path: "sprites/button.png",
        },
        id: :basic_camera,
        justify: :center,
        alignment: :center
      ) do
        node(
          {
            text: "Basic Camera",
            r: 255,
            g: 255,
            b: 255
          }
        )
      end

      node(
        {
          h: 64,
          action: -> { change_scene(to: MultipleCamerasScene.new(:multiple_cameras)) },
          path: "sprites/button.png",
        },
        id: :multiple_cameras,
        justify: :center,
        alignment: :center
      ) do
        node(
          {
            text: "Multiple Cameras",
            r: 255,
            g: 255,
            b: 255
          }
        )
      end

      node(
        {
          h: 64,
          action: -> { change_scene(to: UIScene.new(:ui)) },
          path: "sprites/button.png",
        },
        id: :ui,
        justify: :center,
        alignment: :center
      ) do
        node(
          {
            text: "UI",
            r: 255,
            g: 255,
            b: 255
          }
        )
      end

      node(
        {
          h: 64,
          action: -> { gtk.request_quit },
          path: "sprites/button.png",
        },
        id: :quit,
        justify: :center,
        alignment: :center
      ) do
        node(
          {
            text: "Exit",
            r: 255,
            g: 255,
            b: 255
          }
        )
      end
    end
  end

  def input
    focused_button = @buttons.find_interactive_intersect(inputs.mouse)

    if focused_button
      gtk.set_cursor "sprites/hand-point.png", 6, 4

      instance_exec(&focused_button.action) if inputs.mouse.click
    else
      gtk.set_cursor "sprites/cursor-none.png", 9, 4
    end
  end

  def update
    @buttons.calculate_layout if events.orientation_changed
  end

  def render
    outputs.background_color = [52, 153, 218]

    outputs.primitives << [
      {
        x: grid.w / 2,
        y: grid.h / 2,
        w: 480,
        h: 480,
        path: "sprites/menu-container-background.png",
        anchor_x: 0.5,
        anchor_y: 0.5
      },
      {
        x: grid.w / 2,
        y: grid.h / 2 + 220,
        w: 512 * 0.75,
        h: 128 * 0.75,
        path: "sprites/banner.png",
        anchor_x: 0.5,
        anchor_y: 0.5
      },
      {
        x: grid.w / 2,
        y: grid.h / 2 + 215,
        w: 512 * 0.75,
        h: 128 * 0.75,
        text: "Conjuration Demo",
        size_enum: 2,
        r: 255,
        g: 255,
        b: 255,
        anchor_x: 0.5,
        anchor_y: 0.5
      }
    ]

    outputs.primitives << @buttons.primitives

    if debug?
      outputs.primitives << @buttons.interactive_nodes.map do |node|
        {
          **node.object,
          r: 0,
          g: 255,
          b: 0
        }.border!
      end
    end
  end
end
