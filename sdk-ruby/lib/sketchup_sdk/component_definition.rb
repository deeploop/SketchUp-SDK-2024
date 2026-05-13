module Sketchup
  class ComponentDefinition
    attr_reader :handle

    def initialize(handle)
      @handle = handle
    end

    def entities
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUComponentDefinitionGetEntities(@handle, out), 'SUComponentDefinitionGetEntities'
      Entities.new(SUAPI.rh(out))
    end

    def create_instance
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUComponentDefinitionCreateInstance(@handle, out), 'SUComponentDefinitionCreateInstance'
      ComponentInstance.new(SUAPI.rh(out))
    end

    def entity_handle
      SUAPI.SUComponentDefinitionToEntity(@handle)
    end

    # Write a DC (or any) attribute on the definition entity.
    # This is the canonical place for DC template attributes in SketchUp.
    def set_attribute(dict_name, key, value)
      dict_out = SUAPI.out_h
      SUAPI.check! SUAPI.SUEntityGetAttributeDictionary(entity_handle, dict_name.to_s, dict_out),
                   'SUEntityGetAttributeDictionary (definition)'
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
                   'SUAttributeDictionarySetValue (definition)'
    ensure
      if defined?(tv_h) && tv_h && tv_h != 0
        SUAPI.SUTypedValueRelease(SUAPI.h1(tv_h))
      end
    end
  end

  class ComponentDefinitions
    def initialize(model_handle)
      @model_handle = model_handle
      @defs = []
    end

    # Creates a new named ComponentDefinition and registers it with the model.
    def add(name)
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUComponentDefinitionCreate(out), 'SUComponentDefinitionCreate'
      h = SUAPI.rh(out)
      SUAPI.SUComponentDefinitionSetName(h, name.to_s)

      buf = SUAPI.h1(h)
      SUAPI.check! SUAPI.SUModelAddComponentDefinitions(@model_handle, 1, buf),
                   'SUModelAddComponentDefinitions'

      defn = ComponentDefinition.new(h)
      @defs << defn
      defn
    end

    def size; @defs.size; end
  end
end
