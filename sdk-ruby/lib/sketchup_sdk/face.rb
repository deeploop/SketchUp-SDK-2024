module Sketchup
  class Face
    attr_reader :handle

    def initialize(handle)
      @handle = handle
    end

    def material=(mat)
      SUAPI.SUFaceSetFrontMaterial(@handle, mat.handle)
    end

    def back_material=(mat)
      SUAPI.SUFaceSetBackMaterial(@handle, mat.handle)
    end

    def layer=(layer)
      elem_h = SUAPI.SUFaceToDrawingElement(@handle)
      SUAPI.SUDrawingElementSetLayer(elem_h, layer.handle)
    end

    def to_s;    "Face(0x#{@handle.to_s(16)})"; end
    def inspect; "#<Sketchup::Face handle=0x#{@handle.to_s(16)}>"; end
  end
end
