# door_logic.rb
#
# Pure-Ruby business logic for the North Star advanced door generator.
# No SDK dependency — safe to require from unit tests without SketchUp.
#
# Included by:
#   generate_advanced_door.rb  (adds geometry / SDK calls)
#   test_advanced_door.rb      (minitest assertions only)

require 'json'

# ── LUT Offsets ───────────────────────────────────────────────────────────────
# Compact format (13 elements per Board, 4×4 matrix kept as 1 nested array):
ANCHOR     = 'Board'
CMP_ID     = 1
CMP_MATRIX = 5
CMP_WIDTH  = 6
CMP_HEIGHT = 7
CMP_THICK  = 8
CMP_NAME   = 10
CMP_CAT    = 11
CMP_HW     = 12
CMP_LEN    = 13

# Full positional format offsets (North Star production LUT — catalog spec):
FULL_ID     = 3
FULL_MATRIX = 8
FULL_WIDTH  = 43
FULL_HEIGHT = 44
FULL_THICK  = 45
FULL_NAME   = 90
FULL_SYSTEM = 110

# ── Physical Limits (North Star 2025 Catalog) ─────────────────────────────────
LIMITS = {
  folding_max_panel_w:    500.0,
  folding_max_total_h:   2400.0,
  folding_frame_type:    'LS',
  sync_sliding_min_w:     700.0,
  pivot_top_gap:           16.0,
  pivot_bottom_gap:        15.0,
  pivot_side_gap:           7.0
}.freeze

# ── Height Deduction Formulas ─────────────────────────────────────────────────
HEIGHT_DEDUCTIONS = {
  'Folding'      => 64,
  'Sync_Sliding' => 64,
  'Suspended'    => 64,
  'Floor'        => 32,
  'Pivot'        => 31
}.freeze

DIVIDER_RULES = [
  { max_thick: 5,  rod_w: 10 },
  { max_thick: 11, rod_w: 20 }
].freeze

BUFFER_MIN_W = 700

# ── Profile Library ───────────────────────────────────────────────────────────
# FollowMe cross-section path (local [x, z] 2D points, clockwise outer edge).
# For non-curved profiles this is a simple rectangle.
# For LE (curved), one corner is chamfered to approximate the arc.
PROFILE_DB = {
  'LC' => { w: 16.0,  d: 30.0, style: 'Ultra-Slim',
            section: [[0,0],[16,0],[16,30],[0,30]] },
  'LD' => { w: 22.5,  d: 34.0, style: 'Elegant',
            section: [[0,0],[22.5,0],[22.5,34],[0,34]] },
  'LE' => { w: 33.0,  d: 30.0, style: 'Curved',
            section: [[0,0],[33,0],[33,30],[5,30],[0,25]] },
  'LS' => { w: 33.0,  d: 34.0, style: 'Standard/Heavy',
            section: [[0,0],[33,0],[33,34],[0,34]] }
}.freeze

# ── Material / Color Definitions ──────────────────────────────────────────────
FRAME_COLORS = {
  '鋁本色' => [210, 210, 200],
  '白砂色' => [235, 232, 225],
  '黑砂色' => [45,  45,  48 ],
  '淺灰砂' => [170, 168, 165],
  '香檳金' => [212, 185, 120]
}.freeze

GLASS_TYPES = {
  '長虹玻璃' => { color: [200, 220, 230], alpha: 0.55 },
  '灰玻'     => { color: [140, 145, 148], alpha: 0.60 },
  '黑玻'     => { color: [30,  35,  38 ], alpha: 0.65 },
  '清玻璃'   => { color: [200, 230, 240], alpha: 0.45 }
}.freeze

LAYER_COLORS = {
  'VerticalFrame'   => [70,  70,  75 ],
  'HorizontalFrame' => [65,  65,  70 ],
  'Divider'         => [90,  90,  88 ],
  'Glass'           => [200, 220, 230],
  'Hardware'        => [50,  50,  55 ],
  'Handle'          => [30,  30,  30 ],
  'Milling'         => [255, 80,  80 ],
  'Other'           => [100, 100, 100]
}.freeze

PART_LAYERS = {
  vertical_frame:   'VerticalFrame',
  horizontal_frame: 'HorizontalFrame',
  divider:          'Divider',
  glass:            'Glass',
  hardware:         'Hardware',
  handle:           'Handle',
  other:            'Other'
}.freeze

# ── Hardware / Milling Specs ──────────────────────────────────────────────────
HARDWARE_SPECS = {
  '折門吊輪'   => { w: 58.3,  h: 23.1,  d: 26.3 },
  '連動吊片'   => { w: 40.0,  h: 15.0,  d: 20.0 },
  '緩衝器'     => { w: 80.0,  h: 30.0,  d: 25.0 },
  '嵌入式把手' => { w: 19.0,  h: 105.0, d: 12.0, z_ref: 1050.0 },
  '天地鉸鍊'   => { w: 10.0,  h: 3.5,   d: 20.0 }
}.freeze

MILLING_SPECS = {
  '嵌入式把手' => { w: 19.0, h: 105.0, d: 12.0, z_ref: 1050.0 },
  '天地鉸鍊'   => { w: 10.0, h: 3.5,   d: 20.0, z_ref: :frame_top }
}.freeze

# ── Validation ────────────────────────────────────────────────────────────────
class ValidationError < StandardError; end

module Validator
  def self.validate!(boards, params, system_type)
    errors   = []
    warnings = []

    case system_type
    when 'Folding'      then errors   += validate_folding(boards, params)
    when 'Sync_Sliding' then errors   += validate_sync_sliding(boards, params)
    when 'Pivot'        then warnings += validate_pivot(boards, params)
    end

    total_h = params['H'].to_f
    if total_h > LIMITS[:folding_max_total_h]
      warnings << "高度 #{total_h}mm 超過 2400mm — 建議現場評估結構加強（型錄第 25 頁）"
    end

    warnings.each { |w| warn "  WARNING: #{w}" }
    raise ValidationError, errors.join('; ') unless errors.empty?
    nil
  end

  def self.validate_folding(boards, params)
    errors = []

    # Rule 1: Only LS frames allowed
    frames = boards.select { |b| classify_part(b[:name]) == :vertical_frame }
    non_ls = frames.reject { |b| b[:name].start_with?('LS') }
    unless non_ls.empty?
      errors << "折疊門僅限 LS 框，非法框型: #{non_ls.map { |b| b[:name] }.uniq.join(', ')}"
    end

    # Rule 2: Panel count must be even
    panel_count = params['PanelCount'].to_i
    if panel_count > 0 && panel_count.odd?
      errors << "折疊門片數必須為雙數，實際: #{panel_count} 片"
    end

    # Rule 3: Individual panel width ≤ 500mm
    if panel_count > 0
      panel_w = params['L'].to_f / panel_count
      if panel_w > LIMITS[:folding_max_panel_w]
        errors << "折疊門單片寬 #{panel_w.round(1)}mm 超過上限 #{LIMITS[:folding_max_panel_w]}mm"
      end
    end

    errors
  end

  def self.validate_sync_sliding(boards, params)
    errors      = []
    panel_count = [params['PanelCount'].to_i, 1].max
    panel_w     = params['L'].to_f / panel_count
    if panel_w < LIMITS[:sync_sliding_min_w]
      errors << "連動門單片寬 #{panel_w.round(1)}mm < #{LIMITS[:sync_sliding_min_w]}mm，緩衝五金無法安裝"
    end
    errors
  end

  def self.validate_pivot(boards, params)
    ["旋轉門：保留上方 #{LIMITS[:pivot_top_gap]}mm / 下方 #{LIMITS[:pivot_bottom_gap]}mm / 側邊 #{LIMITS[:pivot_side_gap]}mm 間隙"]
  end
end

# ── Formulas ──────────────────────────────────────────────────────────────────
module Formulas
  def self.frame_height(total_h, system_type)
    total_h - HEIGHT_DEDUCTIONS.fetch(system_type, 64)
  end

  def self.divider_rod_width(glass_thickness)
    rule = DIVIDER_RULES.find { |r| glass_thickness <= r[:max_thick] }
    rule ? rule[:rod_w] : 20
  end

  def self.panel_width(total_w, panel_count)
    panel_count > 0 ? total_w.to_f / panel_count : total_w.to_f
  end

  # Fold-axis X positions for a folding door
  def self.pivot_x_positions(total_w, panel_count, panel_w)
    [0] + (1...panel_count).map { |i| (i * panel_w).round(2) } + [total_w.to_f]
  end

  def self.panel_inner_w(panel_w, profile_key)
    fw = PROFILE_DB.dig(profile_key.to_s.upcase, :w) || 33.0
    panel_w - 2 * fw
  end

  def self.top_rail_z(frame_h, profile_key)
    rail_h = PROFILE_DB.dig(profile_key.to_s.upcase, :w) || 33.0
    frame_h - rail_h
  end

  # Returns { z:, height:, width: } for the glass panel within a frame
  def self.glass_geometry(frame_h, panel_inner_w, profile_key, clearance: 15)
    rail_h = PROFILE_DB.dig(profile_key.to_s.upcase, :w) || 33.0
    z      = rail_h + clearance
    top_z  = frame_h - rail_h - clearance
    { z: z, height: top_z - z, width: panel_inner_w }
  end

  def self.divider_z(glass_z, glass_h, rod_h)
    glass_z + (glass_h / 2.0) - (rod_h / 2.0)
  end
end

# ── Parser ────────────────────────────────────────────────────────────────────
def parse_boards(arr)
  boards = []
  i = 0
  while i < arr.size
    if arr[i] == ANCHOR && (i + CMP_HW) < arr.size
      mat = arr[i + CMP_MATRIX]
      if mat.is_a?(Array) && mat.size == 16
        boards << {
          id:        arr[i + CMP_ID],
          matrix:    mat.map(&:to_f),
          width:     arr[i + CMP_WIDTH].to_f,
          height:    arr[i + CMP_HEIGHT].to_f,
          thickness: arr[i + CMP_THICK].to_f,
          name:      arr[i + CMP_NAME].to_s,
          category:  arr[i + CMP_CAT].to_s,
          hardware:  arr[i + CMP_HW].to_s
        }
        i += CMP_LEN
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

# ── Classification ────────────────────────────────────────────────────────────
def classify_part(name)
  case name
  when /立框/                        then :vertical_frame
  when /橫檔|橫框|上橫|下橫/        then :horizontal_frame
  when /分隔條/                      then :divider
  when /玻璃|灰玻|黑玻|玻$/                then :glass
  when /把手/                        then :handle
  when /吊輪|吊片|緩衝|鉸鍊|五金/   then :hardware
  else                                    :other
  end
end

# ── Matrix Helpers ────────────────────────────────────────────────────────────
def translation(matrix)
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
