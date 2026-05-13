#!/usr/bin/env ruby
# test_door_logic_v3.rb
#
# Pure-Ruby unit tests for door_logic_v3.rb
# No SDK or SketchUp required.

require 'minitest/autorun'
require_relative 'door_logic_v3'

# ── Height deductions ─────────────────────────────────────────────────────────
class TestHeightDeductions < Minitest::Test
  def test_suspended_total
    d = DEDUCTIONS_V3['Suspended']
    assert_equal 64, d[:top] + d[:bottom]
  end

  def test_suspended_top_47_bottom_17
    d = DEDUCTIONS_V3['Suspended']
    assert_equal 47, d[:top]
    assert_equal 17, d[:bottom]
  end

  def test_pivot_total_31
    d = DEDUCTIONS_V3['Pivot']
    assert_equal 31, d[:top] + d[:bottom]
  end

  def test_pivot_top_16_bottom_15
    d = DEDUCTIONS_V3['Pivot']
    assert_equal 16, d[:top]
    assert_equal 15, d[:bottom]
  end

  def test_folding_same_as_suspended
    assert_equal DEDUCTIONS_V3['Suspended'], DEDUCTIONS_V3['Folding']
  end

  def test_sync_sliding_same_as_suspended
    assert_equal DEDUCTIONS_V3['Suspended'], DEDUCTIONS_V3['Sync_Sliding']
  end
end

# ── FormulasV3 panel heights ──────────────────────────────────────────────────
class TestPanelHeight < Minitest::Test
  def test_suspended_2400
    assert_in_delta 2336.0, FormulasV3.panel_h(2400.0, 'Suspended'), 0.001
  end

  def test_pivot_2300
    # 2300 - 16 - 15 = 2269
    assert_in_delta 2269.0, FormulasV3.panel_h(2300.0, 'Pivot'), 0.001
  end

  def test_pivot_2000
    # 2000 - 16 - 15 = 1969
    assert_in_delta 1969.0, FormulasV3.panel_h(2000.0, 'Pivot'), 0.001
  end

  def test_folding_2300
    # 2300 - 47 - 17 = 2236
    assert_in_delta 2236.0, FormulasV3.panel_h(2300.0, 'Folding'), 0.001
  end
end

# ── FormulasV3 panel widths ───────────────────────────────────────────────────
class TestPanelWidth < Minitest::Test
  # Folding: (L - 14) / N
  def test_folding_2000_4panels
    assert_in_delta 496.5, FormulasV3.folding_panel_w(2000.0, 4), 0.001
  end

  def test_folding_2000_2panels
    assert_in_delta 993.0, FormulasV3.folding_panel_w(2000.0, 2), 0.001
  end

  # Pivot: L - 14
  def test_pivot_440
    assert_in_delta 426.0, FormulasV3.pivot_panel_w(440.0), 0.001
  end

  def test_pivot_900
    assert_in_delta 886.0, FormulasV3.pivot_panel_w(900.0), 0.001
  end

  # Sync_Sliding: L / N (no side deduction)
  def test_sliding_2400_3panels
    assert_in_delta 800.0, FormulasV3.sliding_panel_w(2400.0, 3), 0.001
  end

  # panel_w dispatcher
  def test_dispatch_folding
    assert_in_delta 496.5, FormulasV3.panel_w(2000.0, 4, 'Folding'), 0.001
  end

  def test_dispatch_pivot
    assert_in_delta 426.0, FormulasV3.panel_w(440.0, 1, 'Pivot'), 0.001
  end

  def test_dispatch_sync_sliding
    assert_in_delta 800.0, FormulasV3.panel_w(2400.0, 3, 'Sync_Sliding'), 0.001
  end
end

# ── Divider bar selection ─────────────────────────────────────────────────────
class TestDividerBar < Minitest::Test
  def test_5mm_glass_gives_10mm_bar
    assert_equal 10, FormulasV3.divider_rod_w(5.0)
  end

  def test_4mm_glass_gives_10mm_bar
    assert_equal 10, FormulasV3.divider_rod_w(4.0)
  end

  def test_6mm_glass_gives_20mm_bar
    assert_equal 20, FormulasV3.divider_rod_w(6.0)
  end

  def test_11mm_glass_gives_20mm_bar
    assert_equal 20, FormulasV3.divider_rod_w(11.0)
  end

  def test_12mm_glass_gives_20mm_bar
    assert_equal 20, FormulasV3.divider_rod_w(12.0)
  end
end

# ── Divider Y positions ───────────────────────────────────────────────────────
class TestDividerPositions < Minitest::Test
  def test_2_segments_1_bar
    pos = FormulasV3.divider_y_positions(2400.0, 2)
    assert_equal 1, pos.size
    assert_in_delta 1200.0, pos[0], 0.001
  end

  def test_3_segments_2_bars
    pos = FormulasV3.divider_y_positions(2400.0, 3)
    assert_equal 2, pos.size
    assert_in_delta  800.0, pos[0], 0.001
    assert_in_delta 1600.0, pos[1], 0.001
  end

  def test_1_segment_no_bars
    assert_empty FormulasV3.divider_y_positions(2400.0, 1)
  end
end

# ── F1 Milling ────────────────────────────────────────────────────────────────
class TestF1Milling < Minitest::Test
  def setup
    # F1 cabinet: panel_w=426, panel_h=1969, LS profile (fw=33, fd=34)
    @pos = FormulasV3.f1_milling_position(426.0, 1969.0, 'LS')
  end

  def test_x_centered
    # (426 - 3.5) / 2 = 211.25
    assert_in_delta 211.25, @pos[:x], 0.001
  end

  def test_z_10mm_from_top
    # z = 1969 - 10 = 1959
    assert_in_delta 1959.0, @pos[:z], 0.001
  end

  def test_depth_equals_frame_depth
    assert_in_delta 34.0, @pos[:depth], 0.001
  end

  def test_y_is_zero
    assert_in_delta 0.0, @pos[:y], 0.001
  end

  def test_milling_width
    assert_in_delta 3.5, F1_MILLING[:w], 0.001
  end

  def test_milling_height
    assert_in_delta 10.0, F1_MILLING[:h], 0.001
  end
end

# ── F1 limits ────────────────────────────────────────────────────────────────
class TestF1Limits < Minitest::Test
  def test_max_width_450
    assert_equal 450.0, F1_MAX_W
  end

  def test_max_height_2100
    assert_equal 2100.0, F1_MAX_H
  end

  def test_valid_f1_passes
    params = { 'L' => 440, 'H' => 2000, 'PanelCount' => 1,
               'Profile' => 'LS', 'ProductSeries' => 'F1' }
    assert_nil ValidatorV3.validate!(params, 'Pivot')
  end

  def test_oversized_f1_width_fails
    params = { 'L' => 500, 'H' => 2000, 'PanelCount' => 1,
               'Profile' => 'LS', 'ProductSeries' => 'F1' }
    assert_raises(ValidationErrorV3) { ValidatorV3.validate!(params, 'Pivot') }
  end

  def test_oversized_f1_height_fails
    params = { 'L' => 440, 'H' => 2200, 'PanelCount' => 1,
               'Profile' => 'LS', 'ProductSeries' => 'F1' }
    assert_raises(ValidationErrorV3) { ValidatorV3.validate!(params, 'Pivot') }
  end
end

# ── Folding validation ────────────────────────────────────────────────────────
class TestFoldingValidation < Minitest::Test
  def test_even_panel_count_passes
    params = { 'L' => 2000, 'H' => 2300, 'PanelCount' => 4, 'Profile' => 'LS' }
    assert_nil ValidatorV3.validate!(params, 'Folding')
  end

  def test_odd_panel_count_fails
    params = { 'L' => 2000, 'H' => 2300, 'PanelCount' => 3, 'Profile' => 'LS' }
    assert_raises(ValidationErrorV3) { ValidatorV3.validate!(params, 'Folding') }
  end

  def test_non_ls_profile_fails
    params = { 'L' => 2000, 'H' => 2300, 'PanelCount' => 4, 'Profile' => 'LC' }
    assert_raises(ValidationErrorV3) { ValidatorV3.validate!(params, 'Folding') }
  end

  def test_panel_width_too_wide_fails
    # (2400 - 14) / 4 = 596.5 > 500
    params = { 'L' => 2400, 'H' => 2300, 'PanelCount' => 4, 'Profile' => 'LS' }
    assert_raises(ValidationErrorV3) { ValidatorV3.validate!(params, 'Folding') }
  end
end

# ── Sync_Sliding validation ────────────────────────────────────────────────────
class TestSlidingValidation < Minitest::Test
  def test_wide_panel_passes
    params = { 'L' => 2400, 'H' => 2400, 'PanelCount' => 3, 'Profile' => 'LS' }
    assert_nil ValidatorV3.validate!(params, 'Sync_Sliding')
  end

  def test_narrow_panel_fails
    # 1200/3 = 400 < 700
    params = { 'L' => 1200, 'H' => 2400, 'PanelCount' => 3, 'Profile' => 'LS' }
    assert_raises(ValidationErrorV3) { ValidatorV3.validate!(params, 'Sync_Sliding') }
  end
end

# ── DCAttrsV3 pivot ───────────────────────────────────────────────────────────
class TestDCAttrsPivot < Minitest::Test
  def setup
    @a = DCAttrsV3.pivot(426.0, rotation_angle: 90)
  end

  def test_status_zero
    assert_equal '0', @a['status']
  end

  def test_onclick_animates_status
    assert_match(/ANIMATE\("status"/, @a['_onclick_formula'])
    assert_includes @a['_onclick_formula'], ', 0, 90'
  end

  def test_rotz_formula_is_status
    assert_equal 'status', @a['_rotz_formula']
  end

  def test_status_options_format
    assert_match(/關閉=0&開啟=90/, @a['_status_options'])
  end

  def test_status_access_view
    assert_equal 'VIEW', @a['_status_access']
  end
end

# ── DCAttrsV3 folding ─────────────────────────────────────────────────────────
class TestDCAttrsFolding < Minitest::Test
  def test_even_panel_plus_90
    a = DCAttrsV3.folding(0, 496.5)
    assert_includes a['_onclick_formula'], ', 0, 90'
  end

  def test_odd_panel_minus_90
    a = DCAttrsV3.folding(1, 496.5)
    assert_includes a['_onclick_formula'], '-90'
  end

  def test_panel_4_plus_90
    a = DCAttrsV3.folding(4, 496.5)
    assert_includes a['_onclick_formula'], ', 0, 90'
    refute_includes a['_onclick_formula'], '-90'
  end
end

# ── DCAttrsV3 sliding master/slave ────────────────────────────────────────────
class TestDCAttrsSliding < Minitest::Test
  MASTER_NAME = 'NorthStar_Q_P1'.freeze

  def setup
    @master = DCAttrsV3.sliding_master(800.0, overlap: 50, master_name: MASTER_NAME)
    @slave2 = DCAttrsV3.sliding_slave(800.0, factor: 2, master_name: MASTER_NAME)
    @slave3 = DCAttrsV3.sliding_slave(800.0, factor: 3, master_name: MASTER_NAME)
  end

  def test_master_onclick_animates_status
    assert_match(/ANIMATE\("status"/, @master['_onclick_formula'])
  end

  def test_master_travel_750
    # (800 - 50) * -1 = -750
    assert_includes @master['_onclick_formula'], '-750'
  end

  def test_master_x_formula_is_status
    assert_equal 'status', @master['_x_formula']
  end

  def test_slave2_x_formula_references_master
    assert_includes @slave2['_x_formula'], MASTER_NAME
    assert_includes @slave2['_x_formula'], '* 2'
  end

  def test_slave3_x_formula_factor_3
    assert_includes @slave3['_x_formula'], '* 3'
  end

  def test_slave_has_no_onclick
    refute @slave2.key?('_onclick_formula')
  end

  def test_master_status_options_negative_travel
    assert_match(/-750/, @master['_status_options'])
  end
end

# ── Board parser ──────────────────────────────────────────────────────────────
class TestBoardParserV3 < Minitest::Test
  def setup
    @raw = [
      'Board', 501, 1, 1, 'P1_LS_Left',
      [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
      33, 2336, 34, 'Polyline',
      'LS立框', '客廳', '連動吊片'
    ]
    @boards = parse_boards_v3(@raw)
  end

  def test_parses_one_board
    assert_equal 1, @boards.size
  end

  def test_id
    assert_equal 501, @boards[0][:id]
  end

  def test_width
    assert_in_delta 33.0, @boards[0][:width], 0.001
  end

  def test_height
    assert_in_delta 2336.0, @boards[0][:height], 0.001
  end

  def test_thickness
    assert_in_delta 34.0, @boards[0][:thickness], 0.001
  end

  def test_name
    assert_equal 'LS立框', @boards[0][:name]
  end
end

# ── Part classification ────────────────────────────────────────────────────────
class TestClassifyPartV3 < Minitest::Test
  def test_ls_vertical_frame
    assert_equal :vertical_frame, classify_part_v3('LS立框')
  end

  def test_top_rail
    assert_equal :horizontal_frame, classify_part_v3('上橫檔')
  end

  def test_bottom_rail
    assert_equal :horizontal_frame, classify_part_v3('下橫檔')
  end

  def test_glass
    assert_equal :glass, classify_part_v3('長虹玻璃')
  end

  def test_clear_glass
    assert_equal :glass, classify_part_v3('清玻璃')
  end

  def test_roller
    assert_equal :hardware, classify_part_v3('連動吊片')
  end

  def test_divider
    assert_equal :divider, classify_part_v3('分隔條')
  end
end
