module Sketchup
  # Mirrors Sketchup::Material from the official Ruby API.
  # Color is set before the material is committed to the SDK model, so the
  # typical pattern:
  #   mat = model.materials.add("Stucco")
  #   mat.color = Sketchup::Color.new(235, 228, 212)
  # works correctly with lazy initialisation.
  class Material
    attr_reader :name

    def initialize(model_ptr, name)
      @model_ptr  = model_ptr
      @name       = name.to_s
      @color      = Color.new(200, 200, 200)
      @alpha      = 1.0
      @native_ptr = nil
    end

    # Setting color before first use is the recommended workflow.
    # Setting it after first use updates the already-committed material.
    def color=(c)
      @color = c
      if @native_ptr
        SketchUpBridge.material_set_color(@native_ptr,
                                          c.red.to_i, c.green.to_i, c.blue.to_i)
      end
    end

    def color; @color; end

    def alpha=(a)
      @alpha = a.to_f.clamp(0.0, 1.0)
      SketchUpBridge.material_set_opacity(@native_ptr, @alpha) if @native_ptr
    end

    def alpha; @alpha; end

    # Returns the raw SDK pointer, committing the material on first call.
    def native_ptr
      @native_ptr ||= begin
        ptr = SketchUpBridge.model_add_material(
          @model_ptr, @name,
          @color.red.to_i, @color.green.to_i, @color.blue.to_i
        )
        raise "Failed to create material '#{@name}'" if ptr.nil? || ptr.null?
        ptr
      end
    end

    def to_s;    "Material(#{@name}, #{@color})"; end
    def inspect; "#<Sketchup::Material name=#{@name.inspect} color=#{@color}>"; end
  end

  # Collection returned by Model#materials.
  class Materials
    include Enumerable

    def initialize(model_ptr)
      @model_ptr = model_ptr
      @materials = {}
    end

    # Creates and returns a new Material. Mirrors model.materials.add(name).
    def add(name)
      mat = Material.new(@model_ptr, name.to_s)
      @materials[name.to_s] = mat
      mat
    end

    def [](name);  @materials[name.to_s]; end
    def each(&b);  @materials.each_value(&b); end
    def count;     @materials.size; end
    def to_a;      @materials.values; end
  end
end
