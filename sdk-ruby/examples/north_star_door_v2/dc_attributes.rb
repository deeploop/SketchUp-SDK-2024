# dc_attributes.rb
#
# Dynamic Component attribute writer for North Star door types.
# No SDK dependency — pure-Ruby formula logic + constants.
# Geometry-writing code is in generate_dc_door.rb.
#
# SketchUp Dynamic Components read two attribute dictionaries:
#   "dynamic_attributes"   — formula/behaviour keys (DC engine reads these)
#   "SU_DefinitionSet"     — user-visible attribute set metadata
#
# Keys written on component instances:
#   _name         display name shown in Component Options panel
#   status        dropdown string attribute: "Closed|Open"
#   onclick       ANIMATE formula that DC engine executes on click
#   (axis keys)   LenX / LenY / LenZ / X / Y / Z / RotX / RotY / RotZ

DC_DICT = 'dynamic_attributes'

module NorthStar
  module DynamicComponent
    # ── Pivot door (旋轉門) ─────────────────────────────────────────────────
    # Rotates around a vertical axis at axis_fraction * panel_width from left.
    # rotation_angle is typically 90 (interior) or 360 (full spin demo).
    def self.pivot_attrs(panel_w, axis_fraction: 0.33, rotation_angle: 90)
      {
        '_name'   => '旋轉門 (Pivot Door)',
        'status'  => 'Closed|Open',
        'LenX'    => panel_w.to_f,
        'onclick' => "ANIMATE(\"RotZ\", 0, #{rotation_angle})"
      }
    end

    # ── Sync-Sliding door (連動懸吊) ────────────────────────────────────────
    # Each panel slides horizontally by (panel_width - overlap) mm.
    # overlap = how much panels stack; 50mm is a common North Star default.
    def self.sliding_attrs(panel_w, direction: -1, overlap: 50)
      travel = (panel_w - overlap) * direction
      {
        '_name'   => '連動懸吊門 (Sync Sliding)',
        'status'  => 'Closed|Open',
        'LenX'    => panel_w.to_f,
        'onclick' => "ANIMATE(\"X\", 0, #{travel.round(1)})"
      }
    end

    # ── Folding door (折疊門) panel attrs ───────────────────────────────────
    # Alternating panels rotate +90° / -90° (pairs fold toward each other).
    def self.folding_attrs(panel_index, panel_w)
      angle = panel_index.even? ? 90 : -90
      {
        '_name'   => "折疊門扇 #{panel_index + 1} (Folding Panel #{panel_index + 1})",
        'status'  => 'Closed|Open',
        'LenX'    => panel_w.to_f,
        'onclick' => "ANIMATE(\"RotZ\", 0, #{angle})"
      }
    end

    # ── Write attribute hash onto a ComponentInstance ───────────────────────
    def self.apply(instance, attrs)
      attrs.each { |key, val| instance.set_attribute(DC_DICT, key, val) }
    end

    # ── Build column-major translation matrix (identity + tx,ty,tz) ─────────
    def self.translation_matrix(tx, ty, tz)
      [1,0,0,0, 0,1,0,0, 0,0,1,0, tx.to_f, ty.to_f, tz.to_f, 1.0]
    end
  end
end
