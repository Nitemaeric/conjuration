# View components live under app/views and are required per scene. DragonRuby
# resolves require paths from the game root (not the requiring file), so use the
# app/-relative path rather than require_relative "../views/...".
require "app/views/button_view.rb"
require "app/views/bar_view.rb"

# A reactive scene demonstrating the view reconciler. The HUD is declared once
# as `view`, a pure function of state. update() only animates bar[:progress];
# adding a bar (Add button) and removing one (click a row) mutate state.items,
# and the reconciler turns each frame's declaration into keyed create / remove /
# reorder plus prop updates on the retained nodes — no ui.find, no invalidate!,
# no manual geometry. Each row is a BarView component.
class ReactiveScene < Conjuration::Scene
  PANEL_WIDTH = 520

  def setup
    state.items = 3.times.map { |i| new_bar(i) }
    state.next_id = 3
  end

  def new_bar(id)
    { id: id, progress: (id * 20) % 100, rate: 25 + id % 3 * 15 }
  end

  def spawn
    state.items << new_bar(state.next_id)
    state.next_id += 1
  end

  def remove(id)
    state.items.reject! { |item| item[:id] == id }
  end

  def update
    # The only per-frame state mutation is bar[:progress]; structure changes come
    # from the button actions. The view re-derives everything from state.items.
    state.items.each do |item|
      item[:progress] = (item[:progress] + item[:rate] / 60) % 100
    end
  end

  def input
    activate_navigation(:controls) if Conjuration::UI.active_navigation_group.nil? && inputs.last_active != :mouse
  end

  def view
    node({ x: 20, y: 20.from_top, anchor_y: 1 }, group: :controls, direction: :row, gap: 12) do
      ButtonView(id: :back, label: "Back", action: -> { change_scene(to: MenuScene.new(:main)) }, shortcut: { keyboard: :escape, controller: :b })
      ButtonView(id: :add, label: "Add bar", width: 140, action: -> { spawn })
    end

    node({ x: grid.w / 2, y: grid.h / 2, w: PANEL_WIDTH, h: 360, anchor_x: 0.5, anchor_y: 0.5, path: :pixel, r: 24, g: 26, b: 34 }, id: :panel, gap: 10, padding: 20, justify: :center) do
      node({ text: "Reactive bars — click one to remove it", r: 255, g: 255, b: 255 }, id: :title)
      node({ text: "No bars. Click Add bar.", r: 150, g: 150, b: 160 }, id: :empty) if state.items.empty?

      state.items.each do |item|
        # Each row is a view component, invoked as a function call. A fresh
        # on_remove lambda per frame is fine — the component isn't memoized.
        BarView(item: item, on_remove: ->(id) { remove(id) })
      end
    end
  end

  def render
    outputs.primitives << { x: grid.allscreen_x, y: grid.allscreen_y, w: grid.allscreen_w, h: grid.allscreen_h, path: :pixel, r: 28, g: 28, b: 36 }
  end

  private

  # ButtonView draws its own focus brackets; skip the framework's default ring.
end
