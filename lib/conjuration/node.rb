module Conjuration
  class Node
    class << self
      def delegate(*method_names, to:)
        method_names.each do |name|
          define_method(name) do |*args, **kwargs, &block|
            # Splat an empty **kwargs and this mruby build forwards a stray `{}`
            # positional, breaking zero-arg delegates like gtk — so only splat
            # when there are keywords.
            if kwargs.empty?
              send(to).send(name, *args, &block)
            else
              send(to).send(name, *args, **kwargs, &block)
            end
          end
        end
      end
    end

    delegate :inputs, :grid, :gtk, :events, :debug?, to: :game

    def initialize(**attributes)
      merge!(**attributes)
    end

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

    def game
      $game
    end

    def rect
      { x: x, y: y, w: w, h: h }.tap do |rect|
        rect[:anchor_x] = anchor_x if respond_to?(:anchor_x)
        rect[:anchor_y] = anchor_y if respond_to?(:anchor_y)
      end
    end
  end
end
