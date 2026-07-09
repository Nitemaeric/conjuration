require_relative "basic_camera_scene"
require_relative "multiple_cameras_scene"
require_relative "ui_scene"
require_relative "zoom_scene"
require_relative "hit_stop_scene"
require_relative "reactive_scene"

# The single home page. `view` is a pure function of state: before the player
# presses start it emits only the centred "Press <glyph>" prompt; the start /
# ui_confirm press flips state[:started] and the next re-render swaps the prompt
# out for the menu buttons. That swap is structural (different keyed subtrees),
# so it exercises the reconciler's create/discard path rather than a visibility
# toggle. state[:started] lives in the name-keyed scene state, which survives
# scene changes, so returning from a demo skips the prompt.
class MenuScene < Conjuration::Scene
  PROMPT_ACTION = :start

  def setup
    audio[:bgm] = { input: "sounds/bgm.mp3", looping: true, gain: 0.5 }
    activate_navigation(:menu) if state[:started]
  end

  def input
    return if state[:started]

    source = game.input_source
    pad = game.ui_pad
    return unless source.just_pressed?(pad, :start) || source.just_pressed?(pad, :ui_confirm)

    state[:started] = true
    activate_navigation(:menu)
  end

  def view
    state[:started] ? menu : press_prompt
  end

  def render
    outputs.primitives << { x: grid.allscreen_x, y: grid.allscreen_y, w: grid.allscreen_w, h: grid.allscreen_h, path: :pixel, r: 52, g: 153, b: 218 }

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

  private

  # Keyed on glyph_style so the art (and only the art) re-derives when the player
  # swaps between keyboard and controller; unchanged style reuses last frame's
  # subtree, so there's no per-frame glyph lookup or hash allocation.
  def press_prompt
    memo(:press_prompt, DragonInput.glyph_style(game.ui_pad)) do
      node({ x: grid.w / 2, y: grid.h / 2, w: 240, h: 80, anchor_x: 0.5, anchor_y: 0.5 }, id: :press_prompt, direction: :row, justify: :center, align: :center, gap: 14) do
        node({ text: "Press", size_enum: 2, r: 235, g: 235, b: 240 }, id: :press_label)
        glyph = DragonInput.glyph(game.ui_pad, PROMPT_ACTION)
        if glyph
          node({ w: 64, h: 64, path: glyph }, id: :start_glyph)
        else
          node({ w: 64, h: 64, path: :solid, r: 40, g: 40, b: 48 }, id: :start_glyph) do
            node({ text: "Start", r: 235, g: 235, b: 240 }, id: :start_glyph_label)
          end
        end
      end
    end
  end

  def menu
    node({ x: grid.w / 2, y: grid.h / 2 + 140, w: 256, anchor_x: 0.5, anchor_y: 1 }, id: :menu, align: :stretch, gap: 14, group: :menu) do
      menu_items.each do |item|
        node({ h: 46, path: "sprites/button.png", action: -> { change_scene(to: item[:scene].new(item[:id])) } }, id: item[:id], justify: :center, align: :center) do
          node({ text: item[:label], r: 255, g: 255, b: 255 }, id: "#{item[:id]}_label")
        end
      end

      if gtk.can_close_window?
        node({ h: 46, path: "sprites/button.png", action: -> { gtk.request_quit } }, id: :quit, justify: :center, align: :center) do
          node({ text: "Quit", r: 255, g: 255, b: 255 }, id: :quit_label)
        end
      end
    end

    node({ x: 10.from_right, y: 10.from_top, anchor_x: 1, anchor_y: 1 }, id: :mute_bar, direction: :row, justify: :end, gap: 20, group: :menu) do
      node({ w: 120, h: 40, path: "sprites/button.png", action: -> { toggle_mute } }, id: :mute_button, justify: :center, align: :center) do
        node({ text: mute_label, r: 255, g: 255, b: 255 }, id: :mute_button_text)
      end
    end
  end

  def menu_items
    [
      { id: :basic_camera, label: "Basic Camera", scene: BasicCameraScene },
      { id: :multiple_cameras, label: "Multiple Cameras", scene: MultipleCamerasScene },
      { id: :ui, label: "UI", scene: UIScene },
      { id: :zoom, label: "Zoom", scene: ZoomScene },
      { id: :hit_stop, label: "Hit Stop", scene: HitStopScene },
      { id: :reactive, label: "Reactive", scene: ReactiveScene }
    ]
  end

  def mute_label
    audio[:bgm].gain.zero? ? "Unmute" : "Mute"
  end

  def toggle_mute
    audio[:bgm].muted_gain, audio[:bgm].gain = audio[:bgm].gain, audio[:bgm].muted_gain || 0
  end
end
