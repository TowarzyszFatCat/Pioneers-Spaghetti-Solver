class_name UndoClipboardManager
extends RefCounted

const MAX_UNDO_STEPS := 25

var main_ctrl: GraphEdit
var clipboard_data: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

func _init(p_main: GraphEdit) -> void:
	main_ctrl = p_main

func push_undo_state() -> void:
	if main_ctrl.is_loading_project or main_ctrl.serializer == null or not is_instance_valid(main_ctrl.active_graph):
		return
	var gid: String = main_ctrl.active_graph.get_meta("graph_id", "world")
	var snap: Dictionary = main_ctrl.serializer._serialize_graph(main_ctrl.active_graph)
	undo_stack.append({"graph_id": gid, "data": snap})
	if undo_stack.size() > MAX_UNDO_STEPS:
		undo_stack.pop_front()
	redo_stack.clear()

func perform_undo() -> void:
	if undo_stack.is_empty() or main_ctrl.serializer == null:
		return
	var last: Dictionary = undo_stack.pop_back()
	var gid: String = last["graph_id"]
	var target_g: GraphEdit = main_ctrl if gid == "world" else main_ctrl.factory_graphs.get(gid, null)
	if not is_instance_valid(target_g):
		return

	var current_snap: Dictionary = main_ctrl.serializer._serialize_graph(target_g)
	redo_stack.append({"graph_id": gid, "data": current_snap})
	if redo_stack.size() > MAX_UNDO_STEPS:
		redo_stack.pop_front()

	await _restore_graph_snapshot(target_g, gid, last["data"])

func perform_redo() -> void:
	if redo_stack.is_empty() or main_ctrl.serializer == null:
		return
	var next_state: Dictionary = redo_stack.pop_back()
	var gid: String = next_state["graph_id"]
	var target_g: GraphEdit = main_ctrl if gid == "world" else main_ctrl.factory_graphs.get(gid, null)
	if not is_instance_valid(target_g):
		return

	var current_snap: Dictionary = main_ctrl.serializer._serialize_graph(target_g)
	undo_stack.append({"graph_id": gid, "data": current_snap})
	if undo_stack.size() > MAX_UNDO_STEPS:
		undo_stack.pop_front()

	await _restore_graph_snapshot(target_g, gid, next_state["data"])

func _restore_graph_snapshot(target_g: GraphEdit, gid: String, snap_data: Dictionary) -> void:
	main_ctrl.is_loading_project = true
	target_g.clear_connections()
	var to_del: Array[GraphNode] = []
	for ch in target_g.get_children():
		if ch is GraphNode and ch.has_meta("node_kind"):
			to_del.append(ch)
	for n in to_del:
		target_g.remove_child(n)
		n.queue_free()
	var remap = main_ctrl.serializer._deserialize_graph_nodes(target_g, snap_data)
	if gid != "world":
		main_ctrl.builder.sync_factory_ports(gid)
	await main_ctrl.get_tree().process_frame
	main_ctrl.serializer._deserialize_graph_connections(target_g, snap_data, remap)
	main_ctrl.is_loading_project = false
	main_ctrl.recalculate_all()

func delete_selected_nodes() -> void:
	var g = main_ctrl.active_graph
	if not is_instance_valid(g):
		return
	var to_del: Array[GraphNode] = []
	for ch in g.get_children():
		if ch is GraphNode and ch.selected and ch.has_meta("node_kind") and not bool(ch.get_meta("is_locked", false)):
			to_del.append(ch)
	if to_del.is_empty():
		return
	push_undo_state()
	for n in to_del:
		if String(n.get_meta("node_kind")) == "factory":
			main_ctrl.delete_factory_recursive(String(n.get_meta("factory_id")), g, n)
		else:
			main_ctrl.delete_graph_node(g, n)

func toggle_lock_selected_nodes() -> void:
	var g = main_ctrl.active_graph
	if not is_instance_valid(g):
		return
	var sel: Array[GraphNode] = []
	var any_unlocked := false
	for ch in g.get_children():
		if ch is GraphNode and ch.selected and ch.has_meta("node_kind"):
			sel.append(ch)
			if not bool(ch.get_meta("is_locked", false)):
				any_unlocked = true
	if sel.is_empty():
		return
	for n in sel:
		main_ctrl.builder.set_node_locked_state(n, any_unlocked)
	main_ctrl.recalculate_all()

func copy_selected_nodes() -> void:
	var g = main_ctrl.active_graph
	if not is_instance_valid(g) or main_ctrl.serializer == null:
		return
	var full_snap = main_ctrl.serializer._serialize_graph(g)
	var sel_names: Dictionary = {}
	for ch in g.get_children():
		if ch is GraphNode and ch.selected and ch.has_meta("node_kind") and String(ch.get_meta("node_kind")) != "factory":
			sel_names[String(ch.name)] = true
	if sel_names.is_empty():
		return
	var nodes_sub: Array = []
	var center := Vector2.ZERO
	for nd in full_snap["nodes"]:
		if sel_names.has(String(nd["name"])):
			nodes_sub.append(nd)
			center += Vector2(float(nd["pos_x"]), float(nd["pos_y"]))
	center /= float(nodes_sub.size())
	var conns_sub: Array = []
	for c in full_snap["connections"]:
		if sel_names.has(String(c["from_node"])) and sel_names.has(String(c["to_node"])):
			conns_sub.append(c)
	clipboard_data = {"nodes": nodes_sub, "connections": conns_sub, "center": center}

func paste_copied_nodes() -> void:
	var g = main_ctrl.active_graph
	if clipboard_data.is_empty() or not is_instance_valid(g) or main_ctrl.serializer == null:
		return
	push_undo_state()
	for ch in g.get_children():
		if ch is GraphNode:
			ch.selected = false
	var target_pos = (g.get_local_mouse_position() + g.scroll_offset) / g.zoom
	var offset: Vector2 = target_pos - (clipboard_data["center"] as Vector2)
	var paste_pkg := {"nodes": [], "connections": clipboard_data["connections"].duplicate(true)}
	for nd in clipboard_data["nodes"]:
		var d_copy: Dictionary = nd.duplicate(true)
		d_copy["name"] = "%s_copy_%d" % [String(nd["name"]), main_ctrl.builder.node_counter]
		main_ctrl.builder.node_counter += 1
		d_copy["pos_x"] = float(nd["pos_x"]) + offset.x
		d_copy["pos_y"] = float(nd["pos_y"]) + offset.y
		for c in paste_pkg["connections"]:
			if c["from_node"] == nd["name"]:
				c["from_node"] = d_copy["name"]
			if c["to_node"] == nd["name"]:
				c["to_node"] = d_copy["name"]
		paste_pkg["nodes"].append(d_copy)
	var remap = main_ctrl.serializer._deserialize_graph_nodes(g, paste_pkg)
	if g != main_ctrl:
		main_ctrl.builder.sync_factory_ports(g.get_meta("graph_id"))
	await main_ctrl.get_tree().process_frame
	main_ctrl.serializer._deserialize_graph_connections(g, paste_pkg, remap)
	for new_name in remap.values():
		var n := g.get_node_or_null(NodePath(String(new_name))) as GraphNode
		if n:
			n.selected = true
	main_ctrl.recalculate_all()
