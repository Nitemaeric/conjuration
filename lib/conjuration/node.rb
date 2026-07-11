module Conjuration
  # Base class for UI nodes and game entities. Provides convenient attribute
  # initialization, delegation to game, and rect building.
  #
  # @see Conjuration::UI::Node
  class Node
    class << self
      # Define a set of methods that delegate to another object.
      #
      # Creates instance methods that forward to a receiver method on the same object,
      # passing all arguments and blocks through. Handles empty kwargs correctly for
      # mruby compatibility.
      #
      # @param method_names [Array<Symbol>] method names to delegate
      # @param to [Symbol] name of the accessor method that returns the receiver object
      # @example
      #   class Character < Node
      #     delegate :inputs, :grid, to: :game
      #   end
      def delegate(*method_names, to:)
        method_names.each do |name|
          define_method(name) do |*args, **kwargs, &block|
            # Splatting an empty **kwargs makes this mruby build forward a stray `{}`
            # positional, breaking zero-arg delegates — so only splat when keywords exist.
            if kwargs.empty?
              send(to).send(name, *args, &block)
            else
              send(to).send(name, *args, **kwargs, &block)
            end
          end
        end
      end
    end

    # Delegates to common game interfaces
    delegate :inputs, :grid, :gtk, :events, :debug?, to: :game

    # Initialize a node with attribute assignments.
    #
    # @param attributes [Hash] key-value pairs to assign (via writers or ivars)
    def initialize(**attributes)
      merge!(**attributes)
    end

    # Merge attribute assignments into the node. Resolves each key to either
    # a writer method or an instance variable, raising an error if neither exists.
    #
    # @param attributes [Hash] key-value pairs to assign
    # @return [Node] self
    # @raise [ArgumentError] if an attribute has no writer or ivar
    # @example
    #   character.merge!(x: 100, y: 50, moving: true)
    def merge!(**attributes)
      attributes.each do |key, value|
        if respond_to?("#{key}=")
          send("#{key}=", value)
        elsif instance_variable_defined?("@#{key}")
          instance_variable_set("@#{key}", value)
        else
          raise ArgumentError, "#{self.class} has no attribute #{key.inspect} (define a #{key}= writer or initialize @#{key})"
        end
      end
    end

    # Access the game instance ($game).
    #
    # @return [Game] the global game instance
    # @note This is a convenience for accessing $game; it is not set on the node itself.
    def game
      $game
    end

    # Build a rect hash with position and size, optionally including anchors.
    #
    # Returns a hash with x, y, w, h, and conditionally anchor_x and anchor_y
    # if those methods exist on the node.
    #
    # @return [Hash{Symbol => Numeric}] rect with {x, y, w, h} + optional anchors
    def rect
      { x: x, y: y, w: w, h: h }.tap do |rect|
        rect[:anchor_x] = anchor_x if respond_to?(:anchor_x)
        rect[:anchor_y] = anchor_y if respond_to?(:anchor_y)
      end
    end
  end
end
