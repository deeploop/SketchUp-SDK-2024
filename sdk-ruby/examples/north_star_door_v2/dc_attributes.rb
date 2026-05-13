# dc_attributes.rb
#
# Dynamic Component attribute writer for North Star door types.
# No SDK dependency — pure-Ruby formula logic + constants.
#
# SketchUp DC engine reads these attribute dictionaries from the SKP file:
#   "dynamic_attributes"  — DC engine keys
#
# Canonical DC attribute names (SketchUp DC spec):
#   status            current state value (drives rotation)
#   _status_label     label in Component Options panel
#   _status_options   dropdown: "關閉=0&開啟=90" (key=value pairs, & separated)
#   _status_access    "VIEW" → user-visible in Component Options
#   rotz              current Z-rotation value (degrees)
#   _rotz_formula     formula string that drives rotz from status
#   _onclick_formula  ANIMATE formula executed on Interact-tool click
#
# These are written on the ComponentDefinition entity (the template),
# not on individual instances, so all copies share the behavior.

DC_DICT = 'dynamic_attributes'

module NorthStar
  module DynamicComponent

    # ── Pivot door (旋轉門) ─────────────────────────────────────────────────
    # rotation_angle: 90 for interior swing, 360 for full-spin demo
    def self.pivot_def_attrs(rotation_angle: 90)
      {
        'status'           => '0',
        '_status_label'    => '門扇狀態',
        "_status_options"  => "關閉=0&開啟=#{rotation_angle}",
        '_status_access'   => 'VIEW',
        'rotz'             => '0',
        '_rotz_formula'    => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{rotation_angle})"
      }
    end

    # ── Sync-Sliding door (連動懸吊) ────────────────────────────────────────
    # travel: distance the panel moves (negative = left)
    def self.sliding_def_attrs(panel_w, direction: -1, overlap: 50)
      travel = (panel_w - overlap) * direction
      {
        'status'           => '0',
        '_status_label'    => '門扇狀態',
        '_status_options'  => "關閉=0&開啟=#{travel.round(1)}",
        '_status_access'   => 'VIEW',
        'x'                => '0',
        '_x_formula'       => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{travel.round(1)})"
      }
    end

    # ── Folding door (折疊門) panel DC attrs ────────────────────────────────
    # Alternating ±90° pairs fold toward each other.
    def self.folding_def_attrs(panel_index, panel_w)
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

    # ── Write attribute hash onto a ComponentDefinition (template) ──────────
    # Call this on the definition so all instances share the DC behavior.
    def self.apply_to_definition(defn, attrs)
      attrs.each { |key, val| defn.set_attribute(DC_DICT, key, val) }
    end

    # ── Also stamp identifying DC info on the instance itself ───────────────
    # SketchUp allows instance-level overrides; we write the display name here.
    def self.apply_to_instance(instance, name_label, panel_w)
      instance.set_attribute(DC_DICT, '_name',   name_label)
      instance.set_attribute(DC_DICT, 'lenx',    panel_w.to_f)
    end

    # ── Build column-major translation matrix (identity + tx,ty,tz) ─────────
    def self.translation_matrix(tx, ty, tz)
      [1,0,0,0, 0,1,0,0, 0,0,1,0, tx.to_f, ty.to_f, tz.to_f, 1.0]
    end
  end
end
