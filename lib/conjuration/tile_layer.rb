module Conjuration
  # Caches static world content into fixed-size chunk render targets for efficient rendering.
  #
  # Static primitives are filed into chunks once; on draw, only visible chunks are
  # emitted as textured quads instead of thousands of primitives per frame. Chunk
  # targets are bounded by chunk_size, so the world can be arbitrarily large without
  # exceeding GPU texture limits. Zooming out to reveal the whole world costs one
  # draw per visible chunk, not per tile.
  #
  # Content is assumed static; draw dynamic overlays (hover, selection, entities)
  # separately via camera.draw.
  #
  # @example Creating a tile layer and populating it
  #   tiles = Conjuration::TileLayer.new(name: :ground, chunk_size: 512)
  #   100.times do |i|
  #     tiles.add({ x: i * 40, y: 0, w: 40, h: 40, path: :pixel, r: 100, g: 200, b: 100 })
  #   end
  #
  # @example Drawing the tile layer
  #   def draw_world(camera)
  #     @tiles.draw(camera)
  #   end
  #
  # Caches static world content into fixed-size chunk render targets, so a dense
  # world is drawn as a handful of textured quads instead of thousands of
  # primitives every frame.
  #
  # Add static primitives once; on #draw only the chunks overlapping the camera's
  # view are emitted, and each chunk's texture is rendered lazily (once) then
  # sampled. Chunk targets are bounded by chunk_size, so the world itself can be
  # arbitrarily large without exceeding the GPU texture limit, and zooming out to
  # reveal the whole world costs one draw per visible chunk rather than per tile.
  #
  # Content is assumed static. Draw dynamic overlays (hover, selection, entities)
  # separately via camera.draw.
  class TileLayer < Node
    attr_reader :name, :chunk_size

    # Create a new tile layer.
    #
    # @param name [Symbol, String] unique identifier for this layer
    # @param chunk_size [Numeric] size of each chunk's render target (default: 512)
    # @return [void]
    def initialize(name:, chunk_size: 512)
      @name = name
      @chunk_size = chunk_size
      @chunks = {}     # [cx, cy] => [primitives in chunk-local coordinates]
      @rendered = {}   # [cx, cy] => true once its render target is populated
    end

    # File a world-space primitive into every chunk it overlaps.
    #
    # Stores the primitive in chunk-local coordinates; the chunk's render target
    # clips any overhang. A border-spanning primitive is stored in every chunk it
    # straddles.
    #
    # @param primitive [Hash] world-space primitive with x, y, w, h, path, etc.
    # @return [void]
    # @example Adding a static sprite
    #   tiles.add({ x: 100, y: 200, w: 64, h: 64, path: "sprites/tree.png" })
    # @example Adding a grid of cells
    #   (0...10).each do |row|
    #     (0...10).each do |col|
    #       tiles.add({
    #         x: col * 40, y: row * 40, w: 40, h: 40,
    #         path: :pixel, r: 128, g: 128, b: 128
    #       })
    #     end
    #   end
    def add(primitive)
      x = primitive[:x]
      y = primitive[:y]
      w = primitive[:w] || 0
      h = primitive[:h] || 0

      chunk_span(x, x + w).each do |cx|
        chunk_span(y, y + h).each do |cy|
          local = primitive.dup
          local[:x] = x - cx * chunk_size
          local[:y] = y - cy * chunk_size
          (@chunks[[cx, cy]] ||= []) << local
        end
      end
    end

    # Remove primitives that intersect a world-space rectangle.
    #
    # Uses intersect semantics: only primitives whose bounds overlap the removal
    # rect are erased. When a primitive spans multiple chunks, it is removed from
    # all chunks it occupies. Re-renders affected chunks on next draw.
    #
    # @param rect [Hash] world-space rectangle {x:, y:, w:, h:}
    # @return [void]
    # @example Clearing a region
    #   tiles.remove({ x: 100, y: 100, w: 200, h: 200 })
    # @note Primitives that cross chunk boundaries are removed atomically across
    #   all chunks. Per-chunk copies are invalidated and re-rendered on next draw.
    def remove(rect)
      rx = rect[:x]
      ry = rect[:y]
      rw = rect[:w] || 0
      rh = rect[:h] || 0

      pending = []
      chunk_span(rx, rx + rw).each do |cx|
        chunk_span(ry, ry + rh).each do |cy|
          pending << [cx, cy]
        end
      end

      seen = {}
      until pending.empty?
        key = pending.pop
        next if seen[key]

        seen[key] = true
        primitives = @chunks[key]
        next unless primitives

        cx, cy = key
        removed_any = false

        primitives.reject! do |local|
          wx = local[:x] + cx * chunk_size
          wy = local[:y] + cy * chunk_size
          ww = local[:w] || 0
          wh = local[:h] || 0

          next false unless overlap?(wx, wy, ww, wh, rx, ry, rw, rh)

          removed_any = true

          # A border-spanning primitive has a copy in every chunk it straddles; evict them all.
          chunk_span(wx, wx + ww).each do |ox|
            chunk_span(wy, wy + wh).each do |oy|
              pending << [ox, oy] unless seen[[ox, oy]]
            end
          end

          true
        end

        next unless removed_any

        @rendered.delete(key)
        @chunks.delete(key) if primitives.empty?
      end
    end

    # Emit each visible, populated chunk as a sprite into the camera.
    #
    # Renders any chunk whose texture isn't cached yet, then emits it as a
    # textured quad via camera.draw.
    #
    # @param camera [Camera] the camera to draw into
    # @return [void]
    # @example Drawing all visible chunks
    #   def draw_world(camera)
    #     @tile_layer.draw(camera)
    #   end
    def draw(camera)
      view = camera.view_rect

      chunk_span(view[:x], view[:x] + view[:w]).each do |cx|
        chunk_span(view[:y], view[:y] + view[:h]).each do |cy|
          next unless @chunks.key?([cx, cy])

          render_chunk(cx, cy) unless @rendered[[cx, cy]]

          camera.draw({
            x: cx * chunk_size,
            y: cy * chunk_size,
            w: chunk_size,
            h: chunk_size,
            path: chunk_path(cx, cy)
          })
        end
      end
    end

    private

    def chunk_span(from, to)
      (from / chunk_size).floor..(to / chunk_size).floor
    end

    def overlap?(ax, ay, aw, ah, bx, by, bw, bh)
      ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
    end

    def render_chunk(cx, cy)
      target = game.outputs[chunk_path(cx, cy)]
      target.width = chunk_size
      target.height = chunk_size
      # A re-bake after #remove accumulates onto the target's kept primitives unless cleared.
      target.primitives.clear
      @chunks[[cx, cy]].each { |primitive| target.primitives << primitive }
      @rendered[[cx, cy]] = true
    end

    def chunk_path(cx, cy)
      "tile_layer_#{name}_#{cx}_#{cy}"
    end
  end
end
