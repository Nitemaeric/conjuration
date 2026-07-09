# ECS integration: draco compatibility (roadmap D1)

## Verdict: works with glue

[draco](https://github.com/guitsaru/draco) — a small, DragonRuby-native Entity
Component System — integrates with Conjuration **without any core changes**. The
"glue" is a handful of scene-level conventions, not framework code:

1. tick the draco `World` from `Scene#update` (not `#draw_world`);
2. map components (objects) to `camera.draw` (hash primitives) in `#draw_world`;
3. hold the `World` in an instance variable, not in serializable scene `state`;
4. cache the filtered renderable list once per frame so per-camera rendering
   does not re-run draco's entity filter.

None of these needs a change to `Camera`, `Scene`, or `Game`. The runnable proof
lives under `demo/mygame/app/ecs/` and `demo/mygame/app/scenes/ecs_scene.rb`
(see [Recommended layout](#recommended-layout)); it is reachable from the demo
main menu ("ECS (draco)").

## Recommended layout

A shipping game keeps components, entities, and systems in their own files, one
class per file, rather than in a single scene:

```
demo/mygame/app/
  ecs/
    components/     position.rb, velocity.rb, sprite.rb
    entities/       critter.rb
    systems/        movement_system.rb, bounce_system.rb
  scenes/
    ecs_scene.rb    the only Conjuration-aware file: world setup, tick, render
```

This scales past a handful of systems; the small component and system files stay
diff-friendly; and the scene stays the single Conjuration-aware file (world
construction, ticking from `#update`, and the `camera.draw` render path), so ECS
code and engine glue never bleed into one another.

**Require order (DragonRuby-specific).** DR resolves `require "app/..."` from the
game root but `require_relative` cannot traverse `..`, so cross-directory files
use app-root requires: `entities/critter.rb` and each system `require
"app/ecs/components/..."`, and `ecs_scene.rb` requires the entity plus both
systems. `require` de-dupes by path, so shared components load once regardless of
how many files ask for them.

## How draco is vendored

Via **drenv** (the route the project already uses for `frame-timer`):

```
drenv add github:guitsaru/draco
```

This adds the dependency to `demo/mygame/drenv.toml`, records the resolved
commit + integrity hash in `drenv.lock`, and appends the require to the
generated `app/drenv_bundle.rb`. As with `conjuration` and `frame-timer`, the
vendored source under `demo/mygame/vendor/` is git-ignored and re-fetched by
`drenv run` / `drenv bundle` from the lockfile — so the committed change is just
the toml/lock/bundle. No source was copied into the repo. (The fallback of
hand-vendoring the single `draco.rb` was not needed; drenv fetched it cleanly.)

Pinned: draco `v0.6.1`, commit `ef4f18ea726648953021b612b21ee2e93c988162`. draco
is MIT-licensed (© Matt Pruitt / guitsaru).

## Runs under DragonRuby's mruby

draco is written for DragonRuby's patched mruby and loaded + ticked cleanly
under the exact interpreter the test harness builds (`tmp/mruby/bin/mruby`, mruby
3.0.0). Verified out-of-band: the `World` ticks, systems mutate components,
entity iteration and `serialize` all work. No API mismatch with the pinned build
was found. (The one method absent from that build, `Array#sort_by!`, is a stdlib
gap unrelated to draco; draco itself never calls it.)

## What worked out of the box

- **`World#tick` from `Scene#update`.** draco's `World#tick(context)` takes an
  arbitrary context (in DragonRuby, normally `args`). The demo passes the
  `Scene` itself, so systems read world bounds off `context.virtual_w/h`. One
  call per frame; nothing in draco assumes a particular engine object.
- **Clock / hit-stop for free.** Because the tick lives in `#update` — which
  `Game#tick` skips during a hit stop — the entire simulation freezes with the
  game and resumes in step. No integration with `game.clock` is required; the
  ECS inherits the freeze by construction. (This is the reason step 1 of the
  glue matters: ticking the World from `#draw_world` instead would keep it
  running through a freeze, since rendering is not frozen.)
- **`camera.draw(..., z:)`.** Deferred z-ordering works with ECS-driven
  entities exactly as with hand-authored ones: `z: -position.y` gives a y-sort
  and depth falls out of the z buffer, no manual layering.
- **Culling.** `camera.draw` already culls off-screen primitives, so the demo
  hands every critter to every camera and only visible ones are emitted.

## What required glue

### Components (objects) → primitives (hashes)

draco components are plain objects with attribute accessors
(`entity.position.x`); `camera.draw` wants a hash primitive
(`{ x:, y:, w:, path:, r:, g:, b: }`). The mapping is one read per field. The
only subtlety is the **hot-path allocation rule**: building a fresh hash per
entity per camera per frame would allocate heavily. The demo avoids this by
storing a **reusable primitive hash on the `Sprite` component**, built once and
mutated in place each frame:

```ruby
class Sprite < Draco::Component
  attribute :w; attribute :h; attribute :r; attribute :g; attribute :b
  attr_reader :primitive
  def after_initialize
    @primitive = { w: w, h: h, path: :pixel, r: r, g: g, b: b }
  end
end
```

`camera.draw` `dup`s the primitive internally (`to_viewport`), so mutating and
re-handing the same hash is safe — the buffered copy is independent. Verified:
across 30 frames × 2 cameras, each sprite's primitive keeps a single stable
`object_id` (drawn 60×, allocated once). **Note the trap:** this must NOT be a
draco `attribute` with a `{}` default — attribute defaults are evaluated once
and shared, which would hand every entity the *same* hash.

### Keep the World out of serializable scene state

Conjuration's `Scene#state` (`game.state["scene_<name>"]`) is intended to be
serializable (DragonRuby round-trips `args.state` for save/replay/hot-reload). A
draco `World` is a live object graph — `Draco::Set`s, per-entity subscription
lists, class references — that does not belong there. The demo holds it in
`@world`. draco *does* provide `#serialize` (World/Entity/Component all return
plain hashes), so a game that wants ECS state in a save file can serialize
explicitly and rebuild on load; but it should not drop the live `World` into
`state` and expect Conjuration's generic serialization to cope. Minor, but worth
stating as the recommended pattern.

## The registry question (roadmap D3)

**Does per-camera, per-frame entity iteration cost enough to justify an entity
registry in core?** draco's `World#filter(*components)` returns a **fresh set
intersection on every call** (`EntityStore#[]` reduces with `&`, allocating a new
`Set`). Rendering is per-camera, so the naive pattern — calling
`world.filter(...)` inside `#draw_world` — re-runs that intersection once per
camera per frame.

Measured on the DR mruby build (debug build, so absolute numbers are pessimistic
vs. the shipping runtime; the **ratio** is the signal), 4 cameras, 600 frames:

| entities | filter per camera | filter once, iterate cache | overhead |
|---------:|------------------:|---------------------------:|---------:|
| 200      | 0.59 ms/frame     | 0.32 ms/frame              | 1.86×    |
| 1000     | 2.99 ms/frame     | 1.60 ms/frame              | 1.86×    |

The overhead is a consistent ~1.86× and scales linearly. At a few hundred
entities it is negligible; by ~1000 entities across 4 cameras the re-filter
alone is ~3 ms — nearly a fifth of a 16.6 ms frame — before a single draw.

**The mitigation needs no core change.** Filter once per frame in `#update`,
cache the array, and iterate the cache in `#draw_world` (steps 2 + 4 of the
glue, and what the demo does):

```ruby
def update
  @world.tick(self)
  @renderables = @world.filter(Position, Sprite).to_a   # once per frame
end

def draw_world(camera)
  @renderables.each { |e| camera.draw(e.sprite.primitive, z: -e.position.y) }
end
```

This removes the per-camera set allocation and roughly halves the cost, entirely
at the scene level.

**Recommendation: do not build the core entity registry (D3) yet.** The cost
that would motivate it is real but only bites at high entity counts with many
cameras, and it is fully addressed by a three-line scene-level cache. A core
registry would buy standardization (a shared "filter once, iterate per camera"
abstraction so every game doesn't re-derive it) rather than a capability
Conjuration lacks. Defer it until a real game both (a) runs into the high-entity,
multi-camera regime and (b) wants the pattern factored out — at which point D3
becomes a thin convenience layer over exactly this cache, and can be designed
against that game's real access patterns instead of speculatively.

## Compatibility statement

**draco works with Conjuration, with glue — no core changes needed.** The glue
is four scene-level conventions (tick in `#update`; map components to primitives
with a reusable hash; keep the `World` in an ivar; cache the filtered list per
frame), all demonstrated by the demo under `demo/mygame/app/ecs/` and
`demo/mygame/app/scenes/ecs_scene.rb`. The
conditional entity registry (D3) is **not** recommended at this time; revisit it
only when a shipping game exercises the high-entity / multi-camera path.
