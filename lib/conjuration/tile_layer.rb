module Conjuration
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

    def initialize(name:, chunk_size: 512)
      @name = name
      @chunk_size = chunk_size
      @chunks = {}     # [cx, cy] => [primitives in chunk-local coordinates]
      @rendered = {}   # [cx, cy] => true once its render target is populated
    end

    # File a world-space primitive into every chunk it overlaps, storing it in
    # chunk-local coordinates. The chunk's render target clips any overhang.
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

    # Removal is by intersection, not containment: a primitive goes if it
    # overlaps +rect+ at all. A border-spanning primitive is stored as a copy in
    # each chunk it straddles (in that chunk's local coordinates), so it must be
    # dropped from every one of them, not just the chunk the rect touches.
    def remove(rect)
      rx = rect[:x]
      ry = rect[:y]
      rw = rect[:w] || 0
      rh = rect[:h] || 0

      # Any primitive touching the rect has a copy in a chunk the rect covers, so
      # those chunks are complete entry points; from each hit we fan out to the
      # primitive's other chunks to evict its sibling copies. `seen` bounds the walk.
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

    # Emit each visible, populated chunk as a sprite into the camera, rendering
    # any chunk whose texture isn't cached yet.
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
      # A re-bake after #remove must not accumulate onto the stale primitives; on
      # the first bake DragonRuby hands back a fresh collection, so clearing is a
      # no-op there.
      target.primitives.clear
      @chunks[[cx, cy]].each { |primitive| target.primitives << primitive }
      @rendered[[cx, cy]] = true
    end

    def chunk_path(cx, cy)
      "tile_layer_#{name}_#{cx}_#{cy}"
    end
  end
end
