module Conjuration
  class Camera < Node
    include BaseLifecycleMethods
    include UIManagement

    attr_accessor :scene, :name

    # Camera's viewport on the screen
    attr_accessor :x, :y, :w, :h

    attr_accessor :current, :target, :current_at_target_change
    attr_accessor :speed, :zoom_speed

    attr_reader :following, :trauma

    # Screen-shake tuning: peak view offset in world units (at trauma = 1), and
    # trauma lost per tick.
    SHAKE_MAGNITUDE = 24
    SHAKE_DECAY = 0.04

    # The per-tick step is clamped to the remaining distance, so this large speed snaps instantly.
    SNAP = 1_000_000

    def initialize(scene, name:, x: 0, y: 0, w: grid.w, h: grid.h, current: { x: grid.w / 2, y: grid.h / 2, zoom: 1 }, speed: SNAP, zoom_speed: 0.1)
      super(scene: scene, name: name, x: x, y: y, w: w, h: h, speed: speed, zoom_speed: zoom_speed)

      @output_key = "camera_#{name}"

      @current = FocalPoint.new(self, **current)
      @target = FocalPoint.new(self, **current)

      # Per-frame buffer of deferred, z-ordered draws: [z, emission_index,
      # primitive]. Empty (and untouched) unless a draw passes `z:`, so the
      # default draw path allocates nothing here.
      @draw_buffer = []
    end

    def look_at(object)
      # A positional look_at takes manual control, so it ends any active follow;
      # a zoom-only look_at leaves the follow running.
      @following = nil if object.x || object.y

      self.target.x    = object.x    if object.x
      self.target.y    = object.y    if object.y
      self.target.zoom = object.zoom if object.zoom

      self.current_at_target_change = current.dup
    end

    # Continuously centre the view on `object` (anything exposing x/y). The
    # camera approaches it each frame at a constant `speed` (units/tick, clamped
    # to the remaining distance — not an eased/proportional step), so a low speed
    # gives a smooth, lagging follow and a high speed a rigid lock. Call #unfollow
    # (or a positional #look_at) to stop.
    def follow(object)
      @following = object
    end

    def unfollow
      @following = nil
    end

    # Add trauma (0..1) to shake the view. Stacks (capped at 1.0) and decays each
    # tick; the offset scales with trauma squared, so it falls off smoothly. Pass
    # a `direction:` vector (e.g. an impact's direction) to shake along that axis;
    # omit it for an omnidirectional shake.
    def shake(amount = 0.6, direction: nil)
      @trauma = [(@trauma || 0) + amount, 1.0].min
      @shake_direction = normalize_direction(direction)
    end

    def to_world(x:, y:, w: nil, h: nil)
      {
        x: current.x + (x - self.x - self.w / 2) / current.zoom,
        y: current.y + (y - self.y - self.h / 2) / current.zoom,
        w: w ? w / current.zoom : nil,
        h: h ? h / current.zoom : nil
      }
    end

    def to_screen(x:, y:, w: nil, h: nil)
      {
        x: self.x + self.w / 2 + (x - current.x) * current.zoom,
        y: self.y + self.h / 2 + (y - current.y) * current.zoom,
        w: w ? w * current.zoom : nil,
        h: h ? h * current.zoom : nil
      }
    end

    # World-space rectangle this camera currently sees (pan, zoom, and any active
    # screen shake applied). Memoized per render frame.
    #
    # A background layer is culled and transformed against its own derived view —
    # the focal point scaled by `parallax` — not the real view. That is the point
    # of the built-in support: a hand-rolled parallax tests `visible?` against the
    # real view, so it culls layer sprites near the edges wrongly.
    def view_rect(parallax: 1.0)
      return (@view_rect ||= compute_view_rect(1.0)) if parallax == 1.0

      (@parallax_view_rects ||= {})[parallax] ||= compute_view_rect(parallax)
    end

    # Whether a world-space rect overlaps the current view at all. Hand-rolled
    # AABB test with bracket access: this runs per object per camera per frame,
    # so it avoids method_missing and Geometry-call overhead.
    #
    # `parallax` is positional (not a keyword) to keep the per-object hot path
    # free of a kwargs hash allocation; the default 1.0 hits the memoized view.
    def visible?(world_rect, parallax = 1.0)
      view = parallax == 1.0 ? view_rect : view_rect(parallax: parallax)
      rw = world_rect[:w] || 0
      rh = world_rect[:h] || 0

      world_rect[:x]      < view[:x] + view[:w] &&
        world_rect[:x] + rw > view[:x] &&
        world_rect[:y]      < view[:y] + view[:h] &&
        world_rect[:y] + rh > view[:y]
    end

    # World space -> this camera's viewport-local space, (0, 0)..(w, h). Handles
    # rects/sprites (x/y/w/h), lines (x2/y2), and labels (size_px), so any world
    # primitive pans and scales with the camera. Anchors are unitless and carried
    # through unchanged. Bracket access keeps this allocation- and
    # method_missing-light on the hot path.
    def to_viewport(world_rect, parallax = 1.0)
      view = parallax == 1.0 ? view_rect : view_rect(parallax: parallax)
      zoom = current.zoom

      result = world_rect.dup
      result[:x] = (world_rect[:x] - view[:x]) * zoom
      result[:y] = (world_rect[:y] - view[:y]) * zoom
      result[:w] = world_rect[:w] * zoom if world_rect[:w]
      result[:h] = world_rect[:h] * zoom if world_rect[:h]
      result[:x2] = (world_rect[:x2] - view[:x]) * zoom if world_rect[:x2]
      result[:y2] = (world_rect[:y2] - view[:y]) * zoom if world_rect[:y2]
      result[:size_px] = world_rect[:size_px] * zoom if world_rect[:size_px]
      result
    end

    # Cull + transform + emit a world-space primitive into this camera's
    # viewport. A no-op when the rect is outside the view, so a scene can hand
    # every object to every camera and only the visible ones are drawn.
    #
    # Pass `z:` to defer the draw into a per-frame buffer that is flushed, sorted
    # by z, after the whole world pass — so an entity can be interleaved between
    # tiles (player behind a tree, iso depth) without the scene ordering every
    # call. y-sorting is the usual convention: `z: -sprite[:y]`. Deferred draws
    # always render ON TOP of the immediate (no-`z:`) ones, which emit first;
    # equal-z draws keep their call order. Omit `z:` for the immediate fast path.
    def draw(world_rect, z: nil, parallax: 1.0)
      return unless visible?(world_rect, parallax)

      if z
        @draw_buffer << [z, @draw_buffer.length, to_viewport(world_rect, parallax)]
      else
        outputs.primitives << to_viewport(world_rect, parallax)
      end
    end

    # Viewport-relative HUD coordinates. A camera's UI is drawn into its own
    # w x h render target, so HUD positions are relative to the viewport, not the
    # screen grid (DR's Numeric#from_top / #from_right assume the grid, which is
    # only correct for a full-screen camera).
    def from_left(distance);   distance;     end
    def from_right(distance);  w - distance; end
    def from_bottom(distance); distance;     end
    def from_top(distance);    h - distance; end

    def outputs
      game.outputs[@output_key]
    end

    private

    def perform_update
      super

      if following
        self.target.x = following.x
        self.target.y = following.y
      end

      if target.x != current.x || target.y != current.y
        normalized_direction = Geometry.vec2_normalize(x: (target.x - current.x), y: (target.y - current.y))

        self.current.x += (normalized_direction.x * speed).clamp(-(target.x - current.x).abs, (target.x - current.x).abs)
        self.current.y += (normalized_direction.y * speed).clamp(-(target.y - current.y).abs, (target.y - current.y).abs)
      end

      if target.zoom != current.zoom
        zoom_step = target.zoom > current.zoom ? zoom_speed : -zoom_speed

        self.current.zoom += zoom_step.clamp(-(target.zoom - current.zoom).abs, (target.zoom - current.zoom).abs)
      end

      @trauma = [@trauma - SHAKE_DECAY, 0].max if @trauma && @trauma > 0
    end

    # Emit the deferred draws, sorted by z then emission order, and clear the
    # buffer for the next frame. Sorting on the emission index as the tie-breaker
    # makes equal-z order deterministic (call order) regardless of whether the
    # underlying sort is stable — mruby's is not — so equal-z primitives never
    # flicker. The explicit comparator avoids the per-comparison array alloc a
    # `[z, index] <=>` key would cost on this per-frame path.
    def flush_ordered_draws
      return if @draw_buffer.empty?

      @draw_buffer.sort! { |a, b| a[0] == b[0] ? a[1] <=> b[1] : a[0] <=> b[0] }
      @draw_buffer.each { |_, _, primitive| outputs.primitives << primitive }
      @draw_buffer.clear
    end

    # Only the focal-point translation scales by `parallax`; zoom (view size) is
    # un-scaled, so every layer shares a zoom and they never warp apart as you
    # zoom. Shake is a screen effect, applied un-scaled too.
    def compute_view_rect(parallax)
      shake_x, shake_y = shake_offset

      {
        x: current.x * parallax + shake_x - (w / current.zoom) / 2,
        y: current.y * parallax + shake_y - (h / current.zoom) / 2,
        w: w / current.zoom,
        h: h / current.zoom
      }
    end

    # View offset for the current trauma, falling off with trauma squared. With a
    # shake direction set, the offset oscillates along that axis (impact shake);
    # otherwise it is omnidirectional.
    def shake_offset
      return [0, 0] unless @trauma && @trauma > 0

      magnitude = SHAKE_MAGNITUDE * @trauma * @trauma

      if @shake_direction
        amount = magnitude * (rand * 2 - 1)
        [amount * @shake_direction[:x], amount * @shake_direction[:y]]
      else
        [magnitude * (rand * 2 - 1), magnitude * (rand * 2 - 1)]
      end
    end

    # Unit vector for a direction hash, or nil when absent or zero-length.
    def normalize_direction(vector)
      return nil unless vector

      magnitude = Math.sqrt(vector[:x]**2 + vector[:y]**2)
      return nil if magnitude.zero?

      { x: vector[:x] / magnitude, y: vector[:y] / magnitude }
    end

    def perform_render
      @view_rect = nil
      # Nil, not clear: a frame with no parallax draw never re-creates the hash,
      # keeping the no-parallax path allocation-free.
      @parallax_view_rects = nil

      # Size the viewport target once. It stays viewport-sized (never world-sized)
      # so an arbitrarily large world can't exceed the GPU texture limit, and DR
      # retains the size across frames, so there's no need to set it every tick.
      unless @target_sized
        outputs.width, outputs.height = w, h
        @target_sized = true
      end

      # The scene draws its world through us; only on-screen content is emitted.
      # Immediate (no-`z:`) draws land in outputs.primitives here, in call order.
      scene.draw_world(self)

      # Then flush the deferred draws on top of them, z-sorted. Nothing to do
      # unless the scene used `z:`, so the plain path pays only an emptiness check.
      flush_ordered_draws

      # Camera HUD: re-derive from state (no-op unless camera.ui has a view),
      # then relay once per frame. Clean subtrees early-out, so this is near-free
      # when nothing changed.
      ui.render_view
      ui.calculate_layout
      ui.render_scroll_targets

      outputs.primitives << ui.primitives

      indicator = focus_indicator
      outputs.primitives << indicator if indicator

      if debug?
        outputs.debug << ui.interactive_nodes.map do |node|
          {
            **node.rect,
            r: 0,
            g: 255,
            b: 0
          }.border!
        end

        # Invisible layout containers, in magenta — only where they resolve to
        # real bounds (the root has none).
        container_bounds = ui.nodes.reject(&:renderable?).map(&:rect).select { |rect| rect[:w] && rect[:h] }
        outputs.debug << container_bounds.map { |rect| { **rect, r: 255, g: 0, b: 255 }.border! }
      end

      # Blit the camera's viewport onto its rect on the screen.
      game.outputs.primitives << {
        x: x,
        y: y,
        w: w,
        h: h,
        path: @output_key
      }
    end

    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} name: #{name}, x: #{x}, y: #{y}, w: #{w}, h: #{h}, current-x: #{current&.x}, current-y: #{current&.y}, current-zoom: #{current&.zoom}, speed: #{speed}, zoom_speed: #{zoom_speed}>"
    end

    class FocalPoint < Node
      attr_accessor :x, :y, :zoom, :camera

      def initialize(camera, **attributes)
        super(camera: camera, **attributes)
      end

      # Clamp the focal point so the view stays within the scene's virtual
      # bounds. When the scene is unbounded (virtual_w is nil), pan freely.
      def x=(value)
        bound = camera && camera.scene && camera.scene.virtual_w

        if bound
          half = camera.w / 2 / (zoom || 1)
          @x = half <= bound - half ? value.clamp(half, bound - half) : bound / 2
        else
          @x = value
        end
      end

      def y=(value)
        bound = camera && camera.scene && camera.scene.virtual_h

        if bound
          half = camera.h / 2 / (zoom || 1)
          @y = half <= bound - half ? value.clamp(half, bound - half) : bound / 2
        else
          @y = value
        end
      end

      def zoom=(value)
        @zoom = value.clamp(0.1, 10)

        # x=/y= clamp against zoom-dependent bounds, so re-run them to pull the view
        # back in after zooming out. Guarded: zoom= can fire before x/y are set.
        self.x = @x unless @x.nil?
        self.y = @y unless @y.nil?
      end
    end
  end
end
