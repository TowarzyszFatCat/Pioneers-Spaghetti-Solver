class_name ShoppingListModal
extends RefCounted

var main_ctrl: GraphEdit
var db: AppDB
var i18n: AppI18n
var builder: NodeBuilder

var win: Window
var shopping_vbox: VBoxContainer
var belt_margin_title_lbl: Label
var belt_margin_slider: HSlider
var belt_margin_label: Label

func _init(p_main: GraphEdit, p_db: AppDB, p_i18n: AppI18n, p_builder: NodeBuilder) -> void:
	main_ctrl = p_main
	db = p_db
	i18n = p_i18n
	builder = p_builder

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	win = Window.new()
	win.theme = theme_ref
	win.title = i18n.t("shop_title")
	win.size = Vector2i(780, 640)
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
	main_v.add_theme_constant_override("separation", 10)
	margin.add_child(main_v)
	
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 10)
	belt_margin_title_lbl = Label.new()
	belt_margin_title_lbl.text = i18n.t("belt_margin")
	slider_row.add_child(belt_margin_title_lbl)
	
	belt_margin_slider = HSlider.new()
	belt_margin_slider.min_value = 0.0
	belt_margin_slider.max_value = 100.0
	belt_margin_slider.step = 5.0
	belt_margin_slider.value = 20.0
	belt_margin_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	belt_margin_slider.value_changed.connect(func(_v: float): refresh())
	slider_row.add_child(belt_margin_slider)
	
	belt_margin_label = Label.new()
	belt_margin_label.text = "+20%"
	belt_margin_label.modulate = Color.GOLD
	belt_margin_label.custom_minimum_size = Vector2(48, 0)
	slider_row.add_child(belt_margin_label)
	
	var reset_chk_btn := Button.new()
	reset_chk_btn.text = i18n.t("shop_reset_checks_btn")
	reset_chk_btn.pressed.connect(func():
		main_ctrl.checked_shopping_items.clear()
		refresh()
	)
	slider_row.add_child(reset_chk_btn)
	win.set_meta("reset_chk_btn", reset_chk_btn)
	
	var copy_shop_btn := Button.new()
	copy_shop_btn.text = i18n.t("shop_copy_btn")
	copy_shop_btn.modulate = Color.AQUAMARINE
	copy_shop_btn.pressed.connect(func():
		var clip_txt: String = String(win.get_meta("last_clipboard_text", ""))
		if clip_txt != "":
			DisplayServer.clipboard_set(clip_txt)
	)
	slider_row.add_child(copy_shop_btn)
	win.set_meta("copy_shop_btn", copy_shop_btn)
	
	main_v.add_child(slider_row)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_child(scroll)
	
	shopping_vbox = VBoxContainer.new()
	shopping_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shopping_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(shopping_vbox)
	return win

func open_window() -> void:
	refresh_translations()
	refresh()
	win.popup_centered()

func refresh_translations() -> void:
	if win == null:
		return
	win.title = i18n.t("shop_title")
	if belt_margin_title_lbl:
		belt_margin_title_lbl.text = i18n.t("belt_margin")
	if win.has_meta("reset_chk_btn"):
		(win.get_meta("reset_chk_btn") as Button).text = i18n.t("shop_reset_checks_btn")
	if win.has_meta("copy_shop_btn"):
		(win.get_meta("copy_shop_btn") as Button).text = i18n.t("shop_copy_btn")
	if win.visible:
		refresh()

func _is_graph_marked_built(g: GraphEdit) -> bool:
	var cur_id: String = g.get_meta("graph_id", "world")
	var guard := 0
	while cur_id != "world" and cur_id != "" and guard < 32:
		guard += 1
		if main_ctrl.factory_nodes.has(cur_id) and is_instance_valid(main_ctrl.factory_nodes[cur_id]):
			if bool(main_ctrl.factory_nodes[cur_id].get_meta("is_built", false)):
				return true
		cur_id = main_ctrl.factory_parents.get(cur_id, "world")
	return false

func _make_shop_item_card(icon_key: String, title_txt: String, sub_txt: String, chk_key: String, accent_col: Color) -> PanelContainer:
	var is_done: bool = main_ctrl.checked_shopping_items.get(chk_key, false)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.14, 0.11, 0.85) if is_done else Color(0.12, 0.14, 0.18, 0.95)
	sb.border_color = Color.html("#4B8052") if is_done else accent_col.darkened(0.25)
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
	
	var chk := CheckBox.new()
	chk.button_pressed = is_done
	row.add_child(chk)
	
	row.add_child(builder.create_icon_slot(icon_key, 32, accent_col))
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	row.add_child(vbox)
	
	var t_lbl := Label.new()
	t_lbl.text = title_txt
	t_lbl.clip_text = true
	t_lbl.modulate = Color(0.65, 0.85, 0.7, 0.8) if is_done else Color.WHITE
	vbox.add_child(t_lbl)
	
	if sub_txt != "":
		var s_lbl := Label.new()
		s_lbl.text = sub_txt
		s_lbl.clip_text = true
		s_lbl.add_theme_font_size_override("font_size", 11)
		s_lbl.modulate = Color(0.55, 0.7, 0.6, 0.7) if is_done else accent_col.lightened(0.35)
		vbox.add_child(s_lbl)
	
	chk.toggled.connect(func(v: bool):
		main_ctrl.checked_shopping_items[chk_key] = v
		refresh()
	)
	return card

func refresh() -> void:
	if shopping_vbox == null:
		return
	for ch in shopping_vbox.get_children():
		ch.queue_free()
	
	var margin_pct := belt_margin_slider.value
	belt_margin_label.text = "+%d%%" % int(margin_pct)
	var mult := 1.0 + (margin_pct / 100.0)
	
	var all_graphs: Array[GraphEdit] = [main_ctrl]
	for fid in main_ctrl.factory_graphs.keys():
		if is_instance_valid(main_ctrl.factory_graphs[fid]):
			all_graphs.append(main_ctrl.factory_graphs[fid])
	
	var building_counts: Dictionary = {}
	var building_keys: Dictionary = {}
	var total_foundations := 0.0
	var material_costs: Dictionary = {}
	var total_somersloops := 0
	var total_shards := 0
	var total_machine_nodes := 0
	var built_machine_nodes := 0
	var special_shop_kinds := ["awesome_sink", "depot", "container", "truck_station", "train_station", "splitter", "even_splitter", "prop_splitter", "manual_splitter"]
	
	for g in all_graphs:
		var graph_built := _is_graph_marked_built(g)
		for ch in g.get_children():
			if ch is GraphNode and ch.get_meta("node_kind", "") == "machine":
				var r_id: String = ch.get_meta("recipe_id")
				if not db.recipes.has(r_id):
					continue
				total_machine_nodes += 1
				var node_built := graph_built or bool(ch.get_meta("is_built", false))
				if node_built:
					built_machine_nodes += 1
					continue
				
				var data: Dictionary = db.recipes[r_id]
				var is_miner: bool = data.get("is_miner", false)
				var b_key: String = data.get("building_key", "constructor")
				var b_name: String = data.get("building_name", data["category"])
				
				if data.get("has_mk_tiers", false):
					var mk_lvl := clampi(int(ch.get_meta("miner_mk", 1)), 1, 3)
					var t_info: Dictionary = db.MINER_TIERS.get(mk_lvl, db.MINER_TIERS[1])
					b_key = String(t_info["key"])
					b_name = db.get_building_display_name(b_key, String(t_info["name"]))
				
				var count := int(ceilf(float(ch.get_meta("machines"))))
				if count <= 0:
					continue
				building_counts[b_name] = building_counts.get(b_name, 0) + count
				building_keys[b_name] = b_key
				
				var b_meta: Dictionary = db.BUILDING_META.get(b_key, {"foundations": 2.0, "cost": {}})
				if not is_miner:
					total_foundations += float(b_meta["foundations"]) * count * 1.35
				
				var sloops_per_m := int(ch.get_meta("somersloops", 0))
				total_somersloops += sloops_per_m * count
				
				var clk := float(ch.get_meta("clock", 100.0))
				if clk > 100.0001:
					var shards_per_m := int(ceilf((clk - 100.0) / 50.0))
					total_shards += shards_per_m * count
				
				var cost_dict: Dictionary = b_meta["cost"]
				for mat_key in cost_dict.keys():
					material_costs[mat_key] = material_costs.get(mat_key, 0) + int(ceilf(float(cost_dict[mat_key]) * count * mult))
					
			elif ch is GraphNode and ch.get_meta("node_kind", "") in special_shop_kinds:
				total_machine_nodes += 1
				var node_built := graph_built or bool(ch.get_meta("is_built", false))
				if node_built:
					built_machine_nodes += 1
					continue
				var skind: String = ch.get_meta("node_kind")
				var b_key := "splitter"
				if skind == "awesome_sink": b_key = "awesome-sink"
				elif skind == "depot": b_key = "dimensional-depot"
				elif skind == "container": b_key = "storage-container"
				elif skind == "truck_station": b_key = "truck-station"
				elif skind == "train_station": b_key = "train-station"
				var b_name := db.get_building_display_name(b_key, i18n.t(skind + "_node"))
				building_counts[b_name] = building_counts.get(b_name, 0) + 1
				building_keys[b_name] = b_key
				var b_meta: Dictionary = db.BUILDING_META.get(b_key, {"foundations": 1.0, "cost": {}})
				total_foundations += float(b_meta["foundations"]) * 1.2
				var cost_dict: Dictionary = b_meta["cost"]
				for mat_key in cost_dict.keys():
					material_costs[mat_key] = material_costs.get(mat_key, 0) + int(ceilf(float(cost_dict[mat_key]) * mult))
	
	var total_inv_slots := 0
	for mat_key in material_costs.keys():
		var amt: int = material_costs[mat_key]
		var stack: int = int(db.items.get(mat_key, {}).get("stack_size", 100))
		total_inv_slots += int(ceilf(float(amt) / float(stack)))
	
	var summary_card := PanelContainer.new()
	var sum_sb := StyleBoxFlat.new()
	sum_sb.bg_color = Color(0.09, 0.12, 0.17, 0.96)
	sum_sb.border_color = Color(0.3, 0.75, 0.95, 0.7)
	sum_sb.set_border_width_all(1)
	sum_sb.set_corner_radius_all(6)
	sum_sb.content_margin_left = 12
	sum_sb.content_margin_right = 12
	sum_sb.content_margin_top = 8
	sum_sb.content_margin_bottom = 8
	summary_card.add_theme_stylebox_override("panel", sum_sb)
	
	var sum_vbox := VBoxContainer.new()
	sum_vbox.add_theme_constant_override("separation", 6)
	summary_card.add_child(sum_vbox)
	
	var pct := int(roundf((float(built_machine_nodes) / float(maxi(1, total_machine_nodes))) * 100.0)) if total_machine_nodes > 0 else 0
	var prog_lbl := Label.new()
	prog_lbl.text = i18n.tf("shop_progress_fmt", [built_machine_nodes, total_machine_nodes, pct, total_inv_slots])
	prog_lbl.modulate = Color.SPRING_GREEN if (total_machine_nodes > 0 and built_machine_nodes == total_machine_nodes) else Color.WHITE
	sum_vbox.add_child(prog_lbl)
	
	var grid_side := int(ceilf(sqrt(maxf(1.0, total_foundations))))
	var grid_hdr := Label.new()
	grid_hdr.text = i18n.tf("shop_footprint", [
		int(ceilf(total_foundations)), grid_side, grid_side, grid_side * 8, grid_side * 8
	])
	grid_hdr.modulate = Color.AQUAMARINE
	sum_vbox.add_child(grid_hdr)
	
	if total_somersloops > 0 or total_shards > 0:
		var boost_lbl := Label.new()
		boost_lbl.text = i18n.tf("shop_boosters", [total_somersloops, total_shards])
		boost_lbl.modulate = Color(0.95, 0.65, 1.0)
		sum_vbox.add_child(boost_lbl)
	
	shopping_vbox.add_child(summary_card)
	
	if building_counts.is_empty() and total_machine_nodes > 0:
		var done_lbl := Label.new()
		done_lbl.text = i18n.t("shop_all_built_msg")
		done_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done_lbl.modulate = Color.SPRING_GREEN
		shopping_vbox.add_child(done_lbl)
		win.set_meta("last_clipboard_text", done_lbl.text)
		return
	
	var clip_lines: Array[String] = []
	clip_lines.append(i18n.t("shop_machines_hdr"))
	
	var m_hdr := Label.new()
	m_hdr.text = i18n.t("shop_machines_hdr")
	m_hdr.modulate = Color.GOLD
	shopping_vbox.add_child(m_hdr)
	
	var machines_grid := GridContainer.new()
	machines_grid.columns = 2
	machines_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	machines_grid.add_theme_constant_override("h_separation", 10)
	machines_grid.add_theme_constant_override("v_separation", 8)
	shopping_vbox.add_child(machines_grid)
	
	for b_name in building_counts.keys():
		var cnt: int = building_counts[b_name]
		var b_key: String = building_keys.get(b_name, "constructor")
		var cat_col := db.get_category_color(b_key)
		var b_meta: Dictionary = db.BUILDING_META.get(b_key, {"cost": {}})
		var cost_parts: Array[String] = []
		for mk in b_meta["cost"].keys():
			cost_parts.append("%d× %s" % [int(b_meta["cost"][mk]) * cnt, db.get_item_display_name(mk)])
		var sub_cost := ", ".join(cost_parts)
		var title_str := "%dx  %s" % [cnt, b_name]
		clip_lines.append("- " + title_str)
		machines_grid.add_child(_make_shop_item_card(b_key, title_str, sub_cost, "b_" + b_name, cat_col))
	
	var mat_hdr := Label.new()
	mat_hdr.text = i18n.tf("shop_materials_hdr", [int(margin_pct)])
	mat_hdr.modulate = Color.LIGHT_SKY_BLUE
	shopping_vbox.add_child(mat_hdr)
	clip_lines.append("\n" + mat_hdr.text)
	
	var mats_grid := GridContainer.new()
	mats_grid.columns = 2
	mats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mats_grid.add_theme_constant_override("h_separation", 10)
	mats_grid.add_theme_constant_override("v_separation", 8)
	shopping_vbox.add_child(mats_grid)
	
	var sorted_mats := material_costs.keys()
	sorted_mats.sort_custom(func(a, b): return material_costs[a] > material_costs[b])
	
	for mat_key in sorted_mats:
		var amt: int = material_costs[mat_key]
		var stack: int = int(db.items.get(mat_key, {}).get("stack_size", 100))
		var full_stacks := amt / stack
		var rem := amt % stack
		var stack_desc := ""
		if full_stacks > 0 and rem > 0:
			stack_desc = i18n.tf("shop_stacks_rem", [full_stacks, stack, rem])
		elif full_stacks > 0:
			stack_desc = i18n.tf("shop_stacks_exact", [full_stacks, stack])
		else:
			stack_desc = i18n.tf("shop_single_stack_fmt", [rem, stack])
		var dname := db.get_item_display_name(mat_key)
		var sub_str := i18n.tf("shop_mat_sub", [amt, stack_desc])
		var item_col := db.get_item_color(mat_key)
		clip_lines.append("- %s: %s" % [dname, sub_str])
		mats_grid.add_child(_make_shop_item_card(mat_key, dname, sub_str, "m_" + mat_key, item_col))
	win.set_meta("last_clipboard_text", "\n".join(clip_lines))
