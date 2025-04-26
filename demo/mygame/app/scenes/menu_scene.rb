require_relative "basic_camera_scene"
require_relative "multiple_cameras_scene"
require_relative "ui_scene"

class MenuScene < Conjuration::Scene
  attr_reader :menu, :buttons

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4

    audio[:bgm] = { input: "sounds/bgm.mp3", looping: true, gain: 0.5 }

    add_camera(:main)

    ui.node({
      x: grid.w / 2,
      y:  grid.h / 2 + 140,
      w: 256,
      anchor_x: 0.5,
      anchor_y: 1,
    }, align: :stretch, gap: 20) do
      node(
        {
          h: 64,
          action: -> { change_scene(to: BasicCameraScene.new(:basic_camera)) },
          path: "sprites/button.png",
        },
        id: :basic_camera,
        justify: :center,
        align: :center
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
        align: :center
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
        align: :center
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

      if gtk.can_close_window?
        node(
          {
            h: 64,
            action: -> { gtk.request_quit },
            path: "sprites/button.png"
          },
          id: :quit,
          justify: :center,
          align: :center
        ) do
          node(text: "Quit", r: 255, g: 255, b: 255)
        end
      end
    end

    ui.node({
      x: 10.from_right,
      y: 10.from_top,
      anchor_x: 1,
      anchor_y: 1,
    }, direction: :row, justify: :end, gap: 20) do
      node({ w: 120, h: 40, path: "sprites/button.png", action: -> { audio[:bgm].muted_gain, audio[:bgm].gain = audio[:bgm].gain, audio[:bgm].muted_gain || 0 } }, justify: :center, align: :center) do
        node({
          text: "Mute",
          r: 255,
          g: 255,
          b: 255
        }, id: :mute_button_text)
      end
    end
  end

  def update
    ui.find(:mute_button_text).text = audio[:bgm].gain.zero? ? "Unmute" : "Mute"
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
  end
end
