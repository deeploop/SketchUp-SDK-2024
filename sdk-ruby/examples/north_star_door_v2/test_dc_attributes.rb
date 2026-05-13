#!/usr/bin/env ruby
# test_dc_attributes.rb
#
# Pure-Ruby tests for the DC attribute formulas.
# No SDK dependency — requires only dc_attributes.rb and door_logic.rb.

require 'minitest/autorun'
require_relative 'door_logic'
require_relative 'dc_attributes'

# ── DC dictionary constant ────────────────────────────────────────────────────
class TestDCDictConstant < Minitest::Test
  def test_dict_name_is_dynamic_attributes
    assert_equal 'dynamic_attributes', DC_DICT
  end
end

# ── Pivot door definition attributes ─────────────────────────────────────────
class TestPivotDefAttrs < Minitest::Test
  def setup
    @attrs = NorthStar::DynamicComponent.pivot_def_attrs
  end

  def test_status_initial_value_is_zero_string
    assert_equal '0', @attrs['status']
  end

  def test_status_label_present
    assert_includes @attrs['_status_label'], '狀態'
  end

  def test_status_options_closed_and_open
    opts = @attrs['_status_options']
    assert_match(/關閉=0/, opts)
    assert_match(/開啟=90/, opts)
  end

  def test_status_access_is_view
    assert_equal 'VIEW', @attrs['_status_access']
  end

  def test_rotz_initial_zero
    assert_equal '0', @attrs['rotz']
  end

  def test_rotz_formula_is_status
    assert_equal 'status', @attrs['_rotz_formula']
  end

  def test_onclick_formula_animates_status
    assert_match(/ANIMATE\("status"/, @attrs['_onclick_formula'])
  end

  def test_onclick_formula_default_angle_90
    assert_includes @attrs['_onclick_formula'], ', 0, 90'
  end
end

class TestPivotDefAttrsCustomAngle < Minitest::Test
  def test_custom_rotation_360
    attrs = NorthStar::DynamicComponent.pivot_def_attrs(rotation_angle: 360)
    assert_includes attrs['_onclick_formula'], '360'
    assert_match(/開啟=360/, attrs['_status_options'])
  end
end

# ── Sync-Sliding door definition attributes ───────────────────────────────────
class TestSlidingDefAttrs < Minitest::Test
  def setup
    # panel_w=800, overlap=50, direction=-1 → travel = -750
    @attrs = NorthStar::DynamicComponent.sliding_def_attrs(800.0, direction: -1, overlap: 50)
  end

  def test_status_initial_zero
    assert_equal '0', @attrs['status']
  end

  def test_status_label_present
    refute_nil @attrs['_status_label']
  end

  def test_status_options_contains_negative_travel
    assert_match(/-750/, @attrs['_status_options'])
  end

  def test_x_initial_zero
    assert_equal '0', @attrs['x']
  end

  def test_x_formula_is_status
    assert_equal 'status', @attrs['_x_formula']
  end

  def test_onclick_formula_animates_status_with_negative_travel
    assert_match(/ANIMATE\("status"/, @attrs['_onclick_formula'])
    assert_includes @attrs['_onclick_formula'], '-750'
  end
end

class TestSlidingDefAttrsRightPanel < Minitest::Test
  def test_positive_travel_direction_1
    attrs = NorthStar::DynamicComponent.sliding_def_attrs(800.0, direction: 1, overlap: 50)
    assert_includes attrs['_onclick_formula'], '750'
    refute_includes attrs['_onclick_formula'], '-750'
  end

  def test_custom_overlap
    attrs = NorthStar::DynamicComponent.sliding_def_attrs(900.0, direction: -1, overlap: 80)
    assert_includes attrs['_onclick_formula'], '-820'
  end
end

# ── Folding door definition attributes ────────────────────────────────────────
class TestFoldingDefAttrs < Minitest::Test
  def test_even_panel_onclick_positive_90
    attrs = NorthStar::DynamicComponent.folding_def_attrs(0, 500.0)
    assert_includes attrs['_onclick_formula'], ', 0, 90'
    refute_includes attrs['_onclick_formula'], '-90'
  end

  def test_odd_panel_onclick_negative_90
    attrs = NorthStar::DynamicComponent.folding_def_attrs(1, 500.0)
    assert_includes attrs['_onclick_formula'], '-90'
  end

  def test_panel_2_positive_90
    attrs = NorthStar::DynamicComponent.folding_def_attrs(2, 500.0)
    assert_includes attrs['_onclick_formula'], ', 0, 90'
  end

  def test_panel_3_negative_90
    attrs = NorthStar::DynamicComponent.folding_def_attrs(3, 500.0)
    assert_includes attrs['_onclick_formula'], '-90'
  end

  def test_status_options_closed_open
    attrs = NorthStar::DynamicComponent.folding_def_attrs(0, 500.0)
    assert_match(/關閉=0/, attrs['_status_options'])
    assert_match(/開啟=90/, attrs['_status_options'])
  end

  def test_label_includes_panel_number
    attrs = NorthStar::DynamicComponent.folding_def_attrs(0, 500.0)
    assert_includes attrs['_status_label'], '1'
  end

  def test_status_initial_zero
    attrs = NorthStar::DynamicComponent.folding_def_attrs(0, 500.0)
    assert_equal '0', attrs['status']
  end

  def test_rotz_formula_is_status
    attrs = NorthStar::DynamicComponent.folding_def_attrs(0, 500.0)
    assert_equal 'status', attrs['_rotz_formula']
  end
end

# ── Translation matrix ────────────────────────────────────────────────────────
class TestDCTranslationMatrix < Minitest::Test
  def test_16_elements
    m = NorthStar::DynamicComponent.translation_matrix(0, 0, 0)
    assert_equal 16, m.size
  end

  def test_identity_diagonal
    m = NorthStar::DynamicComponent.translation_matrix(0, 0, 0)
    assert_in_delta 1.0, m[0],  0.001
    assert_in_delta 1.0, m[5],  0.001
    assert_in_delta 1.0, m[10], 0.001
    assert_in_delta 1.0, m[15], 0.001
  end

  def test_translation_components
    m = NorthStar::DynamicComponent.translation_matrix(100, 200, 300)
    assert_in_delta 100.0, m[12], 0.001
    assert_in_delta 200.0, m[13], 0.001
    assert_in_delta 300.0, m[14], 0.001
  end
end

# ── Integration with door_logic formulas ──────────────────────────────────────
class TestDCSlidingWithPanelWidth < Minitest::Test
  def test_panel_width_feeds_into_sliding_attrs
    pw    = Formulas.panel_width(1600.0, 2)  # = 800.0
    attrs = NorthStar::DynamicComponent.sliding_def_attrs(pw, direction: -1, overlap: 50)
    assert_includes attrs['_onclick_formula'], '-750'
  end
end

class TestDCPivotWithValidation < Minitest::Test
  def test_pivot_validates_ok
    boards = []
    params = { 'H' => 2300, 'L' => 900, 'PanelCount' => 1 }
    assert_nil Validator.validate!(boards, params, 'Pivot')
  rescue ValidationError => e
    flunk "Unexpected ValidationError: #{e.message}"
  end
end
