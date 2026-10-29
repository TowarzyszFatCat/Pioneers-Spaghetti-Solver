class_name ProjectSerializer
extends RefCounted

const FORMAT_VERSION := 1
const DEFAULT_PROJECTS_DIR := "user://projects"

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var builder: NodeBuilder

var current_file_path: String = ""
var save_dlg: FileDialog
var load_dlg: FileDialog
var confirm_new_dlg: ConfirmationDialog

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n, p_builder: NodeBuilder) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	builder = p_builder
	_ensure_projects_dir()

func _ensure_projects_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("projects"):
		dir.make_dir("projects")

func build_dialogs(parent_layer: CanvasLayer, theme_ref: Theme) -> void:
	save_dlg = FileDialog.new()
	save_dlg.theme = theme_ref
	save_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dlg.access = FileDialog.ACCESS_FILESYSTEM
	save_dlg.current_dir = ProjectSettings.globalize_path(DEFAULT_PROJECTS_DIR)
	save_dlg.current_file = "factory_project.pss"
	save_dlg.file_selected.connect(func(path: String):
		save_project_to_path(path)
	)
	parent_layer.add_child(save_dlg)
	
	load_dlg = FileDialog.new()
	load_dlg.theme = theme_ref
	load_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dlg.access = FileDialog.ACCESS_FILESYSTEM
	load_dlg.current_dir = ProjectSettings.globalize_path(DEFAULT_PROJECTS_DIR)
	load_dlg.file_selected.connect(func(path: String):
		load_project_from_path(path)
	)
	parent_layer.add_child(load_dlg)
	
	confirm_new_dlg = ConfirmationDialog.new()
	confirm_new_dlg.theme = theme_ref
	confirm_new_dlg.confirmed.connect(func():
		new_project()
	)
	parent_layer.add_child(confirm_new_dlg)
	
	refresh_translations()

func refresh_translations() -> void:
	var filter_str := i18n.t("proj_file_filter")
	if save_dlg:
		save_dlg.title = i18n.t("save_proj_title")
		save_dlg.filters = PackedStringArray([filter_str])
	if load_dlg:
		load_dlg.title = i18n.t("load_proj_title")
		load_dlg.filters = PackedStringArray([filter_str])
	if confirm_new_dlg:
		confirm_new_dlg.title = i18n.t("new_proj_btn")
		confirm_new_dlg.dialog_text = i18n.t("new_proj_confirm")
	_update_window_title()

func _update_window_title() -> void:
	var win := main_ctrl.get_window()
	if win == null:
		return
	if current_file_path == "":
		win.title = "PSS — " + i18n.t("untitled_project")
	else:
		win.title = "PSS — " + current_file_path.get_file()

func prompt_new_project() -> void:
	if confirm_new_dlg:
		confirm_new_dlg.popup_centered(Vector2i(420, 130))

func prompt_save_project(save_as: bool = false) -> void:
	if not save_as and current_file_path != "":
		save_project_to_path(current_file_path)
		return
	if save_dlg:
		if current_file_path != "":
			save_dlg.current_path = current_file_path
		else:
			save_dlg.current_dir = ProjectSettings.globalize_path(DEFAULT_PROJECTS_DIR)
			save_dlg.current_file = "factory_project.pss"
		save_dlg.popup_centered(Vector2i(680, 460))

func prompt_load_project() -> void:
	if load_dlg:
		if current_file_path != "":
			load_dlg.current_dir = current_file_path.get_base_dir()
		else:
			load_dlg.current_dir = ProjectSettings.globalize_path(DEFAULT_PROJECTS_DIR)
		load_dlg.popup_centered(Vector2i(680, 460))

func new_project() -> void:
	clear_entire_project()
	current_file_path = ""
	_update_window_title()
	main_ctrl.recalculate_all()
	main_ctrl.hint_label.text = i18n.t("world_hint")
	if main_ctrl.get("autosave_mgr") != null and main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()


func clear_entire_project() -> void:
	main_ctrl.is_loading_project = true
	main_ctrl.return_to_world_map()
	for fid in main_ctrl.factory_graphs.keys():
		var fg: GraphEdit = main_ctrl.factory_graphs[fid]
		if is_instance_valid(fg):
			fg.clear_connections()
			if fg.get_parent() != null:
				fg.get_parent().remove_child(fg)
			fg.queue_free()
	main_ctrl.factory_graphs.clear()
	main_ctrl.factory_nodes.clear()
	main_ctrl.factory_parents.clear()
	main_ctrl.clear_connections()

	var to_remove: Array[Node] = []
	for ch in main_ctrl.get_children():
		if ch is GraphNode and ch.has_meta("node_kind"):
			to_remove.append(ch)
	for n in to_remove:
		main_ctrl.remove_child(n)
		n.queue_free()

	if main_ctrl.grid_planner != null:
		main_ctrl.grid_planner.saved_positions.clear()
		main_ctrl.grid_planner.saved_belts.clear()
		main_ctrl.grid_planner.blocks.clear()
		main_ctrl.grid_planner.wire_links.clear()
		main_ctrl.grid_planner.queue_redraw()

	main_ctrl.checked_shopping_items.clear()
	builder.factory_counter = 1
	main_ctrl.is_loading_project = false

func _sanitize_node_name(raw_name: String) -> String:
	return raw_name.replace("@", "_").strip_edges()

# ==========================================
# SAVING PROJECT TO FILE (.pss)
# ==========================================
func save_project_to_path(path: String, is_silent_autosave: bool = false) -> bool:
	var clean_path := path
	if clean_path.get_extension() == "":
		clean_path += ".pss"
	var graphs_data: Dictionary = {}
	graphs_data["world"] = _serialize_graph(main_ctrl)
	for fid in main_ctrl.factory_graphs.keys():
		var fg: GraphEdit = main_ctrl.factory_graphs[fid]
		if is_instance_valid(fg):
			graphs_data[fid] = _serialize_graph(fg)

	var factories_meta: Array = []
	for fid in main_ctrl.factory_nodes.keys():
		var f_node: GraphNode = main_ctrl.factory_nodes[fid]
		if is_instance_valid(f_node):
			factories_meta.append({
				"factory_id": fid,
				"parent_graph_id": String(main_ctrl.factory_parents.get(fid, "world")),
				"node_name": String(f_node.name),
				"custom_name": String(f_node.get_meta("custom_name", fid)),
				"pos_x": f_node.position_offset.x,
				"pos_y": f_node.position_offset.y
			})

	var grid_saved_pos: Dictionary = {}
	var grid_saved_belts: Dictionary = {}
	if main_ctrl.grid_planner != null:
		for gid in main_ctrl.grid_planner.saved_positions.keys():
			grid_saved_pos[gid] = {}
			var g_mem: Dictionary = main_ctrl.grid_planner.saved_positions[gid]
			for bid in g_mem.keys():
				var entry: Dictionary = g_mem[bid]
				var p: Vector2 = entry["pos_f"]
				var saved_entry := {
					"x": p.x,
					"y": p.y,
					"rot": int(entry.get("rot", 0)),
					"floor": int(entry.get("floor", 0)),
					"locked": bool(entry.get("locked", false))
				}
				if entry.has("target_floor"):
					saved_entry["target_floor"] = int(entry["target_floor"])
				if entry.has("partner_id"):
					saved_entry["partner_id"] = String(entry["partner_id"])
				grid_saved_pos[gid][bid] = saved_entry

		for gid in main_ctrl.grid_planner.saved_belts.keys():
			var b_list: Array = []
			for belt in main_ctrl.grid_planner.saved_belts[gid]:
				var wps_ser: Array = []
				for wp in belt.get("waypoints", []):
					var wp_p: Vector2 = wp["pos_f"]
					wps_ser.append({"x": wp_p.x, "y": wp_p.y, "dir": int(wp.get("dir", 0))})
				var fp_vec: Vector2 = belt.get("from_pos_f", Vector2.ZERO)
				var tp_vec: Vector2 = belt.get("to_pos_f", Vector2.ZERO)
				b_list.append({
					"id": String(belt.get("id", "")),
					"floor": int(belt.get("floor", 0)),
					"from_id": String(belt.get("from_id", "")),
					"from_port": int(belt.get("from_port", 0)),
					"from_x": fp_vec.x,
					"from_y": fp_vec.y,
					"from_side": int(belt.get("from_side", 0)),
					"to_id": String(belt.get("to_id", "")),
					"to_port": int(belt.get("to_port", 0)),
					"to_x": tp_vec.x,
					"to_y": tp_vec.y,
					"to_side": int(belt.get("to_side", 2)),
					"item": String(belt.get("item", "")),
					"rate": float(belt.get("rate", 0.0)),
					"mode": String(belt.get("mode", "straight")),
					"waypoints": wps_ser
				})
			grid_saved_belts[gid] = b_list

	var active_gid: String = main_ctrl.active_graph.get_meta("graph_id", "world") if is_instance_valid(main_ctrl.active_graph) else "world"
	var payload := {
		"format": "PSS_Project",
		"version": FORMAT_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"factory_counter": builder.factory_counter,
		"active_graph_id": active_gid,
		"grid_mode_active": main_ctrl.grid_planner.visible if main_ctrl.grid_planner != null else false,
		"shopping": {
			"belt_margin": main_ctrl.belt_margin_slider.value if main_ctrl.belt_margin_slider != null else 20.0,
			"checked_items": main_ctrl.checked_shopping_items.duplicate()
		},
		"grid_planner": {
			"expand_individual_machines": main_ctrl.grid_planner.expand_individual_machines if main_ctrl.grid_planner != null else true,
			"auto_generate_splitters": main_ctrl.grid_planner.auto_generate_splitters if main_ctrl.grid_planner != null else true,
			"manhattan_wires": main_ctrl.grid_planner.manhattan_wires if main_ctrl.grid_planner != null else false,
			"snap_step": main_ctrl.grid_planner.snap_step if main_ctrl.grid_planner != null else 0.25,
			"saved_positions": grid_saved_pos,
			"saved_belts": grid_saved_belts
		},
		"factories": factories_meta,
		"graphs": graphs_data
	}
	var f := FileAccess.open(clean_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

	if not is_silent_autosave:
		current_file_path = clean_path
		_update_window_title()
		main_ctrl.hint_label.text = i18n.tf("proj_saved_msg", [clean_path.get_file()])
	return true
	
func _serialize_graph(g: GraphEdit) -> Dictionary:
	var nodes_arr: Array = []
	for ch in g.get_children():
		if not (is_instance_valid(ch) and not ch.is_queued_for_deletion() and ch is GraphNode and ch.has_meta("node_kind")):
			continue
		var node := ch as GraphNode
		var kind: String = String(node.get_meta("node_kind"))
		var n_dict := {
			"name": String(node.name),
			"kind": kind,
			"pos_x": node.position_offset.x,
			"pos_y": node.position_offset.y,
			"is_built": bool(node.get_meta("is_built", false)),
			"is_locked": bool(node.get_meta("is_locked", false))
		}
		match kind:
			"machine":
				n_dict["recipe_id"] = String(node.get_meta("recipe_id", ""))
				n_dict["machines"] = float(node.get_meta("machines", 1.0))
				n_dict["clock"] = float(node.get_meta("clock", 100.0))
				n_dict["purity"] = float(node.get_meta("purity", 1.0))
				n_dict["miner_mk"] = int(node.get_meta("miner_mk", 1))
				n_dict["somersloops"] = int(node.get_meta("somersloops", 0))
			"factory":
				n_dict["factory_id"] = String(node.get_meta("factory_id", ""))
				n_dict["parent_graph_id"] = String(node.get_meta("parent_graph_id", "world"))
				n_dict["custom_name"] = String(node.get_meta("custom_name", ""))
			"receiver", "transmitter", "awesome_sink", "depot", "container":
				n_dict["item"] = String(node.get_meta("item", "iron-ore"))
				n_dict["planned_rate"] = float(node.get_meta("planned_rate", 60.0))
			"splitter", "even_splitter", "prop_splitter", "reroute":
				n_dict["item"] = String(node.get_meta("item", "iron-ore"))
			"manual_splitter":
				n_dict["item"] = String(node.get_meta("item", "iron-ore"))
				n_dict["manual_overrides"] = (node.get_meta("manual_overrides", [false, false, false]) as Array).duplicate()
				n_dict["manual_rates"] = (node.get_meta("manual_rates", [0.0, 0.0, 0.0]) as Array).duplicate()
			"truck_station", "train_station":
				n_dict["fuel_item"] = String(node.get_meta("fuel_item", "coal"))
				n_dict["fuel_rate"] = float(node.get_meta("fuel_rate", 15.0))
				n_dict["platforms_count"] = int(node.get_meta("platforms_count", 1))
				n_dict["station_mode"] = String(node.get_meta("station_mode", "pingpong"))
				n_dict["station_out_items"] = (node.get_meta("station_out_items", []) as Array).duplicate()
		nodes_arr.append(n_dict)

	var conns_arr: Array = []
	for conn in g.get_connection_list():
		conns_arr.append({
			"from_node": String(conn.get("from_node", conn.get("from", ""))),
			"from_port": int(conn["from_port"]),
			"to_node": String(conn.get("to_node", conn.get("to", ""))),
			"to_port": int(conn["to_port"])
		})

	var wp_serialized: Dictionary = {}
	var raw_wps: Dictionary = g.get_meta("wire_waypoints", {})
	for wk in raw_wps.keys():
		var pts_arr: Array = []
		for pt in raw_wps[wk]:
			if pt is Vector2:
				pts_arr.append({"x": pt.x, "y": pt.y})
		if not pts_arr.is_empty():
			wp_serialized[wk] = pts_arr

	return {
		"scroll_x": g.scroll_offset.x,
		"scroll_y": g.scroll_offset.y,
		"zoom": g.zoom,
		"nodes": nodes_arr,
		"connections": conns_arr,
		"wire_waypoints": wp_serialized
	}

# ==========================================
# LOADING PROJECT FROM FILE (.pss)
# ==========================================
func load_project_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not parsed.has("graphs"):
		return false

	clear_entire_project()
	main_ctrl.is_loading_project = true

	if parsed.has("shopping") and parsed["shopping"] is Dictionary:
		var sh: Dictionary = parsed["shopping"]
		if main_ctrl.belt_margin_slider != null:
			main_ctrl.belt_margin_slider.value = float(sh.get("belt_margin", 20.0))
		if sh.get("checked_items") is Dictionary:
			main_ctrl.checked_shopping_items = (sh["checked_items"] as Dictionary).duplicate()

	var factories_meta: Array = parsed.get("factories", [])
	for fm in factories_meta:
		if fm is Dictionary:
			var fid := String(fm.get("factory_id", ""))
			var pid := String(fm.get("parent_graph_id", "world"))
			if fid != "" and not main_ctrl.factory_graphs.has(fid):
				main_ctrl.create_factory_sub_graph(fid, pid)
	builder.factory_counter = int(parsed.get("factory_counter", factories_meta.size() + 1))

	var graphs_data: Dictionary = parsed["graphs"]
	var graph_name_remaps: Dictionary = {}
	for gid in graphs_data.keys():
		var target_g: GraphEdit = main_ctrl if gid == "world" else main_ctrl.factory_graphs.get(gid, null)
		if target_g == null or not (graphs_data[gid] is Dictionary):
			continue
		graph_name_remaps[gid] = _deserialize_graph_nodes(target_g, graphs_data[gid])

	for fid in main_ctrl.factory_nodes.keys():
		builder.sync_factory_ports(fid)

	await main_ctrl.get_tree().process_frame

	for gid in graphs_data.keys():
		var target_g: GraphEdit = main_ctrl if gid == "world" else main_ctrl.factory_graphs.get(gid, null)
		if target_g == null or not (graphs_data[gid] is Dictionary):
			continue
		var remap: Dictionary = graph_name_remaps.get(gid, {})
		_deserialize_graph_connections(target_g, graphs_data[gid], remap)

	if parsed.has("grid_planner") and parsed["grid_planner"] is Dictionary and main_ctrl.grid_planner != null:
		var gp: Dictionary = parsed["grid_planner"]
		main_ctrl.grid_planner.expand_individual_machines = bool(gp.get("expand_individual_machines", true))
		main_ctrl.grid_planner.auto_generate_splitters = bool(gp.get("auto_generate_splitters", true))
		main_ctrl.grid_planner.manhattan_wires = bool(gp.get("manhattan_wires", false))
		main_ctrl.grid_planner.snap_step = float(gp.get("snap_step", 0.25))
		main_ctrl.grid_planner.saved_positions.clear()
		var s_pos: Dictionary = gp.get("saved_positions", {})
		for gid in s_pos.keys():
			main_ctrl.grid_planner.saved_positions[gid] = {}
			var g_dict: Dictionary = s_pos[gid]
			var remap: Dictionary = graph_name_remaps.get(gid, {})
			for bid in g_dict.keys():
				var entry: Dictionary = g_dict[bid]
				var fixed_bid := String(bid)
				if fixed_bid.contains("#"):
					var parts := fixed_bid.split("#")
					var old_n := parts[0]
					var new_n: String = String(remap.get(old_n, _sanitize_node_name(old_n)))
					fixed_bid = "%s#%s" % [new_n, parts[1]]
				var loaded_pos_entry := {
					"pos_f": Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
					"rot": int(entry.get("rot", 0)),
					"floor": int(entry.get("floor", 0)),
					"locked": bool(entry.get("locked", false))
				}
				if entry.has("target_floor"):
					loaded_pos_entry["target_floor"] = int(entry["target_floor"])
				if entry.has("partner_id"):
					loaded_pos_entry["partner_id"] = String(entry["partner_id"])
				elif entry.has("pair_id"):
					loaded_pos_entry["partner_id"] = String(entry["pair_id"])
				main_ctrl.grid_planner.saved_positions[gid][fixed_bid] = loaded_pos_entry

		main_ctrl.grid_planner.saved_belts.clear()
		var s_belts: Dictionary = gp.get("saved_belts", {})
		for gid in s_belts.keys():
			main_ctrl.grid_planner.saved_belts[gid] = []
			var remap: Dictionary = graph_name_remaps.get(gid, {})
			for raw_b in s_belts[gid]:
				if not (raw_b is Dictionary):
					continue
				var f_bid := String(raw_b.get("from_id", ""))
				if f_bid.contains("#"):
					var p1 := f_bid.split("#")
					f_bid = "%s#%s" % [String(remap.get(p1[0], _sanitize_node_name(p1[0]))), p1[1]]
				var t_bid := String(raw_b.get("to_id", ""))
				if t_bid.contains("#"):
					var p2 := t_bid.split("#")
					t_bid = "%s#%s" % [String(remap.get(p2[0], _sanitize_node_name(p2[0]))), p2[1]]
				var wps_loaded: Array = []
				for wp_d in raw_b.get("waypoints", []):
					if wp_d is Dictionary:
						wps_loaded.append({
							"pos_f": Vector2(float(wp_d.get("x", 0.0)), float(wp_d.get("y", 0.0))),
							"dir": int(wp_d.get("dir", 0))
						})
				main_ctrl.grid_planner.saved_belts[gid].append({
					"id": String(raw_b.get("id", "belt_%d" % Time.get_ticks_msec())),
					"floor": int(raw_b.get("floor", 0)),
					"from_id": f_bid,
					"from_port": int(raw_b.get("from_port", 0)),
					"from_pos_f": Vector2(float(raw_b.get("from_x", 0.0)), float(raw_b.get("from_y", 0.0))),
					"from_side": int(raw_b.get("from_side", 0)),
					"to_id": t_bid,
					"to_port": int(raw_b.get("to_port", 0)),
					"to_pos_f": Vector2(float(raw_b.get("to_x", 0.0)), float(raw_b.get("to_y", 0.0))),
					"to_side": int(raw_b.get("to_side", 2)),
					"item": String(raw_b.get("item", "")),
					"rate": float(raw_b.get("rate", 0.0)),
					"mode": String(raw_b.get("mode", "straight")),
					"waypoints": wps_loaded
				})

	main_ctrl.is_loading_project = false

	var active_gid := String(parsed.get("active_graph_id", "world"))
	if active_gid != "world" and main_ctrl.factory_graphs.has(active_gid):
		main_ctrl.enter_factory(active_gid)
	else:
		main_ctrl.return_to_world_map()
	var want_grid := bool(parsed.get("grid_mode_active", false))
	if main_ctrl.grid_planner != null and main_ctrl.grid_planner.visible != want_grid:
		main_ctrl.toggle_workspace_mode()

	current_file_path = path
	_update_window_title()
	main_ctrl.recalculate_all()

	for gid in graphs_data.keys():
		var target_g: GraphEdit = main_ctrl if gid == "world" else main_ctrl.factory_graphs.get(gid, null)
		if target_g != null and graphs_data[gid] is Dictionary:
			var g_data: Dictionary = graphs_data[gid]
			target_g.zoom = clampf(float(g_data.get("zoom", 1.0)), target_g.zoom_min, target_g.zoom_max)

	await main_ctrl.get_tree().process_frame

	for gid in graphs_data.keys():
		var target_g: GraphEdit = main_ctrl if gid == "world" else main_ctrl.factory_graphs.get(gid, null)
		if target_g != null and graphs_data[gid] is Dictionary:
			var g_data: Dictionary = graphs_data[gid]
			var target_scroll := Vector2(float(g_data.get("scroll_x", 0.0)), float(g_data.get("scroll_y", 0.0)))
			target_g.scroll_offset = target_scroll
			target_g.set_deferred("scroll_offset", target_scroll)
			target_g.queue_redraw()

	main_ctrl.hint_label.text = i18n.tf("proj_loaded_msg", [path.get_file()])
	return true

func _deserialize_graph_nodes(g: GraphEdit, g_data: Dictionary) -> Dictionary:
	var nodes_arr: Array = g_data.get("nodes", [])
	var spawned_list: Array[Dictionary] = []
	var name_remap: Dictionary = {}

	for i in range(nodes_arr.size()):
		var nd: Dictionary = nodes_arr[i]
		var kind := String(nd.get("kind", ""))
		var pos := Vector2(float(nd.get("pos_x", 0.0)), float(nd.get("pos_y", 0.0)))
		var saved_name := String(nd.get("name", "Node_%d" % i))
		var node: GraphNode = null

		match kind:
			"machine":
				var r_id := String(nd.get("recipe_id", ""))
				if not db.recipes.has(r_id):
					continue
				node = builder.spawn_machine(g, r_id, pos)
				var m_val := float(nd.get("machines", 1.0))
				var clk_val := float(nd.get("clock", 100.0))
				var pur_val := float(nd.get("purity", 1.0))
				var mk_val := clampi(int(nd.get("miner_mk", 1)), 1, 3)
				var sloop_val := int(nd.get("somersloops", 0))
				node.set_meta("machines", m_val)
				if node.has_meta("spinbox"):
					(node.get_meta("spinbox") as SpinBox).set_value_no_signal(m_val)
				node.set_meta("clock", clk_val)
				if node.has_meta("clk_spinbox"):
					(node.get_meta("clk_spinbox") as SpinBox).set_value_no_signal(clk_val)
				node.set_meta("purity", pur_val)
				if node.has_meta("pur_opt"):
					(node.get_meta("pur_opt") as OptionButton).selected = 0 if pur_val < 0.75 else (2 if pur_val > 1.5 else 1)
				node.set_meta("miner_mk", mk_val)
				if node.has_meta("mk_opt"):
					(node.get_meta("mk_opt") as OptionButton).selected = mk_val - 1
				node.set_meta("somersloops", sloop_val)
				if node.has_meta("sloop_opt"):
					(node.get_meta("sloop_opt") as OptionButton).selected = sloop_val
			"factory":
				var fid := String(nd.get("factory_id", ""))
				var cname := String(nd.get("custom_name", fid))
				node = builder.spawn_factory(g, pos, cname, fid)
			"receiver", "transmitter":
				var item_k := String(nd.get("item", "iron-ore"))
				var p_rate := float(nd.get("planned_rate", 60.0))
				node = builder.spawn_io_node(g, kind, item_k, pos)
				node.set_meta("planned_rate", p_rate)
				if node.has_meta("plan_spin"):
					(node.get_meta("plan_spin") as SpinBox).set_value_no_signal(p_rate)
			"awesome_sink", "depot", "container":
				var item_k := String(nd.get("item", "iron-ore"))
				var p_rate := float(nd.get("planned_rate", 60.0))
				node = builder.spawn_storage_sink_node(g, kind, item_k, pos)
				node.set_meta("planned_rate", p_rate)
				if node.has_meta("plan_spin"):
					(node.get_meta("plan_spin") as SpinBox).set_value_no_signal(p_rate)
			"splitter", "even_splitter", "prop_splitter":
				var item_k := String(nd.get("item", "iron-ore"))
				node = builder.spawn_splitter(g, item_k, pos, kind)
			"reroute":
				var item_k := String(nd.get("item", "iron-ore"))
				node = builder.spawn_reroute_node(g, item_k, pos)
			"manual_splitter":
				var item_k := String(nd.get("item", "iron-ore"))
				node = builder.spawn_manual_splitter(g, item_k, pos)
				var ovr: Array = nd.get("manual_overrides", [false, false, false])
				var rts: Array = nd.get("manual_rates", [0.0, 0.0, 0.0])
				node.set_meta("manual_overrides", [bool(ovr[0]), bool(ovr[1]), bool(ovr[2])] if ovr.size() >= 3 else [false, false, false])
				node.set_meta("manual_rates", [float(rts[0]), float(rts[1]), float(rts[2])] if rts.size() >= 3 else [0.0, 0.0, 0.0])
			"truck_station", "train_station":
				var f_it := String(nd.get("fuel_item", "coal"))
				node = builder.spawn_transport_station(g, kind, f_it, pos)
				node.set_meta("fuel_rate", float(nd.get("fuel_rate", 15.0)))
				node.set_meta("platforms_count", int(nd.get("platforms_count", 1)))
				node.set_meta("station_mode", String(nd.get("station_mode", "pingpong")))
				node.set_meta("station_out_items", (nd.get("station_out_items", []) as Array).duplicate())
				builder.rebuild_transport_station_rows(g, node)

		if node != null:
			if nd.has("is_built"):
				builder.set_node_built_state(node, bool(nd.get("is_built", false)))
			if nd.has("is_locked"):
				builder.set_node_locked_state(node, bool(nd.get("is_locked", false)))
			node.name = "__tmp_load_%d" % i
			spawned_list.append({
				"node": node,
				"saved_name": saved_name,
				"clean_name": _sanitize_node_name(saved_name)
			})

	for entry in spawned_list:
		var n: GraphNode = entry["node"]
		var clean_target: String = entry["clean_name"]
		n.name = clean_target
		var final_godot_name := String(n.name)
		name_remap[entry["saved_name"]] = final_godot_name
		name_remap[clean_target] = final_godot_name

	return name_remap

func _deserialize_graph_connections(g: GraphEdit, g_data: Dictionary, name_remap: Dictionary) -> void:
	var conns_arr: Array = g_data.get("connections", [])
	for c in conns_arr:
		if not (c is Dictionary):
			continue
		var raw_fn := String(c.get("from_node", ""))
		var raw_tn := String(c.get("to_node", ""))
		var fn := StringName(String(name_remap.get(raw_fn, _sanitize_node_name(raw_fn))))
		var tn := StringName(String(name_remap.get(raw_tn, _sanitize_node_name(raw_tn))))
		var fp := int(c.get("from_port", 0))
		var tp := int(c.get("to_port", 0))
		
		if g.has_node(NodePath(fn)) and g.has_node(NodePath(tn)):
			g.connect_node(fn, fp, tn, tp)
	
	var loaded_wps: Dictionary = {}
	var raw_wps: Dictionary = g_data.get("wire_waypoints", {})
	for wk in raw_wps.keys():
		var parts := String(wk).split("->")
		if parts.size() == 2:
			var p_left := parts[0].split(":")
			var p_right := parts[1].split(":")
			if p_left.size() == 2 and p_right.size() == 2:
				var fn_new := String(name_remap.get(p_left[0], _sanitize_node_name(p_left[0])))
				var tn_new := String(name_remap.get(p_right[0], _sanitize_node_name(p_right[0])))
				var new_wk := "%s:%s->%s:%s" % [fn_new, p_left[1], tn_new, p_right[1]]
				var vec_list: Array[Vector2] = []
				for pt in raw_wps[wk]:
					if pt is Dictionary:
						vec_list.append(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))))
				if not vec_list.is_empty():
					loaded_wps[new_wk] = vec_list
	g.set_meta("wire_waypoints", loaded_wps)
