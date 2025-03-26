require_relative "basic_camera_scene"
require_relative "multiple_cameras_scene"
require_relative "ui_scene"

class MenuScene < Conjuration::Scene
  attr_accessor :buttons

  def setup
    gtk.set_cursor "sprites/cursor-none.png", 9, 4
    audio[:bgm] = { input: "sounds/bgm.mp3", looping: true }

    add_camera(:main, x: 0, y: 0)

    self.buttons = [
      {
        text: "Basic Camera",
        action: -> { change_scene(to: BasicCameraScene.new(:basic_camera)) }
      },
      {
        text: "Multiple Cameras",
        action: -> { change_scene(to: MultipleCamerasScene.new(:multiple_cameras)) }
      },
      {
        text: "UI",
        action: -> { change_scene(to: UIScene.new(:ui)) }
      },
      {
        text: "Exit",
        action: -> { gtk.request_quit }
      }
    ].map.with_index do |button, index|
      {
        x: grid.w / 2,
        y: grid.h / 2 + 92 - index * 92,
        w: 256,
        h: 64,
        text: button[:text],
        action: button[:action],
        anchor_x: 0.5,
        anchor_y: 0.5
      }
    end
  end

  def input
    focused_button = geometry.find_intersect_rect(inputs.mouse, buttons)

    if focused_button
      gtk.set_cursor "sprites/hand-point.png", 6, 4

      focused_button.action.call if inputs.mouse.click
    else
      gtk.set_cursor "sprites/cursor-none.png", 9, 4
    end
  end

  def update

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

    outputs.primitives << buttons.map.with_index do |button, index|
      [
        {
          **button,
          path: "sprites/button.png",
          primitive_marker: :sprite,
        },
        {
          **button,
          primitive_marker: :label,
          r: 255,
          g: 255,
          b: 255,
        }
      ]
    end
  end
end
