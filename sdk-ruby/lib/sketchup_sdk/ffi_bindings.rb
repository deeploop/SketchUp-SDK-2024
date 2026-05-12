# Low-level FFI bindings to SketchUpBridge.dll.
# Do not use this file directly — use sketchup_sdk.rb instead.

require 'ffi'

module SketchUpBridge
  extend FFI::Library

  # __dir__ is sdk-ruby/lib/sketchup_sdk/
  # ../../bin  →  sdk-ruby/bin/  (MSBuild output; also holds SketchUpAPI.dll)
  BIN_DIR = File.expand_path('../../bin', __dir__).freeze

  if FFI::Platform.windows?
    # Windows DLL search order for transitive dependencies does NOT automatically
    # include the directory of the DLL being loaded — it uses the calling EXE
    # dir, System32, Windows dir, current dir, and PATH.
    #
    # Solution: use Ruby's built-in Fiddle to load the SketchUp SDK DLLs by
    # absolute path BEFORE FFI touches the bridge.  Once a DLL is in the
    # process's loaded-module list Windows finds it by name immediately, so
    # LoadLibrary('SketchUpBridge.dll') resolves its SketchUpAPI.dll import
    # without needing any PATH / search-order tricks.
    require 'fiddle'
    [
      File.join(BIN_DIR, 'SketchUpCommonPreferences.dll'),
      File.join(BIN_DIR, 'SketchUpAPI.dll'),
    ].each do |dll|
      warn "  [ffi_bindings] pre-loading #{dll}" if $VERBOSE
      Fiddle.dlopen(dll)
    end
  end

  ffi_lib File.join(BIN_DIR, 'SketchUpBridge.dll')

  # ── Lifecycle ──────────────────────────────────────────────────────────────
  attach_function :su_initialize, [],        :void
  attach_function :su_terminate,  [],        :void

  # ── Model ──────────────────────────────────────────────────────────────────
  attach_function :model_create,          [],                  :pointer
  attach_function :model_release,         [:pointer],          :void
  attach_function :model_save,            [:pointer, :string], :int
  attach_function :model_set_name,        [:pointer, :string], :void
  attach_function :model_set_description, [:pointer, :string], :void
  attach_function :model_get_entities,    [:pointer],          :pointer
  attach_function :model_add_layer,       [:pointer, :string], :pointer
  attach_function :model_add_material,
                  [:pointer, :string, :uint8, :uint8, :uint8], :pointer

  # ── Material ───────────────────────────────────────────────────────────────
  attach_function :material_set_color,
                  [:pointer, :uint8, :uint8, :uint8], :void
  attach_function :material_set_opacity, [:pointer, :double], :void

  # ── Entities / Face ────────────────────────────────────────────────────────
  # pts_buf: FFI::MemoryPointer of doubles [x0,y0,z0, x1,y1,z1 ...]
  attach_function :entities_add_face,
                  [:pointer, :pointer, :int], :pointer

  attach_function :face_set_front_material, [:pointer, :pointer], :void
  attach_function :face_set_back_material,  [:pointer, :pointer], :void
  attach_function :face_set_layer,          [:pointer, :pointer], :void

  # ── Verification / read-back ──────────────────────────────────────────────
  # Opens an existing .skp file; returns model handle (or null pointer).
  attach_function :model_open,      [:string],           :pointer
  # Fills a caller-allocated int[8] with entity counts (edges, faces, …).
  attach_function :model_get_stats, [:pointer, :pointer], :void
end
