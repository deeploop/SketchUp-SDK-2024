# door_logic_v3.rb
#
# North Star (北二高) door generator v3 — pure-Ruby business logic.
# No SDK dependency. Covers Q-Series, LS-Folding, F1-Cabinet product lines.
#
# Key differences from v2:
#   - Deductions split into top/bottom components (for Z positioning)
#   - Folding panel width: (Total_W - 14) / Panel_Count
#   - Pivot panel width:    Total_W - 14   (7mm clearance each side)
#   - Sync_Sliding:         Total_W / Panel_Count (no side deduction)
#   - Q-Series master/slave DC formulas
#   - F1-Cabinet dimension limits + milling spec

require 'json'

# ── LUT compact-format offsets (same as v2) ───────────────────────────────────
ANCHOR_V3     = 'Board'
CMP_ID_V3     = 1
# offset 2: level, offset 3: sibling
CMP_DEBUG_V3  = 4   # debug label "P1_LS_Left" — used to detect panel group index
CMP_MATRIX_V3 = 5
CMP_WIDTH_V3  = 6
CMP_HEIGHT_V3 = 7
CMP_THICK_V3  = 8
# offset 9: "Polyline" type tag
CMP_NAME_V3   = 10  # production part name "LS立框" — used for classification
CMP_CAT_V3    = 11
CMP_HW_V3     = 12
CMP_LEN_V3    = 13

# ── Height deductions — split top/bottom (mm) ─────────────────────────────────
DEDUCTIONS_V3 = {
  'Suspended'    => { top: 47, bottom: 17 },  # total 64
  'Sync_Sliding' => { top: 47, bottom: 17 },  # same hardware as suspended
  'Pivot'        => { top: 16, bottom: 15 },  # total 31
  'Folding'      => { top: 47, bottom: 17 },  # total 64
  'Floor'        => { top: 32, bottom:  0 }   # total 32
}.freeze

# ── Profile library ───────────────────────────────────────────────────────────
PROFILES_V3 = {
  'LC' => { w: 16.0,  d: 30.0, style: 'Ultra-Slim' },
  'LD' => { w: 22.5,  d: 34.0, style: 'Elegant'    },
  'LE' => { w: 33.0,  d: 30.0, style: 'Curved'     },
  'LS' => { w: 33.0,  d: 34.0, style: 'Standard'   }
}.freeze

# ── Divider-bar selection (by glass thickness, mm) ───────────────────────────
DIVIDER_RULES_V3 = [
  { max_thick:  5, rod_w: 10 },
  { max_thick: 11, rod_w: 20 }
].freeze

# ── F1-Cabinet product limits (mm) ───────────────────────────────────────────
F1_MAX_W = 450.0
F1_MAX_H = 2100.0

# ── Milling spec: F1 hinge slot ───────────────────────────────────────────────
F1_MILLING = { w: 3.5, h: 10.0, label: 'F1_Hinge' }.freeze

# ── DC attribute dictionary name ──────────────────────────────────────────────
DC_DICT_V3 = 'dynamic_attributes'.freeze

# ── Material / color look-up tables ──────────────────────────────────────────
FRAME_COLORS_V3 = {
  '鋁本色' => [210, 210, 200],
  '白砂色' => [235, 232, 225],
  '黑砂鋁' => [45,  45,  48 ],
  '黑砂色' => [45,  45,  48 ],
  '淺灰砂' => [170, 168, 165],
  '香檳金' => [212, 185, 120]
}.freeze

GLASS_TYPES_V3 = {
  '長虹玻璃' => { color: [200, 220, 230], alpha: 0.55 },
  '灰玻'     => { color: [140, 145, 148], alpha: 0.60 },
  '黑玻'     => { color: [30,  35,  38 ], alpha: 0.65 },
  '清玻璃'   => { color: [200, 230, 240], alpha: 0.45 }
}.freeze

LAYER_COLORS_V3 = {
  'VerticalFrame'   => [70,  70,  75 ],
  'HorizontalFrame' => [65,  65,  70 ],
  'Divider'         => [90,  90,  88 ],
  'Glass'           => [200, 220, 230],
  'Hardware'        => [50,  50,  55 ],
  'Handle'          => [30,  30,  30 ],
  'Milling'         => [255,  80,  80 ],
  'Other'           => [100, 100, 100]
}.freeze

PART_LAYERS_V3 = {
  vertical_frame:   'VerticalFrame',
  horizontal_frame: 'HorizontalFrame',
  divider:          'Divider',
  glass:            'Glass',
  hardware:         'Hardware',
  handle:           'Handle',
  other:            'Other'
}.freeze

# ── Validation ────────────────────────────────────────────────────────────────
class ValidationErrorV3 < StandardError; end

module ValidatorV3
  def self.validate!(params, system_type)
    errors   = []
    warnings = []

    total_w     = params['L'].to_f
    total_h     = params['H'].to_f
    panel_count = params['PanelCount'].to_i
    profile_key = params['Profile'].to_s.upcase

    case system_type
    when 'Folding'
      errors << "折疊門片數必須為偶數，實際: #{panel_count}" if panel_count.odd? && panel_count > 0
      pw = FormulasV3.folding_panel_w(total_w, panel_count)
      errors << "折疊門單片寬 #{pw.round(1)}mm 超過 500mm" if pw > 500.0
      errors << "折疊門僅限 LS 框" unless profile_key == 'LS'

    when 'Sync_Sliding'
      pw = FormulasV3.sliding_panel_w(total_w, panel_count)
      errors << "連動門單片寬 #{pw.round(1)}mm < 700mm，緩衝五金無法安裝" if pw < 700.0

    when 'Pivot'
      pw = FormulasV3.pivot_panel_w(total_w)
      if params['ProductSeries'] == 'F1'
        errors << "F1 櫥門寬度 #{total_w}mm 超過上限 #{F1_MAX_W}mm"  if total_w > F1_MAX_W
        errors << "F1 櫥門高度 #{total_h}mm 超過上限 #{F1_MAX_H}mm"  if total_h > F1_MAX_H
      end
    end

    if total_h > 2400
      warnings << "高度 #{total_h}mm 超過 2400mm — 建議現場評估結構加強"
    end

    warnings.each { |w| warn "  WARNING: #{w}" }
    raise ValidationErrorV3, errors.join('; ') unless errors.empty?
    nil
  end
end

# ── Formulas ──────────────────────────────────────────────────────────────────
module FormulasV3
  def self.panel_h(total_h, system_type)
    ded = DEDUCTIONS_V3.fetch(system_type, { top: 47, bottom: 17 })
    total_h - ded[:top] - ded[:bottom]
  end

  def self.panel_h_top_offset(system_type)
    DEDUCTIONS_V3.fetch(system_type, { top: 47, bottom: 17 })[:bottom]
  end

  def self.sliding_panel_w(total_w, panel_count)
    panel_count > 0 ? total_w.to_f / panel_count : total_w.to_f
  end

  # Folding: (Total_W - 14) / Panel_Count  (7mm gap each side)
  def self.folding_panel_w(total_w, panel_count)
    panel_count > 0 ? (total_w.to_f - 14.0) / panel_count : total_w.to_f - 14.0
  end

  # Pivot: Total_W - 14  (7mm clearance each side)
  def self.pivot_panel_w(total_w)
    total_w.to_f - 14.0
  end

  def self.panel_w(total_w, panel_count, system_type)
    case system_type
    when 'Folding'      then folding_panel_w(total_w, panel_count)
    when 'Pivot'        then pivot_panel_w(total_w)
    else                     sliding_panel_w(total_w, panel_count)
    end
  end

  def self.inner_w(panel_w, profile_key)
    fw = PROFILES_V3.dig(profile_key.to_s.upcase, :w) || 33.0
    panel_w - 2.0 * fw
  end

  def self.glass_geometry(panel_h, inner_w, profile_key, clearance: 15)
    fw = PROFILES_V3.dig(profile_key.to_s.upcase, :w) || 33.0
    gz = fw + clearance
    { z: gz, height: panel_h - 2.0 * fw - 2.0 * clearance, width: inner_w }
  end

  def self.divider_rod_w(glass_thickness)
    rule = DIVIDER_RULES_V3.find { |r| glass_thickness <= r[:max_thick] }
    rule ? rule[:rod_w] : 20
  end

  # Y positions for N evenly-spaced divider bars
  def self.divider_y_positions(panel_h, n_segments)
    return [] if n_segments <= 1
    (1...n_segments).map { |i| (panel_h.to_f / n_segments * i).round(2) }
  end

  # F1 milling: centred on top rail, 10mm from top of frame
  def self.f1_milling_position(total_panel_w, total_panel_h, profile_key)
    fw = PROFILES_V3.dig(profile_key.to_s.upcase, :w) || 33.0
    fd = PROFILES_V3.dig(profile_key.to_s.upcase, :d) || 34.0
    x  = (total_panel_w - F1_MILLING[:w]) / 2.0
    z  = total_panel_h - F1_MILLING[:h]   # 10mm from top
    { x: x.round(2), y: 0.0, z: z.round(2), depth: fd }
  end
end

# ── DC attribute builders ─────────────────────────────────────────────────────
module DCAttrsV3
  # Pivot / F1 — single-panel rotation
  def self.pivot(panel_w, rotation_angle: 90)
    {
      'status'           => '0',
      '_status_label'    => '門扇狀態',
      '_status_options'  => "關閉=0&開啟=#{rotation_angle}",
      '_status_access'   => 'VIEW',
      'rotz'             => '0',
      '_rotz_formula'    => 'status',
      '_onclick_formula' => "ANIMATE(\"status\", 0, #{rotation_angle})"
    }
  end

  # Folding — alternating ±90° per panel
  def self.folding(panel_index, panel_w)
    angle = panel_index.even? ? 90 : -90
    {
      'status'           => '0',
      '_status_label'    => "折疊扇 #{panel_index + 1} 狀態",
      '_status_options'  => "關閉=0&開啟=#{angle}",
      '_status_access'   => 'VIEW',
      'rotz'             => '0',
      '_rotz_formula'    => 'status',
      '_onclick_formula' => "ANIMATE(\"status\", 0, #{angle})"
    }
  end

  # Sync-Sliding master (panel 0 / index 0)
  # master_name: the SKP group name so slaves can reference it
  def self.sliding_master(panel_w, overlap: 50, master_name: 'NorthStar_Q_P1')
    travel = panel_w - overlap
    {
      'status'           => '0',
      '_status_label'    => '主門扇狀態',
      '_status_options'  => "關閉=0&開啟=#{-travel.round(1)}",
      '_status_access'   => 'VIEW',
      'x'                => '0',
      '_x_formula'       => 'status',
      '_onclick_formula' => "ANIMATE(\"status\", 0, #{-travel.round(1)})"
    }
  end

  # Sync-Sliding slave  (panels 1, 2, …)
  # factor: integer multiplier (slave 1 → 2×, slave 2 → 3×, …)
  def self.sliding_slave(panel_w, factor:, master_name: 'NorthStar_Q_P1')
    {
      'status'          => '0',
      '_status_label'   => "從門扇 #{factor} 狀態",
      '_status_access'  => 'VIEW',
      'x'               => '0',
      '_x_formula'      => "#{master_name}!status * #{factor}"
    }
  end
end

# ── Board parser (compact format) ─────────────────────────────────────────────
def parse_boards_v3(arr)
  boards = []
  i = 0
  while i < arr.size
    if arr[i] == ANCHOR_V3 && (i + CMP_HW_V3) < arr.size
      mat = arr[i + CMP_MATRIX_V3]
      if mat.is_a?(Array) && mat.size == 16
        boards << {
          id:         arr[i + CMP_ID_V3],
          debug_name: arr[i + CMP_DEBUG_V3].to_s,   # "P1_LS_Left" — panel-group routing
          matrix:     mat.map(&:to_f),
          width:      arr[i + CMP_WIDTH_V3].to_f,
          height:     arr[i + CMP_HEIGHT_V3].to_f,
          thickness:  arr[i + CMP_THICK_V3].to_f,
          name:       arr[i + CMP_NAME_V3].to_s,    # "LS立框" — part classification
          category:   arr[i + CMP_CAT_V3].to_s,
          hardware:   arr[i + CMP_HW_V3].to_s
        }
        i += CMP_LEN_V3
        next
      end
    end
    i += 1
  end
  boards
end

def parse_template_params_v3(arr)
  params = {}
  idx = arr.index('TemplateParam')
  return params unless idx
  j = idx + 1
  while j + 1 < arr.size
    key = arr[j]
    break if key.nil? || key == ANCHOR_V3
    params[key.to_s] = arr[j + 1] if key.is_a?(String)
    j += 2
  end
  params
end

# ── Part classification ────────────────────────────────────────────────────────
def classify_part_v3(name)
  case name
  when /立框/                             then :vertical_frame
  when /橫檔|橫框|上橫|下橫/             then :horizontal_frame
  when /分隔條/                           then :divider
  when /玻璃|灰玻|黑玻|玻$/              then :glass
  when /把手/                             then :handle
  when /吊輪|吊片|緩衝|鉸鍊|五金/        then :hardware
  else                                         :other
  end
end

# Panel grouping helper.
# Reads the debug_name field (offset 4, e.g. "P1_LS_Left") NOT the part name
# (offset 10, e.g. "LS立框") — they are different columns in the LUT.
def panel_index_v3(board)
  board[:debug_name][/\AP(\d+)_/, 1]&.to_i
end

# ── Matrix helpers ────────────────────────────────────────────────────────────
def translation_v3(matrix)
  [matrix[12], matrix[13], matrix[14]]
end

def transform_point_v3(pt, m)
  x, y, z = pt
  [
    x * m[0] + y * m[4] + z * m[8]  + m[12],
    x * m[1] + y * m[5] + z * m[9]  + m[13],
    x * m[2] + y * m[6] + z * m[10] + m[14]
  ]
end
