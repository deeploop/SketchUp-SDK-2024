#!/usr/bin/env ruby
# sketchup_console_dc_door.rb
#
# North Star Dynamic Component Door — SketchUp Ruby Console version
#
# HOW TO USE:
#   1. Open SketchUp
#   2. Window > Ruby Console
#   3. Paste this entire file and press Enter
#
# The script creates a Dynamic Component door in the active model.
# Use the Interact tool (hand icon) to click the door and watch it animate.
#
# Supported SystemTypes: "Pivot", "Sync_Sliding", "Folding"

require 'json'

module NorthStarDC

  # ── Configuration ──────────────────────────────────────────────────────────
  DOOR_CONFIG = {
    system_type:    'Pivot',       # 'Pivot' | 'Sync_Sliding' | 'Folding'
    total_w:        900.0,         # mm — total opening width
    total_h:        2300.0,        # mm — total opening height
    panel_count:    1,
    profile_w:      33.0,          # LS frame width (mm)
    frame_depth:    34.0,          # LS frame depth (mm)
    glass_thick:    5.0,
    glass_offset_y: 14.5,
    rotation_angle: 90,            # degrees (Pivot / Folding)
    overlap:        50.0,          # mm overlap (Sync_Sliding)
    axis_fraction:  0.33,          # pivot axis at 1/3 from left
    frame_color:    [45, 45, 48],  # 黑砂色
    glass_color:    [200, 220, 230]
  }.freeze

  HEIGHT_DEDUCTIONS = { 'Pivot' => 31, 'Sync_Sliding' => 64, 'Folding' => 64 }.freeze
  DC_DICT           = 'dynamic_attributes'.freeze

  # ── Entry point ────────────────────────────────────────────────────────────
  def self.generate(cfg = DOOR_CONFIG)
    model = Sketchup.active_model
    model.start_operation('北二高動態門', true)

    entities  = model.active_entities
    materials = model.materials
    layers    = model.layers

    system = cfg[:system_type]
    total_w = cfg[:total_w]
    total_h = cfg[:total_h]
    n       = [cfg[:panel_count], 1].max
    frame_h = total_h - HEIGHT_DEDUCTIONS.fetch(system, 64)
    panel_w = total_w.to_f / n
    fw      = cfg[:profile_w]
    fd      = cfg[:frame_depth]
    gt      = cfg[:glass_thick]

    frame_mat = materials.add('LS_Frame')
    frame_mat.color = Sketchup::Color.new(*cfg[:frame_color])

    glass_mat = materials.add('Glass')
    glass_mat.color = Sketchup::Color.new(*cfg[:glass_color])
    glass_mat.alpha = 0.55

    n.times do |pi|
      base_x = pi * panel_w

      defn = model.definitions.add("NorthStar_#{system}_Panel#{pi + 1}")
      de   = defn.entities

      # Left frame
      add_box(de, base_x,           0, 0, fw,               frame_h, fd, frame_mat)
      # Right frame
      add_box(de, base_x + panel_w - fw, 0, 0, fw,          frame_h, fd, frame_mat)
      # Top rail
      add_box(de, base_x + fw,      0, frame_h - fw, panel_w - 2*fw, fw, fd, frame_mat)
      # Bottom rail
      add_box(de, base_x + fw,      0, 0,            panel_w - 2*fw, fw, fd, frame_mat)
      # Glass
      inner_w = panel_w - 2 * fw
      glass_z = fw + 15
      glass_h = frame_h - 2 * fw - 30
      add_box(de, base_x + fw, cfg[:glass_offset_y], glass_z, inner_w, glass_h, gt, glass_mat)

      # ── Write DC template attributes on the definition ──────────────────
      write_dc_attrs(defn, system, pi, panel_w, cfg)

      # ── Place instance ──────────────────────────────────────────────────
      t    = Geom::Transformation.translation([0, 0, 0])
      inst = entities.add_instance(defn, t)
      inst.set_attribute DC_DICT, '_name',   "#{system} 門扇 #{pi + 1}"
      inst.set_attribute DC_DICT, 'lenx',    panel_w.to_f
    end

    # Refresh DC observers so Component Options panel shows the dropdowns
    if defined?($dc_observers)
      $dc_observers.get_latest_class.redraw_with_undo(entities.grep(Sketchup::ComponentInstance).first)
    end

    model.commit_operation
    puts "✓ 北二高 #{system} 門生成完畢！請用「互動」工具點擊門扇。"
  rescue => e
    model.abort_operation
    raise e
  end

  # ── Write correct DC attribute keys on the ComponentDefinition ─────────────
  def self.write_dc_attrs(defn, system, panel_index, panel_w, cfg)
    case system
    when 'Pivot'
      angle = cfg[:rotation_angle]
      da = {
        'status'           => '0',
        '_status_label'    => '門扇狀態',
        '_status_options'  => "關閉=0&開啟=#{angle}",
        '_status_access'   => 'VIEW',
        'rotz'             => '0',
        '_rotz_formula'    => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{angle})"
      }

    when 'Sync_Sliding'
      dir    = panel_index.even? ? -1 : 1
      travel = (panel_w - cfg[:overlap]) * dir
      da = {
        'status'           => '0',
        '_status_label'    => '門扇狀態',
        '_status_options'  => "關閉=0&開啟=#{travel.round(1)}",
        '_status_access'   => 'VIEW',
        'x'                => '0',
        '_x_formula'       => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{travel.round(1)})"
      }

    when 'Folding'
      angle = panel_index.even? ? 90 : -90
      da = {
        'status'           => '0',
        '_status_label'    => "折疊扇 #{panel_index + 1} 狀態",
        '_status_options'  => "關閉=0&開啟=#{angle}",
        '_status_access'   => 'VIEW',
        'rotz'             => '0',
        '_rotz_formula'    => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{angle})"
      }

    else
      da = { 'status' => '0', '_onclick_formula' => 'ANIMATE("status", 0, 90)' }
    end

    da.each { |k, v| defn.set_attribute(DC_DICT, k, v) }
  end
  private_class_method :write_dc_attrs

  # ── Build a box from 6 quads directly in an Entities collection ────────────
  def self.add_box(ents, x, y, z, w, h, d, mat)
    pts = [
      [x,   y,   z  ], [x+w, y,   z  ], [x+w, y+d, z  ], [x,   y+d, z  ],
      [x,   y,   z+h], [x+w, y,   z+h], [x+w, y+d, z+h], [x,   y+d, z+h]
    ].map { |p| p.map { |v| v.mm } }

    [
      [pts[0], pts[1], pts[2], pts[3]],
      [pts[4], pts[7], pts[6], pts[5]],
      [pts[0], pts[4], pts[5], pts[1]],
      [pts[3], pts[2], pts[6], pts[7]],
      [pts[0], pts[3], pts[7], pts[4]],
      [pts[1], pts[5], pts[6], pts[2]]
    ].each do |q|
      f = ents.add_face(q)
      next unless f
      f.material = mat
      f.back_material = mat
    end
  end
  private_class_method :add_box
end

# ── Run ────────────────────────────────────────────────────────────────────────
NorthStarDC.generate
