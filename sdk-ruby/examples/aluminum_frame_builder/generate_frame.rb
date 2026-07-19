#!/usr/bin/env ruby
# generate_frame.rb
#
# Headless SKP generator for aluminum window/door frames.
# Uses SketchUp C SDK via FFI — no SketchUp installation needed.
#
# Rod group hierarchy written to model.entities:
#   Group "BottomRod"  — layer BottomRod, material AluminumProfile
#   Group "TopRod"     — layer TopRod
#   Group "LeftRod"    — layer LeftRod
#   Group "RightRod"   — layer RightRod
#   + 3 guide lines in root entities for hinge positions (layer HingeGuide)
#
# Each group contains:
#   2 hollow end-cap faces  (SUFaceCreate + SUFaceAddInnerLoop)
#   8 outer wall quad faces (one per outer-profile segment)
#   6 inner wall quad faces (one per inner-profile segment)
#   = 16 faces per rod
#
# Usage:
#   ruby generate_frame.rb [params.json]   (default: window_frame.json)

$LOAD_PATH.unshift File.join(__dir__, '../../lib')
require 'sketchup_sdk'
require 'json'
require_relative 'frame_logic'

SEP = ('=' * 70).freeze

if __FILE__ == $0
  puts SEP
  puts ' Aluminum Frame Builder — Headless SKP Generator'
  puts " #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
  puts SEP
  puts

  arg       = ARGV[0]
  json_path = arg ? File.expand_path(arg, __dir__) : File.join(__dir__, 'window_frame.json')
  params    = JSON.parse(File.read(json_path))

  frame_w  = params['width'].to_f
  frame_h  = params['height'].to_f
  hinges   = (params['hinges'] || [100, 500, 100]).map(&:to_f)
  material = params.fetch('material_color', 'aluminum')
  code     = params.fetch('product_code',   'UNKNOWN')
  profile  = params.fetch('profile',        'LS-19x22')

  puts "Product    : #{code}  (#{profile})"
  puts "Opening    : W=#{frame_w}mm  H=#{frame_h}mm"
  puts "Hinges     : #{hinges.map { |v| "#{v}mm" }.join(' / ')}"
  puts "Material   : #{material}"
  puts "Input      : #{File.basename(json_path)}"

  base_name = File.basename(json_path, '.json')
  out_path  = File.join(__dir__, "#{base_name}.skp")
  puts "Output     : #{base_name}.skp"
  puts

  # ── Validation ──────────────────────────────────────────────────────────────
  puts 'Validating...'
  begin
    FrameValidator.validate!(params)
    puts '  All checks PASSED'
  rescue FrameValidationError => e
    abort "  VALIDATION FAILED: #{e.message}"
  end
  puts

  # ── Build model ──────────────────────────────────────────────────────────────
  model    = Sketchup::Model.new("AluminumFrame_#{frame_w.to_i}x#{frame_h.to_i}")
  entities = model.entities

  # ── Layers ──────────────────────────────────────────────────────────────────
  layer_defs = {
    bottom: 'BottomRod',
    top:    'TopRod',
    left:   'LeftRod',
    right:  'RightRod',
    guide:  'HingeGuide'
  }
  lays = layer_defs.transform_values { |name| model.layers.add(name) }

  # ── Material ─────────────────────────────────────────────────────────────────
  rgb = FRAME_MATERIAL_COLORS.fetch(material, FRAME_MATERIAL_COLORS['aluminum'])
  mat = model.materials.add('AluminumProfile')
  mat.color = Sketchup::Color.new(*rgb)

  # ── Rod lengths per role ─────────────────────────────────────────────────────
  rod_lengths = { bottom: frame_w, top: frame_w, left: frame_h, right: frame_h }

  puts 'Building geometry + groups...'
  total_faces = 0
  group_count = 0

  ROD_ROLES.each do |role|
    length     = rod_lengths[role]
    face_data  = FrameGeometry.rod_face_data(
      role: role, length: length, frame_w: frame_w, frame_h: frame_h
    )

    grp      = entities.add_group
    grp.name = layer_defs[role]
    grp.layer = lays[role]
    group_count += 1

    g_ents    = grp.entities
    rod_faces = 0

    face_data.each do |fd|
      face = case fd[:type]
             when CAP_WITH_HOLE
               g_ents.add_face_with_hole(fd[:outer_pts], fd[:inner_pts])
             when QUAD_FACE
               g_ents.add_face(*fd[:pts])
             end
      if face
        face.material      = mat
        face.back_material = mat
        face.layer         = lays[role]
        rod_faces  += 1
        total_faces += 1
      end
    end

    puts "  [#{role.to_s.upcase.ljust(6)}] Group=#{grp.name}  length=#{length}mm  faces=#{rod_faces}"
  end

  # ── Hinge guide lines ────────────────────────────────────────────────────────
  hinge_lines = FrameGeometry.hinge_positions(frame_w, frame_h, hinges)
  guide_layer = lays[:guide]
  hinge_lines.each_with_index do |hl, idx|
    entities.add_guide_line(hl[:start], hl[:end_pt])
    puts "  [HINGE #{idx + 1}]  Z=#{hl[:start][2].round(1)}mm  " \
         "(#{hl[:start].map(&:round).inspect} → #{hl[:end_pt].map(&:round).inspect})"
  end

  puts
  puts "Groups: #{group_count}  Total faces: #{total_faces}  Guide lines: #{hinge_lines.size}"

  # ── Save ─────────────────────────────────────────────────────────────────────
  print "\nSaving ... "
  abort 'FAILED — model.save returned false' unless model.save(out_path)
  sz = File.size(out_path)
  puts "OK (#{sz} bytes)"
  model.close

  # ── Round-trip verify ─────────────────────────────────────────────────────────
  puts "\nVerifying round-trip..."
  v     = Sketchup::Model.open(out_path)
  stats = v.statistics
  v.close

  exp_groups    = group_count  # 4
  exp_layers    = layer_defs.size + 1  # 5 named + 1 default = 6
  exp_materials = 1

  result_rows = [
    ['groups',    exp_groups,    stats[:groups]],
    ['layers',    exp_layers,    stats[:layers]],
    ['materials', exp_materials, stats[:materials]]
  ]

  errors = []
  result_rows.each do |key, exp, act|
    ok = act == exp
    puts '  %-20s  expected=%-4d  actual=%-4d  [%s]' % [key, exp, act, ok ? 'OK' : 'MISMATCH']
    errors << "#{key}: expected #{exp}, got #{act}" unless ok
  end

  puts
  if errors.empty?
    puts SEP
    puts ' RESULT: OK'
    puts " #{base_name}.skp  Groups:#{stats[:groups]}  Faces:#{stats[:faces]}  " \
         "Layers:#{stats[:layers]}  Size:#{sz}b"
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
