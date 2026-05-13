module Sketchup
  class Material
    attr_reader :name

    def initialize(model_handle, name)
      @model_handle = model_handle
      @name         = name.to_s
      @color        = Color.new(200, 200, 200)
      @alpha        = 1.0
      @handle       = nil
    end

    # Lazy: committed to the SDK model on first use.
    def handle
      @handle ||= commit!
    end

    def color=(c)
      @color = c
      SUAPI.SUMaterialSetColor(@handle, color_buf) if @handle
    end

    def color; @color; end

    def alpha=(a)
      @alpha = a.to_f.clamp(0.0, 1.0)
      if @handle
        SUAPI.SUMaterialSetOpacity(@handle, @alpha)
        SUAPI.SUMaterialSetUseOpacity(@handle, 1)
      end
    end

    def alpha; @alpha; end

    def to_s;    "Material(#{@name})"; end
    def inspect; "#<Sketchup::Material name=#{@name.inspect} color=#{@color}>"; end

    private

    def commit!
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUMaterialCreate(out), 'SUMaterialCreate'
      h = SUAPI.rh(out)
      SUAPI.SUMaterialSetName(h, @name)
      SUAPI.SUMaterialSetColor(h, color_buf)
      SUAPI.SUModelAddMaterials(@model_handle, 1, SUAPI.h1(h))
      h
    end

    def color_buf
      buf = FFI::MemoryPointer.new(:uint8, 4)
      buf.put_bytes(0, [@color.red, @color.green, @color.blue, @color.alpha].pack('C4'))
      buf
    end
  end

  class Materials
    include Enumerable

    def initialize(model_handle)
      @model_handle = model_handle
      @materials = {}
    end

    def add(name)
      mat = Material.new(@model_handle, name.to_s)
      @materials[name.to_s] = mat
      mat
    end

    def [](name);  @materials[name.to_s]; end
    def each(&b);  @materials.each_value(&b); end
    def count;     @materials.size; end
    def to_a;      @materials.values; end
  end
end
