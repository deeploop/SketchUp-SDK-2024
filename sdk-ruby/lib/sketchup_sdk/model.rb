module Sketchup
  # Mirrors Sketchup::Model from the official Ruby API.
  #
  #   model = Sketchup::Model.new("MyBuilding", "description")
  #   face  = model.entities.add_face(...)
  #   model.save("output.skp")
  #   model.close
  class Model
    attr_reader :native_ptr

    def initialize(name = nil, description = nil)
      @native_ptr = SketchUpBridge.model_create
      raise "SketchUp SDK: failed to create model" if @native_ptr.nil? || @native_ptr.null?

      SketchUpBridge.model_set_name(@native_ptr, name.to_s)             if name
      SketchUpBridge.model_set_description(@native_ptr, description.to_s) if description

      @layers_col    = Layers.new(@native_ptr)
      @materials_col = Materials.new(@native_ptr)
      @entities_obj  = Entities.new(SketchUpBridge.model_get_entities(@native_ptr))
    end

    # Mirrors model.entities
    def entities; @entities_obj; end

    # Mirrors model.layers  (Tags in newer SketchUp)
    def layers;   @layers_col;   end

    # Mirrors model.materials
    def materials; @materials_col; end

    # Saves the model to disk. Returns true on success.
    # Mirrors model.save(path)
    def save(path)
      result = SketchUpBridge.model_save(@native_ptr, path.to_s)
      result == 0
    end

    # Releases the underlying SDK object. Call when done.
    def close
      return unless @native_ptr
      SketchUpBridge.model_release(@native_ptr)
      @native_ptr = nil
    end

    def to_s;    "Sketchup::Model"; end
    def inspect; "#<Sketchup::Model ptr=0x#{@native_ptr&.address.to_s(16)}>"; end
  end
end
