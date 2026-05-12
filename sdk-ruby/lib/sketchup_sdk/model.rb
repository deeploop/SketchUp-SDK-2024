module Sketchup
  # Mirrors Sketchup::Model from the official Ruby API.
  #
  #   model = Sketchup::Model.new("MyBuilding", "description")
  #   face  = model.entities.add_face(...)
  #   model.save("output.skp")
  #   model.close
  #
  #   # Read back an existing file and verify:
  #   model = Sketchup::Model.open("output.skp")
  #   p model.statistics   # => { faces: 8, layers: 4, materials: 4, ... }
  #   model.close
  class Model
    attr_reader :native_ptr

    # ── Constructors ──────────────────────────────────────────────────────

    def initialize(name = nil, description = nil)
      @native_ptr = SketchUpBridge.model_create
      raise "SketchUp SDK: failed to create model" if @native_ptr.nil? || @native_ptr.null?

      SketchUpBridge.model_set_name(@native_ptr, name.to_s)               if name
      SketchUpBridge.model_set_description(@native_ptr, description.to_s) if description

      init_collections
    end

    # Opens an existing .skp file for reading / verification.
    def self.open(path)
      instance = allocate
      instance.send(:initialize_from_file, path)
      instance
    end

    # ── Collections ───────────────────────────────────────────────────────

    def entities;  @entities_obj;  end   # Mirrors model.entities
    def layers;    @layers_col;    end   # Mirrors model.layers (Tags)
    def materials; @materials_col; end   # Mirrors model.materials

    # ── Persistence ───────────────────────────────────────────────────────

    # Saves the model to disk. Returns true on success.
    def save(path)
      SketchUpBridge.model_save(@native_ptr, path.to_s) == 0
    end

    # Releases the underlying SDK object. Call when done.
    def close
      return unless @native_ptr
      SketchUpBridge.model_release(@native_ptr)
      @native_ptr = nil
    end

    # ── Verification ──────────────────────────────────────────────────────

    # Returns a Hash of entity counts read directly from the saved model.
    # Index order matches SUModelStatistics::SUEntityType.
    #
    #   model.statistics
    #   # => { edges: 24, faces: 8, component_instances: 0, groups: 0,
    #   #      images: 0, component_definitions: 0, layers: 4, materials: 4 }
    def statistics
      buf = FFI::MemoryPointer.new(:int, 8)
      SketchUpBridge.model_get_stats(@native_ptr, buf)
      counts = buf.read_array_of_int(8)
      {
        edges:                 counts[0],
        faces:                 counts[1],
        component_instances:   counts[2],
        groups:                counts[3],
        images:                counts[4],
        component_definitions: counts[5],
        layers:                counts[6],
        materials:             counts[7]
      }
    end

    def to_s;    "Sketchup::Model"; end
    def inspect; "#<Sketchup::Model ptr=0x#{@native_ptr&.address.to_s(16)}>"; end

    private

    def init_collections
      @layers_col    = Layers.new(@native_ptr)
      @materials_col = Materials.new(@native_ptr)
      @entities_obj  = Entities.new(SketchUpBridge.model_get_entities(@native_ptr))
    end

    def initialize_from_file(path)
      @native_ptr = SketchUpBridge.model_open(path.to_s)
      raise "SketchUp SDK: failed to open '#{path}'" if @native_ptr.nil? || @native_ptr.null?
      init_collections
    end
  end
end
