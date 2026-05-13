#!/usr/bin/env ruby
# test_dc_attributes.rb
#
# Pure-Ruby tests for the DC attribute formulas.
# No SDK dependency — requires only dc_attributes.rb and door_logic.rb.

require 'minitest/autorun'
require_relative 'door_logic'
require_relative 'dc_attributes'

class TestDCAttributesPivot < Minitest::Test
  def setup
    @attrs = NorthStar::DynamicComponent.pivot_attrs(900.0)
  end

  def test_name_present
    assert_includes @attrs['_name'], '旋轉門'
  end

  def test_status_dropdown
    assert_equal 'Closed|Open', @attrs['status']
  end

  def test_onclick_is_animate_rotz
    assert_match(/ANIMATE\("RotZ"/, @attrs['onclick'])
  end

  def test_onclick_default_angle_90
    assert_includes @attrs['onclick'], ', 0, 90'
  end

  def test_lenx_equals_panel_width
    assert_in_delta 900.0, @attrs['LenX'], 0.001
  end
end

class TestDCAttributesPivotCustom < Minitest::Test
  def test_custom_rotation_360
    attrs = NorthStar::DynamicComponent.pivot_attrs(700.0, rotation_angle: 360)
    assert_includes attrs['onclick'], '360'
  end

  def test_custom_axis_fraction_does_not_change_formula
    # axis_fraction is positional metadata only; ANIMATE key is RotZ
    attrs = NorthStar::DynamicComponent.pivot_attrs(900.0, axis_fraction: 0.5)
    assert_match(/RotZ/, attrs['onclick'])
  end
end

class TestDCAttributesSliding < Minitest::Test
  def setup
    # panel_w=800, overlap=50 → travel = 800-50 = 750, direction=-1 → -750
    @attrs = NorthStar::DynamicComponent.sliding_attrs(800.0, direction: -1, overlap: 50)
  end

  def test_name_present
    assert_includes @attrs['_name'], '連動懸吊門'
  end

  def test_status_dropdown
    assert_equal 'Closed|Open', @attrs['status']
  end

  def test_onclick_animates_x
    assert_match(/ANIMATE\("X"/, @attrs['onclick'])
  end

  def test_onclick_negative_travel_for_left_panel
    # direction=-1: panel slides left (negative X)
    assert_includes @attrs['onclick'], '-750'
  end

  def test_lenx_set
    assert_in_delta 800.0, @attrs['LenX'], 0.001
  end
end

class TestDCAttributesSlidingRightPanel < Minitest::Test
  def test_positive_travel_for_right_panel
    attrs = NorthStar::DynamicComponent.sliding_attrs(800.0, direction: 1, overlap: 50)
    assert_includes attrs['onclick'], '750'
    refute_includes attrs['onclick'], '-750'
  end

  def test_custom_overlap
    attrs = NorthStar::DynamicComponent.sliding_attrs(900.0, direction: -1, overlap: 80)
    # travel = 900 - 80 = 820
    assert_includes attrs['onclick'], '-820'
  end
end

class TestDCAttributesFolding < Minitest::Test
  def test_even_panel_positive_90
    attrs = NorthStar::DynamicComponent.folding_attrs(0, 500.0)
    assert_includes attrs['onclick'], ', 0, 90'
    refute_includes attrs['onclick'], '-90'
  end

  def test_odd_panel_negative_90
    attrs = NorthStar::DynamicComponent.folding_attrs(1, 500.0)
    assert_includes attrs['onclick'], '-90'
  end

  def test_panel_2_positive_90
    attrs = NorthStar::DynamicComponent.folding_attrs(2, 500.0)
    assert_includes attrs['onclick'], ', 0, 90'
    refute_includes attrs['onclick'], '-90'
  end

  def test_panel_3_negative_90
    attrs = NorthStar::DynamicComponent.folding_attrs(3, 500.0)
    assert_includes attrs['onclick'], '-90'
  end

  def test_name_includes_panel_number
    attrs = NorthStar::DynamicComponent.folding_attrs(0, 500.0)
    assert_includes attrs['_name'], '1'
  end

  def test_status_dropdown
    attrs = NorthStar::DynamicComponent.folding_attrs(0, 500.0)
    assert_equal 'Closed|Open', attrs['status']
  end

  def test_lenx_set
    attrs = NorthStar::DynamicComponent.folding_attrs(0, 450.0)
    assert_in_delta 450.0, attrs['LenX'], 0.001
  end
end

class TestDCTranslationMatrix < Minitest::Test
  def test_identity_translation
    m = NorthStar::DynamicComponent.translation_matrix(0, 0, 0)
    assert_equal 16, m.size
    assert_in_delta 1.0, m[0],  0.001   # scale X
    assert_in_delta 1.0, m[5],  0.001   # scale Y
    assert_in_delta 1.0, m[10], 0.001   # scale Z
    assert_in_delta 0.0, m[12], 0.001   # tx
  end

  def test_translation_values
    m = NorthStar::DynamicComponent.translation_matrix(100, 200, 300)
    assert_in_delta 100.0, m[12], 0.001
    assert_in_delta 200.0, m[13], 0.001
    assert_in_delta 300.0, m[14], 0.001
  end
end

class TestDCDictConstant < Minitest::Test
  def test_dict_name_is_dynamic_attributes
    assert_equal 'dynamic_attributes', DC_DICT
  end
end

class TestDCSlidingWithPanelCount < Minitest::Test
  # Integration: ensure Formulas.panel_width + DC attrs agree
  def test_panel_width_feeds_into_sliding_attrs
    total_w = 1600.0
    panels  = 2
    pw      = Formulas.panel_width(total_w, panels)
    attrs   = NorthStar::DynamicComponent.sliding_attrs(pw, direction: -1, overlap: 50)
    # pw = 800, travel = 750
    assert_includes attrs['onclick'], '-750'
  end
end

class TestDCPivotWithValidation < Minitest::Test
  def test_pivot_validates_ok_with_door_logic
    boards = []  # Pivot validator only produces warnings, no hard errors on empty boards
    params = { 'H' => 2300, 'L' => 900, 'PanelCount' => 1 }
    warnings = []
    assert_nil Validator.validate!(boards, params, 'Pivot')
  rescue ValidationError => e
    flunk "Unexpected ValidationError: #{e.message}"
  end
end
