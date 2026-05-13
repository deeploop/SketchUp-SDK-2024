module Sketchup
  class Group
    attr_reader :handle

    def initialize(handle)
      @handle = handle
    end

    def entities
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUGroupGetEntities(@handle, out), 'SUGroupGetEntities'
      Entities.new(SUAPI.rh(out))
    end

    def name=(n)
      SUAPI.check! SUAPI.SUGroupSetName(@handle, n.to_s), 'SUGroupSetName'
    end

    def layer=(layer_obj)
      de = SUAPI.SUGroupToDrawingElement(@handle)
      SUAPI.check! SUAPI.SUDrawingElementSetLayer(de, layer_obj.handle), 'SUDrawingElementSetLayer (group)'
    end

    def entity_handle
      SUAPI.SUGroupToEntity(@handle)
    end

    # Write into any named attribute dictionary on this group entity.
    def set_attribute(dict_name, key, value)
      dict_out = SUAPI.out_h
      SUAPI.check! SUAPI.SUEntityGetAttributeDictionary(entity_handle, dict_name.to_s, dict_out),
                   'SUEntityGetAttributeDictionary (group)'
      dict_h = SUAPI.rh(dict_out)

      tv_out = SUAPI.out_h
      SUAPI.check! SUAPI.SUTypedValueCreate(tv_out), 'SUTypedValueCreate (group)'
      tv_h = SUAPI.rh(tv_out)

      case value
      when Integer then SUAPI.SUTypedValueSetInt32(tv_h, value)
      when Float   then SUAPI.SUTypedValueSetDouble(tv_h, value)
      else              SUAPI.SUTypedValueSetString(tv_h, value.to_s)
      end

      SUAPI.check! SUAPI.SUAttributeDictionarySetValue(dict_h, key.to_s, tv_h),
                   'SUAttributeDictionarySetValue (group)'
    ensure
      if defined?(tv_h) && tv_h && tv_h != 0
        SUAPI.SUTypedValueRelease(SUAPI.h1(tv_h))
      end
    end
  end
end
