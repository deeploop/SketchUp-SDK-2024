#!/usr/bin/env ruby
# test_frame_logic.rb
#
# Pure-Ruby unit tests for frame_logic.rb — no SDK or SketchUp required.

require 'minitest/autorun'
require_relative 'frame_logic'

# ── Profile constants ─────────────────────────────────────────────────────────
class TestProfileConstants < Minitest::Test
  def test_outer_profile_has_8_points
    assert_equal 8, OUTER_PROFILE_2D.size
  end

  def test_inner_profile_has_6_points
    assert_equal 6, INNER_PROFILE_2D.size
  end

  def test_outer_u_range_0_to_19
    us = OUTER_PROFILE_2D.map(&:first)
    assert_equal 0.0, us.min
    assert_equal 19.0, us.max
  end

  def test_outer_v_range_0_to_22
    vs = OUTER_PROFILE_2D.map(&:last)
    assert_equal 0.0, vs.min
    assert_equal 22.0, vs.max
  end

  def test_inner_u_range_1_5_to_17_5
    us = INNER_PROFILE_2D.map(&:first)
    assert_in_delta 1.5,  us.min, 0.001
    assert_in_delta 17.5, us.max, 0.001
  end

  def test_inner_v_range_1_5_to_20_5
    vs = INNER_PROFILE_2D.map(&:last)
    assert_in_delta 1.5,  vs.min, 0.001
    assert_in_delta 20.5, vs.max, 0.001
  end

  def test_profile_u_span
    assert_in_delta 19.0, PROFILE_U_SPAN, 0.001
  end

  def test_profile_v_span
    assert_in_delta 22.0, PROFILE_V_SPAN, 0.001
  end
end

# ── FrameGeometry.faces_per_rod ───────────────────────────────────────────────
class TestFacesPerRod < Minitest::Test
  def test_faces_per_rod_is_16
    # 2 end caps + 8 outer walls + 6 inner walls
    assert_equal 16, FrameGeometry.faces_per_rod
  end
end

# ── Bottom rod geometry ───────────────────────────────────────────────────────
class TestBottomRodGeometry < Minitest::Test
  def setup
    @faces = FrameGeometry.rod_face_data(role: :bottom, length: 800.0, frame_w: 800.0, frame_h: 1000.0)
  end

  def test_face_count
    assert_equal 16, @faces.size
  end

  def test_first_two_are_caps
    assert_equal CAP_WITH_HOLE, @faces[0][:type]
    assert_equal CAP_WITH_HOLE, @faces[1][:type]
  end

  def test_start_cap_at_x0
    cap = @faces[0]
    xs = cap[:outer_pts].map(&:first)
    assert xs.all? { |x| x.abs < 0.001 }, "Start cap outer pts must be at X=0"
    xs_i = cap[:inner_pts].map(&:first)
    assert xs_i.all? { |x| x.abs < 0.001 }, "Start cap inner pts must be at X=0"
  end

  def test_end_cap_at_x_length
    cap = @faces[1]
    xs = cap[:outer_pts].map(&:first)
    assert xs.all? { |x| (x - 800.0).abs < 0.001 }, "End cap pts must be at X=800"
  end

  def test_start_cap_outer_has_8_pts
    assert_equal 8, @faces[0][:outer_pts].size
  end

  def test_start_cap_inner_has_6_pts
    assert_equal 6, @faces[0][:inner_pts].size
  end

  def test_quads_have_4_points
    quads = @faces.select { |f| f[:type] == QUAD_FACE }
    assert quads.all? { |f| f[:pts].size == 4 }
  end

  def test_outer_quad_count
    quads = @faces.select { |f| f[:type] == QUAD_FACE }
    assert_equal 14, quads.size  # 8 outer + 6 inner
  end

  def test_profile_maps_u_to_y
    # First outer profile point: [0,0] → [0, 0, 0] at T=0
    first_outer = @faces[0][:outer_pts][0]
    assert_in_delta 0.0, first_outer[1], 0.001   # Y = U = 0
  end

  def test_profile_maps_v_to_z
    # Profile point [0,22] should map to Z=22
    last_outer = @faces[0][:outer_pts][-1]
    assert_in_delta 22.0, last_outer[2], 0.001   # Z = V = 22
  end

  def test_u_19_maps_to_y_19
    # Profile point [19,0] → [0, 19, 0]
    pt = @faces[0][:outer_pts][1]
    assert_in_delta 19.0, pt[1], 0.001
  end
end

# ── Top rod geometry ──────────────────────────────────────────────────────────
class TestTopRodGeometry < Minitest::Test
  H = 1000.0

  def setup
    @faces = FrameGeometry.rod_face_data(role: :top, length: 800.0, frame_w: 800.0, frame_h: H)
  end

  def test_face_count
    assert_equal 16, @faces.size
  end

  def test_cap_at_x0
    cap = @faces[0]
    xs = cap[:outer_pts].map(&:first)
    assert xs.all? { |x| x.abs < 0.001 }
  end

  def test_v0_maps_to_z_h
    # Profile V=0 → Z = H − 0 = H (top of frame)
    cap = @faces[0]
    # outer_pts[0] has V=0 → Z should be H
    pt = cap[:outer_pts][0]
    assert_in_delta H, pt[2], 0.001
  end

  def test_v22_maps_to_z_h_minus_22
    # Profile V=22 → Z = H − 22 (channel opens downward)
    cap = @faces[0]
    pt = cap[:outer_pts][-1]  # last point = [0,22]
    assert_in_delta H - 22.0, pt[2], 0.001
  end
end

# ── Left rod geometry ─────────────────────────────────────────────────────────
class TestLeftRodGeometry < Minitest::Test
  def setup
    @faces = FrameGeometry.rod_face_data(role: :left, length: 1000.0, frame_w: 800.0, frame_h: 1000.0)
  end

  def test_face_count
    assert_equal 16, @faces.size
  end

  def test_extrudes_along_z
    cap0 = @faces[0]
    cap1 = @faces[1]
    z0 = cap0[:outer_pts].map { |p| p[2] }.uniq
    z1 = cap1[:outer_pts].map { |p| p[2] }.uniq
    assert_equal [0.0], z0
    assert_equal [1000.0], z1
  end

  def test_v_maps_to_x
    # Profile [U=0, V=0] → proj(0, 0, 0) = [X=0, Y=0, Z=0]
    pt = @faces[0][:outer_pts][0]
    assert_in_delta 0.0, pt[0], 0.001   # X = V = 0
  end

  def test_u19_maps_to_y19
    # Profile [U=19, V=0] → proj(19, 0, 0) = [X=0, Y=19, Z=0]
    pt = @faces[0][:outer_pts][1]
    assert_in_delta 19.0, pt[1], 0.001  # Y = U = 19
  end
end

# ── Right rod geometry ────────────────────────────────────────────────────────
class TestRightRodGeometry < Minitest::Test
  W = 800.0

  def setup
    @faces = FrameGeometry.rod_face_data(role: :right, length: 1000.0, frame_w: W, frame_h: 1000.0)
  end

  def test_face_count
    assert_equal 16, @faces.size
  end

  def test_v0_maps_to_x_w
    # Profile V=0 → X = W − 0 = W (right edge of frame)
    pt = @faces[0][:outer_pts][0]
    assert_in_delta W, pt[0], 0.001
  end

  def test_u19_maps_to_y19_for_right_rod
    # Profile [U=19, V=0] → proj(19, 0, 0) = [X=W, Y=19, Z=0]
    # U=19 maps to Y=19; V=0 maps to X=W-0=W
    pt = @faces[0][:outer_pts][1]
    assert_in_delta 19.0, pt[1], 0.001  # Y = U = 19
  end
end

# ── Hinge positions ───────────────────────────────────────────────────────────
class TestHingePositions < Minitest::Test
  def test_three_hinges_returned
    lines = FrameGeometry.hinge_positions(800.0, 1000.0, [100.0, 500.0, 100.0])
    assert_equal 3, lines.size
  end

  def test_top_hinge_z_position
    lines = FrameGeometry.hinge_positions(800.0, 1000.0, [100.0, 500.0, 100.0])
    # from_top = 100 → Z = 1000 − 100 = 900
    assert_in_delta 900.0, lines[0][:start][2], 0.001
  end

  def test_middle_hinge_z_position
    lines = FrameGeometry.hinge_positions(800.0, 1000.0, [100.0, 500.0, 100.0])
    # Z = 1000 − 100 − 500 = 400
    assert_in_delta 400.0, lines[1][:start][2], 0.001
  end

  def test_bottom_hinge_z_position
    lines = FrameGeometry.hinge_positions(800.0, 1000.0, [100.0, 500.0, 100.0])
    # from_bottom = 100 → Z = 100
    assert_in_delta 100.0, lines[2][:start][2], 0.001
  end

  def test_hinge_spans_full_width
    lines = FrameGeometry.hinge_positions(800.0, 1000.0, [100.0, 500.0, 100.0])
    lines.each do |hl|
      assert_in_delta 0.0,   hl[:start][0],  0.001
      assert_in_delta 800.0, hl[:end_pt][0], 0.001
    end
  end

  def test_out_of_range_hinge_skipped
    # If offsets push a hinge below 0 or above H, it is excluded
    lines = FrameGeometry.hinge_positions(800.0, 1000.0, [100.0, 2000.0, 100.0])
    zs = lines.map { |l| l[:start][2] }
    assert zs.all? { |z| z >= 0.0 && z <= 1000.0 }
  end
end

# ── Validator ─────────────────────────────────────────────────────────────────
class TestFrameValidator < Minitest::Test
  VALID = { 'width' => 800, 'height' => 1000, 'hinges' => [100, 500, 100] }

  def test_valid_params_pass
    assert_nil FrameValidator.validate!(VALID)
  end

  def test_width_too_small
    p = VALID.merge('width' => 200)
    assert_raises(FrameValidationError) { FrameValidator.validate!(p) }
  end

  def test_width_too_large
    p = VALID.merge('width' => 4000)
    assert_raises(FrameValidationError) { FrameValidator.validate!(p) }
  end

  def test_height_too_small
    p = VALID.merge('height' => 300)
    assert_raises(FrameValidationError) { FrameValidator.validate!(p) }
  end

  def test_height_too_large
    p = VALID.merge('height' => 3500)
    assert_raises(FrameValidationError) { FrameValidator.validate!(p) }
  end

  def test_wrong_hinge_count
    p = VALID.merge('hinges' => [100, 500])
    assert_raises(FrameValidationError) { FrameValidator.validate!(p) }
  end

  def test_hinge_total_exceeds_height
    p = VALID.merge('hinges' => [400, 400, 400])
    assert_raises(FrameValidationError) { FrameValidator.validate!(p) }
  end

  def test_negative_hinge_fails
    p = VALID.merge('hinges' => [100, 500, -50])
    assert_raises(FrameValidationError) { FrameValidator.validate!(p) }
  end
end

# ── Material color presets ────────────────────────────────────────────────────
class TestMaterialColors < Minitest::Test
  def test_aluminum_color_exists
    assert FRAME_MATERIAL_COLORS.key?('aluminum')
    assert_equal 3, FRAME_MATERIAL_COLORS['aluminum'].size
  end

  def test_black_anodized_is_dark
    rgb = FRAME_MATERIAL_COLORS['black_anodized']
    assert rgb.all? { |v| v <= 60 }
  end

  def test_white_powder_is_light
    rgb = FRAME_MATERIAL_COLORS['white_powder']
    assert rgb.all? { |v| v >= 220 }
  end
end
