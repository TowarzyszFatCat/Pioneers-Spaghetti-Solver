class_name SaveImporter
extends RefCounted

const MAP_DATA_JSON_PATHS := [
	"res://data/map_data_slim.json",
	"res://map_data_slim.json",
	"res://data/map_data.json"
]
const MAP_META_JSON_PATHS := [
	"res://data/map_markers_meta.json",
	"res://map_markers_meta.json"
]
const CALIBRATION_SAVE_PATH := "user://map_calibration.json"
const CHECKED_SAVE_PATH := "user://map_checked.json"

var world_x_min_m: float = -3246.0
var world_x_max_m: float = 4253.0
var world_y_min_m: float = -3750.0
var world_y_max_m: float = 3750.0

var COLLECTIBLES: Array = []
var SCIM_TYPE_TO_KEY: Dictionary = {}
var SLIM_SLUG_TO_KEY: Dictionary = {}
var ICON_NAMES: Dictionary = {}
var SCIM_PURITY_TO_MULT: Dictionary = {}

var deposits: Dictionary = {
	"iron-ore": [], "copper-ore": [], "limestone": [], "coal": [],
	"caterium-ore": [], "crude-oil": [], "sulfur": [], "bauxite": [],
	"raw-quartz": [], "uranium": [], "sam": [], "nitrogen-gas": [], "water": [],
	"hard-drive": [], "blue-slug": [], "yellow-slug": [], "purple-slug": [],
	"mercer-sphere": [], "somersloop": []
}

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n

var show_markers: bool = true
var hide_checked: bool = false
var show_impure: bool = true
var show_normal: bool = true
var show_pure: bool = true
var marker_size_mult: float = 1.0
var enabled_resources: Dictionary = {}
var hovered_deposit: Dictionary = {}
var checked_markers: Dictionary = {}

var marker_window: Window
var res_checkboxes: Dictionary = {}
var _spin_xmin: SpinBox
var _spin_xmax: SpinBox
var _spin_ymin: SpinBox
var _spin_ymax: SpinBox
var _icons_cache: Dictionary = {}
var _ui_refs: Dictionary = {}

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	_load_markers_meta_json()
	_load_calibration()
	_load_checked()
	_load_scim_map_data_json()
	for k in deposits.keys():
		if k in ["iron-ore", "copper-ore", "coal", "limestone"]:
			enabled_resources[k] = true
		else:
			enabled_resources[k] = false

func _load_markers_meta_json() -> void:
	for p in MAP_META_JSON_PATHS:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f == null:
				continue
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				COLLECTIBLES = parsed.get("collectibles", [])
				SCIM_TYPE_TO_KEY = parsed.get("scim_type_to_key", {})
				SLIM_SLUG_TO_KEY = parsed.get("slim_slug_to_key", {})
				ICON_NAMES = parsed.get("icon_names", {})
				SCIM_PURITY_TO_MULT = parsed.get("scim_purity_to_mult", {})
				return

func _get_marker_id(res_key: String, x_m: float, y_m: float) -> String:
	return "%s_%d_%d" % [res_key, int(x_m), int(y_m)]

func _load_checked() -> void:
	if FileAccess.file_exists(CHECKED_SAVE_PATH):
		var f := FileAccess.open(CHECKED_SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			checked_markers = parsed

func _save_checked() -> void:
	var f := FileAccess.open(CHECKED_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(checked_markers))

func _get_display_name(res_key: String) -> String:
	var en_fallback: String = String(ICON_NAMES.get(res_key, res_key))
	if i18n != null:
		return i18n.t_item(res_key, en_fallback)
	if db != null and db.has_method("get_item_display_name"):
		return db.get_item_display_name(res_key)
	return en_fallback

func _get_marker_color(res_key: String) -> Color:
	if db != null and db.has_method("get_item_color"):
		return db.get_item_color(res_key)
	return Color.WHITE

func _get_custom_icon(res_key: String) -> Texture2D:
	if _icons_cache.has(res_key):
		return _icons_cache[res_key]
	var file_name: String = String(ICON_NAMES.get(res_key, res_key))
	var path := "res://data/icons/%s.png" % file_name
	var fallback_path := "res://data/icons/%s.png" % res_key
	if ResourceLoader.exists(path):
		_icons_cache[res_key] = load(path) as Texture2D
		return _icons_cache[res_key]
	elif ResourceLoader.exists(fallback_path):
		_icons_cache[res_key] = load(fallback_path) as Texture2D
		return _icons_cache[res_key]
	if res_key == "sam" and ResourceLoader.exists("res://data/icons/SAM Ore.png"):
		_icons_cache[res_key] = load("res://data/icons/SAM Ore.png") as Texture2D
		return _icons_cache[res_key]
	if db != null and db.has_method("get_icon_texture"):
		var tex = db.get_icon_texture(res_key)
		if tex != null:
			_icons_cache[res_key] = tex
			return tex
	return null

func _load_scim_map_data_json() -> void:
	var loaded_path := ""
	for p in MAP_DATA_JSON_PATHS:
		if FileAccess.file_exists(p):
			loaded_path = p
			break
	if loaded_path == "":
		return
	var f := FileAccess.open(loaded_path, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	for k in deposits.keys():
		deposits[k].clear()

	if parsed is Array:
		for item in parsed:
			if not (item is Dictionary):
				continue
			var slug := String(item.get("slug", ""))
			if not SLIM_SLUG_TO_KEY.has(slug):
				continue
			var map_data: Array = SLIM_SLUG_TO_KEY[slug]
			var item_key: String = String(map_data[0])
			var purity: float = float(map_data[1])
			var is_well: bool = bool(map_data[2])
			for c in item.get("coords", []):
				if c is Array and c.size() >= 2:
					var xm := float(c[0]) / 100.0
					var ym := float(c[1]) / 100.0
					deposits[item_key].append([xm, ym, purity, is_well, _get_marker_id(item_key, xm, ym)])
		return

	if parsed is Dictionary and parsed.has("options"):
		for tab in parsed["options"]:
			if not (tab is Dictionary):
				continue
			var tab_id := String(tab.get("tabId", ""))
			if tab_id != "resource_nodes" and tab_id != "resource_wells":
				continue
			var is_well := (tab_id == "resource_wells")
			for res_group in tab.get("options", []):
				if not (res_group is Dictionary):
					continue
				var group_type := String(res_group.get("type", ""))
				for purity_layer in res_group.get("options", []):
					if not (purity_layer is Dictionary):
						continue
					var layer_purity := String(purity_layer.get("purity", "RP_Normal"))
					for m in purity_layer.get("markers", []):
						if not (m is Dictionary) or not m.has("x") or not m.has("y"):
							continue
						var m_type := String(m.get("type", group_type))
						if not SCIM_TYPE_TO_KEY.has(m_type):
							continue
						var item_key: String = String(SCIM_TYPE_TO_KEY[m_type])
						var pur := float(SCIM_PURITY_TO_MULT.get(String(m.get("purity", layer_purity)), 1.0))
						var xm := float(m["x"]) / 100.0
						var ym := float(m["y"]) / 100.0
						deposits[item_key].append([xm, ym, pur, is_well, _get_marker_id(item_key, xm, ym)])

func _load_calibration() -> void:
	if FileAccess.file_exists(CALIBRATION_SAVE_PATH):
		var f := FileAccess.open(CALIBRATION_SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			world_x_min_m = float(parsed.get("x_min", world_x_min_m))
			world_x_max_m = float(parsed.get("x_max", world_x_max_m))
			world_y_min_m = float(parsed.get("y_min", world_y_min_m))
			world_y_max_m = float(parsed.get("y_max", world_y_max_m))

func _save_calibration() -> void:
	var f := FileAccess.open(CALIBRATION_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"x_min": world_x_min_m, "x_max": world_x_max_m,
			"y_min": world_y_min_m, "y_max": world_y_max_m
		}, "\t"))

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	marker_window = Window.new()
	marker_window.theme = theme_ref
	marker_window.size = Vector2i(1000, 600)
	marker_window.visible = false
	marker_window.close_requested.connect(func(): marker_window.hide())
	parent_layer.add_child(marker_window)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker_window.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	var master_chk := CheckBox.new()
	master_chk.button_pressed = show_markers
	master_chk.modulate = Color.SPRING_GREEN
	master_chk.toggled.connect(func(v: bool):
		show_markers = v
		main_ctrl.queue_redraw()
	)
	top_row.add_child(master_chk)
	_ui_refs["master_chk"] = master_chk

	var hide_chk := CheckBox.new()
	hide_chk.button_pressed = hide_checked
	hide_chk.modulate = Color(0.7, 0.7, 0.7)
	hide_chk.toggled.connect(func(v: bool):
		hide_checked = v
		main_ctrl.queue_redraw()
	)
	top_row.add_child(hide_chk)
	_ui_refs["hide_chk"] = hide_chk

	var sz_lbl := Label.new()
	sz_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sz_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(sz_lbl)
	_ui_refs["sz_lbl"] = sz_lbl

	var sz_slider := HSlider.new()
	sz_slider.min_value = 0.5
	sz_slider.max_value = 2.5
	sz_slider.step = 0.1
	sz_slider.value = marker_size_mult
	sz_slider.custom_minimum_size = Vector2(150, 0)
	sz_slider.value_changed.connect(func(v: float):
		marker_size_mult = v
		main_ctrl.queue_redraw()
	)
	top_row.add_child(sz_slider)
	vbox.add_child(top_row)

	var pur_row := HBoxContainer.new()
	pur_row.add_theme_constant_override("separation", 16)
	var p_lbl := Label.new()
	pur_row.add_child(p_lbl)
	_ui_refs["p_lbl"] = p_lbl

	var imp_chk := CheckBox.new()
	imp_chk.button_pressed = show_impure
	imp_chk.modulate = Color.SALMON
	imp_chk.toggled.connect(func(v: bool): show_impure = v; main_ctrl.queue_redraw())
	pur_row.add_child(imp_chk)
	_ui_refs["imp_chk"] = imp_chk

	var norm_chk := CheckBox.new()
	norm_chk.button_pressed = show_normal
	norm_chk.modulate = Color.LIGHT_SKY_BLUE
	norm_chk.toggled.connect(func(v: bool): show_normal = v; main_ctrl.queue_redraw())
	pur_row.add_child(norm_chk)
	_ui_refs["norm_chk"] = norm_chk

	var pure_chk := CheckBox.new()
	pure_chk.button_pressed = show_pure
	pure_chk.modulate = Color.SPRING_GREEN
	pure_chk.toggled.connect(func(v: bool): show_pure = v; main_ctrl.queue_redraw())
	pur_row.add_child(pure_chk)
	_ui_refs["pure_chk"] = pure_chk
	vbox.add_child(pur_row)

	vbox.add_child(HSeparator.new())

	var cal_hdr := HBoxContainer.new()
	var cal_lbl := Label.new()
	cal_lbl.modulate = Color.AQUAMARINE
	cal_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cal_hdr.add_child(cal_lbl)
	_ui_refs["cal_lbl"] = cal_lbl

	var preset_1_btn := Button.new()
	preset_1_btn.pressed.connect(func(): _apply_bounds_preset(-3246.0, 4253.0, -3750.0, 3750.0))
	cal_hdr.add_child(preset_1_btn)
	_ui_refs["preset_1_btn"] = preset_1_btn
	vbox.add_child(cal_hdr)

	var cal_grid := GridContainer.new()
	cal_grid.columns = 4
	cal_grid.add_theme_constant_override("h_separation", 10)
	cal_grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(cal_grid)

	var xm1 := _make_bound_spin("", world_x_min_m, func(v: float): world_x_min_m = v)
	var xm2 := _make_bound_spin("", world_x_max_m, func(v: float): world_x_max_m = v)
	var ym1 := _make_bound_spin("", world_y_min_m, func(v: float): world_y_min_m = v)
	var ym2 := _make_bound_spin("", world_y_max_m, func(v: float): world_y_max_m = v)
	_ui_refs["xmin_lbl"] = xm1[0]; _ui_refs["xmax_lbl"] = xm2[0]
	_ui_refs["ymin_lbl"] = ym1[0]; _ui_refs["ymax_lbl"] = ym2[0]
	_spin_xmin = xm1[1] as SpinBox; _spin_xmax = xm2[1] as SpinBox
	_spin_ymin = ym1[1] as SpinBox; _spin_ymax = ym2[1] as SpinBox
	for ctrl in [xm1[0], xm1[1], xm2[0], xm2[1], ym1[0], ym1[1], ym2[0], ym2[1]]:
		cal_grid.add_child(ctrl)

	vbox.add_child(HSeparator.new())

	var res_hdr := HBoxContainer.new()
	var res_title := Label.new()
	res_title.add_theme_font_size_override("font_size", 14)
	res_title.modulate = Color(0.8, 0.9, 1.0)
	res_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_hdr.add_child(res_title)
	_ui_refs["res_title"] = res_title

	var res_all_btn := Button.new()
	res_all_btn.pressed.connect(func():
		for k in res_checkboxes.keys():
			if not (k in COLLECTIBLES):
				res_checkboxes[k].button_pressed = true
				enabled_resources[k] = true
		main_ctrl.queue_redraw()
	)
	res_hdr.add_child(res_all_btn)
	_ui_refs["res_all_btn"] = res_all_btn

	var res_none_btn := Button.new()
	res_none_btn.pressed.connect(func():
		for k in res_checkboxes.keys():
			if not (k in COLLECTIBLES):
				res_checkboxes[k].button_pressed = false
				enabled_resources[k] = false
		main_ctrl.queue_redraw()
	)
	res_hdr.add_child(res_none_btn)
	_ui_refs["res_none_btn"] = res_none_btn
	vbox.add_child(res_hdr)

	var res_grid := GridContainer.new()
	res_grid.columns = 4
	res_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_grid.add_theme_constant_override("h_separation", 16)
	res_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(res_grid)

	vbox.add_child(HSeparator.new())

	var col_hdr := HBoxContainer.new()
	var col_title := Label.new()
	col_title.add_theme_font_size_override("font_size", 14)
	col_title.modulate = Color(1.0, 0.85, 0.4)
	col_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_hdr.add_child(col_title)
	_ui_refs["col_title"] = col_title

	var col_all_btn := Button.new()
	col_all_btn.pressed.connect(func():
		for k in res_checkboxes.keys():
			if k in COLLECTIBLES:
				res_checkboxes[k].button_pressed = true
				enabled_resources[k] = true
		main_ctrl.queue_redraw()
	)
	col_hdr.add_child(col_all_btn)
	_ui_refs["col_all_btn"] = col_all_btn

	var col_none_btn := Button.new()
	col_none_btn.pressed.connect(func():
		for k in res_checkboxes.keys():
			if k in COLLECTIBLES:
				res_checkboxes[k].button_pressed = false
				enabled_resources[k] = false
		main_ctrl.queue_redraw()
	)
	col_hdr.add_child(col_none_btn)
	_ui_refs["col_none_btn"] = col_none_btn
	vbox.add_child(col_hdr)

	var col_grid := GridContainer.new()
	col_grid.columns = 4
	col_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_grid.add_theme_constant_override("h_separation", 16)
	col_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(col_grid)

	for res_key in deposits.keys():
		var list: Array = deposits[res_key]
		if list.is_empty():
			continue
		var chk := CheckBox.new()
		chk.button_pressed = enabled_resources.get(res_key, false)
		chk.icon = _get_custom_icon(res_key)
		chk.expand_icon = true
		chk.add_theme_constant_override("icon_max_width", 24)
		chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chk.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chk.modulate = _get_marker_color(res_key).lightened(0.35)
		var rk_copy: String = res_key
		chk.toggled.connect(func(v: bool):
			enabled_resources[rk_copy] = v
			main_ctrl.queue_redraw()
		)
		if res_key in COLLECTIBLES:
			col_grid.add_child(chk)
		else:
			res_grid.add_child(chk)
		res_checkboxes[res_key] = chk

	var tip_lbl := Label.new()
	tip_lbl.modulate = Color(0.75, 0.88, 1.0, 0.85)
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tip_lbl)
	_ui_refs["tip_lbl"] = tip_lbl

	refresh_translations()
	return marker_window

func refresh_translations() -> void:
	if marker_window == null or _ui_refs.is_empty():
		return
	marker_window.title = i18n.t("markers_win_title")
	_ui_refs["master_chk"].text = i18n.t("markers_show")
	_ui_refs["hide_chk"].text = i18n.t("markers_hide_used")
	_ui_refs["sz_lbl"].text = i18n.t("markers_size")
	_ui_refs["p_lbl"].text = i18n.t("markers_purities")
	_ui_refs["imp_chk"].text = i18n.t("markers_impure_opt")
	_ui_refs["norm_chk"].text = i18n.t("markers_normal_opt")
	_ui_refs["pure_chk"].text = i18n.t("markers_pure_opt")
	_ui_refs["cal_lbl"].text = i18n.t("markers_bounds_hdr")
	_ui_refs["preset_1_btn"].text = i18n.t("markers_ingame_preset")
	_ui_refs["xmin_lbl"].text = i18n.t("markers_xmin")
	_ui_refs["xmax_lbl"].text = i18n.t("markers_xmax")
	_ui_refs["ymin_lbl"].text = i18n.t("markers_ymin")
	_ui_refs["ymax_lbl"].text = i18n.t("markers_ymax")
	_ui_refs["res_title"].text = i18n.t("markers_ores_hdr")
	_ui_refs["res_all_btn"].text = i18n.t("markers_show_all")
	_ui_refs["res_none_btn"].text = i18n.t("markers_hide_all")
	_ui_refs["col_title"].text = i18n.t("markers_col_hdr")
	_ui_refs["col_all_btn"].text = i18n.t("markers_show_all")
	_ui_refs["col_none_btn"].text = i18n.t("markers_hide_all")
	_ui_refs["tip_lbl"].text = i18n.t("markers_tip")
	for res_key in res_checkboxes.keys():
		var chk: CheckBox = res_checkboxes[res_key]
		var list: Array = deposits.get(res_key, [])
		chk.text = "%s (%d)" % [_get_display_name(res_key), list.size()]

func _apply_bounds_preset(xmin: float, xmax: float, ymin: float, ymax: float) -> void:
	world_x_min_m = xmin; world_x_max_m = xmax; world_y_min_m = ymin; world_y_max_m = ymax
	if _spin_xmin: _spin_xmin.value = xmin
	if _spin_xmax: _spin_xmax.value = xmax
	if _spin_ymin: _spin_ymin.value = ymin
	if _spin_ymax: _spin_ymax.value = ymax
	_save_calibration()
	main_ctrl.queue_redraw()

func _make_bound_spin(label_txt: String, init_val: float, on_change: Callable) -> Array[Control]:
	var lbl := Label.new()
	lbl.text = label_txt
	var sp := SpinBox.new()
	sp.min_value = -20000.0
	sp.max_value = 20000.0
	sp.step = 10.0
	sp.value = init_val
	sp.suffix = "m"
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.value_changed.connect(func(v: float):
		on_change.call(v)
		_save_calibration()
		main_ctrl.queue_redraw()
	)
	return [lbl, sp]

func meters_to_world_pos(x_m: float, y_m: float) -> Vector2:
	var tex_size := Vector2(8192.0, 8192.0)
	if main_ctrl.map_texture != null:
		tex_size = main_ctrl.map_texture.get_size()
	var scaled_size := tex_size * settings.map_scale
	var u := (x_m - world_x_min_m) / maxf(1.0, world_x_max_m - world_x_min_m)
	var v := (y_m - world_y_min_m) / maxf(1.0, world_y_max_m - world_y_min_m)
	return Vector2(u * scaled_size.x, v * scaled_size.y)

func _is_purity_visible(pur: float) -> bool:
	if pur < 0.75:
		return show_impure
	elif pur > 1.5:
		return show_pure
	return show_normal

func _get_purity_ring_color(pur: float) -> Color:
	if pur > 1.5:
		return Color(0.25, 0.98, 0.55)
	elif pur < 0.75:
		return Color(0.95, 0.45, 0.35)
	return Color(0.45, 0.82, 1.0)

func handle_map_input(event: InputEvent) -> bool:
	if not show_markers or main_ctrl.active_graph != main_ctrl:
		return false
	if main_ctrl.grid_planner != null and main_ctrl.grid_planner.visible:
		return false
	if event is InputEventMouseMotion:
		var hit := _pick_marker_at(event.position)
		if hit != hovered_deposit:
			hovered_deposit = hit
			main_ctrl.queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		var hit := _pick_marker_at(event.position)
		if not hit.is_empty():
			_spawn_miner_on_deposit(hit)
			return true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var old_hide := hide_checked
		hide_checked = false
		var hit := _pick_marker_at(event.position)
		hide_checked = old_hide
		if not hit.is_empty():
			var m_id := _get_marker_id(hit["resource"], hit["x_m"], hit["y_m"])
			if checked_markers.has(m_id):
				checked_markers.erase(m_id)
			else:
				checked_markers[m_id] = true
			_save_checked()
			main_ctrl.queue_redraw()
			return true
	return false

func _pick_marker_at(screen_pos: Vector2) -> Dictionary:
	var z := main_ctrl.zoom
	var scroll := main_ctrl.scroll_offset
	var hit_radius := clampf(14.0 * sqrt(z) * marker_size_mult, 8.0, 26.0) + 4.0
	var hit_r2 := hit_radius * hit_radius
	var tex_size = main_ctrl.map_texture.get_size() if main_ctrl.map_texture != null else Vector2(8192.0, 8192.0)
	var scaled_size = tex_size * settings.map_scale
	var inv_span_x := 1.0 / maxf(1.0, world_x_max_m - world_x_min_m)
	var inv_span_y := 1.0 / maxf(1.0, world_y_max_m - world_y_min_m)

	for res_key in deposits.keys():
		if not enabled_resources.get(res_key, true):
			continue
		var is_collectible = res_key in COLLECTIBLES
		for raw_dep in deposits[res_key]:
			var pur := float(raw_dep[2])
			if not is_collectible and not _is_purity_visible(pur):
				continue
			var xm := float(raw_dep[0])
			var ym := float(raw_dep[1])
			var w_pos := Vector2((xm - world_x_min_m) * inv_span_x * scaled_size.x, (ym - world_y_min_m) * inv_span_y * scaled_size.y)
			var s_pos := w_pos * z - scroll
			if s_pos.distance_squared_to(screen_pos) > hit_r2:
				continue
			var m_id: String = raw_dep[4] if raw_dep.size() > 4 else _get_marker_id(res_key, xm, ym)
			if hide_checked and checked_markers.has(m_id):
				continue
			return {
				"resource": res_key, "x_m": xm, "y_m": ym,
				"purity": pur, "is_well": bool(raw_dep[3]),
				"world_pos": w_pos, "is_collectible": is_collectible
			}
	return {}

func _spawn_miner_on_deposit(dep: Dictionary) -> void:
	if dep.get("is_collectible", false):
		return
	var res_key: String = dep["resource"]
	var is_well := bool(dep.get("is_well", false))
	var rec_id := ("well_%s" % res_key) if is_well else ("extract_%s" % res_key)
	if not db.recipes.has(rec_id):
		rec_id = "extract_%s" % res_key
	if not db.recipes.has(rec_id):
		return
	var w_pos: Vector2 = dep["world_pos"] - Vector2(185.0, 85.0)
	var node: GraphNode = main_ctrl.builder.spawn_machine(main_ctrl, rec_id, w_pos)
	var pur := float(dep["purity"])
	node.set_meta("purity", pur)
	if node.has_meta("pur_opt"):
		var pur_opt: OptionButton = node.get_meta("pur_opt")
		pur_opt.selected = 0 if pur < 0.75 else (2 if pur > 1.5 else 1)
	var p_tag := i18n.t("markers_pure_opt") if pur > 1.5 else (i18n.t("markers_impure_opt") if pur < 0.75 else i18n.t("markers_normal_opt"))
	node.title = "%s (%s)" % [db.recipes[rec_id]["title"], p_tag]
	main_ctrl.recalculate_all()

func draw_markers_on_map(canvas: GraphEdit) -> void:
	if not show_markers or canvas.active_graph != canvas:
		return
	var z := canvas.zoom
	var scroll := canvas.scroll_offset
	var vp_rect := Rect2(Vector2.ZERO, canvas.size).grow(32.0)
	var radius := clampf(11.0 * sqrt(z) * marker_size_mult, 5.5, 22.0)
	var font := ThemeDB.fallback_font
	var has_checked := not checked_markers.is_empty()
	var tex_size = main_ctrl.map_texture.get_size() if main_ctrl.map_texture != null else Vector2(8192.0, 8192.0)
	var scaled_size = tex_size * settings.map_scale
	var inv_span_x := 1.0 / maxf(1.0, world_x_max_m - world_x_min_m)
	var inv_span_y := 1.0 / maxf(1.0, world_y_max_m - world_y_min_m)

	for res_key in deposits.keys():
		if not enabled_resources.get(res_key, true):
			continue
		var is_collectible = res_key in COLLECTIBLES
		var base_item_col := _get_marker_color(res_key)
		var disp_name := _get_display_name(res_key)
		var icon_tex := _get_custom_icon(res_key)
		var label_05 := "%s (0.5x)" % disp_name
		var label_10 := "%s (1x)" % disp_name
		var label_20 := "%s (2x)" % disp_name

		for raw_dep in deposits[res_key]:
			var pur := float(raw_dep[2])
			if not is_collectible and not _is_purity_visible(pur):
				continue
			var xm := float(raw_dep[0])
			var ym := float(raw_dep[1])
			var w_pos := Vector2((xm - world_x_min_m) * inv_span_x * scaled_size.x, (ym - world_y_min_m) * inv_span_y * scaled_size.y)
			var s_pos := w_pos * z - scroll
			if not vp_rect.has_point(s_pos):
				continue
			var is_checked := false
			if has_checked:
				var m_id: String = raw_dep[4] if raw_dep.size() > 4 else _get_marker_id(res_key, xm, ym)
				is_checked = checked_markers.has(m_id)
				if is_checked and hide_checked:
					continue
			var base_ring_col := base_item_col if is_collectible else _get_purity_ring_color(pur)
			var is_hov = (
				not hovered_deposit.is_empty()
				and hovered_deposit.get("resource") == res_key
				and is_equal_approx(float(hovered_deposit.get("x_m", 0.0)), xm)
				and is_equal_approx(float(hovered_deposit.get("y_m", 0.0)), ym)
			)
			var r_draw := radius * (1.35 if is_hov else 1.0)
			var alpha := 0.35 if is_checked else 1.0
			var fill_col := base_item_col.darkened(0.55 if is_checked else 0.35)
			fill_col.a *= alpha
			var border_col := base_ring_col.darkened(0.4 if is_checked else 0.0)
			border_col.a *= alpha

			canvas.draw_circle(s_pos, r_draw + 1.8, Color(0.04, 0.05, 0.07, 0.9 * alpha))
			canvas.draw_circle(s_pos, r_draw, border_col)
			canvas.draw_circle(s_pos, maxf(1.5, r_draw - 2.0), fill_col)
			if icon_tex != null and r_draw >= 7.0:
				var isz := r_draw * 1.35
				canvas.draw_texture_rect(icon_tex, Rect2(s_pos - Vector2(isz * 0.5, isz * 0.5), Vector2(isz, isz)), false, Color(1, 1, 1, alpha))
			if z >= 0.52:
				var tag := disp_name if is_collectible else (label_20 if pur > 1.5 else (label_05 if pur < 0.75 else label_10))
				var txt_col := Color(0.6, 0.6, 0.6, 0.6) if is_checked else Color.WHITE
				canvas.draw_string(font, s_pos + Vector2(r_draw + 5.0, 4.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt_col)

	if not hovered_deposit.is_empty():
		var h_res: String = hovered_deposit["resource"]
		var is_c := bool(hovered_deposit.get("is_collectible", false))
		var check_id := _get_marker_id(h_res, float(hovered_deposit["x_m"]), float(hovered_deposit["y_m"]))
		var status_tag := i18n.t("markers_used_tag") if checked_markers.has(check_id) else ""
		var tip := ""
		var border_col := Color.WHITE
		if is_c:
			tip = i18n.tf("markers_tip_col", [_get_display_name(h_res), status_tag, int(hovered_deposit["x_m"]), int(hovered_deposit["y_m"])])
			border_col = _get_marker_color(h_res)
		else:
			var h_pur := float(hovered_deposit["purity"])
			var p_name := i18n.t("markers_pure_opt") if h_pur > 1.5 else (i18n.t("markers_impure_opt") if h_pur < 0.75 else i18n.t("markers_normal_opt"))
			var well_tag := i18n.t("markers_well_tag") if bool(hovered_deposit.get("is_well", false)) else ""
			tip = i18n.tf("markers_tip_node", [
				_get_display_name(h_res), well_tag, status_tag, p_name, int(hovered_deposit["x_m"]), int(hovered_deposit["y_m"])
			])
			border_col = _get_purity_ring_color(h_pur)

		var h_pos := (hovered_deposit["world_pos"] as Vector2) * z - scroll
		var tw := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0
		var trect := Rect2(h_pos + Vector2(-tw * 0.5, -radius - 32.0), Vector2(tw, 24.0))
		canvas.draw_rect(trect, Color(0.06, 0.08, 0.11, 0.96), true)
		canvas.draw_rect(trect, border_col.darkened(0.5 if checked_markers.has(check_id) else 0.0), false, 1.8)
		canvas.draw_string(font, trect.position + Vector2(9.0, 16.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
