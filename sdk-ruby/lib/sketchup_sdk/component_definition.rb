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
