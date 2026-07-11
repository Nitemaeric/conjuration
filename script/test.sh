#!/usr/bin/env bash
#
# Run the Conjuration test suite under DragonRuby's mruby-patched interpreter.
#
# The standalone `mruby` CLI has no `require`/`require_relative` (DragonRuby
# provides those in its engine), so we preload every file with -r in dependency
# order: DR-surface shims and the dragon_input double first (lib touches the
# DragonInput constant, absent from the mruby harness), then the
# lib sub-files exactly as lib/conjuration.rb requires them (never conjuration.rb
# itself, whose require_relatives would raise), then the test doubles, then each
# *_test.rb.
# test/run.rb is the main script that discovers and runs the test_* methods.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MRUBY="$ROOT/tmp/mruby/bin/mruby"
if [ ! -x "$MRUBY" ]; then
  "$ROOT/script/build-mruby.sh"
fi

# Order mirrors lib/conjuration.rb.
preload=(
  test/support/shims.rb
  test/support/dragon_input.rb
  lib/conjuration/extensions/hash.rb
  lib/conjuration/extensions/array.rb
  lib/conjuration/base_lifecycle_methods.rb
  lib/conjuration/node.rb
  lib/conjuration/vector.rb
  lib/conjuration/input_source.rb
  lib/conjuration/ui/reconciler.rb
  lib/conjuration/ui/navigation.rb
  lib/conjuration/ui/layout.rb
  lib/conjuration/ui/text.rb
  lib/conjuration/ui/scroll.rb
  lib/conjuration/ui/view.rb
  lib/conjuration/ui/node.rb
  lib/conjuration/ui_management.rb
  lib/conjuration/camera.rb
  lib/conjuration/camera_management.rb
  lib/conjuration/tile_layer.rb
  lib/conjuration/projection.rb
  lib/conjuration/scheduler.rb
  lib/conjuration/animation.rb
  lib/conjuration/scene.rb
  lib/conjuration/scene_management.rb
  lib/conjuration/game.rb
  test/support/doubles.rb
  test/support/demo_doubles.rb
  tools/analyze_draw_order.rb
  demo/mygame/app/views/prompt_view.rb
  demo/mygame/app/views/shortcut_badge_view.rb
  demo/mygame/app/views/button_view.rb
  demo/mygame/app/scenes/basic_camera_scene.rb
  demo/mygame/app/scenes/hit_stop_scene.rb
  demo/mygame/app/scenes/zoom_scene.rb
  demo/mygame/app/scenes/ecs_scene.rb
  demo/mygame/app/scenes/parallax_scene.rb
  demo/mygame/app/scenes/ui_scene.rb
  demo/mygame/app/scenes/multiple_cameras_scene.rb
)

for test_file in test/*_test.rb; do
  preload+=("$test_file")
done

mruby_args=()
for file in "${preload[@]}"; do
  mruby_args+=(-r "$file")
done

exec "$MRUBY" "${mruby_args[@]}" test/run.rb
