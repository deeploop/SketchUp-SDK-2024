module Sketchup
  # Mirrors Sketchup::Face from the official Ruby API.
  # Returned by Entities#add_face — do not instantiate directly.
  class Face
    attr_reader :native_ptr

    def initialize(ptr)
      @native_ptr = ptr
    end

    # Assigns a material to the front (outward-facing) side.
    # Mirrors: face.material = material
    def material=(mat)
      SketchUpBridge.face_set_front_material(@native_ptr, mat.native_ptr)
    end

    # Assigns a material to the back (inward-facing) side.
    def back_material=(mat)
      SketchUpBridge.face_set_back_material(@native_ptr, mat.native_ptr)
    end

    # Assigns a layer (Tag) to this face.
    # Mirrors: face.layer = layer
    def layer=(layer)
      SketchUpBridge.face_set_layer(@native_ptr, layer.native_ptr)
    end

    def to_s;    "Face(0x#{@native_ptr.address.to_s(16)})"; end
    def inspect; "#<Sketchup::Face ptr=0x#{@native_ptr.address.to_s(16)}>"; end
  end
end
