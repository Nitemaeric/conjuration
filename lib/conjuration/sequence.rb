module Conjuration
  # A scripted-events primitive — the cutscene backbone. A Sequence is an ordered
  # queue of steps ticked once per frame against the OWNING scene's clock, so a
  # pause, hit stop, or stacked scene freezes the whole performance and resumes
  # mid-step for free (the same clock discipline the Scheduler follows).
  #
  # Coroutine-free by design: mruby fibers are unreliable, so `play_sequence`
  # does NOT suspend a running block. The block runs ONCE up front as a builder,
  # each DSL call (act/wait/animate/parallel/wait_confirm/…) appending a step;
  # the queue then advances a step at a time. `animate` records its motion and
  # kicks the real Scheduler tween only when its step becomes current.
  #
  # Lifecycle: transient like schedules — a Sequence lives on the scene INSTANCE,
  # never in save state (docs/design/scene-lifecycle.md §17), and dies with the
  # scene. A mid-play sequence is not serialized; re-entering a scene starts with
  # none.
  #
  # Zero-cost when unused: a scene that never calls `play_sequence` allocates no
  # Sequence and its tick site is a single nil check.
  #
  # One active sequence per scene (v1): `play_sequence` cancels any in flight and
  # replaces it. A cutscene is one linear performance, so concurrency lives
  # WITHIN a sequence (`parallel`), not across sequences. Input-locking during a
  # sequence is the scene's choice, not enforced here — gate the scene's own
  # `input` on `sequence_playing?`.
  class Sequence
    def initialize
      @steps = []
      @index = 0
      @entered = false
      @cancelled = false
      # Build-time target stack: DSL appends land on the top frame, so `parallel`
      # can redirect its body into a sub-group and pop back.
      @targets = [@steps]
    end

    # Run the builder block once (self is the scene, so its own methods and ivars
    # resolve) and leave the queue ready to tick. `building?` is true only for the
    # block's duration.
    def build(scene, &block)
      @building = true
      scene.instance_exec(&block) if block
      self
    ensure
      @building = false
    end

    def building?
      @building
    end

    def append(step)
      @targets.last << step
      step
    end

    def push_target(steps)
      @targets.push(steps)
    end

    def pop_target
      @targets.pop
    end

    # Advance the current step, entering it once and rolling forward through every
    # step that also completes this same frame — so a run of synchronous `act`s
    # resolves in one tick rather than one per frame. A step that isn't done yet
    # breaks the loop and holds until a later tick.
    def tick(clock, scene)
      return if @cancelled

      loop do
        step = @steps[@index]
        return if step.nil?

        unless @entered
          @entered = true
          step.enter(clock, scene)
        end

        break unless step.done?(clock, scene)

        @index += 1
        @entered = false
      end
    end

    def cancel
      @cancelled = true
    end

    def cancelled?
      @cancelled
    end

    # Ran to its natural end (every step consumed), as opposed to cancelled.
    def completed?
      !@cancelled && @index >= @steps.length
    end

    # No longer playing, for EITHER reason — completed or cancelled. This is the
    # terminal check the tick site uses; `completed?`/`cancelled?` say which.
    def done?
      @cancelled || completed?
    end

    # Runs its block once on entry, completes the same frame. Chains synchronous
    # scene-state changes (portrait swaps, dialogue lines, change_scene).
    class Act
      def initialize(block)
        @block = block
      end

      def enter(_clock, _scene)
        @block.call
      end

      def done?(_clock, _scene)
        true
      end
    end

    # Holds for `ticks` scene-clock ticks. Records the entry clock so a frozen
    # clock simply never reaches the boundary — no catch-up on resume.
    class Wait
      def initialize(ticks)
        @ticks = ticks
      end

      def enter(clock, _scene)
        @started_at = clock
      end

      def done?(clock, _scene)
        clock - @started_at >= @ticks
      end
    end

    # Completes when a predicate first reads true. Not evaluated until the tick
    # after entry, so entry-frame state never satisfies it prematurely.
    class WaitUntil
      def initialize(predicate)
        @predicate = predicate
      end

      def enter(clock, _scene)
        @entered_at = clock
      end

      def done?(clock, _scene)
        clock > @entered_at && @predicate.call
      end
    end

    # Kicks the scene's real tween on entry and blocks for `over` ticks, so the
    # sequence waits for the motion to land. Empty attrs never splat (mruby
    # forwards a stray {} for `**{}`).
    class Animate
      def initialize(target, attrs, over, ease)
        @target = target
        @attrs = attrs
        @over = over
        @ease = ease
      end

      def enter(clock, scene)
        @started_at = clock
        scene.tween(@target, over: @over, ease: @ease, **@attrs) unless @attrs.empty?
      end

      def done?(clock, _scene)
        clock - @started_at >= @over
      end
    end

    # Enters every sub-step at once (kicking all their tweens on the same frame)
    # and completes only when all of them do — simultaneous character moves.
    class Parallel
      attr_reader :steps

      def initialize
        @steps = []
      end

      def enter(clock, scene)
        @steps.each { |step| step.enter(clock, scene) }
      end

      def done?(clock, scene)
        @steps.all? { |step| step.done?(clock, scene) }
      end
    end
  end

  # The scene-facing DSL. Included into Scene; every step keys to the host's own
  # #clock, and the Sequence is allocated only on `play_sequence`.
  module Sequencing
    # Build and start a sequence, cancelling any already in flight. The block runs
    # once as a builder (see Sequence); returns the Sequence as a cancel handle.
    def play_sequence(&block)
      stop_sequence
      @sequence = Sequence.new
      @sequence.build(self, &block)
      @sequence
    end

    def stop_sequence
      @sequence&.cancel
      @sequence = nil
    end

    def sequence_playing?
      !@sequence.nil? && !@sequence.done?
    end

    # --- builder DSL (only meaningful inside a play_sequence block) ---

    def act(&block)
      building_sequence.append(Sequence::Act.new(block))
    end

    def wait(ticks)
      building_sequence.append(Sequence::Wait.new(ticks))
    end

    def wait_until(&predicate)
      building_sequence.append(Sequence::WaitUntil.new(predicate))
    end

    # Advance on the confirm edge OR a mouse/touch click, mirroring the menu's
    # tappable Press-Start prompt (#49) so touch-only players are never stranded
    # mid-cutscene. Confirm resolution goes through the framework's input seam.
    def wait_confirm
      scene = self
      building_sequence.append(Sequence::WaitUntil.new(-> { scene.sequence_confirm? }))
    end
    alias wait_input wait_confirm

    def animate(target, attrs, over:, ease: :identity)
      building_sequence.append(Sequence::Animate.new(target, attrs, over, ease))
    end

    def parallel(&block)
      group = Sequence::Parallel.new
      building_sequence.append(group)
      @sequence.push_target(group.steps)
      block.call
      @sequence.pop_target
      group
    end

    # The confirm predicate wait_confirm reads. Public so custom predicates can
    # reuse it; override in a scene to change what "advance" means.
    def sequence_confirm?
      source = game.input_source
      confirmed = source.just_pressed?(game.ui_pad, :ui_confirm)
      mouse = inputs.mouse
      confirmed || (mouse && mouse.click ? true : false)
    end

    private

    def building_sequence
      raise "sequence DSL called outside play_sequence" unless @sequence&.building?

      @sequence
    end

    def tick_sequence
      return if @sequence.nil?

      @sequence.tick(clock, self)
      @sequence = nil if @sequence.done?
    end
  end
end
