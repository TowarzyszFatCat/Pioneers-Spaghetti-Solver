class_name AppSettings
extends RefCounted

signal settings_changed
signal map_image_selected(path: String)

const SETTINGS_FILE_PATH := "user://app_settings.json"
const BELT_RATES: Array[float] = [60.0, 120.0, 270.0, 480.0, 780.0, 1200.0, 999999.0]
const PIPE_RATES: Array[float] = [300.0, 600.0, 999999.0]

var i18n: AppI18n
var db: AppDB

var realistic_throttle: bool = false
var equal_split_mode: bool = false
var ceil_machines: bool = false
var decimals: int = 2
var belt_limit: float = 1200.0
var pipe_limit: float = 600.0
var show_power: bool = true
var show_wire_labels: bool = true
var orthogonal_wires: bool = false
var compact_ui: bool = false
var show_alternates: bool = true
var auto_balance_on_connect: bool = true
var show_map: bool = true
var map_opacity: float = 0.65
var map_scale: float = 2.0
var selected_map_path: String = ""

var _win: Window
var _ui_refs: Dictionary = {}
var _is_syncing_ui: bool = false

func _init(p_i18n: AppI18n, p_db: AppDB = null) -> void:
	i18n = p_i18n
	db = p_db
	load_settings()

func save_settings() -> void:
	if _is_syncing_ui:
		return
	var data := {
		"lang": i18n.current_lang if i18n != null else "en",
		"realistic_throttle": realistic_throttle,
		"equal_split_mode": equal_split_mode,
		"ceil_machines": ceil_machines,
		"decimals": decimals,
		"belt_limit": belt_limit,
		"pipe_limit": pipe_limit,
		"show_power": show_power,
		"show_wire_labels": show_wire_labels,
		"orthogonal_wires": orthogonal_wires,
		"compact_ui": compact_ui,
		"show_alternates": show_alternates,
		"auto_balance_on_connect": auto_balance_on_connect,
		"show_map": show_map,
		"map_opacity": map_opacity,
		"map_scale": map_scale,
		"selected_map_path": selected_map_path
	}
	var f := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		return
	var f := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	if parsed.has("lang") and i18n != null:
		i18n.set_language(String(parsed["lang"]))
		if db != null:
			db.refresh_localized_texts()
	realistic_throttle = bool(parsed.get("realistic_throttle", realistic_throttle))
	equal_split_mode = bool(parsed.get("equal_split_mode", equal_split_mode))
	ceil_machines = bool(parsed.get("ceil_machines", ceil_machines))
	decimals = clampi(int(parsed.get("decimals", decimals)), 1, 4)
	belt_limit = float(parsed.get("belt_limit", belt_limit))
	pipe_limit = float(parsed.get("pipe_limit", pipe_limit))
	show_power = bool(parsed.get("show_power", show_power))
	show_wire_labels = bool(parsed.get("show_wire_labels", show_wire_labels))
	orthogonal_wires = bool(parsed.get("orthogonal_wires", orthogonal_wires))
	compact_ui = bool(parsed.get("compact_ui", compact_ui))
	show_alternates = bool(parsed.get("show_alternates", show_alternates))
	auto_balance_on_connect = bool(parsed.get("auto_balance_on_connect", auto_balance_on_connect))
	show_map = bool(parsed.get("show_map", show_map))
	map_opacity = clampf(float(parsed.get("map_opacity", map_opacity)), 0.05, 1.0)
	map_scale = clampf(float(parsed.get("map_scale", map_scale)), 0.25, 4.0)
	selected_map_path = String(parsed.get("selected_map_path", selected_map_path))

func _find_rate_index(rates_arr: Array[float], target_val: float, default_idx: int) -> int:
	for i in range(rates_arr.size()):
		if is_equal_approx(rates_arr[i], target_val):
			return i
	return default_idx

func fmt(val: float) -> String:
	if is_zero_approx(val):
		return "0"
	var rounded := snappedf(val, pow(10.0, -decimals))
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d" % int(roundf(rounded))
	var s := ("%." + str(decimals) + "f") % rounded
	while s.contains(".") and (s.ends_with("0") or s.ends_with(".")):
		if s.ends_with("."):
			s = s.left(s.length() - 1)
			break
		s = s.left(s.length() - 1)
	return s

func build_window(parent_layer: CanvasLayer) -> Window:
	_win = Window.new()
	_win.transparent = true
	_win.transparent_bg = true
	_win.size = Vector2i(700, 800)
	_win.visible = false
	_win.close_requested.connect(func(): _win.hide())
	parent_layer.add_child(_win)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win.add_child(scroll)

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

	# AI Translation Disclaimer Banner
	var ai_card := PanelContainer.new()
	var ai_sb := StyleBoxFlat.new()
	ai_sb.bg_color = Color(0.18, 0.14, 0.07, 0.88)
	ai_sb.border_color = Color.html("#FAB757")
	ai_sb.set_border_width_all(1)
	ai_sb.border_width_left = 4
	ai_sb.set_corner_radius_all(6)
	ai_sb.content_margin_left = 10
	ai_sb.content_margin_right = 10
	ai_sb.content_margin_top = 6
	ai_sb.content_margin_bottom = 6
	ai_card.add_theme_stylebox_override("panel", ai_sb)
	var ai_lbl := Label.new()
	ai_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_lbl.add_theme_font_size_override("font_size", 11)
	ai_lbl.modulate = Color(1.0, 0.90, 0.65)
	ai_card.add_child(ai_lbl)
	vbox.add_child(ai_card)
	_ui_refs["ai_disclaimer_lbl"] = ai_lbl

	var lang_row := HBoxContainer.new()
	var lang_lbl := Label.new()
	lang_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lang_opt := OptionButton.new()
	lang_opt.custom_minimum_size = Vector2(360, 0)
	var avail_langs: Array[String] = i18n.get_available_languages()
	var selected_lang_idx := 0
	for i in range(avail_langs.size()):
		var l_code := avail_langs[i]
		lang_opt.add_item(i18n.get_language_option_label(l_code, db), i)
		lang_opt.set_item_metadata(i, l_code)
		if l_code.to_lower() == i18n.current_lang.to_lower() or (i18n.current_lang == "en" and l_code == "en-US"):
			selected_lang_idx = i
	lang_opt.selected = selected_lang_idx
	lang_opt.item_selected.connect(func(idx: int):
		var new_lang := String(lang_opt.get_item_metadata(idx))
		i18n.set_language(new_lang)
		if db != null:
			db.refresh_localized_texts()
		refresh_translations()
		save_settings()
		settings_changed.emit()
	)
	lang_row.add_child(lang_lbl)
	lang_row.add_child(lang_opt)
	vbox.add_child(lang_row)
	_ui_refs["lang_lbl"] = lang_lbl
	_ui_refs["lang_opt"] = lang_opt

	if db != null and not db.available_maps.is_empty():
		var map_sel_row := HBoxContainer.new()
		var map_sel_lbl := Label.new()
		map_sel_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var map_sel_opt := OptionButton.new()
		var initial_map_idx := 0
		for i in range(db.available_maps.size()):
			var m_path := String(db.available_maps[i]["path"])
			map_sel_opt.add_item(String(db.available_maps[i]["name"]), i)
			if selected_map_path != "" and m_path == selected_map_path:
				initial_map_idx = i
		map_sel_opt.selected = initial_map_idx
		map_sel_opt.item_selected.connect(func(idx: int):
			selected_map_path = String(db.available_maps[idx]["path"])
			save_settings()
			map_image_selected.emit(selected_map_path)
		)
		map_sel_row.add_child(map_sel_lbl)
		map_sel_row.add_child(map_sel_opt)
		vbox.add_child(map_sel_row)
		_ui_refs["map_sel_lbl"] = map_sel_lbl
		_ui_refs["map_sel_opt"] = map_sel_opt

	var split_row := HBoxContainer.new()
	var split_lbl := Label.new()
	split_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var split_opt := OptionButton.new()
	split_opt.add_item("", 0)
	split_opt.add_item("", 1)
	split_opt.selected = 1 if equal_split_mode else 0
	split_opt.item_selected.connect(func(idx: int):
		equal_split_mode = (idx == 1)
		save_settings()
		settings_changed.emit()
	)
	split_row.add_child(split_lbl)
	split_row.add_child(split_opt)
	vbox.add_child(split_row)
	_ui_refs["split_lbl"] = split_lbl
	_ui_refs["split_opt"] = split_opt

	var wire_chk := CheckBox.new()
	wire_chk.button_pressed = show_wire_labels
	wire_chk.toggled.connect(func(v: bool):
		show_wire_labels = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(wire_chk)
	_ui_refs["wire_chk"] = wire_chk

	var ortho_chk := CheckBox.new()
	ortho_chk.button_pressed = orthogonal_wires
	ortho_chk.toggled.connect(func(v: bool):
		orthogonal_wires = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(ortho_chk)
	_ui_refs["ortho_chk"] = ortho_chk

	var compact_chk := CheckBox.new()
	compact_chk.button_pressed = compact_ui
	compact_chk.toggled.connect(func(v: bool):
		compact_ui = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(compact_chk)
	_ui_refs["compact_chk"] = compact_chk

	var alt_chk := CheckBox.new()
	alt_chk.button_pressed = show_alternates
	alt_chk.toggled.connect(func(v: bool):
		show_alternates = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(alt_chk)
	_ui_refs["alt_chk"] = alt_chk

	var throttle_chk := CheckBox.new()
	throttle_chk.button_pressed = realistic_throttle
	throttle_chk.toggled.connect(func(v: bool):
		realistic_throttle = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(throttle_chk)
	_ui_refs["throttle_chk"] = throttle_chk

	var ceil_chk := CheckBox.new()
	ceil_chk.button_pressed = ceil_machines
	ceil_chk.toggled.connect(func(v: bool):
		ceil_machines = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(ceil_chk)
	_ui_refs["ceil_chk"] = ceil_chk

	var auto_chk := CheckBox.new()
	auto_chk.button_pressed = auto_balance_on_connect
	auto_chk.toggled.connect(func(v: bool):
		auto_balance_on_connect = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(auto_chk)
	_ui_refs["auto_chk"] = auto_chk

	var pwr_chk := CheckBox.new()
	pwr_chk.button_pressed = show_power
	pwr_chk.toggled.connect(func(v: bool):
		show_power = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(pwr_chk)
	_ui_refs["pwr_chk"] = pwr_chk

	var belt_row := HBoxContainer.new()
	var belt_lbl := Label.new()
	belt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var belt_opt := OptionButton.new()
	for i in range(BELT_RATES.size()):
		belt_opt.add_item("", i)
	belt_opt.selected = _find_rate_index(BELT_RATES, belt_limit, 5)
	belt_opt.item_selected.connect(func(idx: int):
		belt_limit = BELT_RATES[idx]
		save_settings()
		settings_changed.emit()
	)
	belt_row.add_child(belt_lbl)
	belt_row.add_child(belt_opt)
	vbox.add_child(belt_row)
	_ui_refs["belt_lbl"] = belt_lbl
	_ui_refs["belt_opt"] = belt_opt

	var pipe_row := HBoxContainer.new()
	var pipe_lbl := Label.new()
	pipe_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pipe_opt := OptionButton.new()
	for i in range(PIPE_RATES.size()):
		pipe_opt.add_item("", i)
	pipe_opt.selected = _find_rate_index(PIPE_RATES, pipe_limit, 1)
	pipe_opt.item_selected.connect(func(idx: int):
		pipe_limit = PIPE_RATES[idx]
		save_settings()
		settings_changed.emit()
	)
	pipe_row.add_child(pipe_lbl)
	pipe_row.add_child(pipe_opt)
	vbox.add_child(pipe_row)
	_ui_refs["pipe_lbl"] = pipe_lbl
	_ui_refs["pipe_opt"] = pipe_opt

	var dec_row := HBoxContainer.new()
	var dec_lbl := Label.new()
	dec_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dec_opt := OptionButton.new()
	dec_opt.add_item("1 (0.1)", 1)
	dec_opt.add_item("2 (0.01)", 2)
	dec_opt.add_item("3 (0.001)", 3)
	dec_opt.add_item("", 4)
	dec_opt.selected = clampi(decimals - 1, 0, 3)
	dec_opt.item_selected.connect(func(idx: int):
		decimals = idx + 1
		save_settings()
		settings_changed.emit()
	)
	dec_row.add_child(dec_lbl)
	dec_row.add_child(dec_opt)
	vbox.add_child(dec_row)
	_ui_refs["dec_lbl"] = dec_lbl
	_ui_refs["dec_opt"] = dec_opt

	var map_chk := CheckBox.new()
	map_chk.button_pressed = show_map
	map_chk.toggled.connect(func(v: bool):
		show_map = v
		save_settings()
		settings_changed.emit()
	)
	vbox.add_child(map_chk)
	_ui_refs["map_chk"] = map_chk

	var op_row := HBoxContainer.new()
	var op_lbl := Label.new()
	var op_slider := HSlider.new()
	op_slider.min_value = 0.05
	op_slider.max_value = 1.0
	op_slider.step = 0.05
	op_slider.value = map_opacity
	op_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_slider.value_changed.connect(func(v: float):
		map_opacity = v
		save_settings()
		settings_changed.emit()
	)
	op_row.add_child(op_lbl)
	op_row.add_child(op_slider)
	vbox.add_child(op_row)
	_ui_refs["op_lbl"] = op_lbl
	_ui_refs["op_slider"] = op_slider

	var sc_row := HBoxContainer.new()
	var sc_lbl := Label.new()
	var sc_slider := HSlider.new()
	sc_slider.min_value = 0.25
	sc_slider.max_value = 4.0
	sc_slider.step = 0.05
	sc_slider.value = map_scale
	sc_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc_slider.value_changed.connect(func(v: float):
		map_scale = v
		save_settings()
		settings_changed.emit()
	)
	sc_row.add_child(sc_lbl)
	sc_row.add_child(sc_slider)
	vbox.add_child(sc_row)
	_ui_refs["sc_lbl"] = sc_lbl
	_ui_refs["sc_slider"] = sc_slider

	var file_dlg := FileDialog.new()
	file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	file_dlg.file_selected.connect(func(path: String):
		selected_map_path = path
		save_settings()
		map_image_selected.emit(path)
	)
	parent_layer.add_child(file_dlg)
	_ui_refs["file_dlg"] = file_dlg

	var load_btn := Button.new()
	load_btn.pressed.connect(func(): file_dlg.popup_centered(Vector2i(560, 380)))
	vbox.add_child(load_btn)
	_ui_refs["load_btn"] = load_btn

	var exp_i18n_btn := Button.new()
	exp_i18n_btn.modulate = Color.AQUAMARINE
	exp_i18n_btn.pressed.connect(func():
		var saved_path := i18n.export_translation_template(db)
		exp_i18n_btn.text = "✅ " + saved_path
	)
	vbox.add_child(exp_i18n_btn)
	_ui_refs["exp_i18n_btn"] = exp_i18n_btn

	refresh_translations()
	call_deferred("_emit_saved_map_if_any")
	return _win

func _emit_saved_map_if_any() -> void:
	if selected_map_path != "" and (FileAccess.file_exists(selected_map_path) or ResourceLoader.exists(selected_map_path)):
		map_image_selected.emit(selected_map_path)

func sync_ui_from_values() -> void:
	if _win == null:
		return
	_is_syncing_ui = true
	if _ui_refs.has("lang_opt"):
		var lang_opt: OptionButton = _ui_refs["lang_opt"]
		for i in range(lang_opt.item_count):
			if String(lang_opt.get_item_metadata(i)).to_lower() == i18n.current_lang.to_lower():
				lang_opt.selected = i
				break
	if _ui_refs.has("split_opt"):
		(_ui_refs["split_opt"] as OptionButton).selected = 1 if equal_split_mode else 0
	if _ui_refs.has("wire_chk"):
		(_ui_refs["wire_chk"] as CheckBox).button_pressed = show_wire_labels
	if _ui_refs.has("ortho_chk"):
		(_ui_refs["ortho_chk"] as CheckBox).button_pressed = orthogonal_wires
	if _ui_refs.has("compact_chk"):
		(_ui_refs["compact_chk"] as CheckBox).button_pressed = compact_ui
	if _ui_refs.has("alt_chk"):
		(_ui_refs["alt_chk"] as CheckBox).button_pressed = show_alternates
	if _ui_refs.has("throttle_chk"):
		(_ui_refs["throttle_chk"] as CheckBox).button_pressed = realistic_throttle
	if _ui_refs.has("ceil_chk"):
		(_ui_refs["ceil_chk"] as CheckBox).button_pressed = ceil_machines
	if _ui_refs.has("auto_chk"):
		(_ui_refs["auto_chk"] as CheckBox).button_pressed = auto_balance_on_connect
	if _ui_refs.has("pwr_chk"):
		(_ui_refs["pwr_chk"] as CheckBox).button_pressed = show_power
	if _ui_refs.has("belt_opt"):
		(_ui_refs["belt_opt"] as OptionButton).selected = _find_rate_index(BELT_RATES, belt_limit, 5)
	if _ui_refs.has("pipe_opt"):
		(_ui_refs["pipe_opt"] as OptionButton).selected = _find_rate_index(PIPE_RATES, pipe_limit, 1)
	if _ui_refs.has("dec_opt"):
		(_ui_refs["dec_opt"] as OptionButton).selected = clampi(decimals - 1, 0, 3)
	if _ui_refs.has("map_chk"):
		(_ui_refs["map_chk"] as CheckBox).button_pressed = show_map
	if _ui_refs.has("op_slider"):
		(_ui_refs["op_slider"] as HSlider).value = map_opacity
	if _ui_refs.has("sc_slider"):
		(_ui_refs["sc_slider"] as HSlider).value = map_scale
	_is_syncing_ui = false

func refresh_translations() -> void:
	if _win == null:
		return
	_win.title = i18n.t("settings_win_title")
	if _ui_refs.has("ai_disclaimer_lbl"):
		_ui_refs["ai_disclaimer_lbl"].text = i18n.t("ai_disclaimer_text")
	_ui_refs["lang_lbl"].text = i18n.t("set_lang")
	if _ui_refs.has("lang_opt"):
		var lang_opt: OptionButton = _ui_refs["lang_opt"]
		for i in range(lang_opt.item_count):
			var l_code := String(lang_opt.get_item_metadata(i))
			lang_opt.set_item_text(i, i18n.get_language_option_label(l_code, db))
	if _ui_refs.has("map_sel_lbl"):
		_ui_refs["map_sel_lbl"].text = i18n.t("set_map_select")
	if _ui_refs.has("ortho_chk"):
		_ui_refs["ortho_chk"].text = i18n.t("set_ortho_wires")
	_ui_refs["split_lbl"].text = i18n.t("set_split_mode")
	_ui_refs["split_opt"].set_item_text(0, i18n.t("set_split_prop"))
	_ui_refs["split_opt"].set_item_text(1, i18n.t("set_split_equal"))
	_ui_refs["wire_chk"].text = i18n.t("set_wire_badges")
	_ui_refs["compact_chk"].text = i18n.t("set_compact_ui")
	_ui_refs["alt_chk"].text = i18n.t("set_show_alt")
	_ui_refs["throttle_chk"].text = i18n.t("set_realistic")
	_ui_refs["ceil_chk"].text = i18n.t("set_ceil")
	_ui_refs["auto_chk"].text = i18n.t("set_auto_bal")
	_ui_refs["pwr_chk"].text = i18n.t("set_show_pwr")
	_ui_refs["belt_lbl"].text = i18n.t("set_belt_limit")
	var belt_rates_zero := [60, 120, 270, 480, 780, 1200]
	for i in range(6):
		_ui_refs["belt_opt"].set_item_text(i, "%s (%d%s)" % [i18n.t("belt_mk%d" % (i + 1)), belt_rates_zero[i], i18n.t("unit_per_min")])
	_ui_refs["belt_opt"].set_item_text(6, i18n.t("set_unlimited"))
	_ui_refs["pipe_lbl"].text = i18n.t("set_pipe_limit")
	_ui_refs["pipe_opt"].set_item_text(0, i18n.t("set_pipe_mk1_opt"))
	_ui_refs["pipe_opt"].set_item_text(1, i18n.t("set_pipe_mk2_opt"))
	_ui_refs["pipe_opt"].set_item_text(2, i18n.t("set_unlimited"))
	_ui_refs["dec_lbl"].text = i18n.t("set_decimals")
	_ui_refs["dec_opt"].set_item_text(3, i18n.t("set_dec_4"))
	_ui_refs["map_chk"].text = i18n.t("set_show_map")
	_ui_refs["op_lbl"].text = i18n.t("set_map_opacity")
	_ui_refs["sc_lbl"].text = i18n.t("set_map_scale")
	_ui_refs["file_dlg"].filters = PackedStringArray([i18n.t("set_map_filter")])
	_ui_refs["load_btn"].text = i18n.t("set_browse_map")
	_ui_refs["exp_i18n_btn"].text = i18n.t("set_export_i18n")
