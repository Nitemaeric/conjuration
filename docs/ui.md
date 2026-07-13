# UI & HUD Management

## Example

```ruby
class MyScene < Conjuration::Scene
  def setup
    add_camera(:main)

    # Set root container to grid.rect. This is the entire 1280x720 screen.
    state.ui = Conjuration::UI.build(grid.rect, padding: 100, gap: 20) do
      node({ w: 100, h: 50, path: :pixel, r: 128, g: 128, b: 128 }, justify: :center, align: :center) do
        node({ text: "Option 1", r: 255, g: 255, b: 255 })
      end

      node({ w: 100, h: 50, path: :pixel, r: 128, g: 128, b: 128 }, justify: :center, align: :center) do
        node({ text: "Option 2", r: 255, g: 255, b: 255 })
      end
    end
  end

  def render
    outputs.primitives << state.ui.primitives
  end
end
```

![Example Scene](images/ui-example-scene.png)

## API Reference

The entirety of the UI library is managed by a single class, `Conjuration::UI::Node`. You can compose a tree of nodes together to create complex UI layouts.

### `Conjuration::UI.build(root, **options, &block) -> Conjuration::UI::Node`

This is the entry point for building a UI. It takes in a root container as a rect-like hash.

### `node(object, **options, &block)`

Within the block of a `Conjuration::UI::Node`, you can create child nodes using the `node` method.

The `object` will be returned to the following methods:

- `#nodes`
- `#interactive_nodes`
- `#primitives`

It can be set by sending a hash to the `node` method:

```ruby
node({ w: 100, h: 50, path: :pixel, r: 128, g: 128, b: 128 })
```

### `#find(id) -> Conjuration::UI::Node`

Finds a node within the UI tree by its ID. It can be infinite levels deep.

### Sizing

A container with no declared size on an axis derives it from its content: the
main axis is the sum of the in-flow children plus gaps and padding; the cross
axis is the largest in-flow child plus padding. Out-of-flow (`position:
:absolute`) children are excluded from both. Declared sizes always win over the
derived ones, and an externally assigned size (`align: :stretch`, and `grow:`
once available) wins over auto-from-content.

- `max_w:` / `max_h:` — cap a node's size on an axis. The cap clamps whatever the
  size came from — derived, declared, or externally assigned — and never enlarges.

### Overflow

When a container's in-flow content extends past its resolved bounds, `overflow:`
decides what happens. It defaults to scrolling, materialized only on demand.

- `overflow: nil` (default) — a fitting container costs nothing; the first time
  content overflows it becomes a scroll container (render target + scrollbar +
  scroll input, focusable) and warns once.
- `overflow: :scroll` — always a scroll container, from the first frame.
- `overflow: :clip` — clips the content to the box (render target, no scrollbar,
  no scroll interaction).
- `overflow: :visible` — content spills past the box; never scrolls or clips.

Out-of-flow children never count toward overflow, so a deliberate overhang (a
badge pinned outside its parent's corner) never triggers scrolling.
