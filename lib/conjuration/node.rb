class Node
  attr_accessor :setup_at

  def initialize(**attributes)
    merge!(**attributes)
  end

  def perform(phase)
    return if respond_to?("perform_#{phase}?") && !send("perform_#{phase}?")

    send("perform_#{phase}") if respond_to?("perform_#{phase}")
    send(phase) if respond_to?(phase)

    send("#{phase}_at=", Kernel.tick_count) if respond_to?("#{phase}_at=")
  end

  def perform_setup?
    setup_at.nil?
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

  class << self
    def delegate(*method_names, to:)
      method_names.each do |name|
        define_method(name) do
          send(to).send(name)
        end
      end
    end
  end
end
