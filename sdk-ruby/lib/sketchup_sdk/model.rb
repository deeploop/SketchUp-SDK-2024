module Sketchup
  class Model
    attr_reader :handle

    def initialize(name = nil, description = nil)
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUModelCreate(out), 'SUModelCreate'
      @handle = SUAPI.rh(out)
      SUAPI.SUModelSetName(@handle, name.to_s)               if name
      SUAPI.SUModelSetDescription(@handle, description.to_s) if description
      init_collections
    end

    def self.open(path)
      inst = allocate
      inst.send(:init_from_file, path)
      inst
    end

    def entities;              @entities_obj;   end
    def layers;                @layers_col;     end
    def materials;             @materials_col;  end
    def component_definitions; @comp_defs;      end

    def save(path)
      SUAPI.SUModelSaveToFile(@handle, path.to_s) == SUAPI::SU_ERROR_NONE
    end

    def close
      return if !@handle || @handle == 0
      SUAPI.SUModelRelease(SUAPI.h1(@handle))
      @handle = 0
    end

    def statistics
      buf = FFI::MemoryPointer.new(:int, 8)
      SUAPI.SUModelGetStatistics(@handle, buf)
      c = buf.read_array_of_int(8)
      {
        edges:                 c[0],
        faces:                 c[1],
        component_instances:   c[2],
        groups:                c[3],
        images:                c[4],
        component_definitions: c[5],
        layers:                c[6],
        materials:             c[7]
      }
    end

    def to_s;    'Sketchup::Model'; end
    def inspect; "#<Sketchup::Model handle=0x#{@handle.to_s(16)}>"; end

    private

    def init_collections
      ents_out = SUAPI.out_h
      SUAPI.check! SUAPI.SUModelGetEntities(@handle, ents_out), 'SUModelGetEntities'
      @entities_obj  = Entities.new(SUAPI.rh(ents_out))
      @layers_col    = Layers.new(@handle)
      @materials_col = Materials.new(@handle)
      @comp_defs     = ComponentDefinitions.new(@handle)
    end

    def init_from_file(path)
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUModelCreateFromFile(out, path.to_s), 'SUModelCreateFromFile'
      @handle = SUAPI.rh(out)
      init_collections
    end
  end
end
