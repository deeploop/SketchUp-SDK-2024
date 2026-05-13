#!/usr/bin/env ruby
# generate_advanced_door.rb
#
# North Star (北二高) Advanced Door Generator v2
# Supports: Folding (折疊門), Sync_Sliding (連動橫拉), Pivot (旋轉門)
#
# Architecture:
#   door_logic.rb  — pure validation/formula/parser (shared with tests)
#   this file      — SketchUp SDK geometry + main execution
#
# Geometry notes:
#   Profile FollowMe: approximated with box extrusion below.
#     In native SketchUp: draw section face → select perimeter path → followme.
#     Section paths are defined in PROFILE_DB[:section] in door_logic.rb.
#
#   Hardware milling (Boolean subtraction):
#     Rendered as red marker boxes on the 'Milling' layer.
#     In native SketchUp: use solid tools subtract on frame component.

$LOAD_PATH.unshift File.join(__dir__, '../../lib')
require 'sketchup_sdk'
require 'json'
require_relative 'door_logic'

SEP = ('=' * 70).freeze

# ── Geometry ──────────────────────────────────────────────────────────────────

def add_box(entities, matrix, bw, bh, bt, layer, mat)
  # 8 local corners; transform each by the board's 4×4 matrix
  local_pts = [
    [0,  0,  0 ], [bw, 0,  0 ], [bw, bt, 0 ], [0,  bt, 0 ],
    [0,  0,  bh], [bw, 0,  bh], [bw, bt, bh], [0,  bt, bh]
  ]
  pts = local_pts.map { |p| transform_point(p, matrix) }

  # 6 outward-facing quads
  quads = [
    [pts[0], pts[1], pts[2], pts[3]],  # bottom  -Z
    [pts[4], pts[7], pts[6], pts[5]],  # top     +Z
    [pts[0], pts[4], pts[5], pts[1]],  # front   -Y
    [pts[3], pts[2], pts[6], pts[7]],  # back    +Y
    [pts[0], pts[3], pts[7], pts[4]],  # left    -X
    [pts[1], pts[5], pts[6], pts[2]]   # right   +X
  ]

  n = 0
  quads.each do |q|
    f = entities.add_face(*q)
    next unless f
    f.layer         = layer
    f.material      = mat   # front face
    f.back_material = mat   # back face — prevents default bluish color
    n += 1
  end
  n
end

def identity_matrix(tx, ty, tz)
  [1,0,0,0, 0,1,0,0, 0,0,1,0, tx.to_f, ty.to_f, tz.to_f, 1].map(&:to_f)
end

def add_milling_marker(entities, tx, ty, tz, mw, mh, md, layer, mat)
  add_box(entities, identity_matrix(tx, ty, tz), mw, mh, md, layer, mat)
end

# ── Main (guarded so tests can require this file without executing) ─────────
if __FILE__ == $0
  puts SEP
  puts ' North Star (北二高) Advanced Door Generator v2'
  puts " #{Time.now.strftime('%Y-%m-%d %H:%M:%S UTC')}"
  puts SEP
  puts

  dir           = __dir__
  config_path   = File.join(dir, 'system_config_v2.json')
  instance_path = File.join(dir, 'folding_door_instance.json')
  output_path   = File.join(dir, 'NorthStarFolding4Panel.skp')

  config = JSON.parse(File.read(config_path))
  raw    = JSON.parse(File.read(instance_path))

  puts "System : #{config.dig('system_info', 'brand')}"
  puts "Input  : #{File.basename(instance_path)}"
  puts "Output : #{File.basename(output_path)}"
  puts

  boards      = parse_boards(raw)
  params      = parse_template_params(raw)
  system_type = params['SystemType'] || 'Folding'
  total_h     = params['H'].to_f
  total_w     = params['L'].to_f
  panel_count = params['PanelCount'].to_i
  profile_key = params['Profile'].to_s.upcase
  frame_color = params['FrameColor'].to_s
  glass_type  = params['GlassType'].to_s

  frame_h   = Formulas.frame_height(total_h, system_type)
  panel_w   = Formulas.panel_width(total_w, panel_count)
  profile   = PROFILE_DB[profile_key] || PROFILE_DB['LS']
  inner_w   = Formulas.panel_inner_w(panel_w, profile_key)
  top_z     = Formulas.top_rail_z(frame_h, profile_key)
  glass_geo = Formulas.glass_geometry(frame_h, inner_w, profile_key)
  glass_cfg = GLASS_TYPES.fetch(glass_type, GLASS_TYPES['長虹玻璃'])
  fc_rgb    = FRAME_COLORS.fetch(frame_color, FRAME_COLORS['黑砂色'])

  puts "TemplateParam:"
  params.each { |k, v| puts "  %-16s = %s" % [k, v] }
  puts
  puts "Derived:"
  puts "  %-16s = %.1f mm" % ['frame_h',    frame_h]
  puts "  %-16s = %.1f mm" % ['panel_w',    panel_w]
  puts "  %-16s = %.1f mm" % ['inner_w',    inner_w]
  puts "  %-16s = %.1f mm" % ['top_rail_z', top_z]
  puts "  %-16s = z=%.1f h=%.1f w=%.1f" % ['glass', glass_geo[:z], glass_geo[:height], glass_geo[:width]]
  puts

  # Fold-axis positions (偏軌 pivot points per catalog p.25)
  pivots = Formulas.pivot_x_positions(total_w, panel_count, panel_w)
  puts "Fold pivot X positions: #{pivots.map { |x| "#{x.round(1)}mm" }.join(' → ')}"
  puts

  puts "Boards parsed: #{boards.size}"
  puts

  # ── Validation ─────────────────────────────────────────────────────────────
  puts "Validating (North Star 2025 catalog)..."
  begin
    Validator.validate!(boards, params, system_type)
    puts "  All checks PASSED"
  rescue ValidationError => e
    abort "  VALIDATION FAILED: #{e.message}"
  end
  puts

  # Auto divider rod
  glass_board = boards.find { |b| b[:name] =~ /玻/ }
  glass_thick = glass_board ? glass_board[:thickness] : 5.0
  rod_w       = Formulas.divider_rod_width(glass_thick)
  puts "Glass #{glass_thick}mm → divider rod width: #{rod_w}mm"
  if panel_w < BUFFER_MIN_W
    puts "NOTE: Panel width #{panel_w.round(1)}mm < #{BUFFER_MIN_W}mm → 緩衝五金取消"
  end
  puts

  # ── Build model ─────────────────────────────────────────────────────────────
  model     = Sketchup::Model.new(
    'NorthStarFolding',
    "North Star #{system_type} × #{panel_count} panels × #{profile_key} — #{frame_color}"
  )
  entities  = model.entities
  layers    = model.layers
  materials = model.materials

  layer_cache = {}
  mat_cache   = {}

  # Helper: create layer + material on first use only (avoids lazy-init orphans)
  get_lm = lambda do |type_name|
    unless layer_cache[type_name]
      layer_cache[type_name] = layers.add(type_name)
      m   = materials.add("#{type_name}_Mat")
      rgb = LAYER_COLORS.fetch(type_name, [128, 128, 128])
      # Frame catalog color override
      if %w[VerticalFrame HorizontalFrame].include?(type_name)
        rgb = fc_rgb
      end
      # Glass: catalog color + transparency
      if type_name == 'Glass'
        rgb = glass_cfg[:color]
      end
      m.color = Sketchup::Color.new(*rgb)
      m.alpha = glass_cfg[:alpha] if type_name == 'Glass'
      mat_cache[type_name] = m
    end
    [layer_cache[type_name], mat_cache[type_name]]
  end

  puts "Building geometry..."
  total_faces  = 0
  valid_boards = 0

  boards.each do |b|
    next if b[:width] == 0.0 && b[:height] == 0.0

    type_key  = classify_part(b[:name])
    type_name = PART_LAYERS.fetch(type_key, 'Other')
    layer, mat = get_lm.call(type_name)

    n = add_box(entities, b[:matrix], b[:width], b[:height], b[:thickness], layer, mat)
    total_faces  += n
    valid_boards += 1

    tx, ty, tz = translation(b[:matrix])
    hw_tag = b[:hardware] != '不排' ? " [#{b[:hardware]}]" : ''
    puts '  [%3d] %-14s %7.1f×%7.1f×%5.1f  pos(%8.1f,%5.1f,%8.1f)%s' % [
      b[:id], b[:name], b[:width], b[:height], b[:thickness],
      tx, ty, tz, hw_tag
    ]
  end

  # ── Hardware milling markers ────────────────────────────────────────────────
  # 嵌入式把手 slots on LS/LD frames: 19×105×12mm at Z=1050
  puts
  puts "Hardware milling markers (Milling layer = red highlight)..."
  mill_spec = MILLING_SPECS['嵌入式把手']
  mill_count = 0

  if %w[LS LD].include?(profile_key)
    mill_layer, mill_mat = get_lm.call('Milling')
    (0...panel_count).each do |pi|
      # Place on right frame of each panel (inner edge / pull side)
      frame_x = (pi + 1) * panel_w - profile[:w]  # right frame x
      x_slot  = frame_x + (profile[:w] - mill_spec[:w]) / 2.0
      y_slot  = 0.0
      z_slot  = mill_spec[:z_ref]
      add_milling_marker(entities, x_slot, y_slot, z_slot,
                         mill_spec[:w], mill_spec[:h], mill_spec[:d],
                         mill_layer, mill_mat)
      total_faces += 6
      mill_count  += 1
      puts "  [MILL%d] 嵌入式把手  pos(%.1f, %.1f, %.1f)  %.0f×%.0f×%.0fmm" % [
        pi + 1, x_slot, y_slot, z_slot,
        mill_spec[:w], mill_spec[:h], mill_spec[:d]
      ]
    end
  end

  puts
  puts "Boards: #{valid_boards}  Milling markers: #{mill_count}  Total faces: #{total_faces}"

  # ── Save ────────────────────────────────────────────────────────────────────
  print "\nSaving ... "
  unless model.save(output_path)
    abort 'FAILED — model.save returned false'
  end
  sz = File.size(output_path)
  puts "OK (#{sz} bytes)"
  model.close

  # ── Round-trip verification ─────────────────────────────────────────────────
  puts "\nVerifying saved file..."
  v     = Sketchup::Model.open(output_path)
  stats = v.statistics
  v.close

  exp_faces     = total_faces
  exp_layers    = layer_cache.size + 1  # +1 for default Layer0
  exp_materials = mat_cache.size

  result_rows = [
    ['faces',     exp_faces,     stats[:faces]],
    ['layers',    exp_layers,    stats[:layers]],
    ['materials', exp_materials, stats[:materials]]
  ]
  errors = []
  result_rows.each do |key, exp, act|
    ok = act == exp
    puts '  %-22s  expected=%-4d  actual=%-4d  [%s]' % [key, exp, act, ok ? 'OK' : 'MISMATCH']
    errors << "#{key}: expected #{exp}, got #{act}" unless ok
  end
  puts '  %-22s  actual=%-4d' % ['edges', stats[:edges]]

  puts
  if errors.empty?
    puts SEP
    puts ' RESULT: OK'
    puts " #{File.basename(output_path)}"
    puts " Boards:#{valid_boards}  Faces:#{stats[:faces]}  Layers:#{stats[:layers]}  Materials:#{stats[:materials]}  Size:#{sz}b"
    puts SEP
    exit 0
  else
    puts SEP
    puts ' RESULT: FAILED'
    errors.each { |e| puts "  #{e}" }
    puts SEP
    exit 1
  end
end
