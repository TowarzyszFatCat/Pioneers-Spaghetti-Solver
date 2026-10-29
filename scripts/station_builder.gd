class_name StationBuilder
extends RefCounted

const STAT_WIDTH := 460.0

var builder: NodeBuilder
var main_ctrl: GraphEdit
var db: AppDB
var i18n: AppI18n
var styler: NodeStyler

func _init(p_builder: NodeBuilder, p_main: GraphEdit, p_db: AppDB, p_i18n: AppI18n, p_styler: NodeStyler) -> void:
	builder = p_builder
	main_ctrl = p_main
	db = p_db
	i18n = p_i18n
	styler = p_styler

func spawn_transport_station(g: GraphEdit, node_kind: String, initial_item: String, pos: Vector2) -> GraphNode:
	var node := GraphNode.new()
	node.name = "%s_%d" % [node_kind.capitalize().replace("_", ""), builder.node_counter]
	builder.node_counter += 1
	var is_truck := (node_kind == "truck_station")
	var valid_fuel := initial_item if db.is_item_fuel(initial_item) else "coal"

	node.title = i18n.t("truck_station_node" if is_truck else "train_station_node")
	node.position_offset = pos
	node.custom_minimum_size = Vector2(STAT_WIDTH, 0)
	node.size.x = STAT_WIDTH
	node.resizable = false

	node.set_meta("node_kind", node_kind)
	node.set_meta("fuel_item", valid_fuel)
	node.set_meta("fuel_rate", 15.0)
	node.set_meta("platforms_count", 1)
	# Route mode: "pingpong" (back & forth) or "loop" (closed loop)
	node.set_meta("station_mode", "pingpong")
	# Constant 50 MW for Train Station, 20 MW for Truck Station
	node.set_meta("power_mw", 20.0 if is_truck else 50.0)
	node.set_meta("is_built", false)
	node.set_meta("fixed_width", STAT_WIDTH)
	node.set_meta("station_out_items", [])
	node.set_meta("station_total_in", {})
	node.set_meta("station_avail", {})
	node.set_meta("station_taken", {})
	node.set_meta("station_leftover", {})
	node.set_meta("station_out_labels", [])

	var border_col := Color.html("#EB7D15") if is_truck else Color.html("#7AB0D4")
	var hdr_col := Color.html("#3A2416") if is_truck else Color.html("#1F2D42")
	styler.style_node_card(node, hdr_col, border_col, border_col)
	styler.setup_node_header_controls(node, "", func(): main_ctrl.delete_graph_node(g, node), true)

	g.add_child(node)
	rebuild_transport_station_rows(g, node)
	return node

func rebuild_transport_station_rows(g: GraphEdit, node: GraphNode) -> void:
	if not is_instance_valid(node) or not is_instance_valid(g):
		return
	var is_truck := (String(node.get_meta("node_kind")) == "truck_station")
	var old_plat_count := int(node.get_meta("prev_plat_count", int(node.get_meta("platforms_count", 1))))
	var new_plat_count := int(node.get_meta("platforms_count", 1))
	var old_out_items: Array = (node.get_meta("prev_out_items", []) as Array).duplicate()
	var cur_out_items: Array = node.get_meta("station_out_items", [])
	var old_link_in_port := (2 if is_truck else old_plat_count)
	var new_link_in_port := (2 if is_truck else new_plat_count)
	var old_link_out_port := old_out_items.size()
	var new_link_out_port := cur_out_items.size()

	var saved_in_conns: Array[Dictionary] = []
	var saved_out_conns: Array[Dictionary] = []
	if old_out_items != cur_out_items or old_plat_count != new_plat_count:
		for conn in g.get_connection_list():
			var fn: StringName = conn.get("from_node", conn.get("from", ""))
			var tn: StringName = conn.get("to_node", conn.get("to", ""))
			var fp := int(conn["from_port"])
			var tp := int(conn["to_port"])
			if tn == node.name:
				saved_in_conns.append({"fn": fn, "fp": fp, "tp": tp})
				g.disconnect_node(fn, fp, tn, tp)
			elif fn == node.name:
				saved_out_conns.append({"tn": tn, "tp": tp, "fp": fp})
				g.disconnect_node(fn, fp, tn, tp)

	node.set_meta("prev_plat_count", new_plat_count)
	node.set_meta("prev_out_items", cur_out_items.duplicate())

	for i in range(node.get_child_count() - 1, -1, -1):
		var ch := node.get_child(i)
		node.remove_child(ch)
		ch.queue_free()
	node.clear_all_slots()

	var child_idx := 0
	if is_truck:
		var f_item: String = String(node.get_meta("fuel_item", "coal"))
		if not db.is_item_fuel(f_item):
			f_item = "coal"
			node.set_meta("fuel_item", f_item)

		var fuel_row := HBoxContainer.new()
		fuel_row.add_theme_constant_override("separation", 6)
		fuel_row.add_child(styler.create_icon_slot(f_item, 24))

		var f_lbl := Label.new()
		f_lbl.text = i18n.t("fuel_in_lbl")
		fuel_row.add_child(f_lbl)

		var f_btn := Button.new()
		f_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		f_btn.clip_text = true
		styler.apply_item_button_visuals(f_btn, f_item)
		f_btn.pressed.connect(func():
			main_ctrl.open_item_picker(func(new_fuel: String):
				if db.is_item_fuel(new_fuel):
					node.set_meta("fuel_item", new_fuel)
					rebuild_transport_station_rows(g, node)
					main_ctrl.recalculate_all()
			, true)
		)
		fuel_row.add_child(f_btn)

		var f_spin := SpinBox.new()
		f_spin.min_value = 0.0
		f_spin.max_value = 2000.0
		f_spin.step = 0.5
		f_spin.value = float(node.get_meta("fuel_rate", 15.0))
		f_spin.suffix = i18n.t("unit_per_min")
		f_spin.custom_minimum_size = Vector2(95, 0)
		f_spin.value_changed.connect(func(v: float):
			node.set_meta("fuel_rate", v)
			main_ctrl.recalculate_all()
		)
		fuel_row.add_child(f_spin)

		var f_stat := Label.new()
		f_stat.custom_minimum_size = Vector2(55, 0)
		f_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fuel_row.add_child(f_stat)
		node.set_meta("fuel_status_lbl", f_stat)
		node.add_child(fuel_row)
		node.set_slot(child_idx, true, NodeBuilder.FUEL_PORT_TYPE, db.get_item_color(f_item), false, 0, Color.WHITE)
		child_idx += 1

		var cargo_in_row := HBoxContainer.new()
		cargo_in_row.add_theme_constant_override("separation", 8)
		cargo_in_row.add_child(styler.create_icon_slot("truck-station", 26, Color.html("#EB7D15")))

		var ci_lbl := Label.new()
		ci_lbl.text = i18n.t("cargo_in_mixed")
		ci_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ci_lbl.modulate = Color.html("#FAB757")
		cargo_in_row.add_child(ci_lbl)

		var pwr_lbl := Label.new()
		pwr_lbl.text = "⚡ 20 MW"
		pwr_lbl.modulate = Color.GOLD
		cargo_in_row.add_child(pwr_lbl)

		node.add_child(cargo_in_row)
		node.set_slot(child_idx, true, NodeBuilder.CARGO_ANY_PORT_TYPE, Color.html("#FAB757"), false, 0, Color.WHITE)
		child_idx += 1
	else:
		var ctrl_row := HBoxContainer.new()
		ctrl_row.add_theme_constant_override("separation", 6)
		ctrl_row.add_child(styler.create_icon_slot("train-station", 26, Color.html("#7AB0D4")))

		var p_title := Label.new()
		p_title.text = "%s %d" % [i18n.t("platforms_lbl"), new_plat_count]
		p_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_title.modulate = Color.LIGHT_SKY_BLUE
		ctrl_row.add_child(p_title)

		var add_p_btn := Button.new()
		add_p_btn.text = i18n.t("add_platform_btn")
		add_p_btn.modulate = Color.LIGHT_GREEN
		add_p_btn.pressed.connect(func():
			node.set_meta("platforms_count", clampi(new_plat_count + 1, 1, 12))
			rebuild_transport_station_rows(g, node)
			main_ctrl.recalculate_all()
		)
		ctrl_row.add_child(add_p_btn)

		if new_plat_count > 1:
			var rem_p_btn := Button.new()
			rem_p_btn.text = i18n.t("rem_platform_btn")
			rem_p_btn.modulate = Color.SALMON
			rem_p_btn.pressed.connect(func():
				node.set_meta("platforms_count", clampi(new_plat_count - 1, 1, 12))
				rebuild_transport_station_rows(g, node)
				main_ctrl.recalculate_all()
			)
			ctrl_row.add_child(rem_p_btn)

		var pwr_lbl := Label.new()
		pwr_lbl.text = "⚡ 50 MW"
		pwr_lbl.modulate = Color.GOLD
		node.set_meta("power_mw", 50.0)
		ctrl_row.add_child(pwr_lbl)

		node.add_child(ctrl_row)
		node.set_slot(child_idx, false, 0, Color.WHITE, false, 0, Color.WHITE)
		child_idx += 1

		while cur_out_items.size() < new_plat_count:
			cur_out_items.append("")
		if cur_out_items.size() > new_plat_count:
			cur_out_items.resize(new_plat_count)
		node.set_meta("station_out_items", cur_out_items)
		node.set_meta("prev_out_items", cur_out_items.duplicate())
		new_link_out_port = new_plat_count

		var out_labels: Array[Label] = []
		for p_idx in range(new_plat_count):
			var p_item: String = String(cur_out_items[p_idx])
			var has_item := (p_item != "")
			var out_type := db.get_item_type(p_item) if has_item else NodeBuilder.CARGO_ANY_PORT_TYPE
			var out_col := db.get_item_color(p_item) if has_item else Color(0.5, 0.6, 0.7, 0.5)

			var p_row := HBoxContainer.new()
			p_row.add_theme_constant_override("separation", 6)

			var pl_lbl := Label.new()
			pl_lbl.text = i18n.tf("platform_in_fmt", [p_idx + 1, p_idx + 1])
			pl_lbl.modulate = Color.AQUAMARINE
			p_row.add_child(pl_lbl)

			var o_lbl := Label.new()
			o_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			o_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			o_lbl.clip_text = true
			o_lbl.custom_minimum_size = Vector2(170, 22)
			o_lbl.text = i18n.t("station_empty_cargo") if not has_item else ""
			o_lbl.modulate = Color(1, 1, 1, 0.45) if not has_item else out_col.lightened(0.35)
			p_row.add_child(o_lbl)
			out_labels.append(o_lbl)

			if has_item:
				p_row.add_child(styler.create_icon_slot(p_item, 22))
			node.add_child(p_row)
			node.set_slot(child_idx, true, NodeBuilder.CARGO_ANY_PORT_TYPE, Color.AQUAMARINE, true, out_type, out_col)
			child_idx += 1
		node.set_meta("station_out_labels", out_labels)

	if is_truck:
		var sep := HSeparator.new()
		sep.modulate = Color(1, 1, 1, 0.25)
		node.add_child(sep)
		node.set_slot(child_idx, false, 0, Color.WHITE, false, 0, Color.WHITE)
		child_idx += 1

		var out_labels: Array[Label] = []
		if cur_out_items.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = i18n.t("station_empty_cargo")
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.modulate = Color(1, 1, 1, 0.45)
			node.add_child(empty_lbl)
			node.set_slot(child_idx, false, 0, Color.WHITE, false, 0, Color.WHITE)
			child_idx += 1
		else:
			for i in range(cur_out_items.size()):
				var ikey: String = String(cur_out_items[i])
				var it_type := db.get_item_type(ikey)
				var it_col := db.get_item_color(ikey)
				var out_row := HBoxContainer.new()
				out_row.add_theme_constant_override("separation", 6)

				var o_lbl := Label.new()
				o_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				o_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				o_lbl.clip_text = true
				o_lbl.custom_minimum_size = Vector2(220, 22)
				out_row.add_child(o_lbl)
				out_labels.append(o_lbl)
				out_row.add_child(styler.create_icon_slot(ikey, 22))
				node.add_child(out_row)
				node.set_slot(child_idx, false, 0, Color.WHITE, true, it_type, it_col)
				child_idx += 1
		node.set_meta("station_out_labels", out_labels)

	var link_panel := PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.14, 0.18, 0.25, 0.95)
	lsb.border_color = Color.html("#76F5E8")
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(5)
	lsb.content_margin_left = 8
	lsb.content_margin_right = 8
	lsb.content_margin_top = 4
	lsb.content_margin_bottom = 4
	link_panel.add_theme_stylebox_override("panel", lsb)

	var link_row := HBoxContainer.new()
	link_row.add_theme_constant_override("separation", 6)
	link_panel.add_child(link_row)

	var l_in := Label.new()
	l_in.text = i18n.t("station_link_in")
	l_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_in.modulate = Color.html("#76F5E8")
	link_row.add_child(l_in)

	var l_out := Label.new()
	l_out.text = i18n.t("station_link_out")
	l_out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_out.modulate = Color.html("#FAB757")
	link_row.add_child(l_out)

	node.add_child(link_panel)
	node.set_slot(
		child_idx,
		true,
		NodeBuilder.STATION_LINK_PORT_TYPE,
		Color.html("#76F5E8"),
		true,
		NodeBuilder.STATION_LINK_PORT_TYPE,
		Color.html("#FAB757")
	)

	for ic in saved_in_conns:
		var tp: int = int(ic["tp"])
		if tp == old_link_in_port:
			g.connect_node(ic["fn"], int(ic["fp"]), node.name, new_link_in_port)
		elif tp < new_link_in_port:
			g.connect_node(ic["fn"], int(ic["fp"]), node.name, tp)

	for oc in saved_out_conns:
		var fp: int = int(oc["fp"])
		if fp == old_link_out_port:
			g.connect_node(node.name, new_link_out_port, oc["tn"], int(oc["tp"]))
		elif not is_truck and fp < new_link_out_port:
			g.connect_node(node.name, fp, oc["tn"], int(oc["tp"]))
		elif is_truck and fp < old_out_items.size():
			var item_name: String = String(old_out_items[fp])
			var new_idx := cur_out_items.find(item_name)
			if new_idx != -1:
				g.connect_node(node.name, new_idx, oc["tn"], int(oc["tp"]))

	if bool(node.get_meta("is_locked", false)):
		styler.set_node_locked_state(node, true)
