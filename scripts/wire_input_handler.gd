class_name WireInputHandler
extends RefCounted

var main_ctrl: GraphEdit
var _dragging_wp_graph: GraphEdit = null
var _dragging_wp_key: String = ""
var _dragging_wp_idx: int = -1

func _init(p_main: GraphEdit) -> void:
	main_ctrl = p_main

func handle_graph_wire_input(g: GraphEdit, event: InputEvent) -> void:
	if main_ctrl.grid_planner != null and main_ctrl.grid_planner.visible:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return

	var z := g.zoom
	var scroll := g.scroll_offset
	if not g.has_meta("wire_waypoints"):
		g.set_meta("wire_waypoints", {})
	var wire_wps: Dictionary = g.get_meta("wire_waypoints")

	if event is InputEventMouseMotion and _dragging_wp_graph == g and _dragging_wp_key != "":
		if wire_wps.has(_dragging_wp_key):
			var arr: Array = wire_wps[_dragging_wp_key]
			if _dragging_wp_idx >= 0 and _dragging_wp_idx < arr.size():
				var w_pos = (event.position + scroll) / z
				if event.ctrl_pressed or event.shift_pressed:
					w_pos = Vector2(snappedf(w_pos.x, 16.0), snappedf(w_pos.y, 16.0))
				arr[_dragging_wp_idx] = w_pos
				g.queue_redraw()
				g.accept_event()
				return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _dragging_wp_graph != null:
				_dragging_wp_graph = null
				_dragging_wp_key = ""
				_dragging_wp_idx = -1
				if main_ctrl.autosave_mgr != null:
					main_ctrl.autosave_mgr.notify_interaction()
				g.accept_event()
				return

		var mpos: Vector2 = event.position
		for ch in g.get_children():
			if ch is GraphNode and ch.visible and ch.has_meta("node_kind"):
				var n_rect := Rect2(ch.position_offset * z - scroll, ch.size * z)
				if n_rect.has_point(mpos):
					if g == main_ctrl and main_ctrl.map_markers != null and main_ctrl.map_markers.handle_map_input(event):
						g.accept_event()
					return

		var hit_r2 := 121.0
		for wk in wire_wps.keys():
			var arr: Array = wire_wps[wk]
			for idx in range(arr.size()):
				var wp_s: Vector2 = (arr[idx] as Vector2) * z - scroll
				if wp_s.distance_squared_to(mpos) <= hit_r2:
					if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
						main_ctrl._push_undo_state()
						_dragging_wp_graph = g
						_dragging_wp_key = String(wk)
						_dragging_wp_idx = idx
						g.accept_event()
						return
					elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
						main_ctrl._push_undo_state()
						arr.remove_at(idx)
						if arr.is_empty():
							wire_wps.erase(wk)
						g.queue_redraw()
						g.accept_event()
						return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and (event.double_click or event.shift_pressed):
			var is_ortho = main_ctrl.settings.orthogonal_wires
			for conn in g.get_connection_list():
				var fn: StringName = conn.get("from_node", conn.get("from", ""))
				var tn: StringName = conn.get("to_node", conn.get("to", ""))
				var fp := int(conn["from_port"])
				var tp := int(conn["to_port"])
				var src := g.get_node_or_null(NodePath(fn)) as GraphNode
				var dst := g.get_node_or_null(NodePath(tn)) as GraphNode
				if not is_instance_valid(src) or not is_instance_valid(dst):
					continue
				var w_key := "%s:%d->%s:%d" % [fn, fp, tn, tp]
				var p1 := (src.position_offset * z - scroll) + src.get_output_port_position(fp) * z
				var p2 := (dst.position_offset * z - scroll) + dst.get_input_port_position(tp) * z
				var wps_world: Array = wire_wps.get(w_key, [])
				var pts := WireOverlay.build_wire_screen_points(p1, p2, wps_world, z, scroll, is_ortho)
				var hit_wire := false
				for i in range(pts.size() - 1):
					var closest := Geometry2D.get_closest_point_to_segment(mpos, pts[i], pts[i + 1])
					if closest.distance_to(mpos) <= 9.5:
						hit_wire = true
						break
				if hit_wire:
					main_ctrl._push_undo_state()
					var new_wp_world := (mpos + scroll) / z
					if not wire_wps.has(w_key):
						wire_wps[w_key] = []
					var w_arr: Array = wire_wps[w_key]
					var insert_idx := w_arr.size()
					for wi in range(w_arr.size()):
						if new_wp_world.distance_to(src.position_offset) < (w_arr[wi] as Vector2).distance_to(src.position_offset):
							insert_idx = wi
							break
					w_arr.insert(insert_idx, new_wp_world)
					_dragging_wp_graph = g
					_dragging_wp_key = w_key
					_dragging_wp_idx = insert_idx
					g.queue_redraw()
					g.accept_event()
					return

	if g == main_ctrl and main_ctrl.map_markers != null and main_ctrl.map_markers.handle_map_input(event):
		g.accept_event()
