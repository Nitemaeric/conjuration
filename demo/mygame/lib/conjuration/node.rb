module Conjuration
  class Node
    def initialize(**attributes)
      merge!(**attributes)
    end

    def merge!(**attributes)
      attributes.each do |key, value|
        if respond_to?("#{key}=")
          send("#{key}=", value)
        elsif instance_variable_defined?("@#{key}")
          instance_variable_set("@#{key}", value)
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

    class << self
      def delegate(*method_names, to:)
        method_names.each do |name|
          define_method(name) do |*args|
            send(to).send(name, *args)
          end
        end
      end
    end
  end
end
