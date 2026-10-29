class_name ProductionModal
extends RefCounted

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var builder: NodeBuilder

var win: Window
var production_summary_lbl: Label
var prod_col_container_vbox: VBoxContainer
var prod_col_depot_vbox: VBoxContainer
var prod_col_sink_vbox: VBoxContainer
var prod_hdr_container_lbl: Label
var prod_hdr_depot_lbl: Label
var prod_hdr_sink_lbl: Label

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n, p_builder: NodeBuilder) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	builder = p_builder

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	win = Window.new()
	win.theme = theme_ref
	win.title = i18n.t("prod_win_title")
	win.size = Vector2i(1280, 720)
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
	
	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 12)
	margin.add_child(main_v)
	
	var top_card := PanelContainer.new()
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = Color(0.09, 0.12, 0.17, 0.96)
	top_sb.border_color = Color(0.3, 0.75, 0.95, 0.7)
	top_sb.set_border_width_all(1)
	top_sb.set_corner_radius_all(6)
	top_sb.content_margin_left = 12
	top_sb.content_margin_right = 12
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	top_card.add_theme_stylebox_override("panel", top_sb)
	
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_card.add_child(top_row)
	
	production_summary_lbl = Label.new()
	production_summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	production_summary_lbl.modulate = Color.AQUAMARINE
	top_row.add_child(production_summary_lbl)
	
	var copy_btn := Button.new()
	copy_btn.text = i18n.t("prod_copy_btn")
	copy_btn.modulate = Color.LIGHT_GREEN
	copy_btn.pressed.connect(func():
		var clip_txt: String = String(win.get_meta("last_clipboard_text", ""))
		if clip_txt != "":
			DisplayServer.clipboard_set(clip_txt)
	)
	top_row.add_child(copy_btn)
	win.set_meta("copy_btn", copy_btn)
	main_v.add_child(top_card)
	
	var cols_hbox := HBoxContainer.new()
	cols_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_theme_constant_override("separation", 12)
	main_v.add_child(cols_hbox)
	
	var col1 := _create_prod_column("prod_col_container", Color.html("#7AB0D4"))
	prod_hdr_container_lbl = col1["hdr"]
	prod_col_container_vbox = col1["vbox"]
	cols_hbox.add_child(col1["panel"])
	
	var col2 := _create_prod_column("prod_col_depot", Color.html("#BD60D3"))
	prod_hdr_depot_lbl = col2["hdr"]
	prod_col_depot_vbox = col2["vbox"]
	cols_hbox.add_child(col2["panel"])
	
	var col3 := _create_prod_column("prod_col_sink", Color.html("#E49246"))
	prod_hdr_sink_lbl = col3["hdr"]
	prod_col_sink_vbox = col3["vbox"]
	cols_hbox.add_child(col3["panel"])
	return win

func _create_prod_column(title_key: String, accent_col: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	sb.border_color = accent_col.darkened(0.2)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	
	var col_v := VBoxContainer.new()
	col_v.add_theme_constant_override("separation", 8)
	panel.add_child(col_v)
	
	var hdr := Label.new()
	hdr.text = i18n.t(title_key)
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.modulate = accent_col.lightened(0.25)
	col_v.add_child(hdr)
	
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	col_v.add_child(sep)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_v.add_child(scroll)
	
	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(list_vbox)
	
	return {"panel": panel, "hdr": hdr, "vbox": list_vbox}

func open_window() -> void:
	refresh_translations()
	refresh()
	win.popup_centered()

func refresh_translations() -> void:
	if win == null:
		return
	win.title = i18n.t("prod_win_title")
	if win.has_meta("copy_btn"):
		(win.get_meta("copy_btn") as Button).text = i18n.t("prod_copy_btn")
	if prod_hdr_container_lbl:
		prod_hdr_container_lbl.text = i18n.t("prod_col_container")
	if prod_hdr_depot_lbl:
		prod_hdr_depot_lbl.text = i18n.t("prod_col_depot")
	if prod_hdr_sink_lbl:
		prod_hdr_sink_lbl.text = i18n.t("prod_col_sink")
	if win.visible:
		refresh()

func _make_prod_item_row(item_key: String, actual_rate: float, planned_rate: float, node_count: int, accent_col: Color, is_sink_col: bool = false) -> PanelContainer:
	var unit := i18n.t("unit_fluid_per_min") if db.is_item_fluid(item_key) else i18n.t("unit_per_min")
	var item_col := db.get_item_color(item_key)
	var is_ok := actual_rate >= planned_rate - 0.005 and planned_rate > 0.0
	
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	sb.border_color = item_col.darkened(0.15)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	
	row.add_child(builder.create_icon_slot(item_key, 32))
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	row.add_child(vbox)
	
	var top_line := HBoxContainer.new()
	vbox.add_child(top_line)
	
	var name_lbl := Label.new()
	name_lbl.text = db.get_item_display_name(item_key)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.modulate = Color.WHITE
	top_line.add_child(name_lbl)
	
	var rate_lbl := Label.new()
	rate_lbl.text = "%s%s" % [settings.fmt(actual_rate), unit]
	rate_lbl.modulate = Color.LIGHT_GREEN if is_ok else (Color.GOLD if actual_rate > 0.0 else Color.SALMON)
	top_line.add_child(rate_lbl)
	
	var sub_lbl := Label.new()
	var base_sub := i18n.tf("prod_row_sub", [settings.fmt(actual_rate), settings.fmt(planned_rate), unit, node_count])
	if is_sink_col:
		var pts_u := db.get_item_sink_points(item_key)
		base_sub += "  •  " + i18n.tf("sink_pts_fmt", [settings.fmt(actual_rate * float(pts_u)), pts_u])
	sub_lbl.text = base_sub
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.modulate = accent_col.lightened(0.35)
	vbox.add_child(sub_lbl)
	
	return card

func refresh() -> void:
	if win == null:
		return
	for vbox in [prod_col_container_vbox, prod_col_depot_vbox, prod_col_sink_vbox]:
		if vbox != null:
			for ch in vbox.get_children():
				ch.queue_free()
	
	var all_graphs: Array[GraphEdit] = [main_ctrl]
	for fid in main_ctrl.factory_graphs.keys():
		if is_instance_valid(main_ctrl.factory_graphs[fid]):
			all_graphs.append(main_ctrl.factory_graphs[fid])
	
	var data_container: Dictionary = {}
	var data_depot: Dictionary = {}
	var data_sink: Dictionary = {}
	var total_sink_points := 0.0
	
	for g in all_graphs:
		for ch in g.get_children():
			if not (ch is GraphNode and ch.has_meta("node_kind")):
				continue
			var kind: String = ch.get_meta("node_kind")
			if not (kind in ["container", "depot", "awesome_sink"]):
				continue
			
			var item_key: String = ch.get_meta("item", "iron-ore")
			var sup: Array = ch.get_meta("last_supplied", [0.0])
			var in_rate := float(sup[0]) if sup.size() > 0 else 0.0
			var plan_rate := float(ch.get_meta("planned_rate", 60.0))
			
			var net_stored := in_rate
			if kind == "container":
				var dem: Array = ch.get_meta("last_demanded", [0.0])
				var out_taken := float(dem[0]) if dem.size() > 0 else 0.0
				if out_taken > 0.0:
					net_stored = maxf(0.0, in_rate - out_taken)
			elif kind == "awesome_sink":
				total_sink_points += in_rate * float(db.get_item_sink_points(item_key))
			
			var target_dict: Dictionary = data_container if kind == "container" else (data_depot if kind == "depot" else data_sink)
			if not target_dict.has(item_key):
				target_dict[item_key] = {"actual": 0.0, "planned": 0.0, "count": 0}
			target_dict[item_key]["actual"] += net_stored if kind == "container" else in_rate
			target_dict[item_key]["planned"] += plan_rate
			target_dict[item_key]["count"] += 1
	
	var sum_cont := _populate_prod_column(prod_col_container_vbox, data_container, Color.html("#7AB0D4"), false)
	var sum_depot := _populate_prod_column(prod_col_depot_vbox, data_depot, Color.html("#BD60D3"), false)
	var sum_sink := _populate_prod_column(prod_col_sink_vbox, data_sink, Color.html("#E49246"), true)
	
	production_summary_lbl.text = i18n.tf("prod_summary_fmt", [
		settings.fmt(sum_cont["total_rate"]), data_container.size(),
		settings.fmt(sum_depot["total_rate"]), data_depot.size(),
		settings.fmt(sum_sink["total_rate"]), data_sink.size(),
		settings.fmt(total_sink_points)
	])
	
	var clip_lines: Array[String] = [
		production_summary_lbl.text,
		"",
		"=== " + i18n.t("prod_col_container") + " ===",
		sum_cont["clip"],
		"=== " + i18n.t("prod_col_depot") + " ===",
		sum_depot["clip"],
		"=== " + i18n.t("prod_col_sink") + " ===",
		sum_sink["clip"]
	]
	win.set_meta("last_clipboard_text", "\n".join(clip_lines))

func _populate_prod_column(vbox: VBoxContainer, dict_data: Dictionary, accent_col: Color, is_sink_col: bool = false) -> Dictionary:
	var total_rate := 0.0
	var clip_arr: Array[String] = []
	
	if dict_data.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = i18n.t("prod_empty_col")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.modulate = Color(1, 1, 1, 0.45)
		vbox.add_child(empty_lbl)
		return {"total_rate": 0.0, "clip": " - " + i18n.t("prod_empty_col")}
	
	var keys := dict_data.keys()
	keys.sort_custom(func(a, b): return float(dict_data[a]["actual"]) > float(dict_data[b]["actual"]))
	
	for ikey in keys:
		var entry: Dictionary = dict_data[ikey]
		var act := float(entry["actual"])
		var pln := float(entry["planned"])
		var cnt := int(entry["count"])
		total_rate += act
		vbox.add_child(_make_prod_item_row(ikey, act, pln, cnt, accent_col, is_sink_col))
		var unit := i18n.t("unit_fluid_per_min") if db.is_item_fluid(ikey) else i18n.t("unit_per_min")
		clip_arr.append(" - %s: %s / %s%s (%dx)" % [db.get_item_display_name(ikey), settings.fmt(act), settings.fmt(pln), unit, cnt])
	
	return {"total_rate": total_rate, "clip": "\n".join(clip_arr)}
