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

    # Drop every stored primitive whose world-space bounds intersect +rect+ and
    # invalidate only the chunks that lost something, so the next #draw re-bakes
    # those textures and leaves the rest of the world's cached chunks untouched.
    #
    # Intersect, not contain: a primitive is removed if it overlaps +rect+ at
    # all, matching how a destructible region ("blow a hole here") reads. A
    # primitive filed into several chunks (it straddled their borders) is removed
    # from every one of them, since each chunk holds a copy in its own local
    # coordinates.
    #
    # This is an event-time operation, not a per-frame one — dynamic content
    # still belongs in camera.draw. A layer that never calls #remove keeps its
    # add/draw path byte-for-byte identical to a layer without this method.
    def remove(rect)
      rx = rect[:x]
      ry = rect[:y]
      rw = rect[:w] || 0
      rh = rect[:h] || 0

      # The chunks the rect covers are the entry points: any primitive touching
      # the rect has at least one copy here (its overlap with the rect lies
      # inside one of them). From each removed primitive we fan out to its full
      # chunk span, so copies that live in neighbouring chunks the rect doesn't
      # itself cover are dropped too. `seen` keeps the walk from re-scanning a
      # chunk; each chunk that loses a primitive is invalidated as we go.
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

          # Queue the primitive's other chunks so its sibling copies go with it.
          chunk_span(wx, wx + ww).each do |ox|
            chunk_span(wy, wy + wh).each do |oy|
              pending << [ox, oy] unless seen[[ox, oy]]
            end
          end

          true
        end

        next unless removed_any

        # Invalidate the texture so #draw re-bakes it; forget the chunk entirely
        # once empty so it is never re-rendered or emitted again.
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

    # AABB overlap on raw scalars — no hash allocation, so #remove stays cheap
    # even when sweeping a rect across many stored primitives.
    def overlap?(ax, ay, aw, ah, bx, by, bw, bh)
      ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
    end

    def render_chunk(cx, cy)
      target = game.outputs[chunk_path(cx, cy)]
      target.width = chunk_size
      target.height = chunk_size
      # Clear first so an invalidated (re-baked) chunk reflects only its current
      # primitives. On the first bake this is a no-op; DragonRuby hands back a
      # fresh per-tick primitives collection anyway, so unused layers are
      # unaffected.
      target.primitives.clear
      @chunks[[cx, cy]].each { |primitive| target.primitives << primitive }
      @rendered[[cx, cy]] = true
    end

    def chunk_path(cx, cy)
      "tile_layer_#{name}_#{cx}_#{cy}"
    end
  end
end
