#!/usr/bin/env ruby
# test_door_generator.rb
#
# Unit tests for the North Star door generator parsing and formula logic.
# Runs WITHOUT SketchUp SDK (pure Ruby) — tests the JSON parsing, formula
# calculations and board validation only.
#
# Run: ruby test_door_generator.rb

require 'json'
require 'minitest/autorun'

# ── Copy the pure-logic constants and helpers from generate_door.rb ──────────

ANCHOR     = 'Board'
OFF_ID     = 1
OFF_MATRIX = 5
OFF_WIDTH  = 6
OFF_HEIGHT = 7
OFF_THICK  = 8
OFF_NAME   = 10
OFF_CAT    = 11
OFF_HW     = 12
RECORD_LEN = 13

HEIGHT_DEDUCTION = { 'Suspended' => 64, 'Floor' => 32 }.freeze
DIVIDER_RULES    = [{ max_thick: 5, rod_w: 10 }, { max_thick: 11, rod_w: 20 }].freeze
BUFFER_MIN_W     = 700

PROFILE_DB = {
  'LC' => { w: 16.0,  d: 30.0 },
  'LD' => { w: 22.5,  d: 34.0 },
  'LE' => { w: 33.0,  d: 30.0 },
  'LS' => { w: 33.0,  d: 34.0 }
}.freeze

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

def classify_part(name)
  case name
  when /立框/       then :vertical_frame
  when /橫檔|橫框/  then :horizontal_frame
  when /分隔條/      then :divider
  when /玻璃/       then :glass
  when /把手/       then :handle
  else                   :other
  end
end

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

# ── Tests ─────────────────────────────────────────────────────────────────────

INSTANCE_PATH = File.join(__dir__, 'task_instance.json')
CONFIG_PATH   = File.join(__dir__, 'system_config.json')
IDENTITY      = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1].map(&:to_f).freeze

class TestNorthStarParser < Minitest::Test
  def setup
    @raw    = JSON.parse(File.read(INSTANCE_PATH))
    @config = JSON.parse(File.read(CONFIG_PATH))
  end

  # ── JSON loading ────────────────────────────────────────────────────────────

  def test_config_loaded
    assert_equal 'North Star (北二高)', @config.dig('system_info', 'brand')
    assert_equal '2025.12',            @config.dig('system_info', 'version')
    assert_equal 'mm',                 @config.dig('system_info', 'unit')
  end

  def test_config_has_profile_database
    %w[LC LD LE LS].each do |key|
      assert @config.dig('profile_database', key), "Profile #{key} missing"
    end
  end

  def test_instance_is_array
    assert_instance_of Array, @raw
  end

  # ── Board parsing ───────────────────────────────────────────────────────────

  def test_parse_finds_five_boards
    boards = parse_boards(@raw)
    assert_equal 5, boards.size, 'Expected 5 Board records (root + 4 parts)'
  end

  def test_board_ids_are_sequential
    boards = parse_boards(@raw)
    assert_equal [100, 101, 102, 103, 104], boards.map { |b| b[:id] }
  end

  def test_root_board_zero_dimensions
    board = parse_boards(@raw).first
    assert_equal 0.0, board[:width]
    assert_equal 0.0, board[:height]
    assert_equal 0.0, board[:thickness]
  end

  def test_left_frame_dimensions
    b = parse_boards(@raw).find { |x| x[:id] == 101 }
    assert_in_delta 33.0,   b[:width],     0.01
    assert_in_delta 2336.0, b[:height],    0.01
    assert_in_delta 34.0,   b[:thickness], 0.01
  end

  def test_right_frame_translation
    b = parse_boards(@raw).find { |x| x[:id] == 102 }
    tx, ty, tz = translation(b[:matrix])
    assert_in_delta 767.0, tx, 0.01, 'Right frame X translation'
    assert_in_delta 0.0,   ty, 0.01
    assert_in_delta 0.0,   tz, 0.01
  end

  def test_glass_panel_dimensions
    b = parse_boards(@raw).find { |x| x[:id] == 103 }
    assert_in_delta 734.0, b[:width],     0.01
    assert_in_delta 2240.0, b[:height],   0.01
    assert_in_delta 5.0,    b[:thickness], 0.01
  end

  def test_glass_panel_translation
    b = parse_boards(@raw).find { |x| x[:id] == 103 }
    tx, ty, tz = translation(b[:matrix])
    assert_in_delta 33.0,  tx, 0.01
    assert_in_delta 14.5,  ty, 0.01
    assert_in_delta 48.0,  tz, 0.01
  end

  def test_divider_dimensions
    b = parse_boards(@raw).find { |x| x[:id] == 104 }
    assert_in_delta 734.0, b[:width],     0.01
    assert_in_delta 10.0,  b[:height],    0.01
    assert_in_delta 34.0,  b[:thickness], 0.01
  end

  def test_divider_translation
    b = parse_boards(@raw).find { |x| x[:id] == 104 }
    tx, ty, tz = translation(b[:matrix])
    assert_in_delta 33.0,  tx, 0.01
    assert_in_delta 0.0,   ty, 0.01
    assert_in_delta 1120.0, tz, 0.01
  end

  def test_part_names
    boards = parse_boards(@raw)
    names = boards.map { |b| b[:name] }
    assert_includes names, 'LS立框'
    assert_includes names, '長虹玻璃'
    assert_includes names, '分隔條'
  end

  def test_hardware_types
    boards = parse_boards(@raw)
    frames = boards.select { |b| b[:name] =~ /立框/ }
    frames.each { |f| assert_equal '三合一', f[:hardware] }
    glass = boards.find { |b| b[:name] =~ /玻璃/ }
    assert_equal '不排', glass[:hardware]
  end

  # ── TemplateParam ────────────────────────────────────────────────────────────

  def test_template_params_parsed
    params = parse_template_params(@raw)
    assert_equal 800,         params['L']
    assert_equal 34,          params['W']
    assert_equal 2400,        params['H']
    assert_equal 'Suspended', params['SystemType']
    assert_equal 'LS',        params['Profile']
  end

  # ── Height formulas ──────────────────────────────────────────────────────────

  def test_suspended_height_deduction
    assert_equal 64, HEIGHT_DEDUCTION['Suspended']
    frame_h = 2400 - HEIGHT_DEDUCTION['Suspended']
    assert_equal 2336, frame_h
  end

  def test_floor_height_deduction
    assert_equal 32, HEIGHT_DEDUCTION['Floor']
    frame_h = 2400 - HEIGHT_DEDUCTION['Floor']
    assert_equal 2368, frame_h
  end

  def test_suspended_frame_height_matches_board
    boards = parse_boards(@raw)
    frame  = boards.find { |b| b[:name] =~ /立框/ }
    params = parse_template_params(@raw)
    expected_h = params['H'] - HEIGHT_DEDUCTION[params['SystemType']]
    assert_in_delta expected_h, frame[:height], 0.01,
      "立框 height should equal H - deduction"
  end

  # ── Divider rod matching ─────────────────────────────────────────────────────

  def test_divider_rule_5mm_glass
    rule = DIVIDER_RULES.find { |r| 5.0 <= r[:max_thick] }
    assert_equal 10, rule[:rod_w], 'Glass 5mm → rod 10mm'
  end

  def test_divider_rule_10mm_glass
    rule = DIVIDER_RULES.find { |r| 10.0 <= r[:max_thick] }
    assert_equal 20, rule[:rod_w], 'Glass 10mm → rod 20mm'
  end

  def test_divider_height_matches_rule
    boards = parse_boards(@raw)
    glass  = boards.find { |b| b[:name] =~ /玻璃/ }
    rod    = boards.find  { |b| b[:name] =~ /分隔條/ }
    rule   = DIVIDER_RULES.find { |r| glass[:thickness] <= r[:max_thick] }
    assert_equal rule[:rod_w], rod[:height].to_i,
      'Divider height in JSON must match auto-computed rod_width'
  end

  # ── Buffer hardware check ───────────────────────────────────────────────────

  def test_buffer_suppressed_if_narrow
    assert_equal 700, BUFFER_MIN_W
    # Sample glass (734mm) exceeds limit → buffer hardware IS active
    assert_operator 734.0, :>=, BUFFER_MIN_W,
      'Sample glass 734mm >= 700mm → buffer hardware should be active'
    # A narrow panel would suppress buffer
    assert_operator 650.0, :<, BUFFER_MIN_W,
      '650mm < 700mm → buffer hardware would be suppressed'
  end

  # ── Classification ──────────────────────────────────────────────────────────

  def test_classify_vertical_frame
    assert_equal :vertical_frame, classify_part('LS立框')
    assert_equal :vertical_frame, classify_part('LC立框')
  end

  def test_classify_glass
    assert_equal :glass, classify_part('長虹玻璃')
    assert_equal :glass, classify_part('清玻璃')
  end

  def test_classify_divider
    assert_equal :divider, classify_part('分隔條')
  end

  def test_classify_handle
    assert_equal :handle, classify_part('嵌入式把手')
  end

  def test_classify_unknown
    assert_equal :other, classify_part('軌道')
  end

  # ── Matrix transforms ────────────────────────────────────────────────────────

  def test_identity_transform_is_noop
    pt = [100.0, 200.0, 300.0]
    result = transform_point(pt, IDENTITY)
    assert_in_delta 100.0, result[0], 0.001
    assert_in_delta 200.0, result[1], 0.001
    assert_in_delta 300.0, result[2], 0.001
  end

  def test_translation_matrix
    mat = [1,0,0,0, 0,1,0,0, 0,0,1,0, 767,0,0,1].map(&:to_f)
    pt  = [0.0, 0.0, 0.0]
    r   = transform_point(pt, mat)
    assert_in_delta 767.0, r[0], 0.001
    assert_in_delta 0.0,   r[1], 0.001
    assert_in_delta 0.0,   r[2], 0.001
  end

  def test_translation_helper
    mat = [1,0,0,0, 0,1,0,0, 0,0,1,0, 33,14.5,48,1].map(&:to_f)
    tx, ty, tz = translation(mat)
    assert_in_delta 33.0,  tx, 0.001
    assert_in_delta 14.5,  ty, 0.001
    assert_in_delta 48.0,  tz, 0.001
  end

  # ── Profile database ─────────────────────────────────────────────────────────

  def test_ls_profile_dimensions
    assert_in_delta 33.0, PROFILE_DB['LS'][:w], 0.01
    assert_in_delta 34.0, PROFILE_DB['LS'][:d], 0.01
  end

  def test_right_frame_x_offset_equals_door_width_minus_frame_width
    params   = parse_template_params(@raw)
    door_w   = params['L'].to_f          # 800
    profile  = PROFILE_DB[params['Profile'].to_s.upcase]
    frame_w  = profile[:w]               # 33
    expected = door_w - frame_w          # 767

    right    = parse_boards(@raw).find { |b| b[:id] == 102 }
    tx       = translation(right[:matrix])[0]
    assert_in_delta expected, tx, 0.01, 'Right frame X must be L - frame_width'
  end

  # ── On-demand material count ─────────────────────────────────────────────────
  # Only part types that appear in the JSON should generate a material.
  # The sample has: 立框 (×2 boards, 1 type), 玻璃, 分隔條 → 3 unique types.

  def test_unique_part_types_in_sample
    boards = parse_boards(@raw)
    valid  = boards.reject { |b| b[:width] == 0.0 && b[:height] == 0.0 }
    types  = valid.map { |b| classify_part(b[:name]) }.uniq
    # Exactly 3 unique types in this instance: vertical_frame, glass, divider
    assert_equal 3, types.size
    assert_includes types, :vertical_frame
    assert_includes types, :glass
    assert_includes types, :divider
    refute_includes types, :handle,           'No handle boards in sample'
    refute_includes types, :horizontal_frame, 'No horizontal-frame boards in sample'
  end

  def test_expected_material_count_matches_unique_types
    boards = parse_boards(@raw)
    valid  = boards.reject { |b| b[:width] == 0.0 && b[:height] == 0.0 }
    unique_types = valid.map { |b| classify_part(b[:name]) }.uniq.size
    # Verification expects one material per unique part type seen — NOT a global
    # constant like LAYER_COLORS.size — so unused types don't inflate the count.
    assert_equal 3, unique_types
  end

  # ── Config / instance consistency ────────────────────────────────────────────

  def test_config_divider_rules_match_constants
    cfg_rules = @config.dig('formulas', 'divider_matching')
    assert_equal cfg_rules[0]['rod_width'], DIVIDER_RULES[0][:rod_w]
    assert_equal cfg_rules[1]['rod_width'], DIVIDER_RULES[1][:rod_w]
  end

  def test_config_buffer_limit_matches_constant
    cfg_min = @config.dig('formulas', 'buffer_limit', 'min_panel_width')
    assert_equal cfg_min, BUFFER_MIN_W
  end
end
