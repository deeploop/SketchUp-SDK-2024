# frame_logic.rb
#
# Pure-Ruby geometry logic for the aluminum window/door frame builder.
# No SDK dependency — safe to require in plain Ruby for unit tests.
#
# Profile coordinate system (2D: [U, V] in mm):
#   U = cross-section "width" axis  (0..19 mm)
#   V = cross-section "depth" axis  (0..22 mm, into the wall)
#
# When extruded into 3D, U/V map onto world axes depending on rod role:
#   Bottom rod  →  U=Y (depth), V=Z (height),   extrusion along X
#   Top rod     →  U=Y (depth), V=H−Z (flipped), extrusion along X
#   Left rod    →  U=Y (depth), V=X (width),     extrusion along Z
#   Right rod   →  U=Y (depth), V=W−X (flipped), extrusion along Z

require 'json'

# ── Cross-section profiles (mm) ───────────────────────────────────────────────
# LS-series 19×22 aluminum channel profile.
OUTER_PROFILE_2D = [
  [ 0.0,  0.0], [19.0,  0.0], [19.0, 11.0], [17.5, 11.0],
  [17.5, 16.5], [19.0, 16.5], [19.0, 22.0], [ 0.0, 22.0]
].each { |pt| pt.each(&:freeze) }.freeze

INNER_PROFILE_2D = [
  [ 1.5,  1.5], [17.5,  1.5], [17.5,  9.5],
  [11.5,  9.5], [11.5, 20.5], [ 1.5, 20.5]
].each { |pt| pt.each(&:freeze) }.freeze

PROFILE_U_SPAN = 19.0  # mm — narrow face (visible frame width)
PROFILE_V_SPAN = 22.0  # mm — channel depth (into wall)

# ── Rod roles ─────────────────────────────────────────────────────────────────
ROD_ROLES = %i[bottom top left right].freeze

# Face-type constants used in returned face data.
CAP_WITH_HOLE = :cap_with_hole
QUAD_FACE     = :quad

# ── Frame geometry engine ─────────────────────────────────────────────────────
module FrameGeometry
  # Returns an array of face descriptors for one rod.
  #
  # role     — :bottom | :top | :left | :right
  # length   — mm (W for horizontal rods, H for vertical)
  # frame_w  — total opening width  (mm)
  # frame_h  — total opening height (mm)
  #
  # Each descriptor:
  #   { type: CAP_WITH_HOLE, outer_pts: [[x,y,z]...], inner_pts: [[x,y,z]...] }
  #   { type: QUAD_FACE,     pts:       [[x,y,z]×4] }
  def self.rod_face_data(role:, length:, frame_w:, frame_h:)
    proj = projector_for(role, frame_w, frame_h)

    outer = OUTER_PROFILE_2D
    inner = INNER_PROFILE_2D
    no    = outer.size   # 8
    ni    = inner.size   # 6

    faces = []

    # ── End caps (hollow — face with inner loop) ──────────────────────────────
    [0.0, length].each do |t|
      o_pts = outer.map { |u, v| proj.call(u, v, t) }
      i_pts = inner.map { |u, v| proj.call(u, v, t) }
      faces << { type: CAP_WITH_HOLE, outer_pts: o_pts, inner_pts: i_pts }
    end

    # ── Outer side walls ──────────────────────────────────────────────────────
    no.times do |i|
      j = (i + 1) % no
      u0, v0 = outer[i]
      u1, v1 = outer[j]
      faces << {
        type: QUAD_FACE,
        pts: [
          proj.call(u0, v0, 0.0),
          proj.call(u0, v0, length),
          proj.call(u1, v1, length),
          proj.call(u1, v1, 0.0)
        ]
      }
    end

    # ── Inner side walls (reversed winding so normal faces inward) ────────────
    ni.times do |i|
      j = (i + 1) % ni
      u0, v0 = inner[i]
      u1, v1 = inner[j]
      faces << {
        type: QUAD_FACE,
        pts: [
          proj.call(u0, v0, 0.0),
          proj.call(u1, v1, 0.0),
          proj.call(u1, v1, length),
          proj.call(u0, v0, length)
        ]
      }
    end

    faces
  end

  # Hinge guide-line positions (world-space start/end points).
  # hinges = [from_top_mm, span_mm, from_bottom_mm]
  def self.hinge_positions(frame_w, frame_h, hinges)
    z_positions = [
      frame_h - hinges[0],
      frame_h - hinges[0] - hinges[1],
      hinges[2]
    ]
    z_positions.select { |z| z >= 0.0 && z <= frame_h }.map do |z|
      { start: [0.0, 0.0, z], end_pt: [frame_w, 0.0, z] }
    end
  end

  # Face counts for verification
  def self.faces_per_rod
    2 +                       # 2 end caps
      OUTER_PROFILE_2D.size + # outer walls
      INNER_PROFILE_2D.size   # inner walls
  end

  private_class_method def self.projector_for(role, frame_w, frame_h)
    case role
    when :bottom
      # Extrude along X; U→Y, V→Z; origin at floor (Z=0)
      ->(u, v, t) { [t, u, v] }
    when :top
      # Extrude along X; U→Y, V→H−V (profile flipped, opens downward)
      ->(u, v, t) { [t, u, frame_h - v] }
    when :left
      # Extrude along Z; U→Y, V→X; origin at X=0
      ->(u, v, t) { [v, u, t] }
    when :right
      # Extrude along Z; U→Y, V→W−V (profile flipped, opens left)
      ->(u, v, t) { [frame_w - v, u, t] }
    else
      raise ArgumentError, "Unknown rod role: #{role.inspect}"
    end
  end
end

# ── Validator ─────────────────────────────────────────────────────────────────
module FrameValidator
  MIN_W = 300.0;  MAX_W = 3000.0
  MIN_H = 400.0;  MAX_H = 3000.0

  def self.validate!(params)
    errors = []
    w = params['width'].to_f
    h = params['height'].to_f

    errors << "Width #{w}mm < minimum #{MIN_W}mm"  if w < MIN_W
    errors << "Width #{w}mm > maximum #{MAX_W}mm"  if w > MAX_W
    errors << "Height #{h}mm < minimum #{MIN_H}mm" if h < MIN_H
    errors << "Height #{h}mm > maximum #{MAX_H}mm" if h > MAX_H

    hinges = (params['hinges'] || []).map(&:to_f)
    errors << "Need exactly 3 hinge offsets (from_top, span, from_bottom)" if hinges.size != 3
    errors << "All hinge values must be > 0" if hinges.any?(&:zero?) || hinges.any?(&:negative?)

    total_span = hinges[0].to_f + hinges[1].to_f + hinges[2].to_f
    errors << "Hinge total span #{total_span}mm exceeds frame height #{h}mm" if total_span > h

    raise FrameValidationError, errors.join('; ') unless errors.empty?
    nil
  end
end

class FrameValidationError < StandardError; end

# ── Material color presets ────────────────────────────────────────────────────
FRAME_MATERIAL_COLORS = {
  'aluminum'       => [180, 185, 190],
  'white_powder'   => [235, 235, 232],
  'black_anodized' => [40,  42,  45 ],
  'bronze'         => [100, 78,  45 ],
  'champagne'      => [210, 185, 130]
}.freeze
