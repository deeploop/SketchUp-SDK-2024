#!/usr/bin/env ruby
# test_advanced_door.rb
#
# Unit tests for the North Star advanced door logic.
# Pure Ruby — no SketchUp SDK required.
# Run: ruby test_advanced_door.rb

require_relative 'door_logic'
require 'minitest/autorun'

INSTANCE_PATH = File.join(__dir__, 'folding_door_instance.json')
CONFIG_PATH   = File.join(__dir__, 'system_config_v2.json')

class TestAdvancedDoorLogic < Minitest::Test
  def setup
    @raw    = JSON.parse(File.read(INSTANCE_PATH))
    @config = JSON.parse(File.read(CONFIG_PATH))
    @boards = parse_boards(@raw)
    @params = parse_template_params(@raw)
  end

  # ── Config loading ────────────────────────────────────────────────────────

  def test_config_brand
    assert_equal 'North Star (北二高)', @config.dig('system_info', 'brand')
  end

  def test_config_has_four_profiles
    %w[LC LD LE LS].each { |k| assert @config.dig('profile_database', k) }
  end

  def test_config_has_glass_transparency
    assert_in_delta 0.55, @config.dig('glass_types', '長虹玻璃', 'alpha'), 0.001
  end

  def test_config_frame_colors_defined
    %w[鋁本色 白砂色 黑砂色 淺灰砂 香檳金].each do |name|
      assert @config.dig('frame_colors', name), "Missing frame color: #{name}"
    end
  end

  # ── Parser — board count & IDs ────────────────────────────────────────────

  def test_parse_finds_29_boards
    assert_equal 29, @boards.size, '1 root + 4 panels × 7 = 29 boards'
  end

  def test_board_ids_200_to_228
    ids = @boards.map { |b| b[:id] }
    assert_equal (200..228).to_a, ids
  end

  def test_root_board_zero_dims
    root = @boards.find { |b| b[:id] == 200 }
    assert_in_delta 0.0, root[:width],     0.01
    assert_in_delta 0.0, root[:height],    0.01
    assert_in_delta 0.0, root[:thickness], 0.01
  end

  # ── Parser — panel geometry ───────────────────────────────────────────────

  def test_vertical_frame_dims
    b = @boards.find { |b| b[:id] == 201 }
    assert_in_delta 33.0,  b[:width],     0.01
    assert_in_delta 2236.0, b[:height],   0.01
    assert_in_delta 34.0,  b[:thickness], 0.01
  end

  def test_panel1_right_frame_x
    b   = @boards.find { |b| b[:id] == 202 }
    tx, = translation(b[:matrix])
    assert_in_delta 467.0, tx, 0.01, 'Right frame x = 500 - 33 = 467'
  end

  def test_top_rail_z
    b   = @boards.find { |b| b[:id] == 203 }
    _, _, tz = translation(b[:matrix])
    assert_in_delta 2203.0, tz, 0.01, 'Top rail z = 2236 - 33 = 2203'
  end

  def test_bottom_rail_at_z_zero
    b   = @boards.find { |b| b[:id] == 204 }
    _, _, tz = translation(b[:matrix])
    assert_in_delta 0.0, tz, 0.01
  end

  def test_glass_geometry
    b   = @boards.find { |b| b[:id] == 205 }
    _, _, tz = translation(b[:matrix])
    assert_in_delta 48.0,   tz,        0.01
    assert_in_delta 2140.0, b[:height],0.01
    assert_in_delta 5.0,    b[:thickness], 0.01
  end

  def test_divider_at_center
    b   = @boards.find { |b| b[:id] == 206 }
    _, _, tz = translation(b[:matrix])
    assert_in_delta 1113.0, tz, 0.01
    assert_in_delta 10.0, b[:height], 0.01
  end

  def test_hardware_roller_dims
    b = @boards.find { |b| b[:id] == 207 }
    assert_in_delta 58.3, b[:width],     0.1
    assert_in_delta 23.1, b[:height],    0.1
    assert_in_delta 26.3, b[:thickness], 0.1
  end

  def test_panel_x_offsets
    # Each panel group starts 500mm further along X
    [{ id: 208, x: 500 }, { id: 215, x: 1000 }, { id: 222, x: 1500 }].each do |pair|
      b  = @boards.find { |b| b[:id] == pair[:id] }
      tx = translation(b[:matrix])[0]
      assert_in_delta pair[:x], tx, 0.01, "Board #{pair[:id]} X offset"
    end
  end

  def test_all_panels_have_same_glass_dims
    glass_ids = [205, 212, 219, 226]
    glass_ids.each do |gid|
      b = @boards.find { |b| b[:id] == gid }
      assert_in_delta 434.0,  b[:width],     0.01, "Board #{gid} glass width"
      assert_in_delta 2140.0, b[:height],    0.01, "Board #{gid} glass height"
    end
  end

  # ── TemplateParam ─────────────────────────────────────────────────────────

  def test_template_params_complete
    assert_equal 2000,      @params['L']
    assert_equal 2300,      @params['H']
    assert_equal 4,         @params['PanelCount']
    assert_equal 'Folding', @params['SystemType']
    assert_equal 'LS',      @params['Profile']
    assert_equal '黑砂色',  @params['FrameColor']
    assert_equal '長虹玻璃', @params['GlassType']
  end

  # ── Classification ────────────────────────────────────────────────────────

  def test_ls_frame_classified_as_vertical_frame
    assert_equal :vertical_frame, classify_part('LS立框')
  end

  def test_top_rail_classified_as_horizontal_frame
    assert_equal :horizontal_frame, classify_part('上橫檔')
    assert_equal :horizontal_frame, classify_part('下橫檔')
  end

  def test_glass_classification
    assert_equal :glass, classify_part('長虹玻璃')
    assert_equal :glass, classify_part('灰玻')
  end

  def test_hardware_classification
    assert_equal :hardware, classify_part('折門吊輪')
    assert_equal :hardware, classify_part('連動吊片')
    assert_equal :hardware, classify_part('緩衝器')
  end

  def test_handle_classification
    assert_equal :handle, classify_part('嵌入式把手')
  end

  def test_divider_classification
    assert_equal :divider, classify_part('分隔條')
  end

  def test_unique_part_types_in_folding_instance
    valid = @boards.reject { |b| b[:width] == 0.0 && b[:height] == 0.0 }
    types = valid.map { |b| classify_part(b[:name]) }.uniq.sort
    assert_equal %i[divider glass hardware horizontal_frame vertical_frame], types.sort
  end

  def test_hardware_count_matches_panel_count
    hw = @boards.select { |b| classify_part(b[:name]) == :hardware }
    assert_equal 4, hw.size, 'One hinge roller per panel'
  end

  # ── Formulas ─────────────────────────────────────────────────────────────

  def test_frame_height_folding
    assert_equal 2236, Formulas.frame_height(2300, 'Folding'), '2300 - 64 = 2236'
  end

  def test_frame_height_floor
    assert_equal 2268, Formulas.frame_height(2300, 'Floor'), '2300 - 32 = 2268'
  end

  def test_frame_height_pivot
    assert_equal 2269, Formulas.frame_height(2300, 'Pivot'), '2300 - 31 = 2269'
  end

  def test_frame_height_matches_instance
    fh = Formulas.frame_height(@params['H'], @params['SystemType'])
    frame = @boards.find { |b| b[:name] =~ /立框/ }
    assert_in_delta fh, frame[:height], 0.01
  end

  def test_divider_rod_5mm_glass
    assert_equal 10, Formulas.divider_rod_width(5.0), 'Glass ≤5mm → 10mm rod'
  end

  def test_divider_rod_8mm_glass
    assert_equal 20, Formulas.divider_rod_width(8.0), 'Glass 8mm → 20mm rod'
  end

  def test_divider_rod_11mm_glass
    assert_equal 20, Formulas.divider_rod_width(11.0), 'Glass 11mm → 20mm rod'
  end

  def test_divider_rod_default_above_11mm
    assert_equal 20, Formulas.divider_rod_width(12.0), 'Glass >11mm → default 20mm rod'
  end

  def test_divider_height_matches_formula
    glass  = @boards.find { |b| b[:name] =~ /玻璃/ }
    rod    = @boards.find  { |b| b[:name] =~ /分隔條/ }
    exp_rod_w = Formulas.divider_rod_width(glass[:thickness])
    assert_in_delta exp_rod_w, rod[:height], 0.01
  end

  def test_panel_width_calculation
    pw = Formulas.panel_width(@params['L'], @params['PanelCount'])
    assert_in_delta 500.0, pw, 0.01, '2000/4 = 500mm per panel'
  end

  def test_panel_inner_width
    iw = Formulas.panel_inner_w(500.0, 'LS')
    assert_in_delta 434.0, iw, 0.01, '500 - 2×33 = 434mm'
  end

  def test_top_rail_z_calculation
    fh = Formulas.frame_height(@params['H'], @params['SystemType'])
    tz = Formulas.top_rail_z(fh, 'LS')
    assert_in_delta 2203.0, tz, 0.01, '2236 - 33 = 2203'
  end

  def test_glass_geometry_formula
    fh = Formulas.frame_height(@params['H'], @params['SystemType'])
    iw = Formulas.panel_inner_w(500.0, 'LS')
    geo = Formulas.glass_geometry(fh, iw, 'LS')
    assert_in_delta 48.0,   geo[:z],      0.01
    assert_in_delta 2140.0, geo[:height], 0.01
    assert_in_delta 434.0,  geo[:width],  0.01
  end

  def test_divider_z_formula
    z = Formulas.divider_z(48.0, 2140.0, 10.0)
    assert_in_delta 1113.0, z, 0.01, '48 + 2140/2 - 5 = 1113'
  end

  def test_pivot_positions_4_panel
    positions = Formulas.pivot_x_positions(2000.0, 4, 500.0)
    assert_equal [0, 500.0, 1000.0, 1500.0, 2000.0], positions
  end

  def test_pivot_positions_boundary_count
    pos = Formulas.pivot_x_positions(800.0, 2, 400.0)
    assert_equal [0, 400.0, 800.0], pos, '2 panels = 3 pivot axes'
  end

  # ── Validator — valid cases ───────────────────────────────────────────────

  def test_valid_folding_door_passes
    assert_nil Validator.validate!(@boards, @params, 'Folding')
  end

  def test_valid_sync_sliding_passes
    params = @params.merge('L' => 1400, 'PanelCount' => 2)  # 700mm per panel
    assert_nil Validator.validate!(@boards, params, 'Sync_Sliding')
  end

  # ── Validator — folding failure cases ────────────────────────────────────

  def test_odd_panel_count_raises
    params = @params.merge('PanelCount' => 3)
    err = assert_raises(ValidationError) { Validator.validate!(@boards, params, 'Folding') }
    assert_match(/雙數/, err.message)
  end

  def test_panel_too_wide_raises
    params = @params.merge('L' => 3000, 'PanelCount' => 4)  # 750mm per panel
    err = assert_raises(ValidationError) { Validator.validate!(@boards, params, 'Folding') }
    assert_match(/500/, err.message)
  end

  def test_non_ls_frame_raises
    non_ls_board = { id: 999, matrix: [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1].map(&:to_f),
                     width: 33.0, height: 2236.0, thickness: 34.0,
                     name: 'LC立框', category: '測試', hardware: '不排' }
    boards_with_lc = @boards + [non_ls_board]
    err = assert_raises(ValidationError) { Validator.validate!(boards_with_lc, @params, 'Folding') }
    assert_match(/LS/, err.message)
  end

  # ── Validator — sync sliding failure ─────────────────────────────────────

  def test_sync_sliding_narrow_panel_raises
    params = @params.merge('L' => 1200, 'PanelCount' => 2)  # 600mm < 700mm
    err = assert_raises(ValidationError) { Validator.validate!(@boards, params, 'Sync_Sliding') }
    assert_match(/700/, err.message)
  end

  def test_sync_sliding_exact_min_passes
    params = @params.merge('L' => 1400, 'PanelCount' => 2)  # exactly 700mm
    assert_nil Validator.validate!(@boards, params, 'Sync_Sliding')
  end

  # ── Validator — pivot warning (no raise) ─────────────────────────────────

  def test_pivot_does_not_raise
    assert_nil Validator.validate!(@boards, @params, 'Pivot')
  end

  # ── Material / color definitions ─────────────────────────────────────────

  def test_frame_colors_defined
    assert FRAME_COLORS.key?('黑砂色')
    assert FRAME_COLORS.key?('鋁本色')
  end

  def test_glass_transparency_below_1
    GLASS_TYPES.each do |name, cfg|
      assert_operator cfg[:alpha], :<, 1.0, "#{name} must be transparent"
      assert_operator cfg[:alpha], :>, 0.0, "#{name} must be visible"
    end
  end

  def test_glass_color_is_not_cyan_default
    refute_equal [0, 255, 255], GLASS_TYPES['長虹玻璃'][:color], 'Glass has its own catalog color'
  end

  def test_milling_layer_color_is_red
    r, g, b = LAYER_COLORS['Milling']
    assert_operator r, :>, 200, 'Milling markers must be red for visibility'
    assert_operator g, :<, 150
    assert_operator b, :<, 150
  end

  # ── Hardware specs ────────────────────────────────────────────────────────

  def test_hinge_roller_spec
    spec = HARDWARE_SPECS['折門吊輪']
    assert_in_delta 58.3, spec[:w], 0.01
    assert_in_delta 23.1, spec[:h], 0.01
    assert_in_delta 26.3, spec[:d], 0.01
  end

  def test_handle_milling_spec
    spec = MILLING_SPECS['嵌入式把手']
    assert_in_delta 19.0,  spec[:w], 0.01
    assert_in_delta 105.0, spec[:h], 0.01
    assert_in_delta 12.0,  spec[:d], 0.01
    assert_in_delta 1050.0, spec[:z_ref], 0.01
  end

  # ── Profile database ──────────────────────────────────────────────────────

  def test_ls_profile_dims
    assert_in_delta 33.0, PROFILE_DB['LS'][:w], 0.01
    assert_in_delta 34.0, PROFILE_DB['LS'][:d], 0.01
  end

  def test_le_profile_has_curved_section
    section = PROFILE_DB['LE'][:section]
    assert_operator section.size, :>, 4, 'LE curved section needs more than 4 pts'
  end

  def test_all_profiles_have_sections
    PROFILE_DB.each do |key, prof|
      assert prof[:section], "#{key} profile missing section path"
      assert_operator prof[:section].size, :>=, 4
    end
  end

  # ── Matrix transforms ─────────────────────────────────────────────────────

  def test_identity_matrix_is_noop
    m  = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1].map(&:to_f)
    pt = transform_point([100.0, 200.0, 300.0], m)
    assert_in_delta 100.0, pt[0], 0.001
    assert_in_delta 200.0, pt[1], 0.001
    assert_in_delta 300.0, pt[2], 0.001
  end

  def test_translation_matrix
    m  = [1,0,0,0,0,1,0,0,0,0,1,0,1500,0,0,1].map(&:to_f)
    pt = transform_point([0.0, 0.0, 0.0], m)
    assert_in_delta 1500.0, pt[0], 0.001
  end

  def test_translation_helper
    m = [1,0,0,0,0,1,0,0,0,0,1,0,533,14.5,48,1].map(&:to_f)
    tx, ty, tz = translation(m)
    assert_in_delta 533.0, tx, 0.001
    assert_in_delta 14.5,  ty, 0.001
    assert_in_delta 48.0,  tz, 0.001
  end

  # ── Config / instance consistency ────────────────────────────────────────

  def test_config_deduction_matches_constant
    cfg_ded = @config.dig('height_deductions', 'Folding')
    assert_equal cfg_ded, HEIGHT_DEDUCTIONS['Folding']
  end

  def test_config_divider_rules_match_constants
    cfg = @config.dig('divider_matching')
    assert_equal cfg[0]['rod_width'], DIVIDER_RULES[0][:rod_w]
    assert_equal cfg[1]['rod_width'], DIVIDER_RULES[1][:rod_w]
  end

  def test_config_profile_dims_match_constants
    @config.dig('profile_database').each do |key, prof|
      assert_in_delta prof['w'], PROFILE_DB[key][:w], 0.01
      assert_in_delta prof['d'], PROFILE_DB[key][:d], 0.01
    end
  end

  def test_limits_match_config
    cfg = @config.dig('physical_limits')
    assert_equal cfg.dig('folding', 'max_panel_width'),   LIMITS[:folding_max_panel_w]
    assert_equal cfg.dig('folding', 'max_total_height'),  LIMITS[:folding_max_total_h]
    assert_equal cfg.dig('sync_sliding', 'min_panel_width'), LIMITS[:sync_sliding_min_w]
  end
end
