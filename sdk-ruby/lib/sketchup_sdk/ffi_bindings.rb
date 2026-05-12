# Low-level FFI bindings to SketchUpBridge.dll.
# Do not use this file directly — use sketchup_sdk.rb instead.

require 'ffi'

module SketchUpBridge
  extend FFI::Library

  # Locate sdk-ruby/bin/ relative to this file (lib/sketchup_sdk/).
  BIN_DIR = File.expand_path('../../../bin', __dir__).freeze

  # Make Windows find SketchUpAPI.dll (bridge dependency) from the same dir.
  if FFI::Platform.windows?
    ENV['PATH'] = "#{BIN_DIR};#{ENV['PATH']}"
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
end
