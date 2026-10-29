class_name CustomRecipeManager
extends RefCounted

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var builder: NodeBuilder

var win: Window
var _hdr_lbl: Label
var _bldg_lbl: Label
var _bldg_opt: OptionButton
var _cat_edit: LineEdit
var _title_edit: LineEdit
var _time_spin: SpinBox
var _btn_60s: Button
var _pwr_spin: SpinBox
var _in_hdr_lbl: Label
var _out_hdr_lbl: Label
var _save_btn: Button
var _cancel_btn: Button
var _list_hdr_lbl: Label
var _list_vbox: VBoxContainer

var editing_id: String = ""
var _in_slots: Array[Dictionary] = []
var _out_slots: Array[Dictionary] = []

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n, p_builder: NodeBuilder) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	builder = p_builder

func _get_building_choices() -> Array:
	if not db.CUSTOM_RECIPE_BUILDINGS.is_empty():
		return db.CUSTOM_RECIPE_BUILDINGS
	return [
		{"key": "constructor", "name": "Constructor", "mw": 4.0},
		{"key": "assembler", "name": "Assembler", "mw": 15.0},
		{"key": "manufacturer", "name": "Manufacturer", "mw": 55.0}
	]

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	win = Window.new()
	win.theme = theme_ref
	win.size = Vector2i(760, 740)
	win.visible = false
	win.close_requested.connect(func(): win.hide())
	parent_layer.add_child(win)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	win.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	_hdr_lbl = Label.new()
	_hdr_lbl.add_theme_font_size_override("font_size", 15)
	_hdr_lbl.modulate = Color.GOLD
	main_vbox.add_child(_hdr_lbl)

	# Row 1: Building selection + optional custom category + recipe title
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	_bldg_lbl = Label.new()
	row1.add_child(_bldg_lbl)

	var choices := _get_building_choices()
	_bldg_opt = OptionButton.new()
	_bldg_opt.custom_minimum_size = Vector2(180, 0)
	for i in range(choices.size()):
		_bldg_opt.add_item(String(choices[i]["name"]), i)
	_bldg_opt.selected = mini(2, choices.size() - 1)
	_bldg_opt.item_selected.connect(func(idx: int):
		if editing_id == "":
			var c_list := _get_building_choices()
			if idx >= 0 and idx < c_list.size():
				_pwr_spin.value = float(c_list[idx]["mw"])
	)
	row1.add_child(_bldg_opt)

	_title_edit = LineEdit.new()
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_title_edit)

	_cat_edit = LineEdit.new()
	_cat_edit.custom_minimum_size = Vector2(160, 0)
	row1.add_child(_cat_edit)
	main_vbox.add_child(row1)

	# Row 2: Cycle time (default 60s = per minute rates) + Power consumption MW
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	_time_spin = SpinBox.new()
	_time_spin.min_value = 0.0
	_time_spin.max_value = 3600.0
	_time_spin.step = 0.5
	_time_spin.value = 60.0
	_time_spin.suffix = " s"
	_time_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_spin.value_changed.connect(func(_v: float): _update_per_min_previews())
	row2.add_child(_time_spin)

	_btn_60s = Button.new()
	_btn_60s.modulate = Color.AQUAMARINE
	_btn_60s.pressed.connect(func(): _time_spin.value = 60.0)
	row2.add_child(_btn_60s)

	_pwr_spin = SpinBox.new()
	_pwr_spin.min_value = -10000.0
	_pwr_spin.max_value = 10000.0
	_pwr_spin.step = 1.0
	_pwr_spin.value = 55.0
	_pwr_spin.suffix = " MW"
	_pwr_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_pwr_spin)
	main_vbox.add_child(row2)

	# 4 Inputs and 4 Outputs side-by-side in two columns
	var io_cols := HBoxContainer.new()
	io_cols.add_theme_constant_override("separation", 14)
	main_vbox.add_child(io_cols)

	var in_col := VBoxContainer.new()
	in_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	in_col.add_theme_constant_override("separation", 5)
	_in_hdr_lbl = Label.new()
	_in_hdr_lbl.modulate = Color.LIGHT_SKY_BLUE
	in_col.add_child(_in_hdr_lbl)
	_in_slots.clear()
	for i in range(4):
		var slot := _create_io_slot_row(i == 0, "iron-ingot" if i == 0 else "")
		_in_slots.append(slot)
		in_col.add_child(slot["row"])
	io_cols.add_child(in_col)

	var out_col := VBoxContainer.new()
	out_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_col.add_theme_constant_override("separation", 5)
	_out_hdr_lbl = Label.new()
	_out_hdr_lbl.modulate = Color.SPRING_GREEN
	out_col.add_child(_out_hdr_lbl)
	_out_slots.clear()
	for i in range(4):
		var slot := _create_io_slot_row(i == 0, "iron-plate" if i == 0 else "")
		_out_slots.append(slot)
		out_col.add_child(slot["row"])
	io_cols.add_child(out_col)

	# Save / Cancel edit buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	_save_btn = Button.new()
	_save_btn.custom_minimum_size = Vector2(0, 34)
	_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_btn.modulate = Color.SPRING_GREEN
	_save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(_save_btn)

	_cancel_btn = Button.new()
	_cancel_btn.custom_minimum_size = Vector2(130, 34)
	_cancel_btn.modulate = Color.SALMON
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(_reset_form)
	btn_row.add_child(_cancel_btn)
	main_vbox.add_child(btn_row)

	main_vbox.add_child(HSeparator.new())

	_list_hdr_lbl = Label.new()
	_list_hdr_lbl.modulate = Color.AQUAMARINE
	main_vbox.add_child(_list_hdr_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_vbox)

	refresh_translations()
	_update_per_min_previews()
	return win

func _create_io_slot_row(active_by_default: bool, default_item: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var slot_data := {
		"row": row,
		"item": default_item if active_by_default else "",
		"btn": null,
		"spin": null,
		"rate_lbl": null,
		"clear_btn": null
	}

	var item_btn := Button.new()
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_btn.clip_text = true
	slot_data["btn"] = item_btn

	var amt_spin := SpinBox.new()
	amt_spin.min_value = 0.0
	amt_spin.max_value = 50000.0
	amt_spin.step = 0.1
	amt_spin.custom_arrow_step = 5.0
	amt_spin.value = 30.0
	amt_spin.custom_minimum_size = Vector2(88, 0)
	amt_spin.value_changed.connect(func(_v: float): _update_per_min_previews())
	slot_data["spin"] = amt_spin

	var rate_lbl := Label.new()
	rate_lbl.custom_minimum_size = Vector2(68, 0)
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rate_lbl.add_theme_font_size_override("font_size", 11)
	rate_lbl.modulate = Color(0.75, 0.88, 1.0)
	slot_data["rate_lbl"] = rate_lbl

	var clear_btn := Button.new()
	clear_btn.text = "✕"
	clear_btn.custom_minimum_size = Vector2(26, 0)
	clear_btn.modulate = Color.SALMON
	slot_data["clear_btn"] = clear_btn

	item_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(chosen_item: String):
			slot_data["item"] = chosen_item
			_refresh_slot_visuals(slot_data)
			_update_per_min_previews()
		)
	)
	clear_btn.pressed.connect(func():
		slot_data["item"] = ""
		_refresh_slot_visuals(slot_data)
		_update_per_min_previews()
	)

	row.add_child(item_btn)
	row.add_child(amt_spin)
	row.add_child(rate_lbl)
	row.add_child(clear_btn)
	_refresh_slot_visuals(slot_data)
	return slot_data

func _refresh_slot_visuals(slot: Dictionary) -> void:
	var ikey: String = String(slot["item"])
	var btn: Button = slot["btn"]
	var spin: SpinBox = slot["spin"]
	var r_lbl: Label = slot["rate_lbl"]
	var clr: Button = slot["clear_btn"]
	if ikey == "":
		btn.text = i18n.t("custom_rec_empty_slot")
		btn.icon = null
		btn.modulate = Color(0.65, 0.7, 0.78, 0.8)
		spin.editable = false
		r_lbl.text = "—"
		clr.disabled = true
	else:
		builder._apply_item_button_visuals(btn, ikey)
		spin.editable = true
		clr.disabled = false

func _update_per_min_previews() -> void:
	if _time_spin == null:
		return
	var cpm := 60.0 / maxf(0.1, _time_spin.value)
	var u_str := i18n.t("unit_per_min")
	for list in [_in_slots, _out_slots]:
		for slot in list:
			var ikey: String = String(slot["item"])
			var r_lbl: Label = slot["rate_lbl"]
			var spin: SpinBox = slot["spin"]
			if ikey == "":
				r_lbl.text = "—"
			else:
				var rate := spin.value * cpm
				r_lbl.text = "%s%s" % [settings.fmt(rate), u_str]

func open_window() -> void:
	refresh_translations()
	_refresh_saved_list()
	win.popup_centered()

func refresh_translations() -> void:
	if win == null:
		return
	win.title = i18n.t("custom_rec_win_title")
	_hdr_lbl.text = i18n.t("custom_rec_add_hdr") if editing_id == "" else i18n.tf("custom_rec_edit_hdr", [_title_edit.text])
	_bldg_lbl.text = i18n.t("custom_rec_bldg_lbl")
	var choices := _get_building_choices()
	for i in range(mini(_bldg_opt.item_count, choices.size())):
		var b_key: String = String(choices[i]["key"])
		_bldg_opt.set_item_text(i, db.get_building_display_name(b_key, String(choices[i]["name"])))
	_cat_edit.placeholder_text = i18n.t("custom_rec_cat_ph")
	_title_edit.placeholder_text = i18n.t("custom_rec_title_ph")
	_time_spin.prefix = i18n.t("custom_rec_time_prefix")
	if _btn_60s:
		_btn_60s.text = i18n.t("custom_rec_60s_btn")
		_btn_60s.tooltip_text = i18n.t("custom_rec_60s_tip")
	_pwr_spin.prefix = i18n.t("custom_rec_pwr_prefix")
	_in_hdr_lbl.text = i18n.t("custom_rec_inputs_hdr")
	_out_hdr_lbl.text = i18n.t("custom_rec_outputs_hdr")
	_save_btn.text = i18n.t("custom_rec_save_btn") if editing_id == "" else i18n.t("custom_rec_update_btn")
	_cancel_btn.text = i18n.t("custom_rec_cancel_btn")
	_list_hdr_lbl.text = i18n.t("custom_rec_list_hdr")
	for list in [_in_slots, _out_slots]:
		for slot in list:
			_refresh_slot_visuals(slot)
	_update_per_min_previews()
	if win.visible:
		_refresh_saved_list()

func _reset_form() -> void:
	editing_id = ""
	_title_edit.text = ""
	_cat_edit.text = ""
	_time_spin.value = 60.0
	var choices := _get_building_choices()
	_bldg_opt.selected = mini(2, choices.size() - 1)
	_pwr_spin.value = 55.0
	for i in range(4):
		_in_slots[i]["item"] = "iron-ingot" if i == 0 else ""
		_in_slots[i]["spin"].value = 30.0
		_refresh_slot_visuals(_in_slots[i])
		_out_slots[i]["item"] = "iron-plate" if i == 0 else ""
		_out_slots[i]["spin"].value = 20.0
		_refresh_slot_visuals(_out_slots[i])
	_cancel_btn.visible = false
	refresh_translations()

func _on_save_pressed() -> void:
	var title := _title_edit.text.strip_edges()
	if title == "":
		title = "Custom Recipe"
	var choices := _get_building_choices()
	var b_idx := clampi(_bldg_opt.selected, 0, choices.size() - 1)
	var b_key: String = String(choices[b_idx]["key"])
	var cat := _cat_edit.text.strip_edges()
	var ins: Array = []
	for slot in _in_slots:
		var ikey := String(slot["item"])
		if ikey != "":
			ins.append({"item": ikey, "amount": float(slot["spin"].value)})
	var outs: Array = []
	for slot in _out_slots:
		var okey := String(slot["item"])
		if okey != "":
			outs.append({"item": okey, "amount": float(slot["spin"].value)})
	if ins.is_empty() and outs.is_empty():
		return
	db.add_custom_recipe(cat, title, _pwr_spin.value, _time_spin.value, ins, outs, editing_id, b_key)
	_reset_form()
	_refresh_saved_list()
	main_ctrl.recalculate_all()

func _load_recipe_into_form(rec_id: String) -> void:
	if not db.recipes.has(rec_id):
		return
	var r: Dictionary = db.recipes[rec_id]
	editing_id = rec_id
	_title_edit.text = String(r.get("raw_name_en", r.get("raw_name", rec_id)))
	_cat_edit.text = String(r.get("category_en", ""))
	_time_spin.value = float(r.get("time", 60.0))
	var pwr := float(r.get("power", 15.0))
	var gen := float(r.get("power_generated", 0.0))
	_pwr_spin.value = -gen if gen > 0.0 else pwr
	var b_key := String(r.get("building_key", "manufacturer"))
	var choices := _get_building_choices()
	for i in range(choices.size()):
		if String(choices[i]["key"]) == b_key:
			_bldg_opt.selected = i
			break
	var ins: Array = r.get("inputs", [])
	for i in range(4):
		if i < ins.size():
			_in_slots[i]["item"] = String(ins[i]["item"])
			_in_slots[i]["spin"].value = float(ins[i].get("amount", ins[i].get("rate", 10.0)))
		else:
			_in_slots[i]["item"] = ""
		_refresh_slot_visuals(_in_slots[i])
	var outs: Array = r.get("outputs", [])
	for i in range(4):
		if i < outs.size():
			_out_slots[i]["item"] = String(outs[i]["item"])
			_out_slots[i]["spin"].value = float(outs[i].get("amount", outs[i].get("rate", 10.0)))
		else:
			_out_slots[i]["item"] = ""
		_refresh_slot_visuals(_out_slots[i])
	_cancel_btn.visible = true
	refresh_translations()

func _refresh_saved_list() -> void:
	if _list_vbox == null:
		return
	for ch in _list_vbox.get_children():
		ch.queue_free()
	var ids := db.get_custom_recipe_ids()
	if ids.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = i18n.t("custom_rec_empty")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(1, 1, 1, 0.5)
		_list_vbox.add_child(empty_lbl)
		return
	var u_str := i18n.t("unit_per_min")
	for rec_id in ids:
		var r: Dictionary = db.recipes[rec_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		var in_parts: Array[String] = []
		for e in r.get("inputs", []):
			in_parts.append("%s %s%s" % [db.get_item_display_name(String(e["item"])), settings.fmt(float(e["rate"])), u_str])
		var out_parts: Array[String] = []
		for e in r.get("outputs", []):
			out_parts.append("%s %s%s" % [db.get_item_display_name(String(e["item"])), settings.fmt(float(e["rate"])), u_str])
		var in_txt := ", ".join(in_parts) if not in_parts.is_empty() else i18n.t("custom_rec_none")
		var out_txt := ", ".join(out_parts) if not out_parts.is_empty() else i18n.t("custom_rec_power_out")
		lbl.text = "⚙ %s  |  ⏱ %ss  |  📥 %s ➔ 📤 %s" % [
			String(r["title"]), settings.fmt(float(r.get("time", 60.0))), in_txt, out_txt
		]
		row.add_child(lbl)

		var edit_btn := Button.new()
		edit_btn.text = i18n.t("custom_rec_edit_btn")
		edit_btn.modulate = Color.AQUAMARINE
		var rid_copy := rec_id
		edit_btn.pressed.connect(func(): _load_recipe_into_form(rid_copy))
		row.add_child(edit_btn)

		var del_btn := Button.new()
		del_btn.text = "✕"
		del_btn.modulate = Color.SALMON
		del_btn.tooltip_text = i18n.t("custom_rec_del_tooltip")
		del_btn.pressed.connect(func():
			db.delete_custom_recipe(rid_copy)
			if editing_id == rid_copy:
				_reset_form()
			_refresh_saved_list()
			main_ctrl.recalculate_all()
		)
		row.add_child(del_btn)
		_list_vbox.add_child(row)
