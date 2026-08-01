module Conjuration
  # A virtual resolution: scene-space geometry is authored in canvas pixels, the
  # frame is composed into a canvas-sized render target, and that target is
  # blitted to the window centred and letterboxed (LOWREZJAM-style 64x64, a
  # 320x180 pixel-art game, anything fixed). The zoom/offset math mirrors
  # DragonRuby's own lowrez sample.
  #
  # Fixed for the lifetime of a scene: declare it, never mutate it.
  class Canvas
    attr_reader :w, :h, :integer_scale

    def self.coerce(value)
      return nil if value.nil?
      return value if value.is_a?(Canvas)

      new(w: value[:w], h: value[:h], integer_scale: value.key?(:integer_scale) ? value[:integer_scale] : true)
    end

    def initialize(w:, h:, integer_scale: true)
      raise ArgumentError, "canvas needs positive w/h (got #{w.inspect}x#{h.inspect})" unless w.to_i > 0 && h.to_i > 0

      @w = w.to_i
      @h = h.to_i
      @integer_scale = integer_scale
    end

    # Blit geometry for this canvas inside a window: the zoom, the centred
    # offsets, and the scaled extent. Memoized per window size — the window only
    # changes on a resize.
    def metrics(window_w, window_h)
      return @metrics if @metrics && @metrics_w == window_w && @metrics_h == window_h

      zoom = fit_zoom(window_w, window_h)
      scaled_w = @w * zoom
      scaled_h = @h * zoom

      @metrics_w = window_w
      @metrics_h = window_h
      @metrics = {
        zoom: zoom,
        offset_x: (window_w - scaled_w).to_f / 2,
        offset_y: (window_h - scaled_h).to_f / 2,
        w: scaled_w,
        h: scaled_h
      }
    end

    def blit(window_w, window_h, path)
      view = metrics(window_w, window_h)

      { x: view[:offset_x], y: view[:offset_y], w: view[:w], h: view[:h], path: path }
    end

    # Window point -> canvas pixel. Floored (DragonRuby's `idiv`), so a point
    # names the pixel it lands in and a point in the letterbox bars lands outside
    # 0...w / 0...h rather than clamping onto an edge pixel.
    def to_canvas(x, y, window_w, window_h)
      view = metrics(window_w, window_h)

      {
        x: ((x - view[:offset_x]).to_f / view[:zoom]).floor,
        y: ((y - view[:offset_y]).to_f / view[:zoom]).floor
      }
    end

    def inspect
      "#<#{self.class.name} #{@w}x#{@h} integer_scale=#{@integer_scale}>"
    end

    private

    def fit_zoom(window_w, window_h)
      width_zoom = window_w.to_f / @w
      height_zoom = window_h.to_f / @h
      fit = width_zoom < height_zoom ? width_zoom : height_zoom
      return fit unless @integer_scale

      # A window too small for even 1:1 keeps the fractional fit rather than
      # collapsing the canvas to nothing.
      floored = fit.floor
      floored < 1 ? fit : floored
    end
  end

  # The mouse in canvas coordinates. Everything the framework transforms (x/y and
  # the rect/hit helpers built on them) is recomputed; everything else — click,
  # held, wheel, buttons — is the raw device state and is delegated untouched.
  class CanvasMouse
    attr_reader :x, :y

    def initialize(source, canvas, window_w, window_h)
      @source = source

      point = canvas.to_canvas(source.x, source.y, window_w, window_h)
      @x = point[:x]
      @y = point[:y]
    end

    def w; 1; end
    def h; 1; end

    def rect
      { x: @x, y: @y, w: 1, h: 1 }
    end

    def inside_rect?(other)
      @x >= other.x && @x <= other.x + other.w &&
        @y >= other.y && @y <= other.y + other.h
    end

    def intersect_rect?(other)
      Geometry.intersect_rect?(rect, other.respond_to?(:rect) ? other.rect : other)
    end

    def method_missing(name, *args, &block)
      @source.send(name, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      @source.respond_to?(name, include_private)
    end
  end

  # The resolution seam. `view_w`/`view_h` are the dimensions SCENE-space
  # geometry is expressed in — the canvas when one resolves, the window
  # otherwise. Debug tooling deliberately does NOT use them: outputs.debug
  # bypasses the canvas, so it stays on grid.w/grid.h. Mixed into anything that
  # can answer #active_canvas.
  module ViewDimensions
    def view_w
      canvas = active_canvas
      canvas ? canvas.w : grid.w
    end

    def view_h
      canvas = active_canvas
      canvas ? canvas.h : grid.h
    end
  end

  # The game side of the resolution chain, for whatever owns the scene stack.
  module CanvasHost
    include ViewDimensions

    # Game-level default: `game.canvas = { w: 64, h: 64 }` (add
    # `integer_scale: false` for the max fractional fit). Scenes declare their
    # own with the class-level `canvas` DSL. nil = native window resolution.
    attr_reader :canvas

    def canvas=(value)
      @canvas = Canvas.coerce(value)
    end

    # The canvas in force this frame: the top scene's declaration, else the game
    # default, else nil.
    def active_canvas
      scene = current_scene
      scene.respond_to?(:active_canvas) ? scene.active_canvas : @canvas
    end

    # The mouse in SCENE space — canvas coordinates when a canvas resolves, the
    # raw device mouse otherwise. Framework hit-testing (UI hover/click/wheel,
    # camera focus, sequence advance) reads this; debug tooling that draws in
    # window space keeps reading `inputs.mouse`.
    def mouse
      raw = inputs && inputs.mouse
      canvas = active_canvas
      return raw unless canvas && raw

      CanvasMouse.new(raw, canvas, grid.w, grid.h)
    end
  end
end
