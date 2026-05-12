#!/usr/bin/env ruby
# generate_office.rb
#
# Generates a 3-room office building SKP file using the sketchup_sdk Ruby gem.
# The API mirrors the official SketchUp Ruby API — no SketchUp installation needed.
#
# Building layout (all dimensions in inches; 1 ft = 12 in):
#
#   ┌──────────────────────────────────┐   y = D  (240")  North
#   │   Back Office  (60%)             │
#   ├──────────────────────────────────┤   y = W2 (216")
#   │   Corridor     (2 ft)            │
#   ├──────────────────────────────────┤   y = W1 (192")
#   │   Front Office (40%)             │
#   └──────────────────────────────────┘   y = 0         South
#   x = 0                          x = W (360")
#
# Height: H = 10 ft = 120"

$LOAD_PATH.unshift File.join(__dir__, '../lib')
require 'sketchup_sdk'

puts "=" * 60
puts " SketchUp SDK – Ruby API (no SketchUp software needed)"
puts " Generating: RubyOfficeBuilding.skp"
puts "=" * 60
puts

# ── Dimensions ────────────────────────────────────────────────────────────────
FT = 12.0
W  = (30 * FT)   # 30 ft wide   (X)
D  = (20 * FT)   # 20 ft deep   (Y)
H  = (10 * FT)   # 10 ft tall   (Z)
W1 = (16 * FT)   # front office rear wall Y
W2 = (18 * FT)   # corridor rear wall Y

# ── Model  ────────────────────────────────────────────────────────────────────
model = Sketchup::Model.new(
  "RubyOfficeBuilding",
  "30 ft x 20 ft x 10 ft, 3-room office. " \
  "Generated via Ruby API backed by the SketchUp C SDK."
)

# ── Layers (Tags) ─────────────────────────────────────────────────────────────
layer_floor    = model.layers.add("Floor")
layer_ext_wall = model.layers.add("Exterior Walls")
layer_int_wall = model.layers.add("Interior Walls")
layer_ceiling  = model.layers.add("Ceiling")

puts "Layers created: #{model.layers.map(&:name).join(', ')}"

# ── Materials ─────────────────────────────────────────────────────────────────
mat_concrete = model.materials.add("Concrete")
mat_concrete.color = Sketchup::Color.new(160, 150, 135)    # warm gray

mat_stucco = model.materials.add("Stucco")
mat_stucco.color = Sketchup::Color.new(235, 228, 212)      # off-white

mat_drywall = model.materials.add("Drywall")
mat_drywall.color = Sketchup::Color.new(220, 218, 210)     # light gray

mat_ceiling_paint = model.materials.add("CeilingPaint")
mat_ceiling_paint.color = Sketchup::Color.new(245, 245, 240) # near-white

puts "Materials created: #{model.materials.map(&:name).join(', ')}"
puts

# ── Geometry helper ───────────────────────────────────────────────────────────
def add_plane(entities, pts, layer:, material:)
  face = entities.add_face(*pts)
  if face
    face.layer    = layer
    face.material = material
    puts "  [OK] #{layer.name} face  (#{pts.size} verts)"
  else
    warn "  [WARN] face creation returned nil for layer '#{layer.name}'"
  end
  face
end

entities = model.entities
puts "Building faces..."

# Floor slab  (z = 0,  normal +Z — CCW from above)
add_plane(entities,
  [[0,0,0], [W,0,0], [W,D,0], [0,D,0]],
  layer: layer_floor, material: mat_concrete)

# Ceiling     (z = H,  normal -Z — front visible from inside)
add_plane(entities,
  [[0,0,H], [0,D,H], [W,D,H], [W,0,H]],
  layer: layer_ceiling, material: mat_ceiling_paint)

# South exterior wall  (y = 0,  outward normal -Y)
add_plane(entities,
  [[W,0,0], [0,0,0], [0,0,H], [W,0,H]],
  layer: layer_ext_wall, material: mat_stucco)

# North exterior wall  (y = D,  outward normal +Y)
add_plane(entities,
  [[0,D,0], [W,D,0], [W,D,H], [0,D,H]],
  layer: layer_ext_wall, material: mat_stucco)

# West exterior wall   (x = 0,  outward normal -X)
add_plane(entities,
  [[0,0,0], [0,D,0], [0,D,H], [0,0,H]],
  layer: layer_ext_wall, material: mat_stucco)

# East exterior wall   (x = W,  outward normal +X)
add_plane(entities,
  [[W,D,0], [W,0,0], [W,0,H], [W,D,H]],
  layer: layer_ext_wall, material: mat_stucco)

# Interior partition 1 — front office / corridor  (y = W1)
add_plane(entities,
  [[0,W1,0], [W,W1,0], [W,W1,H], [0,W1,H]],
  layer: layer_int_wall, material: mat_drywall)

# Interior partition 2 — corridor / back office   (y = W2)
add_plane(entities,
  [[W,W2,0], [0,W2,0], [0,W2,H], [W,W2,H]],
  layer: layer_int_wall, material: mat_drywall)

# ── Save ──────────────────────────────────────────────────────────────────────
output = "RubyOfficeBuilding.skp"
puts
if model.save(output)
  sz = File.size(output)
  puts "Saved: #{output}  (#{sz} bytes)"
else
  abort "ERROR: model.save(#{output.inspect}) returned false"
end

model.close

puts
puts "Building summary:"
puts "  Width:   #{(W/FT).to_i} ft  (#{W.to_i}\")"
puts "  Depth:   #{(D/FT).to_i} ft  (#{D.to_i}\")"
puts "  Height:  #{(H/FT).to_i} ft  (#{H.to_i}\")"
puts "  Rooms:   Front Office | Corridor | Back Office"
puts "  Layers:  #{model.respond_to?(:layers) ? '(closed)' : 4}"
puts
puts "Open #{output} in SketchUp to inspect the 3-D model."
