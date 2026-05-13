#!/usr/bin/env ruby
# sketchup_console_dc_door.rb
#
# 北二高 (North Star) 動態門生成器 — SketchUp Ruby Console 版本
#
# 使用方法：
#   1. 開啟 SketchUp
#   2. 視窗 (Window) → Ruby 主控台 (Ruby Console)
#   3. 貼上此完整腳本，按 Enter
#
# 效果：
#   - 依 JSON 設定生成門扇幾何體
#   - 寫入 dynamic_attributes 字典（status / _onclick_formula 等）
#   - 調用 $dc_observers 使動態組件立即生效
#   - 在「組件選項」面板可見「門扇狀態」下拉選單（關閉 / 開啟）
#   - 使用工具列「互動 (Interact)」工具點擊門扇即可播放動畫

require 'json'

module NorthStarDC

  # ── 門型設定 ──────────────────────────────────────────────────────────────
  # 修改此 Hash 即可切換門型
  CONFIG = {
    system_type:    'Pivot',        # 'Pivot' | 'Sync_Sliding' | 'Folding'
    total_w:        900.0,          # mm — 開口總寬
    total_h:        2300.0,         # mm — 開口總高
    panel_count:    1,
    frame_w:        33.0,           # LS 框寬 mm
    frame_depth:    34.0,           # LS 框深 mm
    glass_thick:    5.0,
    glass_y_offset: 14.5,           # 玻璃在框內的 Y 偏移 mm
    rotation_angle: 90,             # 旋轉門/折疊門的開啟角度
    overlap:        50.0,           # 連動門面板重疊量 mm
    frame_color:    [45,  45,  48], # 黑砂色
    glass_color:    [200, 220, 230],
    glass_alpha:    0.55
  }.freeze

  # 北二高型錄高度扣除公式（mm）
  HEIGHT_DEDUCTIONS = {
    'Pivot'        => 31,
    'Sync_Sliding' => 64,
    'Folding'      => 64
  }.freeze

  DC_DICT = 'dynamic_attributes'.freeze

  # ── 主要入口 ──────────────────────────────────────────────────────────────
  def self.generate(cfg = CONFIG)
    model = Sketchup.active_model
    model.start_operation('北二高動態門', true)

    entities  = model.active_entities
    materials = model.materials

    system  = cfg[:system_type]
    total_w = cfg[:total_w]
    total_h = cfg[:total_h]
    n       = [cfg[:panel_count], 1].max
    frame_h = total_h - HEIGHT_DEDUCTIONS.fetch(system, 64)
    panel_w = total_w.to_f / n
    fw      = cfg[:frame_w]
    fd      = cfg[:frame_depth]

    frame_mat = materials.add("LS_Frame_#{system}")
    frame_mat.color = Sketchup::Color.new(*cfg[:frame_color])

    glass_mat = materials.add("Glass_#{system}")
    glass_mat.color = Sketchup::Color.new(*cfg[:glass_color])
    glass_mat.alpha = cfg[:glass_alpha]

    n.times do |pi|
      base_x = pi * panel_w

      defn = model.definitions.add("NorthStar_#{system}_P#{pi + 1}")
      de   = defn.entities

      # ── 幾何體（依 LS 框型尺寸）────────────────────────────────────────
      # 左立框
      add_box(de, base_x,               0, 0,            fw,               frame_h, fd, frame_mat)
      # 右立框
      add_box(de, base_x + panel_w - fw, 0, 0,            fw,               frame_h, fd, frame_mat)
      # 上橫檔
      add_box(de, base_x + fw,          0, frame_h - fw,  panel_w - 2 * fw, fw,      fd, frame_mat)
      # 下橫檔
      add_box(de, base_x + fw,          0, 0,             panel_w - 2 * fw, fw,      fd, frame_mat)
      # 玻璃（5mm 厚）
      inner_w = panel_w - 2 * fw
      glass_z = fw + 15
      glass_h = frame_h - 2 * fw - 30
      add_box(de, base_x + fw, cfg[:glass_y_offset], glass_z, inner_w, glass_h, cfg[:glass_thick], glass_mat)

      # ── Dynamic Component 屬性寫入 Definition ──────────────────────────
      # SketchUp DC 引擎從 Definition 的 'dynamic_attributes' 字典讀取範本
      write_dc_template(defn, system, pi, panel_w, cfg)

      # ── 放置 Instance ──────────────────────────────────────────────────
      t    = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 0))
      inst = entities.add_instance(defn, t)

      # Instance 層級覆寫：顯示名稱 + 面板寬度
      inst.set_attribute DC_DICT, '_name',  "#{system} 門扇 #{pi + 1}"
      inst.set_attribute DC_DICT, 'lenx',   panel_w.to_f
    end

    # ── 觸發 DC 觀察者使動畫立即生效 ────────────────────────────────────
    # $dc_observers 只在 SketchUp 內部環境中存在
    if defined?($dc_observers)
      first_inst = entities.grep(Sketchup::ComponentInstance).first
      $dc_observers.get_latest_class.redraw_with_undo(first_inst) if first_inst
    end

    model.commit_operation
    puts "✓ 北二高 #{system} 門生成完畢！"
    puts "  → 使用「互動」工具點擊門扇可播放開/關動畫"
    puts "  → 右鍵 → 動態組件 → 組件選項，可見「門扇狀態」下拉選單"
  rescue => e
    model.abort_operation
    puts "✗ 生成失敗：#{e.message}"
    raise
  end

  # ── 寫入 DC 範本屬性 ────────────────────────────────────────────────────
  # 屬性寫在 ComponentDefinition 上（範本層），所有 Instance 繼承
  def self.write_dc_template(defn, system, panel_index, panel_w, cfg)
    case system

    when 'Pivot'
      angle = cfg[:rotation_angle]
      attrs = {
        'status'           => '0',
        '_status_label'    => '門扇狀態',
        '_status_options'  => "關閉=0&開啟=#{angle}",
        '_status_access'   => 'VIEW',
        'rotz'             => '0',
        '_rotz_formula'    => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{angle})"
      }

    when 'Sync_Sliding'
      dir    = panel_index.even? ? -1 : 1
      travel = (panel_w - cfg[:overlap]) * dir
      attrs = {
        'status'           => '0',
        '_status_label'    => '門扇狀態',
        '_status_options'  => "關閉=0&開啟=#{travel.round(1)}",
        '_status_access'   => 'VIEW',
        'x'                => '0',
        '_x_formula'       => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{travel.round(1)})"
      }

    when 'Folding'
      angle = panel_index.even? ? 90 : -90
      attrs = {
        'status'           => '0',
        '_status_label'    => "折疊扇 #{panel_index + 1} 狀態",
        '_status_options'  => "關閉=0&開啟=#{angle}",
        '_status_access'   => 'VIEW',
        'rotz'             => '0',
        '_rotz_formula'    => 'status',
        '_onclick_formula' => "ANIMATE(\"status\", 0, #{angle})"
      }

    else
      attrs = {
        'status'           => '0',
        '_onclick_formula' => 'ANIMATE("status", 0, 90)'
      }
    end

    attrs.each { |key, val| defn.set_attribute(DC_DICT, key, val) }
  end
  private_class_method :write_dc_template

  # ── 六面體（6 個四邊形面） ──────────────────────────────────────────────
  # 所有尺寸為 mm；.mm 轉為 SketchUp 內部單位（英寸）
  def self.add_box(ents, x, y, z, w, h, d, mat)
    p = [
      [x,   y,   z  ], [x+w, y,   z  ], [x+w, y+d, z  ], [x,   y+d, z  ],
      [x,   y,   z+h], [x+w, y,   z+h], [x+w, y+d, z+h], [x,   y+d, z+h]
    ].map { |pt| pt.map { |v| v.mm } }

    [
      [p[0], p[1], p[2], p[3]], # 底
      [p[4], p[7], p[6], p[5]], # 頂
      [p[0], p[4], p[5], p[1]], # 前
      [p[3], p[2], p[6], p[7]], # 後
      [p[0], p[3], p[7], p[4]], # 左
      [p[1], p[5], p[6], p[2]]  # 右
    ].each do |quad|
      face = ents.add_face(quad)
      next unless face
      face.material      = mat
      face.back_material = mat
    end
  end
  private_class_method :add_box

end

# ── 執行 ──────────────────────────────────────────────────────────────────────
NorthStarDC.generate
