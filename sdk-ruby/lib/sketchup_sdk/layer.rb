module Sketchup
  # Mirrors Sketchup::Layer from the official Ruby API.
  # Instances are returned by Sketchup::Layers#add — do not instantiate directly.
  class Layer
    attr_reader :native_ptr, :name

    def initialize(ptr, name)
      @native_ptr = ptr
      @name       = name.to_s
    end

    def to_s;    "Layer(#{@name})"; end
    def inspect; "#<Sketchup::Layer name=#{@name.inspect}>"; end
  end

  # Collection returned by Model#layers.
  class Layers
    include Enumerable

    def initialize(model_ptr)
      @model_ptr = model_ptr
      @layers    = {}
    end

    # Adds and returns a new Layer (Tag). Mirrors Model.layers.add(name).
    def add(name)
      ptr = SketchUpBridge.model_add_layer(@model_ptr, name.to_s)
      raise "Failed to create layer '#{name}'" if ptr.nil? || ptr.null?
      layer = Layer.new(ptr, name)
      @layers[name.to_s] = layer
      layer
    end

    def [](name);  @layers[name.to_s]; end
    def each(&b);  @layers.each_value(&b); end
    def count;     @layers.size; end
    def to_a;      @layers.values; end
  end
end
