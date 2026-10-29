class_name AlertInspectorTool
extends RefCounted

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var builder: NodeBuilder
var nav_tool: NavigatorTool

var win: Window
var alert_list_vbox: VBoxContainer
var last_alert_count: int = 0

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n, p_builder: NodeBuilder, p_nav: NavigatorTool) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	builder = p_builder
	nav_tool = p_nav

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	win = Window.new()
	win.theme = theme_ref
	win.size = Vector2i(720, 520)
	win.visible = false
	win.close_requested.connect(func(): win.hide())
	parent_layer.add_child(win)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	win.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(scroll)

	alert_list_vbox = VBoxContainer.new()
	alert_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alert_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(alert_list_vbox)
	return win

func open_window() -> void:
	refresh_translations()
	refresh()
	win.popup_centered()

func refresh_translations() -> void:
	if win == null:
		return
	win.title = i18n.t("alert_win_title")
	if win.visible:
		refresh()

func scan_alerts() -> Dictionary:
	var starved: Array[Dictionary] = []
	var overloaded: Array[Dictionary] = []
	var all_graphs: Array[GraphEdit] = [main_ctrl]
	for fid in main_ctrl.factory_graphs.keys():
		if is_instance_valid(main_ctrl.factory_graphs[fid]):
			all_graphs.append(main_ctrl.factory_graphs[fid])

	for g in all_graphs:
		var gid: String = g.get_meta("graph_id", "world")
		var loc_name := i18n.t("world_map") if gid == "world" else ("🏭 " + String(main_ctrl.factory_nodes[gid].get_meta("custom_name", gid)) if main_ctrl.factory_nodes.has(gid) else gid)

		for ch in g.get_children():
			if not (ch is GraphNode and ch.has_meta("node_kind")):
				continue
			var node := ch as GraphNode
			var kind := String(node.get_meta("node_kind"))
			var sup: Array = node.get_meta("last_supplied", [])

			if kind == "machine":
				var r_id := String(node.get_meta("recipe_id", ""))
				if not db.recipes.has(r_id):
					continue
				var data: Dictionary = db.recipes[r_id]
				var m := float(node.get_meta("machines", 1.0))
				var clk := float(node.get_meta("clock", 100.0)) / 100.0
				var ins: Array = data.get("inputs", [])
				for i in range(ins.size()):
					var ikey := String(ins[i]["item"])
					var need := float(ins[i]["rate"]) * m * clk
					var s := float(sup[i]) if i < sup.size() else 0.0
					if need > 0.01 and s < need - 0.02:
						starved.append({
							"gid": gid, "loc": loc_name, "node": node,
							"item": ikey, "supplied": s, "needed": need
						})
			elif kind == "truck_station":
				var f_need := float(node.get_meta("fuel_rate", 15.0))
				var f_sup := float(sup[0]) if sup.size() > 0 else 0.0
				var f_item := String(node.get_meta("fuel_item", "coal"))
				if f_need > 0.01 and f_sup < f_need - 0.02:
					starved.append({
						"gid": gid, "loc": loc_name, "node": node,
						"item": f_item, "supplied": f_sup, "needed": f_need
					})

		var wire_flows: Dictionary = g.get_meta("wire_flows", {})
		for conn in g.get_connection_list():
			var fn: StringName = conn.get("from_node", conn.get("from", ""))
			var tn: StringName = conn.get("to_node", conn.get("to", ""))
			var fp := int(conn["from_port"])
			var tp := int(conn["to_port"])
			var w_key := "%s:%d->%s:%d" % [fn, fp, tn, tp]
			var info: Dictionary = wire_flows.get(w_key, {"rate": 0.0, "item": ""})
			if bool(info.get("is_station_link", false)) or String(info.get("item", "")) == "__station_route__":
				continue
			var rate := float(info["rate"])
			var ikey := String(info["item"])
			if ikey == "":
				continue
			var tier_info := db.get_min_logistics_tier(ikey, rate)
			var lim := settings.pipe_limit if db.is_item_fluid(ikey) else settings.belt_limit
			if bool(tier_info["over"]) or rate > lim + 0.05:
				var src := g.get_node_or_null(NodePath(fn)) as GraphNode
				if is_instance_valid(src):
					overloaded.append({
						"gid": gid, "loc": loc_name, "node": src,
						"item": ikey, "rate": rate, "label": String(tier_info["label"])
					})

	last_alert_count = starved.size() + overloaded.size()
	return {"starved": starved, "overloaded": overloaded, "total": last_alert_count}

func refresh() -> void:
	if alert_list_vbox == null:
		return
	for ch in alert_list_vbox.get_children():
		ch.queue_free()
	var res := scan_alerts()
	var starved: Array = res["starved"]
	var overloaded: Array = res["overloaded"]

	if starved.is_empty() and overloaded.is_empty():
		var ok_l := Label.new()
		ok_l.text = i18n.t("alert_none")
		ok_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ok_l.modulate = Color.SPRING_GREEN
		alert_list_vbox.add_child(ok_l)
		return

	var unit_m := i18n.t("unit_per_min")
	if not starved.is_empty():
		var hdr1 := Label.new()
		hdr1.text = i18n.t("alert_starved_hdr")
		hdr1.modulate = Color.SALMON
		alert_list_vbox.add_child(hdr1)
		for st in starved:
			var ikey: String = st["item"]
			var s := float(st["supplied"])
			var n := float(st["needed"])
			var sub := i18n.tf("alert_starved_sub", [
				db.get_item_display_name(ikey), settings.fmt(s), settings.fmt(n), unit_m,
				settings.fmt(n - s), unit_m
			])
			alert_list_vbox.add_child(_make_alert_card(ikey, "%s  (%s)" % [st["node"].title, st["loc"]], sub, Color.SALMON, st["gid"], st["node"]))

	if not overloaded.is_empty():
		var hdr2 := Label.new()
		hdr2.text = i18n.t("alert_belt_hdr")
		hdr2.modulate = Color.GOLD
		alert_list_vbox.add_child(hdr2)
		for ov in overloaded:
			var ikey: String = ov["item"]
			var r := float(ov["rate"])
			var sub := i18n.tf("alert_belt_sub", [
				db.get_item_display_name(ikey), settings.fmt(r), unit_m, ov["label"]
			])
			alert_list_vbox.add_child(_make_alert_card(ikey, "%s  (%s)" % [ov["node"].title, ov["loc"]], sub, Color.GOLD, ov["gid"], ov["node"]))

func _make_alert_card(ikey: String, title_txt: String, sub_txt: String, col: Color, gid: String, node: GraphNode) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.10, 0.11, 0.95)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	row.add_child(builder.create_icon_slot(ikey, 28, col))

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t_lbl := Label.new()
	t_lbl.text = title_txt
	t_lbl.clip_text = true
	vbox.add_child(t_lbl)

	var s_lbl := Label.new()
	s_lbl.text = sub_txt
	s_lbl.add_theme_font_size_override("font_size", 11)
	s_lbl.modulate = col.lightened(0.25)
	vbox.add_child(s_lbl)
	row.add_child(vbox)

	var jmp := Button.new()
	jmp.text = i18n.t("nav_jump_btn")
	jmp.modulate = Color.AQUAMARINE
	jmp.pressed.connect(func():
		win.hide()
		nav_tool.jump_to_node(gid, node)
	)
	row.add_child(jmp)
	return card
