class_name AutoChainTool
extends RefCounted

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var builder: NodeBuilder

var win: Window
var chain_item_btn: Button
var chain_rate_spin: SpinBox
var chain_miners_chk: CheckBox
var chain_factory_chk: CheckBox
var chain_preview_vbox: VBoxContainer
var chain_gen_btn: Button
var selected_chain_item: String = "modular-frame"
var _refs: Dictionary = {}

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n, p_builder: NodeBuilder) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	builder = p_builder
	if not db.items.has(selected_chain_item) and not db.item_order.is_empty():
		selected_chain_item = db.item_order[0]

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	win = Window.new()
	win.theme = theme_ref
	win.size = Vector2i(620, 560)
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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	var item_lbl := Label.new()
	row1.add_child(item_lbl)
	_refs["item_lbl"] = item_lbl

	chain_item_btn = Button.new()
	chain_item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain_item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	builder._apply_item_button_visuals(chain_item_btn, selected_chain_item)
	chain_item_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(new_item: String):
			selected_chain_item = new_item
			builder._apply_item_button_visuals(chain_item_btn, new_item)
			refresh_preview()
		)
	)
	row1.add_child(chain_item_btn)

	var rate_lbl := Label.new()
	row1.add_child(rate_lbl)
	_refs["rate_lbl"] = rate_lbl

	chain_rate_spin = SpinBox.new()
	chain_rate_spin.min_value = 0.0
	chain_rate_spin.max_value = 50000.0
	chain_rate_spin.step = 0.0001
	chain_rate_spin.custom_arrow_step = 1.0
	chain_rate_spin.value = 10.0
	chain_rate_spin.custom_minimum_size = Vector2(110, 0)
	chain_rate_spin.value_changed.connect(func(_v: float): refresh_preview())
	row1.add_child(chain_rate_spin)
	vbox.add_child(row1)

	chain_miners_chk = CheckBox.new()
	chain_miners_chk.button_pressed = true
	chain_miners_chk.toggled.connect(func(_v: bool): refresh_preview())
	vbox.add_child(chain_miners_chk)

	chain_factory_chk = CheckBox.new()
	chain_factory_chk.button_pressed = false
	vbox.add_child(chain_factory_chk)

	vbox.add_child(HSeparator.new())

	var prev_hdr := Label.new()
	prev_hdr.modulate = Color.GOLD
	vbox.add_child(prev_hdr)
	_refs["prev_hdr"] = prev_hdr

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	chain_preview_vbox = VBoxContainer.new()
	chain_preview_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain_preview_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(chain_preview_vbox)

	chain_gen_btn = Button.new()
	chain_gen_btn.custom_minimum_size = Vector2(0, 38)
	chain_gen_btn.modulate = Color.SPRING_GREEN
	chain_gen_btn.pressed.connect(func():
		win.hide()
		execute_generate_chain()
	)
	vbox.add_child(chain_gen_btn)
	return win

func open_window() -> void:
	refresh_translations()
	refresh_preview()
	win.popup_centered()

func refresh_translations() -> void:
	if win == null:
		return
	win.title = i18n.t("chain_win_title")
	_refs["item_lbl"].text = i18n.t("chain_target_item")
	_refs["rate_lbl"].text = i18n.t("chain_target_rate")
	chain_miners_chk.text = i18n.t("chain_spawn_miners")
	chain_factory_chk.text = i18n.t("chain_as_factory")
	_refs["prev_hdr"].text = i18n.t("chain_preview_hdr")
	chain_gen_btn.text = i18n.t("chain_generate_btn")
	builder._apply_item_button_visuals(chain_item_btn, selected_chain_item)
	if win.visible:
		refresh_preview()

func _find_best_standard_recipe_for_item(item_key: String, allow_miners: bool) -> String:
	# 1. Always use extraction for raw resources if an extractor/miner recipe exists
	var extract_id := "extract_" + item_key
	if db.recipes.has(extract_id):
		return extract_id if allow_miners else ""
	var well_id := "well_" + item_key
	if db.recipes.has(well_id):
		return well_id if allow_miners else ""

	# 2. For processed items, find the simplest standard recipe (excluding Converter ore transmutation and Alternates)
	var best_id := ""
	var best_score := 999999
	for r_id in db.recipes.keys():
		var r: Dictionary = db.recipes[r_id]
		if bool(r.get("is_generator", false)) or bool(r.get("is_miner", false)):
			continue
		if bool(r.get("is_alternate", false)):
			continue
		var b_key := String(r.get("building_key", ""))
		if b_key == "converter" and not (item_key in ["ficsite-ingot", "ficsite-trigon", "time-crystal", "dark-matter-crystal", "excited-photonic-matter"]):
			continue
		if String(r.get("raw_name_en", "")).begins_with("Unpackage "):
			continue
		var outs: Array = r.get("outputs", [])
		var produces := false
		for o in outs:
			if String(o["item"]) == item_key and float(o["rate"]) > 0.0:
				produces = true
				break
		if not produces:
			continue
		var score = outs.size() * 20 + r.get("inputs", []).size() * 10
		var clean_raw := String(r.get("raw_name_en", "")).to_lower().replace(" ", "-")
		if String(r_id) == item_key or clean_raw == item_key:
			score -= 100
		if score < best_score:
			best_score = score
			best_id = r_id
	return best_id

func _compute_chain_plan(target_item: String, target_rate: float, include_miners: bool) -> Dictionary:
	var item_recipe: Dictionary = {}
	var edges: Array[Dictionary] = []
	var visited_edges: Dictionary = {}
	var raw_inputs: Dictionary = {}

	# 1. Gather all recipes and dependency edges in the production chain
	var queue: Array[String] = [target_item]
	var discovered: Dictionary = {target_item: true}
	var guard := 0
	while not queue.is_empty() and guard < 256:
		guard += 1
		var cur_item: String = queue.pop_front()
		var r_id := _find_best_standard_recipe_for_item(cur_item, include_miners)
		if r_id == "":
			raw_inputs[cur_item] = true
			continue
		item_recipe[cur_item] = r_id
		var r_data: Dictionary = db.recipes[r_id]
		if bool(r_data.get("is_miner", false)):
			continue
		for inp in r_data["inputs"]:
			var in_item := String(inp["item"])
			if in_item == cur_item:
				continue
			var edge_key := "%s->%s" % [in_item, cur_item]
			if not visited_edges.has(edge_key):
				visited_edges[edge_key] = true
				edges.append({"from_item": in_item, "to_item": cur_item})
			if not discovered.has(in_item):
				discovered[in_item] = true
				queue.append(in_item)

	# 2. Compute topological depth (longest path from the final product)
	var item_depth: Dictionary = {target_item: 0}
	for it in discovered.keys():
		if not item_depth.has(it):
			item_depth[it] = 1
	for _iter in range(20):
		var changed := false
		for e in edges:
			var parent_it := String(e["to_item"])
			var child_it := String(e["from_item"])
			var want_d := mini(18, int(item_depth.get(parent_it, 0)) + 1)
			if want_d > int(item_depth.get(child_it, 0)):
				item_depth[child_it] = want_d
				changed = true
		if not changed:
			break

	# 3. Calculate exact demand in strict topological order (from depth 0 downwards)
	var items_by_depth := item_recipe.keys()
	items_by_depth.sort_custom(func(a, b): return int(item_depth.get(a, 0)) < int(item_depth.get(b, 0)))

	var exact_demand: Dictionary = {target_item: target_rate}
	for it in items_by_depth:
		var r_id: String = item_recipe[it]
		var r_data: Dictionary = db.recipes[r_id]
		var out_rate := 1.0
		for o in r_data["outputs"]:
			if String(o["item"]) == it:
				out_rate = float(o["rate"])
				break
		var m_cnt := float(exact_demand.get(it, 0.0)) / maxf(0.0001, out_rate)
		if settings.ceil_machines:
			m_cnt = ceilf(m_cnt)
		for inp in r_data["inputs"]:
			var in_it := String(inp["item"])
			if in_it != it:
				exact_demand[in_it] = float(exact_demand.get(in_it, 0.0)) + float(inp["rate"]) * m_cnt

	return {
		"item_recipe": item_recipe,
		"item_depth": item_depth,
		"item_demand": exact_demand,
		"edges": edges,
		"raw_inputs": raw_inputs
	}

func refresh_preview() -> void:
	if chain_preview_vbox == null:
		return
	for ch in chain_preview_vbox.get_children():
		ch.queue_free()
	var plan := _compute_chain_plan(selected_chain_item, chain_rate_spin.value, chain_miners_chk.button_pressed)
	var item_recipe: Dictionary = plan["item_recipe"]
	var item_depth: Dictionary = plan["item_depth"]
	var item_demand: Dictionary = plan["item_demand"]

	var sorted_items := item_recipe.keys()
	sorted_items.sort_custom(func(a, b): return int(item_depth[a]) > int(item_depth[b]))

	for ikey in sorted_items:
		var r_id: String = item_recipe[ikey]
		var r: Dictionary = db.recipes[r_id]
		var out_r := 1.0
		for o in r["outputs"]:
			if String(o["item"]) == ikey:
				out_r = float(o["rate"])
				break
		var dem := float(item_demand.get(ikey, 0.0))
		var m_cnt := dem / maxf(0.0001, out_r)
		if settings.ceil_machines:
			m_cnt = ceilf(m_cnt)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(builder.create_icon_slot(ikey, 26))

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%sx  %s   ➔   %s (%s%s)" % [
			settings.fmt(m_cnt), String(r["title"]),
			db.get_item_display_name(ikey), settings.fmt(dem), i18n.t("unit_per_min")
		]
		lbl.modulate = db.get_item_color(ikey).lightened(0.3)
		row.add_child(lbl)
		chain_preview_vbox.add_child(row)

func execute_generate_chain() -> void:
	main_ctrl._push_undo_state()
	var plan := _compute_chain_plan(selected_chain_item, chain_rate_spin.value, chain_miners_chk.button_pressed)
	var item_recipe: Dictionary = plan["item_recipe"]
	var item_depth: Dictionary = plan["item_depth"]
	var item_demand: Dictionary = plan["item_demand"]
	var edges: Array = plan["edges"]
	var raw_inputs: Dictionary = plan["raw_inputs"]
	if item_recipe.is_empty():
		return

	var target_g: GraphEdit = main_ctrl.active_graph
	var base_pos := (target_g.scroll_offset + target_g.size * 0.25) / target_g.zoom
	var created_fid := ""

	if chain_factory_chk.button_pressed:
		var f_title := "%s (%s/m)" % [db.get_item_display_name(selected_chain_item), settings.fmt(chain_rate_spin.value)]
		var f_node := builder.spawn_factory(target_g, base_pos, f_title)
		created_fid = String(f_node.get_meta("factory_id"))
		target_g = main_ctrl.factory_graphs[created_fid]
		base_pos = Vector2(460, 140)

	var max_d := 0
	var cols: Dictionary = {}
	for ikey in item_recipe.keys():
		var d := int(item_depth[ikey])
		max_d = maxi(max_d, d)
		if not cols.has(d):
			cols[d] = []
		cols[d].append(ikey)

	var spawned_by_item: Dictionary = {}
	var col_step_x := 580.0
	var row_step_y := 270.0

	for d in cols.keys():
		var col_idx := max_d - int(d)
		var items_in_col: Array = cols[d]
		for row_idx in range(items_in_col.size()):
			var ikey: String = items_in_col[row_idx]
			var r_id: String = item_recipe[ikey]
			var r_data: Dictionary = db.recipes[r_id]
			var out_r := 1.0
			for o in r_data["outputs"]:
				if String(o["item"]) == ikey:
					out_r = float(o["rate"])
					break
			var dem := float(item_demand.get(ikey, 0.0))
			var m_cnt := dem / maxf(0.0001, out_r)
			m_cnt = ceilf(m_cnt) if settings.ceil_machines else snappedf(m_cnt, 0.0001)
			var pos := base_pos + Vector2(float(col_idx) * col_step_x, float(row_idx) * row_step_y)
			var m_node := builder.spawn_machine(target_g, r_id, pos)
			m_node.set_meta("machines", m_cnt)
			if m_node.has_meta("spinbox"):
				(m_node.get_meta("spinbox") as SpinBox).set_value_no_signal(m_cnt)
			spawned_by_item[ikey] = m_node

	var tx_node: GraphNode = null
	var rx_nodes: Dictionary = {}
	if chain_factory_chk.button_pressed and spawned_by_item.has(selected_chain_item):
		var final_node: GraphNode = spawned_by_item[selected_chain_item]
		tx_node = builder.spawn_io_node(target_g, "transmitter", selected_chain_item, final_node.position_offset + Vector2(col_step_x, 0))
		tx_node.set_meta("planned_rate", chain_rate_spin.value)
		if tx_node.has_meta("plan_spin"):
			(tx_node.get_meta("plan_spin") as SpinBox).set_value_no_signal(chain_rate_spin.value)

		# Spawn Receiver nodes for raw inputs when miners are not included
		var rx_idx := 0
		for raw_k in raw_inputs.keys():
			var raw_dem := float(item_demand.get(raw_k, 60.0))
			var rx := builder.spawn_io_node(target_g, "receiver", raw_k, base_pos + Vector2(-380.0, float(rx_idx) * 200.0))
			rx.set_meta("planned_rate", raw_dem)
			if rx.has_meta("plan_spin"):
				(rx.get_meta("plan_spin") as SpinBox).set_value_no_signal(raw_dem)
			rx_nodes[raw_k] = rx
			rx_idx += 1
		if created_fid != "":
			builder.sync_factory_ports(created_fid)

	# Wait 1 frame so Godot registers all newly created node slots inside GraphEdit
	await main_ctrl.get_tree().process_frame

	for e in edges:
		var f_it := String(e["from_item"])
		var t_it := String(e["to_item"])
		if spawned_by_item.has(f_it) and spawned_by_item.has(t_it):
			var src_n: GraphNode = spawned_by_item[f_it]
			var dst_n: GraphNode = spawned_by_item[t_it]
			var src_r: Dictionary = db.recipes[src_n.get_meta("recipe_id")]
			var dst_r: Dictionary = db.recipes[dst_n.get_meta("recipe_id")]
			var fp := 0
			for i in range(src_r["outputs"].size()):
				if String(src_r["outputs"][i]["item"]) == f_it:
					fp = i
					break
			var tp := -1
			for i in range(dst_r["inputs"].size()):
				if String(dst_r["inputs"][i]["item"]) == f_it:
					tp = i
					break
			if tp != -1:
				target_g.connect_node(src_n.name, fp, dst_n.name, tp)
		elif rx_nodes.has(f_it) and spawned_by_item.has(t_it):
			var rx_n: GraphNode = rx_nodes[f_it]
			var dst_n: GraphNode = spawned_by_item[t_it]
			var dst_r: Dictionary = db.recipes[dst_n.get_meta("recipe_id")]
			for i in range(dst_r["inputs"].size()):
				if String(dst_r["inputs"][i]["item"]) == f_it:
					target_g.connect_node(rx_n.name, 0, dst_n.name, i)
					break

	if is_instance_valid(tx_node) and spawned_by_item.has(selected_chain_item):
		var final_node: GraphNode = spawned_by_item[selected_chain_item]
		var final_r: Dictionary = db.recipes[final_node.get_meta("recipe_id")]
		var final_fp := 0
		for i in range(final_r["outputs"].size()):
			if String(final_r["outputs"][i]["item"]) == selected_chain_item:
				final_fp = i
				break
		target_g.connect_node(final_node.name, final_fp, tx_node.name, 0)

	main_ctrl.recalculate_all()
