#!/usr/bin/env ruby
# generate_northstar.rb
#
# North Star (北二高) v3 — standalone SKP generator via SketchUp C SDK (FFI)
#
# Supported product lines:
#   Q-Series  (Sync_Sliding)  — 3-panel master/slave DC, suspended hardware
#   LS-Folding (Folding)      — even-panel folding, (L-14)/N width formula
#   F1-Cabinet (Pivot)        — ≤450mm×2100mm, F1 hinge milling at top rail
#
# Group hierarchy per panel (written to model.entities):
#   Group "NorthStar_{system}_P{n}" (carries DC attrs on entity)
#     ├── Frame geometry  (LS立框 × 2, 上橫檔, 下橫檔) — VerticalFrame/HorizontalFrame layers
#     ├── Glass geometry  (玻璃)                        — Glass layer
#     ├── Hardware        (吊輪/吊片)                   — Hardware layer
#     └── Milling marker  (F1 only, red box)            — Milling layer
#
# HEADLESS: no SketchUp installation needed. The C SDK DLL is loaded via FFI.
# ANIMATE / $dc_observers only activate when the SKP is opened in SketchUp.

$LOAD_PATH.unshift File.join(__dir__, '../../lib')
require 'sketchup_sdk'
require 'json'
require_relative 'door_logic_v3'

SEP = ('=' * 70).freeze

# ── Geometry helpers ─────────────────────────────────────────────────────────

def add_box_to(entities, matrix, bw, bh, bt, layer, mat)
  local_pts = [
    [0,  0,  0 ], [bw, 0,  0 ], [bw, bt, 0 ], [0,  bt, 0 ],
    [0,  0,  bh], [bw, 0,  bh], [bw, bt, bh], [0,  bt, bh]
  ]
  pts = local_pts.map { |p| transform_point_v3(p, matrix) }
  quads = [
    [pts[0], pts[1], pts[2], pts[3]],
    [pts[4], pts[7], pts[6], pts[5]],
    [pts[0], pts[4], pts[5], pts[1]],
    [pts[3], pts[2], pts[6], pts[7]],
    [pts[0], pts[3], pts[7], pts[4]],
    [pts[1], pts[5], pts[6], pts[2]]
  ]
  n = 0
  quads.each do |q|
    f = entities.add_face(*q)
    next unless f
    f.layer         = layer
    f.material      = mat
    f.back_material = mat
    n += 1
  end
  n
end

def identity_matrix_v3(tx, ty, tz)
  [1,0,0,0, 0,1,0,0, 0,0,1,0, tx.to_f, ty.to_f, tz.to_f, 1.0]
end

# ── Main ─────────────────────────────────────────────────────────────────────
if __FILE__ == $0
  puts SEP
  puts ' North Star (北二高) v3 SKP Generator'
  puts " #{Time.now.strftime('%Y-%m-%d %H:%M:%S UTC')}"
  puts SEP
  puts

  dir  = __dir__
  arg  = ARGV[0]
  json_path = arg ? File.expand_path(arg, dir) : File.join(dir, 'q_series_instance.json')

  raw    = JSON.parse(File.read(json_path))
  boards = parse_boards_v3(raw)
  params = parse_template_params_v3(raw)

  system_type    = params['SystemType']    || 'Sync_Sliding'
  total_h        = params['H'].to_f
  total_w        = params['L'].to_f
  panel_count    = [params['PanelCount'].to_i, 1].max
  profile_key    = params['Profile'].to_s.upcase
  frame_color    = params['FrameColor'].to_s
  glass_type     = params['GlassType'].to_s
  overlap        = params.fetch('Overlap',        50).to_f
  rot_angle      = params.fetch('RotationAngle',  90).to_i
  product_series = params['ProductSeries'].to_s
  milling_flag   = params.fetch('Milling', '').to_s
  product_code   = params.fetch('ProductCode', 'UNKNOWN').to_s

  panel_w   = FormulasV3.panel_w(total_w, panel_count, system_type)
  panel_h   = FormulasV3.panel_h(total_h, system_type)
  fc_rgb    = FRAME_COLORS_V3.fetch(frame_color, FRAME_COLORS_V3['黑砂色'])
  glass_cfg = GLASS_TYPES_V3.fetch(glass_type, GLASS_TYPES_V3['長虹玻璃'])
  profile   = PROFILES_V3.fetch(profile_key, PROFILES_V3['LS'])

  base_name = File.basename(json_path, '.json')
  out_name  = "#{base_name}.skp"
  out_path  = File.join(dir, out_name)

  puts "Product    : #{product_code}  (#{product_series}-Series)"
  puts "System     : #{system_type}  Profile=#{profile_key}"
  puts "Opening    : W=#{total_w}mm  H=#{total_h}mm  N=#{panel_count}"
  puts "Panel geom : W=#{panel_w.round(1)}mm  H=#{panel_h.round(1)}mm"
  puts "Milling    : #{milling_flag.empty? ? 'none' : milling_flag}"
  puts "Input      : #{File.basename(json_path)}"
  puts "Output     : #{out_name}"
  puts

  # ── Validation ─────────────────────────────────────────────────────────────
  puts 'Validating...'
  begin
    ValidatorV3.validate!(params, system_type)
    puts '  All checks PASSED'
  rescue ValidationErrorV3 => e
    abort "  VALIDATION FAILED: #{e.message}"
  end
  puts

  # ── Build model ─────────────────────────────────────────────────────────────
  model     = Sketchup::Model.new("NorthStar_V3_#{system_type}")
  entities  = model.entities
  layers    = model.layers
  materials = model.materials

  layer_cache = {}
  mat_cache   = {}

  get_lm = lambda do |type_name|
    unless layer_cache[type_name]
      layer_cache[type_name] = layers.add(type_name)
      m   = materials.add("#{type_name}_Mat")
      rgb = LAYER_COLORS_V3.fetch(type_name, [128, 128, 128])
      rgb = fc_rgb             if %w[VerticalFrame HorizontalFrame].include?(type_name)
      rgb = glass_cfg[:color]  if type_name == 'Glass'
      m.color = Sketchup::Color.new(*rgb)
      m.alpha = glass_cfg[:alpha] if type_name == 'Glass'
      mat_cache[type_name] = m
    end
    [layer_cache[type_name], mat_cache[type_name]]
  end

  # Always ensure Milling layer/mat exists for F1 (even if no F1 boards in JSON)
  has_milling = milling_flag == 'F1_Hinge'
  get_lm.call('Milling') if has_milling

  # ── Group boards by panel index ─────────────────────────────────────────────
  by_panel = Hash.new { |h, k| h[k] = [] }
  boards.each do |b|
    pi = panel_index_v3(b) || 0
    by_panel[pi] << b
  end

  # Root (panel 0) boards — add flat to model entities
  (by_panel.delete(0) || []).each do |b|
    next if b[:width] == 0.0 && b[:height] == 0.0
    type_name  = PART_LAYERS_V3.fetch(classify_part_v3(b[:name]), 'Other')
    layer, mat = get_lm.call(type_name)
    add_box_to(entities, b[:matrix], b[:width], b[:height], b[:thickness], layer, mat)
  end

  puts 'Building geometry + groups + DC attributes...'
  total_faces   = 0
  group_count   = 0
  master_name   = "NorthStar_Q_P1"  # used by sync-sliding slave reference

  by_panel.keys.sort.each do |pi|
    pboards  = by_panel[pi]
    pi_human = pi - 1  # 0-based

    # ── Create parent group for this panel ─────────────────────────────────
    grp      = entities.add_group
    grp_name = "NorthStar_#{system_type.gsub('_','')}_P#{pi}"
    grp.name = grp_name
    group_count += 1
    g_ents = grp.entities

    # ── Add board geometry into the group ──────────────────────────────────
    pboards.each do |b|
      next if b[:width] == 0.0 && b[:height] == 0.0
      type_name  = PART_LAYERS_V3.fetch(classify_part_v3(b[:name]), 'Other')
      layer, mat = get_lm.call(type_name)
      n = add_box_to(g_ents, b[:matrix], b[:width], b[:height], b[:thickness], layer, mat)
      total_faces += n
    end

    # ── F1 milling marker ──────────────────────────────────────────────────
    if has_milling
      mill_pos = FormulasV3.f1_milling_position(panel_w, panel_h, profile_key)
      mill_mat_layer, mill_mat = get_lm.call('Milling')
      n = add_box_to(
        g_ents,
        identity_matrix_v3(mill_pos[:x], mill_pos[:y], mill_pos[:z]),
        F1_MILLING[:w], F1_MILLING[:h], mill_pos[:depth],
        mill_mat_layer, mill_mat
      )
      total_faces += n
      puts "  [MILL] F1_Hinge  pos(%.2f, %.2f, %.2f)  %.1f×%.1f×%.1fmm" % [
        mill_pos[:x], mill_pos[:y], mill_pos[:z],
        F1_MILLING[:w], F1_MILLING[:h], mill_pos[:depth]
      ]
    end

    # ── DC attributes on group entity ──────────────────────────────────────
    dc_attrs = case system_type
               when 'Pivot'
                 DCAttrsV3.pivot(panel_w, rotation_angle: rot_angle)
               when 'Folding'
                 DCAttrsV3.folding(pi_human, panel_w)
               when 'Sync_Sliding'
                 if pi_human == 0
                   DCAttrsV3.sliding_master(panel_w, overlap: overlap, master_name: master_name)
                 else
                   DCAttrsV3.sliding_slave(panel_w, factor: pi_human + 1, master_name: master_name)
                 end
               else
                 { 'status' => '0', '_onclick_formula' => 'ANIMATE("status", 0, 90)' }
               end

    dc_attrs.each { |k, v| grp.set_attribute(DC_DICT_V3, k, v) }
    # Instance-level label
    grp.set_attribute(DC_DICT_V3, '_name', "#{system_type} P#{pi}")
    grp.set_attribute(DC_DICT_V3, 'lenx',  panel_w.round(1).to_f)

    onclick = dc_attrs['_onclick_formula'] || dc_attrs['_x_formula'] || '(slave)'
    puts "  [Panel #{pi}] #{grp_name}  DC: #{onclick}  faces=#{total_faces}"
  end

  puts
  puts "Groups: #{group_count}  Total faces: #{total_faces}"
  puts "Layers: #{layer_cache.size + 1}  Materials: #{mat_cache.size}"

  # ── Save ────────────────────────────────────────────────────────────────────
  print "\nSaving ... "
  abort 'FAILED — model.save returned false' unless model.save(out_path)
  sz = File.size(out_path)
  puts "OK (#{sz} bytes)"
  model.close

  # ── Round-trip verify ────────────────────────────────────────────────────────
  puts "\nVerifying..."
  v     = Sketchup::Model.open(out_path)
  stats = v.statistics
  v.close

  exp_faces     = total_faces
  exp_layers    = layer_cache.size + 1
  exp_materials = mat_cache.size
  exp_groups    = group_count

  result_rows = [
    ['faces',     exp_faces,     stats[:faces]],
    ['layers',    exp_layers,    stats[:layers]],
    ['materials', exp_materials, stats[:materials]],
    ['groups',    exp_groups,    stats[:groups]]
  ]

  errors = []
  result_rows.each do |key, exp, act|
    ok = act == exp
    puts '  %-22s  expected=%-4d  actual=%-4d  [%s]' % [key, exp, act, ok ? 'OK' : 'MISMATCH']
    errors << "#{key}: expected #{exp}, got #{act}" unless ok
  end

  puts
  if errors.empty?
    puts SEP
    puts ' RESULT: OK'
    puts " #{out_name}  Groups:#{stats[:groups]}  Faces:#{stats[:faces]}  Layers:#{stats[:layers]}  Size:#{sz}b"
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
