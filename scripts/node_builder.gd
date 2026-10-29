class_name NodeBuilder
extends RefCounted

const MACHINE_WIDTH := 500.0
const MACHINE_COMPACT_WIDTH := 175.0
const FACTORY_WIDTH := 400.0
const IO_WIDTH := 300.0
const SPLITTER_WIDTH := 250.0
const FUEL_PORT_TYPE := 997
const CARGO_ANY_PORT_TYPE := 998
const STATION_LINK_PORT_TYPE := 999

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var styler: NodeStyler
var station_builder: StationBuilder

var factory_counter: int = 1
var node_counter: int = 1

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	styler = NodeStyler.new(main_ctrl, db, settings, i18n)
	station_builder = StationBuilder.new(self, main_ctrl, db, i18n, styler)

func _style_node_card(node: GraphNode, header_col: Color, border_col: Color, body_tint: Color = Color.TRANSPARENT) -> void:
	styler.style_node_card(node, header_col, border_col, body_tint)

func set_node_built_state(node: GraphNode, built: bool) -> void:
	styler.set_node_built_state(node, built)
	
func set_node_locked_state(node: GraphNode, locked: bool) -> void:
	styler.set_node_locked_state(node, locked)

func _setup_node_header_controls(node: GraphNode, item_key: String, on_delete: Callable, allow_built_check: bool = true) -> void:
	styler.setup_node_header_controls(node, item_key, on_delete, allow_built_check)

func update_header_color_buttons(node: GraphNode, item_key: String = "") -> void:
	styler.update_header_color_buttons(node, item_key)

func apply_compact_mode(node: GraphNode, is_compact: bool) -> void:
	styler.apply_compact_mode(node, is_compact, MACHINE_COMPACT_WIDTH)

func create_icon_slot(key_or_name: String, slot_size: int = 36, custom_col: Color = Color.TRANSPARENT) -> Control:
	return styler.create_icon_slot(key_or_name, slot_size, custom_col)

func _apply_item_button_visuals(btn: Button, item_key: String) -> void:
	styler.apply_item_button_visuals(btn, item_key)

func spawn_transport_station(g: GraphEdit, node_kind: String, initial_item: String, pos: Vector2) -> GraphNode:
	return station_builder.spawn_transport_station(g, node_kind, initial_item, pos)

func rebuild_transport_station_rows(g: GraphEdit, node: GraphNode) -> void:
	station_builder.rebuild_transport_station_rows(g, node)

func spawn_machine(g: GraphEdit, recipe_id: String, pos: Vector2) -> GraphNode:
	const COMPACT_MACHINE_W := 340.0
	var data: Dictionary = db.recipes[recipe_id]
	var inputs: Array = data["inputs"]
	var outputs: Array = data["outputs"]
	var is_miner: bool = data.get("is_miner", false)
	var has_mk_tiers: bool = data.get("has_mk_tiers", false)
	var is_gen: bool = data.get("is_generator", false)
	var b_key: String = data.get("building_key", "constructor")
	var b_name: String = data.get("building_name", data["category"])
	var max_sloops: int = int(data.get("somersloop_slots", db.get_building_somersloop_slots(b_key)))
	var main_item: String = outputs[0]["item"] if outputs.size() > 0 else (inputs[0]["item"] if inputs.size() > 0 else "")

	var node := GraphNode.new()
	node.name = "Machine_%d" % node_counter
	node_counter += 1
	node.title = data["title"]
	node.position_offset = pos
	var init_w := MACHINE_COMPACT_WIDTH if settings.compact_ui else COMPACT_MACHINE_W
	node.custom_minimum_size = Vector2(init_w, 0)
	node.size.x = init_w
	node.resizable = false

	node.set_meta("node_kind", "machine")
	node.set_meta("recipe_id", recipe_id)
	node.set_meta("machines", 1.0)
	node.set_meta("clock", 100.0)
	node.set_meta("purity", 1.0)
	node.set_meta("miner_mk", 1)
	node.set_meta("somersloops", 0)
	node.set_meta("max_somersloops", max_sloops)
	node.set_meta("is_built", false)
	node.set_meta("fixed_width", COMPACT_MACHINE_W)

	var cat_col := db.get_category_color(b_key, is_miner, is_gen)
	if main_item != "":
		var pal := db.get_item_palette(main_item)
		_style_node_card(node, pal["header"], pal["border"], pal["primary"])
	else:
		_style_node_card(node, cat_col.darkened(0.35), cat_col)
	_setup_node_header_controls(node, main_item, func(): main_ctrl.delete_graph_node(g, node), true)

	var in_labels: Array[Label] = []
	var out_labels: Array[Label] = []
	var max_rows := maxi(inputs.size(), outputs.size())
	for i in range(max_rows):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var has_in := i < inputs.size()
		var in_box := HBoxContainer.new()
		in_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		in_box.add_theme_constant_override("separation", 4)
		var in_lbl := Label.new()
		in_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		in_lbl.custom_minimum_size = Vector2(38 if settings.compact_ui else 90, 22)
		in_lbl.clip_text = true
		if has_in:
			in_box.add_child(create_icon_slot(inputs[i]["item"], 20))
			in_labels.append(in_lbl)
		in_box.add_child(in_lbl)
		row.add_child(in_box)

		var has_out := i < outputs.size()
		var out_box := HBoxContainer.new()
		out_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_box.alignment = BoxContainer.ALIGNMENT_END
		out_box.add_theme_constant_override("separation", 4)
		var out_lbl := Label.new()
		out_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		out_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_lbl.custom_minimum_size = Vector2(38 if settings.compact_ui else 90, 22)
		out_lbl.clip_text = true
		out_box.add_child(out_lbl)
		if has_out:
			out_box.add_child(create_icon_slot(outputs[i]["item"], 20))
			out_labels.append(out_lbl)
		row.add_child(out_box)

		node.add_child(row)
		var in_type := db.get_item_type(inputs[i]["item"]) if has_in else 0
		var in_col := db.get_item_color(inputs[i]["item"]) if has_in else Color.WHITE
		var out_type := db.get_item_type(outputs[i]["item"]) if has_out else 0
		var out_col := db.get_item_color(outputs[i]["item"]) if has_out else Color.WHITE
		node.set_slot(i, has_in, in_type, in_col, has_out, out_type, out_col)

	if max_rows > 0:
		var sep := HSeparator.new()
		sep.modulate = Color(1, 1, 1, 0.25)
		node.add_child(sep)
		node.set_meta("sep_row", sep)

	var showcase_row := HBoxContainer.new()
	showcase_row.add_theme_constant_override("separation", 6)
	showcase_row.add_child(create_icon_slot(b_key, 34, cat_col))
	if main_item != "":
		showcase_row.add_child(create_icon_slot(main_item, 34))

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 0)
	var rec_title_lbl := Label.new()
	rec_title_lbl.text = data.get("raw_name", data["title"])
	rec_title_lbl.clip_text = true
	rec_title_lbl.add_theme_font_size_override("font_size", 12)
	rec_title_lbl.modulate = Color(0.95, 0.96, 1.0)
	info_vbox.add_child(rec_title_lbl)
	node.set_meta("rec_title_lbl", rec_title_lbl)

	var b_lbl := Label.new()
	var cycle_s := float(data.get("time", 60.0))
	var init_b_disp := db.get_building_display_name("miner-mk1", "Miner MK1") if has_mk_tiers else b_name
	b_lbl.text = "%s • %ss" % [init_b_disp, settings.fmt(cycle_s)]
	b_lbl.clip_text = true
	b_lbl.add_theme_font_size_override("font_size", 10)
	var accent_col: Color = db.get_item_color(main_item) if main_item != "" else cat_col
	b_lbl.modulate = accent_col.lightened(0.35)
	info_vbox.add_child(b_lbl)
	showcase_row.add_child(info_vbox)
	node.set_meta("b_lbl", b_lbl)

	if is_miner:
		if has_mk_tiers:
			var mk_opt := OptionButton.new()
			mk_opt.add_item("Mk.1", 0)
			mk_opt.add_item("Mk.2", 1)
			mk_opt.add_item("Mk.3", 2)
			mk_opt.selected = 0
			mk_opt.tooltip_text = i18n.t("miner_mk_tooltip")
			mk_opt.modulate = Color.GOLD
			mk_opt.item_selected.connect(func(idx: int):
				var mk_level := idx + 1
				node.set_meta("miner_mk", mk_level)
				var mk_key := "miner-mk%d" % mk_level
				b_lbl.text = "%s • 60s" % db.get_building_display_name(mk_key, "Miner MK%d" % mk_level)
				main_ctrl.recalculate_all()
			)
			node.set_meta("mk_opt", mk_opt)
			showcase_row.add_child(mk_opt)

		var pur_opt := OptionButton.new()
		pur_opt.add_item(i18n.t("purity_impure"), 0)
		pur_opt.add_item(i18n.t("purity_normal"), 1)
		pur_opt.add_item(i18n.t("purity_pure"), 2)
		pur_opt.selected = 1
		pur_opt.tooltip_text = i18n.t("purity_tooltip")
		var pur_mults: Array[float] = [0.5, 1.0, 2.0]
		pur_opt.item_selected.connect(func(idx: int):
			node.set_meta("purity", pur_mults[idx])
			main_ctrl.recalculate_all()
		)
		node.set_meta("pur_opt", pur_opt)
		showcase_row.add_child(pur_opt)

	node.add_child(showcase_row)
	node.set_meta("showcase_row", showcase_row)

	# Control row 1: Machines count + quick multiplier buttons (x0.5, x2)
	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 4)
	var m_lbl := Label.new()
	m_lbl.text = i18n.t("machines")
	ctrl_row.add_child(m_lbl)
	node.set_meta("m_lbl", m_lbl)

	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 5000.0
	spin.step = 0.0001
	spin.custom_arrow_step = 1.0
	spin.value = 1.0
	spin.custom_minimum_size = Vector2(90, 0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(val: float):
		node.set_meta("machines", val)
		main_ctrl.recalculate_all()
	)
	ctrl_row.add_child(spin)

	var half_btn := Button.new()
	half_btn.text = "½"
	half_btn.custom_minimum_size = Vector2(24, 24)
	half_btn.tooltip_text = "Halve machine count"
	half_btn.pressed.connect(func():
		spin.value = maxf(0.0001, spin.value * 0.5)
	)
	ctrl_row.add_child(half_btn)

	var double_btn := Button.new()
	double_btn.text = "2×"
	double_btn.custom_minimum_size = Vector2(24, 24)
	double_btn.tooltip_text = "Double machine count"
	double_btn.pressed.connect(func():
		spin.value = spin.value * 2.0
	)
	ctrl_row.add_child(double_btn)

	node.add_child(ctrl_row)
	node.set_meta("ctrl_row", ctrl_row)

	# Control row 2: Auto IN, Auto OUT, OCA
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER

	if inputs.size() > 0:
		var auto_s_btn := Button.new()
		auto_s_btn.text = i18n.t("auto_sup")
		auto_s_btn.tooltip_text = i18n.t("auto_sup_tooltip")
		auto_s_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		auto_s_btn.pressed.connect(func():
			if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL):
				main_ctrl.auto_balance_chain_upstream(g, node)
			else:
				main_ctrl.auto_balance_node(g, node)
		)
		action_row.add_child(auto_s_btn)
		node.set_meta("auto_s_btn", auto_s_btn)

	if outputs.size() > 0:
		var auto_d_btn := Button.new()
		auto_d_btn.text = i18n.t("auto_dem")
		auto_d_btn.tooltip_text = i18n.t("auto_dem_tooltip")
		auto_d_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		auto_d_btn.pressed.connect(func():
			if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL):
				main_ctrl.auto_balance_chain_downstream(g, node)
			else:
				main_ctrl.auto_balance_node_to_demand(g, node)
		)
		action_row.add_child(auto_d_btn)
		node.set_meta("auto_d_btn", auto_d_btn)

	var oc_btn := Button.new()
	oc_btn.text = i18n.t("oc_helper")
	oc_btn.modulate = Color.KHAKI
	oc_btn.tooltip_text = i18n.t("oc_title")
	oc_btn.pressed.connect(func(): main_ctrl.open_overclock_helper(node))
	action_row.add_child(oc_btn)
	node.set_meta("oc_btn", oc_btn)

	node.add_child(action_row)
	node.set_meta("action_row", action_row)

	# Control row 3: Clock + Somersloop + Power
	var pwr_row := HBoxContainer.new()
	pwr_row.add_theme_constant_override("separation", 6)
	var clk_lbl := Label.new()
	clk_lbl.text = i18n.t("clock")
	pwr_row.add_child(clk_lbl)
	node.set_meta("clk_lbl", clk_lbl)

	var clk_spin := SpinBox.new()
	clk_spin.min_value = 0.0001
	clk_spin.max_value = 250.0
	clk_spin.step = 0.0001
	clk_spin.custom_arrow_step = 1.0
	clk_spin.value = 100.0
	clk_spin.suffix = "%"
	clk_spin.custom_minimum_size = Vector2(85, 0)
	clk_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clk_spin.value_changed.connect(func(val: float):
		node.set_meta("clock", val)
		main_ctrl.recalculate_all()
	)
	pwr_row.add_child(clk_spin)

	if max_sloops > 0:
		pwr_row.add_child(create_icon_slot("somersloop", 20))
		var sloop_opt := OptionButton.new()
		sloop_opt.tooltip_text = i18n.t("somersloop_tooltip")
		for s in range(max_sloops + 1):
			var boost_pct := int(roundf((float(s) / float(max_sloops)) * 100.0))
			sloop_opt.add_item("%d/%d (+%d%%)" % [s, max_sloops, boost_pct], s)
		sloop_opt.selected = 0
		sloop_opt.modulate = Color.html("#BD60D3").lightened(0.25)
		sloop_opt.item_selected.connect(func(idx: int):
			node.set_meta("somersloops", idx)
			main_ctrl.recalculate_all()
		)
		node.set_meta("sloop_opt", sloop_opt)
		pwr_row.add_child(sloop_opt)

	var pwr_lbl := Label.new()
	pwr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pwr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pwr_lbl.clip_text = true
	pwr_lbl.custom_minimum_size = Vector2(75, 22)
	pwr_lbl.modulate = Color.SPRING_GREEN if is_gen else Color.GOLD
	pwr_row.add_child(pwr_lbl)

	node.add_child(pwr_row)
	node.set_meta("in_labels", in_labels)
	node.set_meta("out_labels", out_labels)
	node.set_meta("spinbox", spin)
	node.set_meta("clk_spinbox", clk_spin)
	node.set_meta("pwr_row", pwr_row)
	node.set_meta("pwr_label", pwr_lbl)
	node.set_meta("last_supplied", [])
	node.set_meta("last_has_wire", [])
	node.set_meta("last_demanded", [])

	apply_compact_mode(node, settings.compact_ui)
	g.add_child(node)
	return node

func spawn_factory(parent_graph: GraphEdit, pos: Vector2, custom_title: String = "", forced_fid: String = "") -> GraphNode:
	var fid := forced_fid if forced_fid != "" else ("factory_%d" % factory_counter)
	if forced_fid == "":
		factory_counter += 1
	var parent_id: String = parent_graph.get_meta("graph_id", "world")
	if not main_ctrl.factory_graphs.has(fid):
		main_ctrl.create_factory_sub_graph(fid, parent_id)

	var default_name := custom_title if custom_title != "" else i18n.tf("factory_default_name", [factory_counter - 1])
	var node := GraphNode.new()
	node.name = "FactoryNode_%d" % node_counter
	node_counter += 1
	node.title = "🏭 " + default_name
	node.position_offset = pos
	node.custom_minimum_size = Vector2(FACTORY_WIDTH, 0)
	node.size.x = FACTORY_WIDTH
	node.resizable = false

	node.set_meta("node_kind", "factory")
	node.set_meta("factory_id", fid)
	node.set_meta("parent_graph_id", parent_id)
	node.set_meta("custom_name", default_name)
	node.set_meta("is_built", false)
	node.set_meta("fixed_width", FACTORY_WIDTH)
	node.set_meta("in_labels", [])
	node.set_meta("out_labels", [])
	node.set_meta("in_items", [])
	node.set_meta("out_items", [])

	_style_node_card(node, Color.html("#2D3248"), Color.html("#7AB0D4"), Color.html("#2D3248"))
	_setup_node_header_controls(node, "", func(): main_ctrl.delete_factory_recursive(fid, parent_graph, node), true)

	var header_box := VBoxContainer.new()
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_row.add_child(create_icon_slot("Factory", 34, Color.html("#7AB0D4")))

	var name_edit := LineEdit.new()
	name_edit.text = default_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(new_txt: String):
		node.set_meta("custom_name", new_txt)
		node.title = "🏭 " + new_txt
	)
	top_row.add_child(name_edit)
	header_box.add_child(top_row)

	var enter_btn := Button.new()
	enter_btn.text = i18n.t("enter_factory")
	enter_btn.modulate = Color.AQUAMARINE
	enter_btn.pressed.connect(func(): main_ctrl.enter_factory(fid))
	header_box.add_child(enter_btn)

	var stats_lbl := Label.new()
	stats_lbl.text = i18n.t("factory_stats_zero")
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.modulate = Color.GOLD
	header_box.add_child(stats_lbl)

	node.add_child(header_box)
	node.set_meta("enter_btn", enter_btn)
	node.set_meta("stats_label", stats_lbl)
	parent_graph.add_child(node)
	main_ctrl.factory_nodes[fid] = node
	sync_factory_ports(fid)
	return node

func spawn_io_node(g: GraphEdit, io_kind: String, initial_item: String, pos: Vector2) -> GraphNode:
	var node := GraphNode.new()
	node.name = "IO_%d" % node_counter
	node_counter += 1
	var is_receiver := (io_kind == "receiver")
	node.title = i18n.t("receiver_in") if is_receiver else i18n.t("transmitter_out")
	node.position_offset = pos
	node.custom_minimum_size = Vector2(IO_WIDTH, 0)
	node.size.x = IO_WIDTH
	node.resizable = false

	node.set_meta("node_kind", io_kind)
	node.set_meta("item", initial_item)
	node.set_meta("planned_rate", 60.0)
	node.set_meta("has_ext_wire", false)
	node.set_meta("is_built", false)
	node.set_meta("fixed_width", IO_WIDTH)

	var pal := db.get_item_palette(initial_item)
	_style_node_card(node, pal["header"], pal["border"], pal["primary"])
	_setup_node_header_controls(node, initial_item, func(): main_ctrl.delete_graph_node(g, node), false)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	var icon_holder := HBoxContainer.new()
	icon_holder.add_child(create_icon_slot(initial_item, 26))

	var flow_lbl := Label.new()
	flow_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow_lbl.custom_minimum_size = Vector2(180, 22)
	flow_lbl.clip_text = true
	flow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if is_receiver else HORIZONTAL_ALIGNMENT_LEFT

	if is_receiver:
		port_row.add_child(icon_holder)
		port_row.add_child(flow_lbl)
	else:
		port_row.add_child(flow_lbl)
		port_row.add_child(icon_holder)
	node.add_child(port_row)

	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 6)
	var item_btn := Button.new()
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_btn.clip_text = true
	_apply_item_button_visuals(item_btn, initial_item)
	node.set_meta("item_btn", item_btn)

	item_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(new_item: String):
			node.set_meta("item", new_item)
			_apply_item_button_visuals(item_btn, new_item)
			var new_pal := db.get_item_palette(new_item)
			_style_node_card(node, new_pal["header"], new_pal["border"], new_pal["primary"])
			update_header_color_buttons(node, new_item)
			for ch in icon_holder.get_children():
				ch.queue_free()
			icon_holder.add_child(create_icon_slot(new_item, 26))
			main_ctrl.remove_node_connections(g, node.name)
			_apply_io_slot(node)
			sync_factory_ports(g.get_meta("graph_id"))
			main_ctrl.recalculate_all()
		)
	)
	ctrl_row.add_child(item_btn)
	node.add_child(ctrl_row)
	node.set_meta("ctrl_row", ctrl_row)

	var plan_row := HBoxContainer.new()
	plan_row.add_theme_constant_override("separation", 6)
	var p_lbl := Label.new()
	p_lbl.text = i18n.t("planned_in") if is_receiver else i18n.t("planned_out")
	plan_row.add_child(p_lbl)

	var p_spin := SpinBox.new()
	p_spin.min_value = 0.0
	p_spin.max_value = 50000.0
	p_spin.step = 0.01
	p_spin.custom_arrow_step = 15.0
	p_spin.value = 60.0
	p_spin.suffix = i18n.t("unit_per_min")
	p_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_spin.value_changed.connect(func(v: float):
		node.set_meta("planned_rate", v)
		main_ctrl.recalculate_all()
	)
	plan_row.add_child(p_spin)
	node.add_child(plan_row)

	node.set_meta("plan_row", plan_row)
	node.set_meta("plan_label", p_lbl)
	node.set_meta("plan_spin", p_spin)
	node.set_meta("flow_label", flow_lbl)

	_apply_io_slot(node)
	apply_compact_mode(node, settings.compact_ui)
	g.add_child(node)
	sync_factory_ports(g.get_meta("graph_id"))
	return node

func _apply_io_slot(node: GraphNode) -> void:
	var io_kind: String = node.get_meta("node_kind")
	var item_key: String = node.get_meta("item")
	var t := db.get_item_type(item_key)
	var c := db.get_item_color(item_key)
	if io_kind == "receiver":
		node.set_slot(0, false, 0, Color.WHITE, true, t, c)
	else:
		node.set_slot(0, true, t, c, false, 0, Color.WHITE)

func spawn_splitter(g: GraphEdit, initial_item: String, pos: Vector2, sp_kind: String = "splitter") -> GraphNode:
	var node := GraphNode.new()
	node.name = "Splitter_%d" % node_counter
	node_counter += 1
	var title_key := "splitter_node"
	if sp_kind == "even_splitter":
		title_key = "even_splitter_node"
	elif sp_kind == "prop_splitter":
		title_key = "prop_splitter_node"
	node.title = i18n.t(title_key)
	node.position_offset = pos
	node.custom_minimum_size = Vector2(SPLITTER_WIDTH, 0)
	node.size.x = SPLITTER_WIDTH
	node.resizable = false

	node.set_meta("node_kind", sp_kind)
	node.set_meta("item", initial_item)
	node.set_meta("is_built", false)
	node.set_meta("fixed_width", SPLITTER_WIDTH)

	var pal := db.get_item_palette(initial_item)
	_style_node_card(node, pal["header"], pal["border"], pal["primary"])
	_setup_node_header_controls(node, initial_item, func(): main_ctrl.delete_graph_node(g, node), true)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var in_lbl := Label.new()
	in_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	in_lbl.clip_text = true

	var icon_holder := HBoxContainer.new()
	icon_holder.add_child(create_icon_slot(initial_item, 24))

	var out_lbl := Label.new()
	out_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	out_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_lbl.clip_text = true

	row.add_child(in_lbl)
	row.add_child(icon_holder)
	row.add_child(out_lbl)
	node.add_child(row)

	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 6)
	var item_btn := Button.new()
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_btn.clip_text = true
	_apply_item_button_visuals(item_btn, initial_item)
	node.set_meta("item_btn", item_btn)

	item_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(new_item: String):
			node.set_meta("item", new_item)
			_apply_item_button_visuals(item_btn, new_item)
			var new_pal := db.get_item_palette(new_item)
			_style_node_card(node, new_pal["header"], new_pal["border"], new_pal["primary"])
			update_header_color_buttons(node, new_item)
			for ch in icon_holder.get_children():
				ch.queue_free()
			icon_holder.add_child(create_icon_slot(new_item, 24))
			main_ctrl.remove_node_connections(g, node.name)
			var it := db.get_item_type(new_item)
			var ic := db.get_item_color(new_item)
			node.set_slot(0, true, it, ic, true, it, ic)
			main_ctrl.recalculate_all()
		)
	)
	ctrl_row.add_child(item_btn)
	node.add_child(ctrl_row)
	node.set_meta("ctrl_row", ctrl_row)

	var t := db.get_item_type(initial_item)
	var c := db.get_item_color(initial_item)
	node.set_slot(0, true, t, c, true, t, c)
	node.set_meta("in_label", in_lbl)
	node.set_meta("out_label", out_lbl)

	apply_compact_mode(node, settings.compact_ui)
	g.add_child(node)
	return node

func spawn_reroute_node(g: GraphEdit, initial_item: String, pos: Vector2) -> GraphNode:
	const REROUTE_W := 155.0
	var node := GraphNode.new()
	node.name = "Reroute_%d" % node_counter
	node_counter += 1
	node.title = i18n.t("reroute_short")
	node.position_offset = pos
	node.custom_minimum_size = Vector2(REROUTE_W, 0)
	node.size.x = REROUTE_W
	node.resizable = false

	node.set_meta("node_kind", "reroute")
	node.set_meta("item", initial_item)
	node.set_meta("is_built", true)
	node.set_meta("fixed_width", REROUTE_W)

	var pal := db.get_item_palette(initial_item)
	_style_node_card(node, pal["header"], pal["border"], pal["primary"])
	_setup_node_header_controls(node, "", func(): main_ctrl.delete_graph_node(g, node), false)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon_holder := HBoxContainer.new()
	icon_holder.add_child(create_icon_slot(initial_item, 22))
	row.add_child(icon_holder)

	var item_btn := Button.new()
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_btn.clip_text = true
	item_btn.text = "0"
	item_btn.tooltip_text = db.get_item_display_name(initial_item)
	node.set_meta("item_btn", item_btn)
	node.set_meta("icon_holder", icon_holder)

	item_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(new_item: String):
			set_reroute_node_item(node, new_item)
			main_ctrl.recalculate_all()
		)
	)
	row.add_child(item_btn)
	node.add_child(row)

	var t := db.get_item_type(initial_item)
	var c := db.get_item_color(initial_item)
	node.set_slot(0, true, CARGO_ANY_PORT_TYPE, c, true, t, c)
	node.set_meta("in_label", item_btn)
	node.set_meta("out_label", item_btn)
	g.add_child(node)
	return node

func set_reroute_node_item(node: GraphNode, new_item: String) -> void:
	if not is_instance_valid(node) or new_item == "" or new_item == "__station_route__":
		return
	node.set_meta("item", new_item)
	var new_pal := db.get_item_palette(new_item)
	_style_node_card(node, new_pal["header"], new_pal["border"], new_pal["primary"])
	if node.has_meta("icon_holder"):
		var ih: HBoxContainer = node.get_meta("icon_holder")
		if is_instance_valid(ih):
			for ch in ih.get_children():
				ch.queue_free()
			ih.add_child(create_icon_slot(new_item, 22))
	var it := db.get_item_type(new_item)
	var ic := db.get_item_color(new_item)
	node.set_slot(0, true, CARGO_ANY_PORT_TYPE, ic, true, it, ic)

func spawn_manual_splitter(g: GraphEdit, initial_item: String, pos: Vector2) -> GraphNode:
	const MAN_WIDTH := 330.0
	var node := GraphNode.new()
	node.name = "ManSplitter_%d" % node_counter
	node_counter += 1
	node.title = i18n.t("manual_splitter_node")
	node.position_offset = pos
	node.custom_minimum_size = Vector2(MAN_WIDTH, 0)
	node.size.x = MAN_WIDTH
	node.resizable = false

	node.set_meta("node_kind", "manual_splitter")
	node.set_meta("item", initial_item)
	node.set_meta("is_built", false)
	node.set_meta("fixed_width", MAN_WIDTH)
	node.set_meta("manual_overrides", [false, false, false])
	node.set_meta("manual_rates", [0.0, 0.0, 0.0])
	node.set_meta("actual_out_rates", [0.0, 0.0, 0.0])
	node.set_meta("updating_spins", false)

	var pal := db.get_item_palette(initial_item)
	_style_node_card(node, pal["header"], pal["border"], pal["primary"])
	_setup_node_header_controls(node, initial_item, func(): main_ctrl.delete_graph_node(g, node), true)

	var out_spins: Array[SpinBox] = []
	var out_tags: Array[Label] = []
	var in_lbl: Label = null
	var icon_holder: HBoxContainer = null

	for i in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		if i == 0:
			icon_holder = HBoxContainer.new()
			icon_holder.add_child(create_icon_slot(initial_item, 22))
			row.add_child(icon_holder)
			in_lbl = Label.new()
			in_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			in_lbl.clip_text = true
			row.add_child(in_lbl)
		else:
			var spc := Control.new()
			spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spc)

		var out_tag := Label.new()
		out_tag.text = i18n.tf("manual_out_fmt", [i + 1])
		out_tag.modulate = Color(0.75, 0.88, 1.0)
		row.add_child(out_tag)
		out_tags.append(out_tag)

		var spin := SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = 50000.0
		spin.step = 0.01
		spin.custom_arrow_step = 5.0
		spin.custom_minimum_size = Vector2(115, 0)
		spin.suffix = " (" + i18n.t("manual_auto_tag") + ")"
		var port_idx := i
		spin.value_changed.connect(func(v: float):
			if bool(node.get_meta("updating_spins", false)):
				return
			var ovr: Array = node.get_meta("manual_overrides", [false, false, false])
			var rts: Array = node.get_meta("manual_rates", [0.0, 0.0, 0.0])
			ovr[port_idx] = true
			rts[port_idx] = v
			node.set_meta("manual_overrides", ovr)
			node.set_meta("manual_rates", rts)
			main_ctrl.recalculate_all()
		)
		row.add_child(spin)
		out_spins.append(spin)
		node.add_child(row)

	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 6)
	var item_btn := Button.new()
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_btn.clip_text = true
	_apply_item_button_visuals(item_btn, initial_item)
	node.set_meta("item_btn", item_btn)

	item_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(new_item: String):
			node.set_meta("item", new_item)
			_apply_item_button_visuals(item_btn, new_item)
			var new_pal := db.get_item_palette(new_item)
			_style_node_card(node, new_pal["header"], new_pal["border"], new_pal["primary"])
			update_header_color_buttons(node, new_item)
			for ch in icon_holder.get_children():
				ch.queue_free()
			icon_holder.add_child(create_icon_slot(new_item, 22))
			main_ctrl.remove_node_connections(g, node.name)
			_apply_manual_splitter_slots(node)
			main_ctrl.recalculate_all()
		)
	)
	ctrl_row.add_child(item_btn)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 Auto"
	reset_btn.modulate = Color.AQUAMARINE
	reset_btn.tooltip_text = i18n.t("manual_reset_tooltip")
	reset_btn.pressed.connect(func():
		node.set_meta("manual_overrides", [false, false, false])
		node.set_meta("manual_rates", [0.0, 0.0, 0.0])
		main_ctrl.recalculate_all()
	)
	ctrl_row.add_child(reset_btn)
	node.add_child(ctrl_row)
	node.set_meta("ctrl_row", ctrl_row)

	node.set_meta("in_label", in_lbl)
	node.set_meta("out_spins", out_spins)
	node.set_meta("out_tags", out_tags)
	node.set_meta("reset_btn", reset_btn)

	_apply_manual_splitter_slots(node)
	apply_compact_mode(node, settings.compact_ui)
	g.add_child(node)
	return node

func _apply_manual_splitter_slots(node: GraphNode) -> void:
	var item_key: String = node.get_meta("item")
	var t := db.get_item_type(item_key)
	var c := db.get_item_color(item_key)
	node.set_slot(0, true, t, c, true, t, c)
	node.set_slot(1, false, 0, Color.WHITE, true, t, c)
	node.set_slot(2, false, 0, Color.WHITE, true, t, c)

func spawn_storage_sink_node(g: GraphEdit, node_kind: String, initial_item: String, pos: Vector2) -> GraphNode:
	var node := GraphNode.new()
	node.name = "%s_%d" % [node_kind.capitalize().replace("_", ""), node_counter]
	node_counter += 1
	var has_output := (node_kind == "container")
	var default_rate := 240.0 if node_kind == "depot" else 60.0
	var pwr_mw := 30.0 if node_kind == "awesome_sink" else (10.0 if node_kind == "depot" else 0.0)
	var b_icon_key := "awesome-sink" if node_kind == "awesome_sink" else ("dimensional-depot" if node_kind == "depot" else "storage-container")
	var accent_col := Color.html("#E49246") if node_kind == "awesome_sink" else (Color.html("#BD60D3") if node_kind == "depot" else Color.html("#7AB0D4"))
	var title_key := "container_node"
	if node_kind == "awesome_sink":
		title_key = "awesome_sink_node"
	elif node_kind == "depot":
		title_key = "depot_node"

	node.title = i18n.t(title_key)
	node.position_offset = pos
	node.custom_minimum_size = Vector2(IO_WIDTH, 0)
	node.size.x = IO_WIDTH
	node.resizable = false

	node.set_meta("node_kind", node_kind)
	node.set_meta("item", initial_item)
	node.set_meta("planned_rate", default_rate)
	node.set_meta("power_mw", pwr_mw)
	node.set_meta("is_built", false)
	node.set_meta("fixed_width", IO_WIDTH)

	var pal := db.get_item_palette(initial_item)
	_style_node_card(node, pal["header"], accent_col, pal["primary"])
	_setup_node_header_controls(node, initial_item, func(): main_ctrl.delete_graph_node(g, node), true)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 6)
	port_row.add_child(create_icon_slot(b_icon_key, 26, accent_col))
	var icon_holder := HBoxContainer.new()
	icon_holder.add_child(create_icon_slot(initial_item, 26))
	port_row.add_child(icon_holder)

	var flow_lbl := Label.new()
	flow_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow_lbl.custom_minimum_size = Vector2(140, 22)
	flow_lbl.clip_text = true
	port_row.add_child(flow_lbl)
	node.add_child(port_row)

	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 6)
	var item_btn := Button.new()
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_btn.clip_text = true
	_apply_item_button_visuals(item_btn, initial_item)
	node.set_meta("item_btn", item_btn)

	item_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(new_item: String):
			node.set_meta("item", new_item)
			_apply_item_button_visuals(item_btn, new_item)
			var new_pal := db.get_item_palette(new_item)
			_style_node_card(node, new_pal["header"], accent_col, new_pal["primary"])
			update_header_color_buttons(node, new_item)
			for ch in icon_holder.get_children():
				ch.queue_free()
			icon_holder.add_child(create_icon_slot(new_item, 26))
			main_ctrl.remove_node_connections(g, node.name)
			var it := db.get_item_type(new_item)
			var ic := db.get_item_color(new_item)
			node.set_slot(0, true, it, ic, has_output, it if has_output else 0, ic if has_output else Color.WHITE)
			main_ctrl.recalculate_all()
		)
	)
	ctrl_row.add_child(item_btn)
	node.add_child(ctrl_row)
	node.set_meta("ctrl_row", ctrl_row)

	var plan_row := HBoxContainer.new()
	plan_row.add_theme_constant_override("separation", 6)
	var p_lbl := Label.new()
	var lbl_key := "store_rate_lbl"
	if node_kind == "awesome_sink":
		lbl_key = "sink_rate_lbl"
	elif node_kind == "depot":
		lbl_key = "depot_rate_lbl"
	p_lbl.text = i18n.t(lbl_key)
	plan_row.add_child(p_lbl)

	var p_spin := SpinBox.new()
	p_spin.min_value = 0.0
	p_spin.max_value = 50000.0
	p_spin.step = 0.01
	p_spin.custom_arrow_step = 15.0
	p_spin.value = default_rate
	p_spin.suffix = i18n.t("unit_per_min")
	p_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_spin.value_changed.connect(func(v: float):
		node.set_meta("planned_rate", v)
		main_ctrl.recalculate_all()
	)
	plan_row.add_child(p_spin)

	if pwr_mw > 0.0:
		var pwr_tag := Label.new()
		pwr_tag.text = "⚡%dMW" % int(pwr_mw)
		pwr_tag.modulate = Color.GOLD
		plan_row.add_child(pwr_tag)

	node.add_child(plan_row)
	node.set_meta("plan_row", plan_row)

	var t := db.get_item_type(initial_item)
	var c := db.get_item_color(initial_item)
	node.set_slot(0, true, t, c, has_output, t if has_output else 0, ic_or_white(c, has_output))
	node.set_meta("plan_label", p_lbl)
	node.set_meta("plan_spin", p_spin)
	node.set_meta("flow_label", flow_lbl)

	apply_compact_mode(node, settings.compact_ui)
	g.add_child(node)
	return node

func ic_or_white(c: Color, cond: bool) -> Color:
	return c if cond else Color.WHITE

func sync_factory_ports(fid: String) -> void:
	if not main_ctrl.factory_nodes.has(fid) or not main_ctrl.factory_graphs.has(fid):
		return
	var f_node: GraphNode = main_ctrl.factory_nodes[fid]
	var f_graph: GraphEdit = main_ctrl.factory_graphs[fid]
	if not is_instance_valid(f_node) or not is_instance_valid(f_graph):
		return

	var receivers: Array = []
	var transmitters: Array = []
	for ch in f_graph.get_children():
		if is_instance_valid(ch) and not ch.is_queued_for_deletion() and ch is GraphNode and ch.has_meta("node_kind"):
			var kind: String = ch.get_meta("node_kind")
			if kind == "receiver":
				receivers.append(ch)
			elif kind == "transmitter":
				transmitters.append(ch)

	# Sort by Y position so factory pins match the top-to-bottom order inside the factory
	receivers.sort_custom(func(a: GraphNode, b: GraphNode): return a.position_offset.y < b.position_offset.y)
	transmitters.sort_custom(func(a: GraphNode, b: GraphNode): return a.position_offset.y < b.position_offset.y)

	f_node.clear_all_slots()
	for i in range(f_node.get_child_count() - 1, 0, -1):
		var old_row: Node = f_node.get_child(i)
		f_node.remove_child(old_row)
		old_row.free()

	var in_labels: Array[Label] = []
	var out_labels: Array[Label] = []
	var in_items: Array[String] = []
	var out_items: Array[String] = []

	var max_ports := maxi(receivers.size(), transmitters.size())
	if max_ports == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = i18n.t("empty_factory_io")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(1, 1, 1, 0.5)
		f_node.add_child(empty_lbl)
		f_node.set_meta("empty_lbl", empty_lbl)
		f_node.set_slot(0, false, 0, Color.WHITE, false, 0, Color.WHITE)
		f_node.set_slot(1, false, 0, Color.WHITE, false, 0, Color.WHITE)
	else:
		f_node.set_meta("empty_lbl", null)
		f_node.set_slot(0, false, 0, Color.WHITE, false, 0, Color.WHITE)

	for i in range(max_ports):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var has_in := i < receivers.size()
		var in_item: String = receivers[i].get_meta("item") if has_in else ""
		var in_box := HBoxContainer.new()
		in_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var in_lbl := Label.new()
		in_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		in_lbl.custom_minimum_size = Vector2(125, 22)
		in_lbl.clip_text = true
		if has_in:
			in_box.add_child(create_icon_slot(in_item, 20))
			in_labels.append(in_lbl)
			in_items.append(in_item)
		in_box.add_child(in_lbl)
		row.add_child(in_box)

		var has_out := i < transmitters.size()
		var out_item: String = transmitters[i].get_meta("item") if has_out else ""
		var out_box := HBoxContainer.new()
		out_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_box.alignment = BoxContainer.ALIGNMENT_END
		var out_lbl := Label.new()
		out_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		out_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_lbl.custom_minimum_size = Vector2(125, 22)
		out_lbl.clip_text = true
		out_box.add_child(out_lbl)
		if has_out:
			out_box.add_child(create_icon_slot(out_item, 20))
			out_labels.append(out_lbl)
			out_items.append(out_item)
		row.add_child(out_box)

		f_node.add_child(row)
		var slot_idx := f_node.get_child_count() - 1
		f_node.set_slot(
			slot_idx,
			has_in,
			db.get_item_type(in_item) if has_in else 0,
			db.get_item_color(in_item) if has_in else Color.WHITE,
			has_out,
			db.get_item_type(out_item) if has_out else 0,
			db.get_item_color(out_item) if has_out else Color.WHITE
		)

	f_node.set_meta("receivers", receivers)
	f_node.set_meta("transmitters", transmitters)
	f_node.set_meta("in_labels", in_labels)
	f_node.set_meta("out_labels", out_labels)
	f_node.set_meta("in_items", in_items)
	f_node.set_meta("out_items", out_items)
	var target_w := MACHINE_COMPACT_WIDTH if settings.compact_ui else FACTORY_WIDTH
	f_node.size = Vector2(target_w, 0)
