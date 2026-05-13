module Sketchup
  class Layer
    attr_reader :handle, :name

    def initialize(handle, name)
      @handle = handle
      @name   = name.to_s
    end

    def to_s;    "Layer(#{@name})"; end
    def inspect; "#<Sketchup::Layer name=#{@name.inspect}>"; end
  end

  class Layers
    include Enumerable

    def initialize(model_handle)
      @model_handle = model_handle
      @layers = {}
    end

    def add(name)
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SULayerCreate(out), 'SULayerCreate'
      h = SUAPI.rh(out)
      SUAPI.SULayerSetName(h, name.to_s)
      SUAPI.SUModelAddLayers(@model_handle, 1, SUAPI.h1(h))
      layer = Layer.new(h, name)
      @layers[name.to_s] = layer
      layer
    end

    def [](name);  @layers[name.to_s]; end
    def each(&b);  @layers.each_value(&b); end
    def count;     @layers.size; end
    def to_a;      @layers.values; end
  end
end
