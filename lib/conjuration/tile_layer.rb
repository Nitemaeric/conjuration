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

    def render_chunk(cx, cy)
      target = game.outputs[chunk_path(cx, cy)]
      target.width = chunk_size
      target.height = chunk_size
      @chunks[[cx, cy]].each { |primitive| target.primitives << primitive }
      @rendered[[cx, cy]] = true
    end

    def chunk_path(cx, cy)
      "tile_layer_#{name}_#{cx}_#{cy}"
    end
  end
end
