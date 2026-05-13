require 'ffi'

# Internal FFI module — calls SketchUpAPI.dll directly. No bridge DLL.
#
# On Windows x64 (MSVC ABI), a struct with a single pointer member (8 bytes)
# is passed/returned in a single register, ABI-identical to uint64.
# All SUxxxRef handles are { void* ptr }, so we use:
#   :uint64   for by-value handle arguments
#   :pointer  for output params (SUxxxRef*) — then read_uint64 to get handle
module SUAPI
  extend FFI::Library

  # sdk-ruby/lib/sketchup_sdk/ -> ../../bin = sdk-ruby/bin/
  BIN_DIR = File.expand_path('../../bin', __dir__).freeze

  SU_ERROR_NONE = 0

  if FFI::Platform.windows?
    require 'fiddle'
    # SetDllDirectoryA adds BIN_DIR to the process-wide DLL search path.
    # This lets Windows find transitive dependencies of SketchUpAPI.dll
    # without requiring them to be in PATH or System32.
    kernel32 = Fiddle.dlopen('kernel32.dll')
    set_dll_dir = Fiddle::Function.new(
      kernel32['SetDllDirectoryA'],
      [Fiddle::TYPE_VOIDP],
      Fiddle::TYPE_INT
    )
    set_dll_dir.call(BIN_DIR)
    # Also explicitly pre-load each DLL so they are in the loaded-module list.
    %w[SketchUpCommonPreferences.dll SketchUpAPI.dll].each do |dll|
      Fiddle.dlopen(File.join(BIN_DIR, dll))
    end
  end

  ffi_lib File.join(BIN_DIR, 'SketchUpAPI.dll')

  # ── Lifecycle ──────────────────────────────────────────────────────────
  attach_function :SUInitialize, [], :void
  attach_function :SUTerminate,  [], :void

  # ── Model ──────────────────────────────────────────────────────────────
  attach_function :SUModelCreate,          [:pointer],                   :int
  attach_function :SUModelRelease,         [:pointer],                   :int
  attach_function :SUModelSaveToFile,      [:uint64, :string],           :int
  attach_function :SUModelSetName,         [:uint64, :string],           :int
  attach_function :SUModelSetDescription,  [:uint64, :string],           :int
  attach_function :SUModelGetEntities,     [:uint64, :pointer],          :int
  attach_function :SUModelAddLayers,       [:uint64, :size_t, :pointer], :int
  attach_function :SUModelAddMaterials,    [:uint64, :size_t, :pointer], :int
  attach_function :SUModelGetStatistics,   [:uint64, :pointer],          :int
  attach_function :SUModelCreateFromFile,  [:pointer, :string],          :int

  # ── Layer ──────────────────────────────────────────────────────────────
  attach_function :SULayerCreate,  [:pointer],         :int
  attach_function :SULayerSetName, [:uint64, :string], :int

  # ── Material ───────────────────────────────────────────────────────────
  attach_function :SUMaterialCreate,        [:pointer],          :int
  attach_function :SUMaterialSetName,       [:uint64, :string],  :int
  attach_function :SUMaterialSetColor,      [:uint64, :pointer], :int
  attach_function :SUMaterialSetOpacity,    [:uint64, :double],  :int
  attach_function :SUMaterialSetUseOpacity, [:uint64, :int],     :int

  # ── Loop input ─────────────────────────────────────────────────────────
  attach_function :SULoopInputCreate,         [:pointer],         :int
  attach_function :SULoopInputAddVertexIndex, [:uint64, :size_t], :int

  # ── Face ───────────────────────────────────────────────────────────────
  # SUFaceCreate(SUFaceRef* out, const SUPoint3D* pts, SULoopInputRef* loop)
  attach_function :SUFaceCreate,           [:pointer, :pointer, :pointer], :int
  attach_function :SUFaceSetFrontMaterial, [:uint64, :uint64],             :int
  attach_function :SUFaceSetBackMaterial,  [:uint64, :uint64],             :int
  attach_function :SUFaceToDrawingElement, [:uint64],                      :uint64

  # ── Drawing element ────────────────────────────────────────────────────
  attach_function :SUDrawingElementSetLayer, [:uint64, :uint64], :int

  # ── Entities ───────────────────────────────────────────────────────────
  # SUEntitiesAddFaces(SUEntitiesRef, size_t len, const SUFaceRef faces[])
  attach_function :SUEntitiesAddFaces, [:uint64, :size_t, :pointer], :int
  # SUEntitiesAddInstance(SUEntitiesRef, SUComponentInstanceRef, SUStringRef* name_out)
  # Pass NULL for name_out to auto-assign.
  attach_function :SUEntitiesAddInstance, [:uint64, :uint64, :pointer], :int
  attach_function :SUEntitiesAddGroup,    [:uint64, :uint64],           :int

  # ── Group ──────────────────────────────────────────────────────────────
  # SUGroupToEntity / SUGroupToDrawingElement return by value (uint64 ABI).
  attach_function :SUGroupCreate,           [:pointer],          :int
  attach_function :SUGroupSetName,          [:uint64, :string],  :int
  attach_function :SUGroupGetEntities,      [:uint64, :pointer], :int
  attach_function :SUGroupToEntity,         [:uint64],           :uint64
  attach_function :SUGroupToDrawingElement, [:uint64],           :uint64

  # ── Component Definition ───────────────────────────────────────────────
  attach_function :SUComponentDefinitionCreate,         [:pointer],          :int
  attach_function :SUComponentDefinitionSetName,        [:uint64, :string],  :int
  attach_function :SUComponentDefinitionGetEntities,    [:uint64, :pointer], :int
  attach_function :SUComponentDefinitionCreateInstance, [:uint64, :pointer], :int
  attach_function :SUComponentDefinitionToEntity,       [:uint64],           :uint64

  # SUModelAddComponentDefinitions(SUModelRef, size_t, const SUComponentDefinitionRef[])
  attach_function :SUModelAddComponentDefinitions, [:uint64, :size_t, :pointer], :int

  # ── Component Instance ─────────────────────────────────────────────────
  # SUComponentInstanceSetTransform(SUComponentInstanceRef, const struct SUTransformation*)
  # SUTransformation = struct { double values[16]; } (column-major 4x4)
  attach_function :SUComponentInstanceSetTransform, [:uint64, :pointer], :int
  attach_function :SUComponentInstanceToEntity,     [:uint64],           :uint64

  # ── Entity ─────────────────────────────────────────────────────────────
  # SUEntityGetAttributeDictionary(SUEntityRef, const char* name, SUAttributeDictionaryRef* out)
  attach_function :SUEntityGetAttributeDictionary, [:uint64, :string, :pointer], :int

  # ── Attribute Dictionary ───────────────────────────────────────────────
  # SUAttributeDictionarySetValue(SUAttributeDictionaryRef, const char* key, SUTypedValueRef value_in)
  attach_function :SUAttributeDictionarySetValue, [:uint64, :string, :uint64], :int

  # ── Typed Value ────────────────────────────────────────────────────────
  attach_function :SUTypedValueCreate,    [:pointer],         :int
  attach_function :SUTypedValueRelease,   [:pointer],         :int
  attach_function :SUTypedValueSetString, [:uint64, :string], :int
  attach_function :SUTypedValueSetDouble, [:uint64, :double], :int
  attach_function :SUTypedValueSetInt32,  [:uint64, :int],    :int

  # ── Helpers ────────────────────────────────────────────────────────────

  def self.out_h
    FFI::MemoryPointer.new(:uint64, 1)
  end

  def self.rh(ptr)
    ptr.read_uint64
  end

  def self.h1(handle)
    p = FFI::MemoryPointer.new(:uint64, 1)
    p.write_uint64(handle)
    p
  end

  def self.check!(r, label = '')
    return if r == SU_ERROR_NONE
    raise "SketchUp SDK error #{r}#{label.empty? ? '' : " [#{label}]"}"
  end
end
