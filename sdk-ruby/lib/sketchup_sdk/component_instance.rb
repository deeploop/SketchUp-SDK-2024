module Sketchup
  class ComponentInstance
    attr_reader :handle

    def initialize(handle)
      @handle = handle
    end

    # Set a 4×4 column-major transformation (16 floats/doubles, or identity if nil).
    def transformation=(values)
      values ||= [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
      buf = FFI::MemoryPointer.new(:double, 16)
      values.each_with_index { |v, i| buf.put_double(i * 8, v.to_f) }
      SUAPI.check! SUAPI.SUComponentInstanceSetTransform(@handle, buf),
                   'SUComponentInstanceSetTransform'
    end

    def entity_handle
      SUAPI.SUComponentInstanceToEntity(@handle)
    end

    # Write an attribute to the given dictionary on this instance.
    # value can be String, Integer, or Float.
    def set_attribute(dict_name, key, value)
      dict_out = SUAPI.out_h
      SUAPI.check! SUAPI.SUEntityGetAttributeDictionary(entity_handle, dict_name.to_s, dict_out),
                   'SUEntityGetAttributeDictionary'
      dict_h = SUAPI.rh(dict_out)

      tv_out = SUAPI.out_h
      SUAPI.check! SUAPI.SUTypedValueCreate(tv_out), 'SUTypedValueCreate'
      tv_h = SUAPI.rh(tv_out)

      case value
      when Integer then SUAPI.SUTypedValueSetInt32(tv_h, value)
      when Float   then SUAPI.SUTypedValueSetDouble(tv_h, value)
      else              SUAPI.SUTypedValueSetString(tv_h, value.to_s)
      end

      SUAPI.check! SUAPI.SUAttributeDictionarySetValue(dict_h, key.to_s, tv_h),
                   'SUAttributeDictionarySetValue'
    ensure
      if defined?(tv_h) && tv_h && tv_h != 0
        SUAPI.SUTypedValueRelease(SUAPI.h1(tv_h))
      end
    end
  end
end
