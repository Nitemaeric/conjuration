require "app/views/button_view.rb"

# The G3 acceptance demo: a two-character dialogue cutscene, staged entirely by a
# single `play_sequence`. Turn-taking, portrait swaps, and character movement are
# all steps in that one sequence, and every motion is a G1 tween keyed to the
# scene clock — so a pause or hit-stop freezes the whole performance mid-beat.
#
# What composes what:
#   - `say(who, line)` is a demo helper: it appends an `act` that flips the
#     dialogue state (speaker + line), then the sequence `wait_confirm`s. That
#     confirm-gated wait is the entire turn-taking mechanism.
#   - The active speaker drives the LARGE portrait (which side, which face) and
#     the talk/idle body pose — read reactively from state, no imperative swap.
#   - `parallel { animate … animate … }` steps both bodies toward each other on a
#     beat; `emphasize` pops a body on an emphasized line. Idle bob runs the whole
#     time as a self-arming tween (see #start_bob).
#
# Input policy (the scene's choice, not the primitive's): navigation is NOT
# activated, so Enter/A is free to advance dialogue via `wait_confirm` rather than
# triggering a focused button. Back is a shortcut (Esc/B) plus a mouse target;
# a tap anywhere also advances, mirroring the menu's tappable prompt.
class CutsceneScene < Conjuration::Scene
  GROUND_Y = 150
  BODY_W = 150
  BODY_H = 200

  HERO_HOME = 360
  RIVAL_HOME = 920
  HERO_CLOSE = 520
  RIVAL_CLOSE = 760

  BOB_H = 8
  BOB_PERIOD = 45

  HERO_INK = { r: 78, g: 138, b: 210 }.freeze
  RIVAL_INK = { r: 202, g: 96, b: 140 }.freeze

  SPEAKERS = {
    hero: { name: "Rurik", ink: HERO_INK, face: "sprites/cutscene/hero_face.png", side: :left },
    rival: { name: "Sable", ink: RIVAL_INK, face: "sprites/cutscene/rival_face.png", side: :right }
  }.freeze

  def setup
    state.hero = { x: HERO_HOME, bob: 0, bob_up: false, gesture: 0.0 }
    state.rival = { x: RIVAL_HOME, bob: 0, bob_up: true, gesture: 0.0 }
    state.speaker = nil
    state.line = nil

    start_bob(state.hero)
    start_bob(state.rival)

    play_cutscene
  end

  # The whole cutscene is one sequence. Read top to bottom, it IS the script.
  def play_cutscene
    play_sequence do
      say(:hero, "Sable. You came. I half expected the pass to swallow you whole.")
      say(:rival, "The pass and I have an understanding. You, though — you look terrible.")

      act { emphasize(state.hero) }
      say(:hero, "Three nights without sleep will do that. The seal is failing.")

      parallel do
        animate(state.hero, { x: HERO_CLOSE }, over: 26, ease: :smooth_stop)
        animate(state.rival, { x: RIVAL_CLOSE }, over: 26, ease: :smooth_stop)
      end

      act { emphasize(state.rival) }
      say(:rival, "Then we don't have long. Show me.")

      act { emphasize(state.hero) }
      say(:hero, "This way. And Sable — thank you. Truly.")

      act { change_scene(to: MenuScene.new(:main)) }
    end
  end

  # DEMO helper: queue a line, then wait for the player to confirm/tap. The
  # sequence primitive knows nothing of dialogue — this is just act + wait_confirm.
  def say(who, line)
    act do
      state.speaker = who
      state.line = line
    end
    wait_confirm
  end

  # A self-arming idle bob: each tween runs exactly one BOB_PERIOD, and `every`
  # re-kicks the next as it lands, so the body breathes continuously. All on the
  # scene clock, so it freezes under a pause with the rest of the scene.
  def start_bob(entity)
    bob_once(entity)
    every(BOB_PERIOD) { bob_once(entity) }
  end

  def bob_once(entity)
    entity[:bob_up] = !entity[:bob_up]
    tween(entity, :bob, to: entity[:bob_up] ? BOB_H : 0, over: BOB_PERIOD, ease: :smooth_step)
  end

  # A quick emphasis pop: hop up on a fast curve, settle back on a slow one.
  def emphasize(entity)
    entity[:gesture] = 0.0
    tween(entity, :gesture, to: 1.0, over: 10, ease: :smooth_stop)
    after(10) { tween(entity, :gesture, to: 0.0, over: 16, ease: :smooth_start) }
  end

  def view
    node({ x: 20, y: 20.from_top, anchor_y: 1 }, id: :back_bar) do
      ButtonView(id: :back, label: "Back", action: -> { change_scene(to: MenuScene.new(:main)) }, height: 46, shortcut: { keyboard: :escape, controller: :b }, pad: game.ui_pad)
    end

    dialogue_box if state.speaker
  end

  # The reactive dialogue box: a bottom panel that re-derives from state.speaker
  # and state.line every frame — speaker name in their ink, the line wrapped to
  # the panel, and a pulsing advance hint. Keyed subtrees per speaker so a turn
  # change reconciles rather than mutating in place.
  def dialogue_box
    speaker = SPEAKERS[state.speaker]

    # Explicit height: a wrap: container can't auto-derive its height (its width
    # is parent-driven, so content sizing is width-first — see docs). overflow:
    # :visible lets a long line spill rather than lazily scrolling the panel.
    node({ x: grid.w / 2, y: 30, w: 900, h: 190, anchor_x: 0.5, path: :pixel, r: 26, g: 22, b: 32 }, id: :dialogue, padding: 24, gap: 10, wrap: true, overflow: :visible) do
      node({ text: speaker[:name], size_enum: 2, **speaker[:ink] }, id: :speaker_name)
      node({ text: state.line, size_enum: 1, r: 240, g: 236, b: 228 }, id: :line)
      node({ text: hint_text, size_enum: 0, r: 150, g: 146, b: 156, a: advance_pulse }, id: :advance_hint)
    end
  end

  def hint_text
    "> confirm or tap to continue"
  end

  # Alpha-pulsed on the scene clock, so it holds still under a pause like every
  # other animated element here.
  def advance_pulse
    (150 + Math.sin(clock * 0.12) * 90).to_i.clamp(60, 255)
  end

  def render
    outputs.primitives << { x: 0, y: 0, w: grid.w, h: grid.h, path: :pixel, r: 44, g: 40, b: 58 }
    outputs.primitives << { x: 0, y: 0, w: grid.w, h: GROUND_Y, path: :pixel, r: 30, g: 27, b: 40 }
    outputs.primitives << { x: 0, y: GROUND_Y, w: grid.w, h: 3, path: :pixel, r: 92, g: 84, b: 120 }

    draw_body(state.hero, "sprites/cutscene/hero_idle.png", "sprites/cutscene/hero_talk.png", :hero, flip: false)
    draw_body(state.rival, "sprites/cutscene/rival_idle.png", "sprites/cutscene/rival_talk.png", :rival, flip: true)

    draw_portrait if state.speaker
  end

  private

  def draw_body(entity, idle_path, talk_path, who, flip:)
    talking = state.speaker == who
    pop = entity[:gesture] * 18
    scale = 1.0 + entity[:gesture] * 0.06

    outputs.primitives << {
      x: entity[:x],
      y: GROUND_Y + entity[:bob] + pop,
      w: BODY_W * scale,
      h: BODY_H * scale,
      path: talking ? talk_path : idle_path,
      anchor_x: 0.5,
      flip_horizontally: flip
    }
  end

  # The large portrait of whoever is speaking: a framed face on the speaker's
  # side, tinted with their ink so the highlight reads at a glance. The frame and
  # side both swap with the speaker — the whole point of the demo.
  def draw_portrait
    speaker = SPEAKERS[state.speaker]
    panel = 200
    x = speaker[:side] == :left ? 40 : grid.w - 40 - panel
    y = grid.h - 40 - panel

    outputs.primitives << { x: x - 4, y: y - 4, w: panel + 8, h: panel + 8, path: :pixel, **speaker[:ink] }
    outputs.primitives << { x: x, y: y, w: panel, h: panel, path: :pixel, r: 22, g: 19, b: 28 }
    outputs.primitives << { x: x + panel / 2, y: y + panel / 2, w: 150, h: 150, path: speaker[:face], anchor_x: 0.5, anchor_y: 0.5 }
  end
end
