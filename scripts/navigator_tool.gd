class_name NavigatorTool
extends RefCounted

var main_ctrl: GraphEdit
var db: AppDB
var i18n: AppI18n
var builder: NodeBuilder

var win: Window
var nav_search: LineEdit
var nav_filter_opt: OptionButton
var nav_list_vbox: VBoxContainer

func _init(p_main: GraphEdit, p_db: AppDB, p_i18n: AppI18n, p_builder: NodeBuilder) -> void:
	main_ctrl = p_main
	db = p_db
	i18n = p_i18n
	builder = p_builder

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	win = Window.new()
	win.theme = theme_ref
	win.size = Vector2i(680, 540)
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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	nav_search = LineEdit.new()
	nav_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_search.clear_button_enabled = true
	nav_search.text_changed.connect(func(_q: String): refresh())
	top_row.add_child(nav_search)

	nav_filter_opt = OptionButton.new()
	for i in range(5):
		nav_filter_opt.add_item("", i)
	nav_filter_opt.selected = 0
	nav_filter_opt.item_selected.connect(func(_idx: int): refresh())
	top_row.add_child(nav_filter_opt)
	vbox.add_child(top_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	nav_list_vbox = VBoxContainer.new()
	nav_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(nav_list_vbox)
	return win

func open_window() -> void:
	refresh_translations()
	refresh()
	win.popup_centered()

func refresh_translations() -> void:
	if win == null:
		return
	win.title = i18n.t("nav_win_title")
	nav_search.placeholder_text = i18n.t("nav_search_ph")
	nav_filter_opt.set_item_text(0, i18n.t("nav_filter_all"))
	nav_filter_opt.set_item_text(1, i18n.t("nav_filter_factories"))
	nav_filter_opt.set_item_text(2, i18n.t("nav_filter_miners"))
	nav_filter_opt.set_item_text(3, i18n.t("nav_filter_stations"))
	nav_filter_opt.set_item_text(4, i18n.t("nav_filter_machines"))
	if win.visible:
		refresh()

func jump_to_node(gid: String, node: GraphNode) -> void:
	if not is_instance_valid(node):
		return
	if main_ctrl.grid_planner != null and main_ctrl.grid_planner.visible:
		main_ctrl.toggle_workspace_mode()
	if gid == "world":
		main_ctrl.return_to_world_map()
	elif main_ctrl.factory_graphs.has(gid):
		main_ctrl.enter_factory(gid)
	var g: GraphEdit = main_ctrl.active_graph
	for ch in g.get_children():
		if ch is GraphNode:
			ch.selected = (ch == node)
	var target_scroll := (node.position_offset + node.size * 0.5) * g.zoom - g.size * 0.5
	g.scroll_offset = target_scroll
	g.queue_redraw()

func refresh() -> void:
	if nav_list_vbox == null:
		return
	for ch in nav_list_vbox.get_children():
		ch.queue_free()
	var q := nav_search.text.strip_edges().to_lower()
	var f_mode := nav_filter_opt.selected

	var all_graphs: Array[GraphEdit] = [main_ctrl]
	for fid in main_ctrl.factory_graphs.keys():
		if is_instance_valid(main_ctrl.factory_graphs[fid]):
			all_graphs.append(main_ctrl.factory_graphs[fid])

	var count := 0
	for g in all_graphs:
		var gid: String = g.get_meta("graph_id", "world")
		var loc_name := i18n.t("world_map") if gid == "world" else ("🏭 " + String(main_ctrl.factory_nodes[gid].get_meta("custom_name", gid)) if main_ctrl.factory_nodes.has(gid) else gid)
		for ch in g.get_children():
			if not (ch is GraphNode and ch.has_meta("node_kind")):
				continue
			var node := ch as GraphNode
			var kind := String(node.get_meta("node_kind"))
			var is_miner := false
			var icon_key := "Factory"

			if kind == "machine":
				var r_id := String(node.get_meta("recipe_id", ""))
				if db.recipes.has(r_id):
					var r: Dictionary = db.recipes[r_id]
					is_miner = bool(r.get("is_miner", false))
					icon_key = String(r["outputs"][0]["item"]) if r["outputs"].size() > 0 else String(r.get("building_key", "constructor"))
			elif kind in ["truck_station", "train_station"]:
				icon_key = "truck-station" if kind == "truck_station" else "train-station"
			elif node.has_meta("item"):
				icon_key = String(node.get_meta("item"))

			if f_mode == 1 and kind != "factory":
				continue
			if f_mode == 2 and not is_miner:
				continue
			if f_mode == 3 and not (kind in ["truck_station", "train_station"]):
				continue
			if f_mode == 4 and (kind != "machine" or is_miner):
				continue

			var title_str := node.title
			if q != "" and not (title_str.to_lower().contains(q) or loc_name.to_lower().contains(q) or icon_key.to_lower().contains(q)):
				continue

			count += 1
			var card := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.11, 0.13, 0.17, 0.95)
			sb.border_color = Color(0.3, 0.55, 0.8, 0.7)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(6)
			sb.content_margin_left = 8; sb.content_margin_right = 8
			sb.content_margin_top = 5; sb.content_margin_bottom = 5
			card.add_theme_stylebox_override("panel", sb)

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			card.add_child(row)
			row.add_child(builder.create_icon_slot(icon_key, 28))

			var info_v := VBoxContainer.new()
			info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var t_lbl := Label.new()
			t_lbl.text = title_str
			t_lbl.clip_text = true
			info_v.add_child(t_lbl)

			var s_lbl := Label.new()
			s_lbl.text = i18n.tf("nav_pos_fmt", [loc_name, int(node.position_offset.x), int(node.position_offset.y)])
			s_lbl.add_theme_font_size_override("font_size", 11)
			s_lbl.modulate = Color.LIGHT_SKY_BLUE
			info_v.add_child(s_lbl)
			row.add_child(info_v)

			var jmp_btn := Button.new()
			jmp_btn.text = i18n.t("nav_jump_btn")
			jmp_btn.modulate = Color.AQUAMARINE
			var n_ref := node
			var gid_copy := gid
			jmp_btn.pressed.connect(func(): jump_to_node(gid_copy, n_ref))
			row.add_child(jmp_btn)
			nav_list_vbox.add_child(card)

	if count == 0:
		var empty_l := Label.new()
		empty_l.text = i18n.t("nav_empty")
		empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_l.modulate = Color(1, 1, 1, 0.5)
		nav_list_vbox.add_child(empty_l)
