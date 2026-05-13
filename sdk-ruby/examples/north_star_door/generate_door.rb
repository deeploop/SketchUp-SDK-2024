#!/usr/bin/env ruby
# generate_door.rb
#
# North Star (北二高) Aluminum Frame Door Generator
#
# Reads a JSON positional flat array (compact format) and generates a 3D SKP
# file via the SketchUp Ruby SDK — no SketchUp software installation required.
#
# Compact array record format (13 elements per Board):
#   "Board", id, level, sibling, debug_name,
#   [m00..m33],          ← nested 4x4 matrix (16 floats, row-major)
#   width, height, thickness, "Polyline",
#   part_name, category, hardware_type
#
# Height deductions (北二高 formulas):
#   Suspended: frame_h = total_H - 64  (47mm top + 17mm bottom)
#   Floor:     frame_h = total_H - 32  (32mm top only)
#   Pivot:     top=16mm, bottom=15mm, side=7mm gap
#
# Divider rod auto-match:
#   Glass thickness ≤ 5mm  → 10mm rod
#   Glass thickness 6-11mm → 20mm rod

$LOAD_PATH.unshift File.join(__dir__, '../../lib')
require 'sketchup_sdk'
require 'json'

SEP = ('=' * 65).freeze

# ── LUT offsets (compact format, relative to "Board" anchor) ─────────────────
ANCHOR     = 'Board'
OFF_ID     = 1
OFF_MATRIX = 5   # nested array of 16 floats
OFF_WIDTH  = 6
OFF_HEIGHT = 7
OFF_THICK  = 8
OFF_NAME   = 10
OFF_CAT    = 11
OFF_HW     = 12
RECORD_LEN = 13  # compact record length (matrix kept as 1 nested element)

# ── Technical constants ───────────────────────────────────────────────────────
HEIGHT_DEDUCTION = {
  'Suspended' => 64,
  'Floor'     => 32
}.freeze

DIVIDER_RULES = [
  { max_thick: 5,  rod_w: 10 },
  { max_thick: 11, rod_w: 20 }
].freeze

BUFFER_MIN_W = 700  # mm — below this, buffer hardware is suppressed

PROFILE_DB = {
  'LC' => { w: 16.0,  d: 30.0 },
  'LD' => { w: 22.5,  d: 34.0 },
  'LE' => { w: 33.0,  d: 30.0 },
  'LS' => { w: 33.0,  d: 34.0 }
}.freeze

PART_LAYERS = {
  vertical_frame:   'VerticalFrame',
  horizontal_frame: 'HorizontalFrame',
  divider:          'Divider',
  glass:            'Glass',
  handle:           'Handle',
  other:            'Other'
}.freeze

LAYER_COLORS = {
  'VerticalFrame'   => [140, 140, 140],
  'HorizontalFrame' => [130, 130, 130],
  'Divider'         => [160, 160, 155],
  'Glass'           => [180, 210, 240],
  'Handle'          => [80,  80,  80 ],
  'Other'           => [100, 100, 100]
}.freeze

# ── Parser ────────────────────────────────────────────────────────────────────

def parse_boards(arr)
  boards = []
  i = 0
  while i < arr.size
    if arr[i] == ANCHOR && (i + OFF_HW) < arr.size
      mat = arr[i + OFF_MATRIX]
      if mat.is_a?(Array) && mat.size == 16
        boards << {
          id:        arr[i + OFF_ID],
          matrix:    mat.map(&:to_f),
          width:     arr[i + OFF_WIDTH].to_f,
          height:    arr[i + OFF_HEIGHT].to_f,
          thickness: arr[i + OFF_THICK].to_f,
          name:      arr[i + OFF_NAME].to_s,
          category:  arr[i + OFF_CAT].to_s,
          hardware:  arr[i + OFF_HW].to_s
        }
        i += RECORD_LEN
        next
      end
    end
    i += 1
  end
  boards
end

def parse_template_params(arr)
  params = {}
  idx = arr.index('TemplateParam')
  return params unless idx
  j = idx + 1
  while j + 1 < arr.size
    key = arr[j]
    break if key.nil? || key == ANCHOR
    params[key.to_s] = arr[j + 1] if key.is_a?(String)
    j += 2
  end
  params
end

# ── Part classification ───────────────────────────────────────────────────────

def classify_part(name)
  case name
  when /立框/        then :vertical_frame
  when /橫檔|橫框/   then :horizontal_frame
  when /分隔條/       then :divider
  when /玻璃/        then :glass
  when /把手/        then :handle
  else                    :other
  end
end

# ── Matrix helpers ────────────────────────────────────────────────────────────

def translation(matrix)
  # Row-major 4x4: translation row is [12..14]
  [matrix[12], matrix[13], matrix[14]]
end

def transform_point(pt, matrix)
  x, y, z = pt
  m = matrix
  [
    x * m[0] + y * m[4] + z * m[8]  + m[12],
    x * m[1] + y * m[5] + z * m[9]  + m[13],
    x * m[2] + y * m[6] + z * m[10] + m[14]
  ]
end

# ── Geometry ──────────────────────────────────────────────────────────────────

def add_box(entities, matrix, bw, bh, bt, layer, mat)
  # 8 local corners
  local_pts = [
    [0,  0,  0 ], [bw, 0,  0 ], [bw, bt, 0 ], [0,  bt, 0 ],
    [0,  0,  bh], [bw, 0,  bh], [bw, bt, bh], [0,  bt, bh]
  ]
  pts = local_pts.map { |p| transform_point(p, matrix) }

  # 6 faces (outward-facing normals)
  quads = [
    [pts[0], pts[1], pts[2], pts[3]],  # bottom  -Z
    [pts[4], pts[7], pts[6], pts[5]],  # top     +Z
    [pts[0], pts[4], pts[5], pts[1]],  # front   -Y
    [pts[3], pts[2], pts[6], pts[7]],  # back    +Y
    [pts[0], pts[3], pts[7], pts[4]],  # left    -X
    [pts[1], pts[5], pts[6], pts[2]]   # right   +X
  ]

  created = 0
  quads.each do |q|
    f = entities.add_face(*q)
    next unless f
    f.layer    = layer
    f.material = mat
    created   += 1
  end
  created
end

# ── Main ──────────────────────────────────────────────────────────────────────

puts SEP
puts ' North Star (北二高) — Aluminum Frame Door Generator'
puts " #{Time.now.strftime('%Y-%m-%d %H:%M:%S UTC')}"
puts SEP
puts

dir           = __dir__
config_path   = File.join(dir, 'system_config.json')
instance_path = File.join(dir, 'task_instance.json')
output_path   = File.join(dir, 'NorthStarDoor.skp')

config   = JSON.parse(File.read(config_path))
raw      = JSON.parse(File.read(instance_path))

puts "System : #{config.dig('system_info', 'brand')} v#{config.dig('system_info', 'version')}"
puts "Input  : #{instance_path}"
puts "Output : #{output_path}"
puts

# ── Parse ─────────────────────────────────────────────────────────────────────
params      = parse_template_params(raw)
system_type = params['SystemType'] || 'Suspended'
total_h     = params['H'].to_f
deduction   = HEIGHT_DEDUCTION.fetch(system_type, 64)
frame_h     = total_h - deduction
profile_key = params['Profile'].to_s.upcase
profile     = PROFILE_DB[profile_key]

puts "TemplateParam:"
params.each { |k, v| puts "  %-14s = %s" % [k, v] }
puts "  %-14s = %.1f mm (%.1f - %d)" % ['frame_h', frame_h, total_h, deduction]
puts "  Profile        = #{profile_key} #{profile ? "(w=#{profile[:w]}×d=#{profile[:d]}mm)" : '(unknown)'}"
puts

# Pivot clearance warning
if system_type == 'Pivot'
  puts "PIVOT door: top=16mm, bottom=15mm, side=7mm clearances apply"
  puts
end

boards = parse_boards(raw)
puts "Boards parsed: #{boards.size}"

# ── Validation ────────────────────────────────────────────────────────────────

# Folding door: must have even number of glass panels
if system_type == 'Folding'
  glass_count = boards.count { |b| classify_part(b[:name]) == :glass }
  if glass_count.odd?
    warn "WARNING: 折疊門玻璃數量為單數 (#{glass_count})，請確認設計！"
  end
end

# Divider rod width auto-match
glass_board  = boards.find { |b| classify_part(b[:name]) == :glass }
glass_thick  = glass_board ? glass_board[:thickness] : 0.0
rod_rule     = DIVIDER_RULES.find { |r| glass_thick <= r[:max_thick] }
auto_rod_w   = rod_rule ? rod_rule[:rod_w] : 20
puts "Glass thickness #{glass_thick}mm → auto divider rod width: #{auto_rod_w}mm"

# Buffer hardware check
panel_w = glass_board ? glass_board[:width] : 0.0
if panel_w > 0 && panel_w < BUFFER_MIN_W
  puts "NOTE: Panel width #{panel_w}mm < #{BUFFER_MIN_W}mm → 緩衝五金組件取消"
end
puts

# ── Build model ───────────────────────────────────────────────────────────────
model     = Sketchup::Model.new(
  'NorthStarDoor',
  "North Star #{system_type} door — #{profile_key} profile — generated by Ruby SDK"
)
entities  = model.entities
layers    = model.layers
materials = model.materials

layer_cache = {}
mat_cache   = {}

puts 'Building geometry...'
total_faces  = 0
valid_boards = 0

boards.each do |b|
  # Skip root / zero-dimension records
  next if b[:width] == 0.0 && b[:height] == 0.0

  type_key  = classify_part(b[:name])
  type_name = PART_LAYERS[type_key]

  # Create layer + material on first encounter of each part type.
  # Lazy SDK commit in Material#handle means materials MUST be assigned to
  # at least one face before save — creating them here guarantees that.
  unless layer_cache[type_name]
    layer_cache[type_name] = layers.add(type_name)
    m = materials.add("#{type_name}_Mat")
    m.color = Sketchup::Color.new(*LAYER_COLORS[type_name])
    mat_cache[type_name] = m
  end

  layer = layer_cache[type_name]
  mat   = mat_cache[type_name]

  n = add_box(entities, b[:matrix], b[:width], b[:height], b[:thickness], layer, mat)
  total_faces  += n
  valid_boards += 1

  tx, ty, tz = translation(b[:matrix])
  hw_note = b[:hardware] == '三合一' ? ' [三合一]' : ''
  puts '  [%3d] %-14s %7.1f×%7.1f×%5.1fmm  pos(%7.1f,%6.1f,%7.1f)%s' % [
    b[:id], b[:name], b[:width], b[:height], b[:thickness],
    tx, ty, tz, hw_note
  ]
end

puts
puts "Valid boards: #{valid_boards}  |  Faces created: #{total_faces}"

# ── Save ──────────────────────────────────────────────────────────────────────
print "\nSaving ... "
unless model.save(output_path)
  abort 'FAILED — model.save returned false'
end
sz = File.size(output_path)
puts "OK (#{sz} bytes)"
model.close

# ── Round-trip verification ───────────────────────────────────────────────────
puts "\nVerifying saved file..."
v     = Sketchup::Model.open(output_path)
stats = v.statistics
v.close

# Expected counts derived from what was actually created — not a hard-coded
# constant — so adding new board types to the JSON never causes a mismatch.
expected_faces     = valid_boards * 6        # 6 quads per box
expected_user_lyr  = layer_cache.size        # one layer per unique part type seen
expected_layers    = expected_user_lyr + 1   # +1 for SketchUp's default Layer0
expected_materials = mat_cache.size          # one material per unique part type seen

puts '  %-22s  expected=%-4d  actual=%-4d  [%s]' % [
  'faces', expected_faces, stats[:faces],
  stats[:faces] == expected_faces ? 'OK' : 'MISMATCH'
]
puts '  %-22s  expected=%-4d  actual=%-4d  [%s]' % [
  'layers', expected_layers, stats[:layers],
  stats[:layers] == expected_layers ? 'OK' : 'MISMATCH'
]
puts '  %-22s  expected=%-4d  actual=%-4d  [%s]' % [
  'materials', expected_materials, stats[:materials],
  stats[:materials] == expected_materials ? 'OK' : 'MISMATCH'
]
puts '  %-22s  actual=%-4d' % ['edges', stats[:edges]]

errors = []
errors << "faces: expected #{expected_faces}, got #{stats[:faces]}"         if stats[:faces]     != expected_faces
errors << "layers: expected #{expected_layers}, got #{stats[:layers]}"      if stats[:layers]    != expected_layers
errors << "materials: expected #{expected_materials}, got #{stats[:materials]}" if stats[:materials] != expected_materials

puts
if errors.empty?
  puts SEP
  puts ' RESULT: OK'
  puts " #{File.basename(output_path)} generated and verified (#{sz} bytes)"
  puts " Boards: #{valid_boards}  Faces: #{stats[:faces]}  Layers: #{stats[:layers]}  Materials: #{stats[:materials]}"
  puts SEP
  exit 0
else
  puts SEP
  puts ' RESULT: FAILED'
  errors.each { |e| puts "  #{e}" }
  puts SEP
  exit 1
end
