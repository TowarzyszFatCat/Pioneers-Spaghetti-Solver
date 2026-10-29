class_name WireOverlay
extends RefCounted

class WireLayer extends Control:
	var graph: GraphEdit
	var main_ref: GraphEdit
	var cached_screen_pts: Dictionary = {}
	var _last_hash: int = 0
	
	func _init(p_graph: GraphEdit, p_main: GraphEdit) -> void:
		graph = p_graph
		main_ref = p_main
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 1
	
	func _process(_delta: float) -> void:
		var should_show = graph.visible and (main_ref.grid_planner == null or not main_ref.grid_planner.visible)
		if visible != should_show:
			visible = should_show
			if should_show:
				_last_hash = 0
		if not should_show:
			return
		if size != graph.size:
			size = graph.size
			_last_hash = 0
		var cur_h = WireOverlay.compute_graph_visual_hash(graph, main_ref)
		if cur_h != _last_hash:
			_last_hash = cur_h
			queue_redraw()
			for ch in graph.get_children():
				if ch is WireBadgeOverlay:
					ch.queue_redraw()
	
	func _draw() -> void:
		cached_screen_pts.clear()
		if main_ref.grid_planner != null and main_ref.grid_planner.visible:
			return
		var z := graph.zoom
		var scroll := graph.scroll_offset
		var vp_rect := Rect2(Vector2.ZERO, size).grow(120.0)
		var wire_flows: Dictionary = graph.get_meta("wire_flows", {})
		var wire_wps: Dictionary = graph.get_meta("wire_waypoints", {})
		var is_ortho: bool = main_ref.settings.orthogonal_wires
		
		for conn in graph.get_connection_list():
			var fn: StringName = conn.get("from_node", conn.get("from", ""))
			var tn: StringName = conn.get("to_node", conn.get("to", ""))
			var fp := int(conn["from_port"])
			var tp := int(conn["to_port"])
			var src := graph.get_node_or_null(NodePath(fn)) as GraphNode
			var dst := graph.get_node_or_null(NodePath(tn)) as GraphNode
			if not is_instance_valid(src) or not is_instance_valid(dst) or not src.visible or not dst.visible:
				continue
			
			var p1 := (src.position_offset * z - scroll) + src.get_output_port_position(fp) * z
			var p2 := (dst.position_offset * z - scroll) + dst.get_input_port_position(tp) * z
			var w_key := "%s:%d->%s:%d" % [fn, fp, tn, tp]
			var wps_world: Array = wire_wps.get(w_key, [])
			
			if wps_world.is_empty():
				var min_p := Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y))
				var max_p := Vector2(maxf(p1.x, p2.x), maxf(p1.y, p2.y))
				if not vp_rect.intersects(Rect2(min_p, max_p - min_p)):
					continue
			
			var info: Dictionary = wire_flows.get(w_key, {"rate": 0.0, "item": ""})
			var item_key := String(info["item"])
			if item_key == "":
				item_key = main_ref.solver.get_node_output_item(src, fp)
			var is_route := bool(info.get("is_station_link", false)) or item_key == "__station_route__"
			var col: Color = Color.html("#FAB757") if is_route else main_ref.db.get_item_color(item_key)
			col.a = 0.92
			
			var pts := WireOverlay.build_wire_screen_points(p1, p2, wps_world, z, scroll, is_ortho)
			cached_screen_pts[w_key] = pts
			if pts.size() >= 2:
				var width := maxf(2.0, (4.8 if is_route else 2.8) * sqrt(z))
				draw_polyline(pts, col, width, false)

class WireBadgeOverlay extends Control:
	var graph: GraphEdit
	var main_ref: GraphEdit
	var wire_layer_ref: WireLayer
	var _badge_cache: Dictionary = {}
	
	func _init(p_graph: GraphEdit, p_main: GraphEdit, p_wire_layer: WireLayer = null) -> void:
		graph = p_graph
		main_ref = p_main
		wire_layer_ref = p_wire_layer
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 20
	
	func _process(_delta: float) -> void:
		var should_show = graph.visible and (main_ref.grid_planner == null or not main_ref.grid_planner.visible)
		if visible != should_show:
			visible = should_show
		if should_show and size != graph.size:
			size = graph.size
	
	func _draw() -> void:
		if main_ref.grid_planner != null and main_ref.grid_planner.visible:
			return
		var z := graph.zoom
		var show_badges: bool = main_ref.settings.show_wire_labels and z >= 0.40
		
		var has_any_selected := false
		for ch in graph.get_children():
			if ch is GraphNode and ch.selected and ch.has_meta("node_kind"):
				has_any_selected = true
				break
		
		var wire_wps: Dictionary = graph.get_meta("wire_waypoints", {})
		if not show_badges and not has_any_selected and (z < 0.25 or wire_wps.is_empty()):
			return
		
		var scroll := graph.scroll_offset
		var is_ortho: bool = main_ref.settings.orthogonal_wires
		var wire_flows: Dictionary = graph.get_meta("wire_flows", {})
		var font := ThemeDB.fallback_font
		const FIXED_FONT_SIZE := 11
		var base_alpha := clampf((z - 0.40) / 0.12, 0.0, 1.0)
		
		for conn in graph.get_connection_list():
			var fn: StringName = conn.get("from_node", conn.get("from", ""))
			var tn: StringName = conn.get("to_node", conn.get("to", ""))
			var fp := int(conn["from_port"])
			var tp := int(conn["to_port"])
			var w_key := "%s:%d->%s:%d" % [fn, fp, tn, tp]
			
			if wire_layer_ref != null and not wire_layer_ref.cached_screen_pts.has(w_key):
				continue
			
			var src := graph.get_node_or_null(NodePath(fn)) as GraphNode
			var dst := graph.get_node_or_null(NodePath(tn)) as GraphNode
			if not is_instance_valid(src) or not is_instance_valid(dst) or not src.visible or not dst.visible:
				continue
			
			var is_highlighted := (src.selected or dst.selected)
			var p1 := (src.position_offset * z - scroll) + src.get_output_port_position(fp) * z
			var p2 := (dst.position_offset * z - scroll) + dst.get_input_port_position(tp) * z
			
			var info: Dictionary = wire_flows.get(w_key, {"rate": 0.0, "item": ""})
			var rate := float(info["rate"])
			var item_key := String(info["item"])
			if item_key == "":
				item_key = main_ref.solver.get_node_output_item(src, fp)
			
			var wire_col: Color = Color.html("#FAB757") if item_key == "__station_route__" else main_ref.db.get_item_color(item_key)
			var wps_world: Array = wire_wps.get(w_key, [])
			var pts: PackedVector2Array = wire_layer_ref.cached_screen_pts[w_key] if (wire_layer_ref != null and wire_layer_ref.cached_screen_pts.has(w_key)) else WireOverlay.build_wire_screen_points(p1, p2, wps_world, z, scroll, is_ortho)
			
			if is_highlighted and pts.size() >= 2:
				var glow_col: Color = wire_col.lightened(0.25)
				glow_col.a = 0.38
				draw_polyline(pts, glow_col, maxf(4.0, 8.0 * z), false)
				var core_col: Color = wire_col.lightened(0.45)
				core_col.a = 0.95
				draw_polyline(pts, core_col, maxf(2.0, 3.0 * z), false)
				draw_circle(p1, maxf(3.5, 5.5 * z), Color.html("#FAB757"))
				draw_circle(p2, maxf(3.5, 5.5 * z), Color.html("#FAB757"))
			
			if z >= 0.25 and not wps_world.is_empty():
				var wp_r := clampf(6.0 * sqrt(z), 4.0, 8.5)
				for wp_v in wps_world:
					if wp_v is Vector2:
						var wp_s: Vector2 = wp_v * z - scroll
						draw_circle(wp_s, wp_r + 1.8, Color(0.05, 0.06, 0.08, 0.95))
						draw_circle(wp_s, wp_r, wire_col.lightened(0.25))
						draw_arc(wp_s, wp_r, 0.0, TAU, 10, Color.WHITE, 1.5)
			
			if not show_badges:
				continue
			
			var mid := WireOverlay.get_polyline_midpoint(pts, (p1 + p2) * 0.5)
			var alpha := base_alpha * (1.0 if (not has_any_selected or is_highlighted) else 0.28)
			
			if bool(info.get("is_station_link", false)) or item_key == "__station_route__":
				var badge_pos := mid
				if p1.x > p2.x:
					badge_pos.y += 22.0
				var r_txt = main_ref.i18n.tf("station_route_badge", [int(info.get("item_count", 0)), main_ref.settings.fmt(rate)])
				var r_tw := font.get_string_size(r_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FIXED_FONT_SIZE).x + 14.0
				var r_th := 20.0
				var r_rect := Rect2(badge_pos - Vector2(r_tw * 0.5, r_th * 0.5), Vector2(r_tw, r_th))
				draw_rect(r_rect, Color(0.14, 0.10, 0.05, 0.95 * alpha), true)
				draw_rect(r_rect, Color(0.98, 0.72, 0.34, alpha), false, 2.0 if is_highlighted else 1.5)
				draw_string(font, r_rect.position + Vector2(7.0, 14.0), r_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FIXED_FONT_SIZE, Color(1.0, 0.84, 0.0, alpha))
				continue
			
			var cache_sig := "%s_%.4f_%s_%d" % [item_key, rate, main_ref.i18n.current_lang, main_ref.settings.decimals]
			var b_entry: Dictionary
			if _badge_cache.has(w_key) and _badge_cache[w_key]["sig"] == cache_sig:
				b_entry = _badge_cache[w_key]
			else:
				var tier_info: Dictionary = main_ref.db.get_min_logistics_tier(item_key, rate)
				var unit = main_ref.i18n.t("unit_fluid_per_min") if main_ref.db.is_item_fluid(item_key) else main_ref.i18n.t("unit_per_min")
				var txt := "%s %s • %s" % [main_ref.settings.fmt(rate), unit, tier_info["label"]]
				var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FIXED_FONT_SIZE).x + 14.0
				b_entry = {"sig": cache_sig, "txt": txt, "tw": tw, "over": bool(tier_info["over"])}
				_badge_cache[w_key] = b_entry
			
			var is_over: bool = bool(b_entry["over"]) or (
				rate > (main_ref.settings.pipe_limit if main_ref.db.is_item_fluid(item_key) else main_ref.settings.belt_limit) + 0.01
			)
			var col: Color = Color(0.95, 0.25, 0.25) if is_over else wire_col
			var border_c := Color.html("#FAB757") if is_highlighted else col.lightened(0.2)
			border_c.a = alpha
			
			var bw := float(b_entry["tw"])
			var bh := 20.0
			var rect := Rect2(mid - Vector2(bw * 0.5, bh * 0.5), Vector2(bw, bh))
			draw_rect(rect, Color(0.08, 0.09, 0.12, 0.94 * alpha), true)
			draw_rect(rect, border_c, false, 2.0 if is_highlighted else 1.3)
			var txt_col := Color.WHITE if not is_over else Color.GOLD
			txt_col.a = alpha
			draw_string(font, rect.position + Vector2(7.0, 14.0), String(b_entry["txt"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FIXED_FONT_SIZE, txt_col)

static func compute_graph_visual_hash(g: GraphEdit, main_ref: GraphEdit) -> int:
	var h := hash(g.scroll_offset)
	h = hash(Vector3(g.zoom, float(main_ref.settings.orthogonal_wires), float(main_ref.settings.show_wire_labels))) ^ h
	h = hash(g.get_connection_list().size()) ^ h
	if main_ref._dragging_wp_graph == g:
		h = hash(main_ref.get_viewport().get_mouse_position()) ^ h
	for ch in g.get_children():
		if ch is GraphNode and ch.visible and ch.has_meta("node_kind"):
			h = hash(Vector4(ch.position_offset.x, ch.position_offset.y, ch.size.x, float(ch.selected))) ^ h
	return h

static func build_wire_screen_points(p1: Vector2, p2: Vector2, wps_world: Array, z: float, scroll: Vector2, is_ortho: bool) -> PackedVector2Array:
	var anchors: Array[Vector2] = [p1]
	for w in wps_world:
		if w is Vector2:
			anchors.append(w * z - scroll)
	anchors.append(p2)
	
	var pts := PackedVector2Array()
	var n_seg := anchors.size() - 1
	if is_ortho:
		var pad := 26.0 * z
		pts.append(anchors[0])
		for i in range(n_seg):
			var a := anchors[i]
			var b := anchors[i + 1]
			if n_seg == 1:
				if b.x >= a.x + 16.0 * z:
					var mid_x := (a.x + b.x) * 0.5
					pts.append(Vector2(mid_x, a.y))
					pts.append(Vector2(mid_x, b.y))
				else:
					var mid_y := (a.y + b.y) * 0.5
					pts.append(Vector2(a.x + pad, a.y))
					pts.append(Vector2(a.x + pad, mid_y))
					pts.append(Vector2(b.x - pad, mid_y))
					pts.append(Vector2(b.x - pad, b.y))
			elif i == 0:
				var out_x := a.x + pad if b.x < a.x + pad else minf(a.x + pad, (a.x + b.x) * 0.5)
				pts.append(Vector2(out_x, a.y))
				pts.append(Vector2(out_x, b.y))
			elif i == n_seg - 1:
				var in_x := b.x - pad if b.x - pad > a.x else maxf(b.x - pad, (a.x + b.x) * 0.5)
				pts.append(Vector2(in_x, a.y))
				pts.append(Vector2(in_x, b.y))
			else:
				if absf(b.x - a.x) >= absf(b.y - a.y):
					pts.append(Vector2(b.x, a.y))
				else:
					pts.append(Vector2(a.x, b.y))
			pts.append(b)
	else:
		var steps := 8 if z < 0.35 else 14
		for i in range(n_seg):
			var a := anchors[i]
			var b := anchors[i + 1]
			var dx := maxf(36.0 * z, absf(b.x - a.x) * 0.42)
			var c1 := a + (Vector2(dx, 0.0) if i == 0 else (b - anchors[i - 1]).normalized() * dx * 0.55)
			var c2 := b - (Vector2(dx, 0.0) if i == n_seg - 1 else (anchors[i + 2] - a).normalized() * dx * 0.55)
			var start_s := 0 if i == 0 else 1
			for s in range(start_s, steps + 1):
				var t := float(s) / float(steps)
				var omt := 1.0 - t
				var pt := (omt * omt * omt) * a + (3.0 * omt * omt * t) * c1 + (3.0 * omt * t * t) * c2 + (t * t * t) * b
				pts.append(pt)
	return pts

static func get_polyline_midpoint(pts: PackedVector2Array, fallback: Vector2) -> Vector2:
	if pts.size() < 2:
		return fallback
	var total_len := 0.0
	for i in range(pts.size() - 1):
		total_len += pts[i].distance_to(pts[i + 1])
	var half := total_len * 0.5
	var acc := 0.0
	for i in range(pts.size() - 1):
		var seg_l := pts[i].distance_to(pts[i + 1])
		if acc + seg_l >= half and seg_l > 0.001:
			return pts[i].lerp(pts[i + 1], (half - acc) / seg_l)
		acc += seg_l
	return fallback
