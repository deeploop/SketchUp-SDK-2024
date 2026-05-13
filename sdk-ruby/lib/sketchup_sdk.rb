# sketchup_sdk.rb
#
# Ruby API for generating SketchUp SKP files without SketchUp installed.
# Mirrors the official SketchUp Ruby API surface:
#
#   require 'sketchup_sdk'
#
#   model = Sketchup::Model.new("MyBuilding")
#   layer = model.layers.add("Walls")
#   mat   = model.materials.add("Brick")
#   mat.color = Sketchup::Color.new(180, 90, 60)
#
#   face = model.entities.add_face([0,0,0], [120,0,0], [120,0,96], [0,0,96])
#   face.material = mat
#   face.layer    = layer
#
#   model.save("MyBuilding.skp")
#   model.close

require_relative 'sketchup_sdk/ffi_bindings'
require_relative 'sketchup_sdk/color'
require_relative 'sketchup_sdk/layer'
require_relative 'sketchup_sdk/material'
require_relative 'sketchup_sdk/face'
require_relative 'sketchup_sdk/entities'
require_relative 'sketchup_sdk/component_definition'
require_relative 'sketchup_sdk/component_instance'
require_relative 'sketchup_sdk/model'

# Initialise the underlying C SDK on load; terminate cleanly on exit.
SUAPI.SUInitialize
at_exit { SUAPI.SUTerminate }

# ── Sketchup module ─────────────────────────────────────────────────────────
module Sketchup
  VERSION = '1.0.0'

  # Convenience factory — mirrors Sketchup.active_model semantics when building
  # a fresh file from scratch.
  def self.create_model(name = nil, description = nil)
    Model.new(name, description)
  end
end

# ── Geom module ─────────────────────────────────────────────────────────────
# Provides Geom::Point3d so scripts written against the official API compile
# without changes.
module Geom
  Point3d = Struct.new(:x, :y, :z) do
    def initialize(x = 0, y = 0, z = 0)
      super(x.to_f, y.to_f, z.to_f)
    end

    def +(other) Point3d.new(x + other.x, y + other.y, z + other.z); end
    def -(other) Point3d.new(x - other.x, y - other.y, z - other.z); end
    def to_a;    [x, y, z]; end
    def to_s;    "(#{x}, #{y}, #{z})"; end

    def distance(other)
      Math.sqrt((x-other.x)**2 + (y-other.y)**2 + (z-other.z)**2)
    end
  end
end
