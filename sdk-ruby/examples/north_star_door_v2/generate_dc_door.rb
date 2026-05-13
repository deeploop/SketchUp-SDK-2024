#!/usr/bin/env ruby
# generate_dc_door.rb
#
# North Star Dynamic Component Door Generator
# Reads a door JSON instance and emits an SKP with DC onClick ANIMATE formulas.
#
# Supported SystemTypes:
#   Pivot        — ANIMATE("RotZ", 0, angle) on whole panel component
#   Sync_Sliding — ANIMATE("X", 0, -travel) per panel
#   Folding      — ANIMATE("RotZ", 0, ±90) alternating per panel

$LOAD_PATH.unshift File.join(__dir__, '../../lib')
require 'sketchup_sdk'
require 'json'
require_relative 'door_logic'
require_relative 'dc_attributes'

SEP = ('=' * 70).freeze

# ── Geometry helpers (same as generate_advanced_door.rb) ──────────────────────

def add_box(entities, matrix, bw, bh, bt, layer, mat)
  local_pts = [
    [0,  0,  0 ], [bw, 0,  0 ], [bw, bt, 0 ], [0,  bt, 0 ],
    [0,  0,  bh], [bw, 0,  bh], [bw, bt, bh], [0,  bt, bh]
  ]
  pts = local_pts.map { |p| transform_point(p, matrix) }
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

def identity_matrix(tx, ty, tz)
  [1,0,0,0, 0,1,0,0, 0,0,1,0, tx.to_f, ty.to_f, tz.to_f, 1.0]
end

# ── Group boards by panel index ───────────────────────────────────────────────
# Board debug names follow "P{N}_*" convention.
def panel_index_of(board)
  board[:name][/\AP(\d+)_/, 1]&.to_i
end

# ── Build one ComponentDefinition containing all geometry for a panel ─────────
def build_panel_component(model, boards, layer_cache, mat_cache, get_lm)
  defn     = model.component_definitions.add("Panel_#{SecureRandom.hex(4)}")
  ents     = defn.entities
  n_faces  = 0
  boards.each do |b|
    next if b[:width] == 0.0 && b[:height] == 0.0
    type_key  = classify_part(b[:name])
    type_name = PART_LAYERS.fetch(type_key, 'Other')
    layer, mat = get_lm.call(type_name)
    n_faces += add_box(ents, b[:matrix], b[:width], b[:height], b[:thickness], layer, mat)
  end
  [defn, n_faces]
end

# ── Main ──────────────────────────────────────────────────────────────────────
if __FILE__ == $0
  require 'securerandom'

  puts SEP
  puts ' North Star Dynamic Component Door Generator'
  puts " #{Time.now.strftime('%Y-%m-%d %H:%M:%S UTC')}"
  puts SEP
  puts

  dir = __dir__

  # Accept a JSON path argument (relative to __dir__ or absolute), fall back to pivot demo
  arg       = ARGV[0]
  json_path = if arg
                File.expand_path(arg, dir)
              else
                File.join(dir, 'pivot_door_instance.json')
              end
  raw       = JSON.parse(File.read(json_path))
  params    = parse_template_params(raw)
  boards    = parse_boards(raw)

  system_type = params['SystemType'] || 'Pivot'
  total_h     = params['H'].to_f
  total_w     = params['L'].to_f
  panel_count = [params['PanelCount'].to_i, 1].max
  profile_key = params['Profile'].to_s.upcase
  frame_color = params['FrameColor'].to_s
  glass_type  = params['GlassType'].to_s
  overlap     = params.fetch('Overlap', 50).to_f
  axis_loc    = params.fetch('AxisLocation', 0.33).to_f
  rot_angle   = params.fetch('RotationAngle', 90).to_i

  panel_w   = Formulas.panel_width(total_w, panel_count)
  fc_rgb    = FRAME_COLORS.fetch(frame_color, FRAME_COLORS['黑砂色'])
  glass_cfg = GLASS_TYPES.fetch(glass_type, GLASS_TYPES['長虹玻璃'])

  base_name = File.basename(json_path, '.json')
  out_name  = "#{base_name}_DC.skp"
  out_path  = File.join(dir, out_name)

  puts "System     : #{system_type}"
  puts "Input      : #{File.basename(json_path)}"
  puts "Output     : #{out_name}"
  puts "Panels     : #{panel_count}  W=#{total_w}mm  H=#{total_h}mm  panel_w=#{panel_w.round(1)}mm"
  puts

  # ── Validate ────────────────────────────────────────────────────────────────
  puts 'Validating...'
  begin
    Validator.validate!(boards, params, system_type)
    puts '  All checks PASSED'
  rescue ValidationError => e
    abort "  VALIDATION FAILED: #{e.message}"
  end
  puts

  # ── Build model ─────────────────────────────────────────────────────────────
  model     = Sketchup::Model.new("NorthStar_DC_#{system_type}")
  entities  = model.entities
  layers    = model.layers
  materials = model.materials

  layer_cache = {}
  mat_cache   = {}

  get_lm = lambda do |type_name|
    unless layer_cache[type_name]
      layer_cache[type_name] = layers.add(type_name)
      m   = materials.add("#{type_name}_Mat")
      rgb = LAYER_COLORS.fetch(type_name, [128, 128, 128])
      rgb = fc_rgb           if %w[VerticalFrame HorizontalFrame].include?(type_name)
      rgb = glass_cfg[:color] if type_name == 'Glass'
      m.color = Sketchup::Color.new(*rgb)
      m.alpha = glass_cfg[:alpha] if type_name == 'Glass'
      mat_cache[type_name] = m
    end
    [layer_cache[type_name], mat_cache[type_name]]
  end

  puts 'Building geometry + Dynamic Components...'

  # Group boards by panel (boards with no P{N}_ prefix go to panel 0)
  by_panel = Hash.new { |h, k| h[k] = [] }
  boards.each do |b|
    pi = panel_index_of(b) || 0
    by_panel[pi] << b
  end

  total_faces      = 0
  instance_count   = 0

  # Root (panel 0) boards that are not panel-specific go directly into model
  root_boards = by_panel.delete(0) || []
  root_boards.each do |b|
    next if b[:width] == 0.0 && b[:height] == 0.0
    type_name = PART_LAYERS.fetch(classify_part(b[:name]), 'Other')
    layer, mat = get_lm.call(type_name)
    total_faces += add_box(entities, b[:matrix], b[:width], b[:height], b[:thickness], layer, mat)
  end

  # Build one ComponentDefinition per panel, write DC template attrs on the
  # definition entity (SketchUp reads them as the DC behavior template), then
  # place one instance into the model.
  panel_indices = by_panel.keys.sort

  panel_indices.each do |pi|
    pboards  = by_panel[pi]
    pi_human = pi - 1  # 0-based index for DC formulas

    defn, nf = build_panel_component(model, pboards, layer_cache, mat_cache, get_lm)
    total_faces += nf

    # ── Write DC template attributes on the definition entity ──────────────
    # These are the canonical DC keys SketchUp's engine reads from the SKP.
    def_attrs = case system_type
                when 'Pivot'
                  NorthStar::DynamicComponent.pivot_def_attrs(rotation_angle: rot_angle)
                when 'Sync_Sliding'
                  dir = pi_human.even? ? -1 : 1
                  NorthStar::DynamicComponent.sliding_def_attrs(panel_w,
                    direction: dir, overlap: overlap)
                when 'Folding'
                  NorthStar::DynamicComponent.folding_def_attrs(pi_human, panel_w)
                else
                  { 'status' => '0', '_onclick_formula' => 'ANIMATE("status", 0, 90)' }
                end

    NorthStar::DynamicComponent.apply_to_definition(defn, def_attrs)
    onclick = def_attrs['_onclick_formula'] || ''

    # ── Create and place the instance ──────────────────────────────────────
    inst = defn.create_instance
    inst.transformation = NorthStar::DynamicComponent.translation_matrix(0, 0, 0)
    entities.add_instance(inst)
    instance_count += 1

    # Instance-level DC override: display name + panel width
    label = case system_type
            when 'Pivot'        then "旋轉門扇 #{pi}"
            when 'Sync_Sliding' then "連動門扇 #{pi}"
            when 'Folding'      then "折疊門扇 #{pi}"
            else                     "Panel #{pi}"
            end
    NorthStar::DynamicComponent.apply_to_instance(inst, label, panel_w)

    puts "  [Panel #{pi}] #{onclick}  (#{nf} faces)"
  end

  puts
  puts "Panels: #{instance_count}  Total faces: #{total_faces}"

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

  exp_layers    = layer_cache.size + 1
  exp_materials = mat_cache.size
  exp_instances = instance_count

  result_rows = [
    ['faces',               total_faces,    stats[:faces]],
    ['layers',              exp_layers,     stats[:layers]],
    ['materials',           exp_materials,  stats[:materials]],
    ['component_instances', exp_instances,  stats[:component_instances]]
  ]

  errors = []
  result_rows.each do |key, exp, act|
    ok = act == exp
    puts '  %-26s  expected=%-4d  actual=%-4d  [%s]' % [key, exp, act, ok ? 'OK' : 'MISMATCH']
    errors << "#{key}: expected #{exp}, got #{act}" unless ok
  end

  puts
  if errors.empty?
    puts SEP
    puts ' RESULT: OK'
    puts " #{out_name}  Instances:#{stats[:component_instances]}  Faces:#{stats[:faces]}  Size:#{sz}b"
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
