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

    # Half-extent (px) of a debug focal crosshair, held constant across zoom.
    DEBUG_MARKER_RADIUS = 6

    def initialize(scene, name:, x: 0, y: 0, w: grid.w, h: grid.h, current: { x: grid.w / 2, y: grid.h / 2, zoom: 1 }, speed: SNAP, zoom_speed: 0.1)
      super(scene: scene, name: name, x: x, y: y, w: w, h: h, speed: speed, zoom_speed: zoom_speed)

      # Namespace by scene instance: two stacked scenes that both add a `:main`
      # camera would otherwise share (and corrupt) one global render target.
      @output_key = "camera_#{scene.uid}_#{name}"

      @current = FocalPoint.new(self, **current)
      @target = FocalPoint.new(self, **current)

      # Per-frame buffer of deferred, z-ordered draws: [z, emission_index,
      # primitive]. Empty (and untouched) unless a draw passes `z:`, so the
      # default draw path allocates nothing here.
      @draw_buffer = []
    end

    # The indicator toggle is scene-scoped; camera HUDs follow their scene.
    def focus_indicator_enabled?
      return super unless scene.respond_to?(:focus_indicator_enabled?)

      scene.focus_indicator_enabled?
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
    def view_rect(parallax: 1.0)
      return (@view_rect ||= compute_view_rect(1.0)) if parallax == 1.0

      (@parallax_view_rects ||= {})[parallax] ||= compute_view_rect(parallax)
    end

    # Whether a world-space rect overlaps the current view at all. Hand-rolled
    # AABB test with bracket access: this runs per object per camera per frame,
    # so it avoids method_missing and Geometry-call overhead.
    def visible?(world_rect, parallax = 1.0)
      view = parallax == 1.0 ? view_rect : view_rect(parallax: parallax)
      rw = world_rect[:w] || 0
      rh = world_rect[:h] || 0

      # DR renders anchored sprites offset by anchor * extent, so the visual
      # bounds differ from the x/y/w/h rect; cull against what will be drawn.
      ax = world_rect[:anchor_x]
      ay = world_rect[:anchor_y]
      left   = ax ? world_rect[:x] - ax * rw : world_rect[:x]
      bottom = ay ? world_rect[:y] - ay * rh : world_rect[:y]

      left        < view[:x] + view[:w] &&
        left + rw > view[:x] &&
        bottom        < view[:y] + view[:h] &&
        bottom + rh > view[:y]
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

    # Serialise this frame's deferred draw buffer in post-sort flush order — the
    # draw-order inspector (roadmap H3, promoted from the isometric demo's ad-hoc
    # forensics). Debug-only by convention, but callable anytime; nothing is kept
    # between calls, so a game that never dumps pays nothing.
    #
    # Each primitive line carries its flush index, z band, emission index,
    # viewport rect (x/y/w/h), anchors, path, and an optional caller tag. The tag
    # is the DEBUG-TAG CONVENTION: set a `dbg:` key on any primitive handed to
    # #draw and it rides through unchanged into the dump. It costs nothing on the
    # render path — #to_viewport dups the source hash, so an absent `dbg:` is
    # never present, and DragonRuby's renderer reads only the keys it knows and
    # ignores the rest, so a present one is a free passenger.
    #
    # `io_or_path`: an IO-ish sink (anything responding to `<<` — a StringIO, an
    # array) receives the text; a String path (or nil, defaulting to a per-camera
    # filename) routes through `gtk.write_file` into DR's sandboxed write root.
    # The full text is always returned, so a harness with no file sandbox can just
    # capture it.
    def dump_draw_order(io_or_path = nil)
      view = view_rect

      lines = []
      lines << "# conjuration draw-order dump v1 (viewport space, y-up; rect = [x - ax*w, y - ay*h, w, h])"
      lines << "camera name=#{name} x=#{current.x} y=#{current.y} zoom=#{current.zoom} w=#{w} h=#{h}"
      lines << "view x=#{view[:x]} y=#{view[:y]} w=#{view[:w]} h=#{view[:h]}"

      idx = 0
      each_ordered_draw do |z, em, prim|
        lines << "prim idx=#{idx} z=#{z} em=#{em} x=#{prim[:x]} y=#{prim[:y]} w=#{prim[:w]} h=#{prim[:h]} ax=#{prim[:anchor_x]} ay=#{prim[:anchor_y]} path=#{prim[:path]} tag=#{prim[:dbg]}"
        idx += 1
      end

      text = lines.join("\n") + "\n"

      if io_or_path.respond_to?(:<<) && !io_or_path.is_a?(String)
        io_or_path << text
      else
        gtk.write_file(io_or_path || "draw_order_#{name}.txt", text)
      end

      text
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

    # Emit the deferred draws in composite order, then clear the buffer for the
    # next frame. The ordering itself lives in #each_ordered_draw, shared with the
    # debug dump so the two can never drift.
    def flush_ordered_draws
      return if @draw_buffer.empty?

      each_ordered_draw { |_z, _em, primitive| outputs.primitives << primitive }
      @draw_buffer.clear
    end

    # World-space introspection drawn into the camera's own viewport: the cull
    # frame, focal current/target (with a link when they differ), the follow
    # target, and the scene's world bounds, plus a corner text readout. World
    # elements route through #to_viewport, so they track pan and zoom exactly as
    # scene content does. Guarded here as well as at the call site so it builds
    # nothing when debug is off — the whole overlay is a no-op then.
    def render_debug_overlay
      return unless debug?

      outputs.debug << debug_view_rect_outline
      debug_focal_markers.each { |primitive| outputs.debug << primitive }
      outputs.debug << debug_follow_marker if following
      outputs.debug << debug_world_bounds if scene.virtual_w && scene.virtual_h
      debug_readout_labels.each { |label| outputs.debug << label }
    end

    def debug_view_rect_outline
      { **to_viewport(view_rect), r: 255, g: 255, b: 0, primitive_marker: :border }
    end

    def debug_focal_markers
      markers = debug_crosshair(current.x, current.y, 0, 255, 255)
      debug_crosshair(target.x, target.y, 255, 160, 0).each { |marker| markers << marker }

      if target.x != current.x || target.y != current.y
        from = to_viewport({ x: current.x, y: current.y })
        to = to_viewport({ x: target.x, y: target.y })
        markers << { x: from[:x], y: from[:y], x2: to[:x], y2: to[:y], r: 255, g: 255, b: 255, primitive_marker: :line }
      end

      markers
    end

    def debug_follow_marker
      point = to_viewport({ x: following.x, y: following.y })
      radius = DEBUG_MARKER_RADIUS * 2

      { x: point[:x] - radius, y: point[:y] - radius, w: radius * 2, h: radius * 2, r: 80, g: 160, b: 255, primitive_marker: :border }
    end

    def debug_world_bounds
      { **to_viewport({ x: 0, y: 0, w: scene.virtual_w, h: scene.virtual_h }), r: 255, g: 140, b: 0, primitive_marker: :border }
    end

    # Bottom-left of the viewport, on a translucent backing — the top-left corner
    # belongs to the game debug panel, which draws later and would bury these.
    def debug_readout_labels
      zoom = (current.zoom * 100).round / 100.0
      lines = [
        name.to_s,
        "x #{current.x.round} y #{current.y.round} z #{zoom}",
        following ? "follow on" : "follow off"
      ]

      widest = lines.map { |text| gtk.calcstringbox(text)[0] }.max
      labels = [{ x: from_left(2), y: from_bottom(2), w: widest + 8, h: lines.length * 16 + 6, path: :pixel, r: 0, g: 0, b: 0, a: 190 }]
      lines.each_with_index do |text, index|
        labels << { x: from_left(6), y: from_bottom(6) + (lines.length - 1 - index) * 16, text: text, size_px: 14, r: 255, g: 255, b: 0, anchor_y: 0 }
      end
      labels
    end

    # Two viewport-space lines centred on a world point, drawn at a fixed pixel
    # size (position transformed, extent not) so a marker stays legible at any zoom.
    def debug_crosshair(world_x, world_y, red, green, blue)
      point = to_viewport({ x: world_x, y: world_y })
      cx = point[:x]
      cy = point[:y]

      [
        { x: cx - DEBUG_MARKER_RADIUS, y: cy, x2: cx + DEBUG_MARKER_RADIUS, y2: cy, r: red, g: green, b: blue, primitive_marker: :line },
        { x: cx, y: cy - DEBUG_MARKER_RADIUS, x2: cx, y2: cy + DEBUG_MARKER_RADIUS, r: red, g: green, b: blue, primitive_marker: :line }
      ]
    end

    # Sort the deferred buffer into final composite order and yield each entry
    # [z, emission_index, primitive]. THE single source of draw-order truth: the
    # render flush and #dump_draw_order both go through here, so a dump reports
    # exactly what DragonRuby composites. Sorting on the emission index as the
    # tie-breaker makes equal-z order deterministic (call order) regardless of
    # whether the underlying sort is stable — mruby's is not — so equal-z
    # primitives never flicker. The explicit comparator avoids the per-comparison
    # array alloc a `[z, index] <=>` key would cost on this per-frame path. Sorts
    # in place; idempotent, so a dump before the flush leaves the flush correct.
    def each_ordered_draw
      @draw_buffer.sort! { |a, b| a[0] == b[0] ? a[1] <=> b[1] : a[0] <=> b[0] }
      @draw_buffer.each { |entry| yield(entry[0], entry[1], entry[2]) }
    end

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

      # Camera HUD, into this camera's own viewport target.
      render_ui(outputs)

      render_debug_overlay if debug?

      # Blit the camera's viewport onto its rect on the screen. Through
      # render_output so a transition snapshot captures the composed frame.
      game.render_output.primitives << {
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
