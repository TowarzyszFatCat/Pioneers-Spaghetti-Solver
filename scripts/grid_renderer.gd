class_name GridRenderer
extends RefCounted

const PERMS_3 := [
	[0, 1, 2], [0, 2, 1],
	[1, 0, 2], [1, 2, 0],
	[2, 0, 1], [2, 1, 0]
]

var view: GridPlannerView
var db: AppDB
var settings: AppSettings
var i18n: AppI18n

func _init(p_view: GridPlannerView, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	view = p_view
	db = p_db
	settings = p_settings
	i18n = p_i18n

func _side_to_dir_vec(side: int) -> Vector2:
	match side % 4:
		0: return Vector2.RIGHT
		1: return Vector2.DOWN
		2: return Vector2.LEFT
		_: return Vector2.UP

func get_block_port_info(b: Dictionary, rect: Rect2, is_input: bool, port_idx: int) -> Dictionary:
	var rot := int(b.get("rot", 0))
	var b_name := String(b.get("b_name", ""))

	if b_name == "splitter":
		var side := 0
		if is_input:
			side = (rot + 2) % 4
		else:
			var out_sides := [(rot + 3) % 4, rot % 4, (rot + 1) % 4]
			side = out_sides[clampi(port_idx, 0, 2)]
		return {"pos": _get_wall_point(rect, side, 0.5), "side": side}

	if b_name == "merger":
		var side := 0
		if is_input:
			var in_sides := [(rot + 3) % 4, (rot + 2) % 4, (rot + 1) % 4]
			side = in_sides[clampi(port_idx, 0, 2)]
		else:
			side = rot % 4
		return {"pos": _get_wall_point(rect, side, 0.5), "side": side}

	if b_name in ["lift_in", "lift_out"]:
		var l_side := (rot + (2 if is_input else 0)) % 4
		return {"pos": _get_wall_point(rect, l_side, 0.5), "side": l_side}

	var total_ports := int(b.get("in_ports" if is_input else "out_ports", 0))
	var std_side := (rot + (2 if is_input else 0)) % 4
	var t := float(clampi(port_idx, 0, maxi(0, total_ports - 1)) + 1) / float(maxi(1, total_ports) + 1)
	return {"pos": _get_wall_point(rect, std_side, t), "side": std_side}

func _get_wall_point(rect: Rect2, side: int, t: float) -> Vector2:
	match side % 4:
		0: return Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, t))
		1: return Vector2(lerpf(rect.position.x, rect.end.x, t), rect.end.y)
		2: return Vector2(rect.position.x, lerpf(rect.position.y, rect.end.y, t))
		_: return Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y)

func _compute_wire_port_assignments(step_px: float) -> Dictionary:
	var out_map: Dictionary = {}
	var in_map: Dictionary = {}
	var outgoing_by_block: Dictionary = {}
	var incoming_by_block: Dictionary = {}

	for i in range(view.wire_links.size()):
		var wl: Dictionary = view.wire_links[i]
		var f_id := String(wl["from_id"])
		var t_id := String(wl["to_id"])
		if not view.blocks.has(f_id) or not view.blocks.has(t_id):
			continue
		out_map[i] = 0
		in_map[i] = 0
		if not outgoing_by_block.has(f_id):
			outgoing_by_block[f_id] = []
		outgoing_by_block[f_id].append(i)
		if not incoming_by_block.has(t_id):
			incoming_by_block[t_id] = []
		incoming_by_block[t_id].append(i)

	for bid in outgoing_by_block.keys():
		var b: Dictionary = view.blocks[bid]
		var w_indices: Array = outgoing_by_block[bid]
		var b_name := String(b.get("b_name", ""))
		var b_rect := Rect2(view._world_f_to_screen(b["pos_f"]), view._get_effective_size_f(b) * step_px)
		var b_center := b_rect.get_center()

		if b_name == "splitter":
			_assign_three_way_ports(b, b_rect, b_center, w_indices, false, out_map, step_px)
		else:
			var out_cnt := maxi(1, int(b.get("out_ports", 1)))
			if out_cnt > 1 and w_indices.size() > 1:
				w_indices.sort_custom(func(ia: int, ib: int):
					var ta: Dictionary = view.blocks[view.wire_links[ia]["to_id"]]
					var tb: Dictionary = view.blocks[view.wire_links[ib]["to_id"]]
					return ta["pos_f"].y < tb["pos_f"].y
				)
				for idx in range(w_indices.size()):
					out_map[w_indices[idx]] = idx % out_cnt

	for bid in incoming_by_block.keys():
		var b: Dictionary = view.blocks[bid]
		var w_indices: Array = incoming_by_block[bid]
		var b_name := String(b.get("b_name", ""))
		var b_rect := Rect2(view._world_f_to_screen(b["pos_f"]), view._get_effective_size_f(b) * step_px)
		var b_center := b_rect.get_center()

		if b_name == "merger":
			_assign_three_way_ports(b, b_rect, b_center, w_indices, true, in_map, step_px)
		else:
			var in_cnt := maxi(1, int(b.get("in_ports", 1)))
			if in_cnt > 1 and w_indices.size() > 1:
				w_indices.sort_custom(func(ia: int, ib: int):
					var sa: Dictionary = view.blocks[view.wire_links[ia]["from_id"]]
					var sb_blk: Dictionary = view.blocks[view.wire_links[ib]["from_id"]]
					return sa["pos_f"].y < sb_blk["pos_f"].y
				)
				for idx in range(w_indices.size()):
					in_map[w_indices[idx]] = idx % in_cnt

	return {"out_ports": out_map, "in_ports": in_map}

func _assign_three_way_ports(b: Dictionary, b_rect: Rect2, b_center: Vector2, w_indices: Array, is_input: bool, result_map: Dictionary, step_px: float) -> void:
	var n := w_indices.size()
	if n == 0:
		return

	var rot := int(b.get("rot", 0))
	var main_side := (rot + (2 if is_input else 0)) % 4
	var main_axis := _side_to_dir_vec(main_side)
	var lat_axis := Vector2(-main_axis.y, main_axis.x)

	var target_dirs: Array[Vector2] = []
	for wi in w_indices:
		var wl: Dictionary = view.wire_links[wi]
		var other_id: String = String(wl["from_id"] if is_input else wl["to_id"])
		var other_b: Dictionary = view.blocks[other_id]
		var other_rect := Rect2(view._world_f_to_screen(other_b["pos_f"]), view._get_effective_size_f(other_b) * step_px)
		var other_c := other_rect.get_center()
		if is_input and bool(wl.get("is_feedback", false)):
			other_c = b_center + Vector2(0.0, -80.0 * view.cam_zoom)
		var raw_d := other_c - b_center
		var fwd_comp := raw_d.dot(main_axis)
		var lat_comp := raw_d.dot(lat_axis) * 1.45
		var weighted := (main_axis * fwd_comp + lat_axis * lat_comp).normalized()
		if weighted.length_squared() < 0.001:
			weighted = main_axis
		target_dirs.append(weighted)

	if n <= 3:
		var best_perm: Array = PERMS_3[0]
		var best_score := -999999.0
		for perm in PERMS_3:
			var score := 0.0
			for i in range(n):
				var p_idx: int = int(perm[i])
				var p_info := get_block_port_info(b, b_rect, is_input, p_idx)
				var p_vec := _side_to_dir_vec(int(p_info["side"]))
				score += p_vec.dot(target_dirs[i])
			if score > best_score:
				best_score = score
				best_perm = perm
		for i in range(n):
			result_map[w_indices[i]] = int(best_perm[i])
	else:
		for i in range(n):
			result_map[w_indices[i]] = i % 3

func draw_grid_view() -> void:
	var vp_size := view.size
	var cam_zoom := view.cam_zoom
	var cam_offset := view.cam_offset
	var cur_floor := view.current_floor

	if view.belt_builder != null:
		view.belt_builder.solve_physical_belt_network(cur_floor)

	view.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.05, 0.07, 0.10, 1.0), true)
	var font := ThemeDB.fallback_font
	var step_px := GridPlannerView.PX_PER_FOUNDATION * cam_zoom
	var sub_px := step_px * 0.25
	var snap1m_px := step_px * 0.125
	var mem := view._get_active_mem()

	var focus_id := view.dragging_id if view.dragging_id != "" else view.hovered_id
	var connected_in_sources: Dictionary = {}
	var connected_out_targets: Dictionary = {}
	if focus_id != "":
		for wl in view.wire_links:
			if wl["to_id"] == focus_id:
				connected_in_sources[wl["from_id"]] = true
			elif wl["from_id"] == focus_id:
				connected_out_targets[wl["to_id"]] = true

	var port_assignments := _compute_wire_port_assignments(step_px)
	var wire_out_ports: Dictionary = port_assignments["out_ports"]
	var wire_in_ports: Dictionary = port_assignments["in_ports"]

	# 1. Draw lower floor blueprint preview (Onion Skin / Ghost Floor)
	if view.show_ghost_floor:
		var ghost_fl := cur_floor - 1
		for k in mem.keys():
			var ks := String(k)
			if ks.begins_with("__tile_") and int(mem[k].get("floor", 0)) == ghost_fl:
				var tp: Vector2 = mem[k]["pos_f"]
				var trect := Rect2(view._world_f_to_screen(tp), Vector2(step_px, step_px))
				view.draw_rect(trect, Color(0.12, 0.18, 0.25, 0.22), true)
		for bid in view.blocks.keys():
			var gb: Dictionary = view.blocks[bid]
			if int(gb.get("floor", 0)) != ghost_fl:
				continue
			var g_rect := Rect2(view._world_f_to_screen(gb["pos_f"]), view._get_effective_size_f(gb) * step_px)
			view.draw_rect(g_rect, Color(0.2, 0.45, 0.65, 0.15), true)
			view.draw_rect(g_rect, Color(0.35, 0.65, 0.85, 0.30), false, 1.2)

	# 2. Draw painted foundation tiles on the current floor
	for k in mem.keys():
		var ks := String(k)
		if ks.begins_with("__tile_") and int(mem[k].get("floor", 0)) == cur_floor:
			var tp: Vector2 = mem[k]["pos_f"]
			var st := int(mem[k].get("rot", 1))
			var trect := Rect2(view._world_f_to_screen(tp), Vector2(step_px, step_px))
			var f_col := Color(0.16, 0.20, 0.26, 0.88)
			if st == 2:
				f_col = Color(0.24, 0.19, 0.13, 0.88)
			elif st == 3:
				f_col = Color(0.14, 0.24, 0.22, 0.88)
			view.draw_rect(trect, f_col, true)
			view.draw_rect(trect.grow(-2.0), f_col.lightened(0.12), false, 1.0)

	# 3. Draw foundation grid lines (8m, 4m, 2m, and 1m sub-grid when building belts/lifts)
	var start_x := fmod(-cam_offset.x, step_px)
	var start_y := fmod(-cam_offset.y, step_px)
	if start_x > 0:
		start_x -= step_px
	if start_y > 0:
		start_y -= step_px

	var main_grid_col := Color(0.22, 0.31, 0.42, 0.78)
	var half_grid_col := Color(0.15, 0.21, 0.29, 0.55)
	var sub16_grid_col := Color(0.11, 0.15, 0.22, 0.38)
	var sub1m_grid_col := Color(0.10, 0.14, 0.20, 0.24)
	var show_1m_grid := (view.current_tool in [GridPlannerView.ToolMode.BELT, GridPlannerView.ToolMode.LIFT] and snap1m_px >= 5.0)

	var x := start_x
	while x < vp_size.x:
		if show_1m_grid:
			for m_idx in [1, 3, 5, 7]:
				view.draw_line(Vector2(x + snap1m_px * float(m_idx), 0), Vector2(x + snap1m_px * float(m_idx), vp_size.y), sub1m_grid_col, 1.0)
		if sub_px >= 6.0:
			view.draw_line(Vector2(x + sub_px, 0), Vector2(x + sub_px, vp_size.y), sub16_grid_col, 1.0)
			view.draw_line(Vector2(x + sub_px * 3.0, 0), Vector2(x + sub_px * 3.0, vp_size.y), sub16_grid_col, 1.0)
		view.draw_line(Vector2(x + sub_px * 2.0, 0), Vector2(x + sub_px * 2.0, vp_size.y), half_grid_col, 1.0)
		view.draw_line(Vector2(x, 0), Vector2(x, vp_size.y), main_grid_col, 1.3)
		x += step_px

	var y := start_y
	while y < vp_size.y:
		if show_1m_grid:
			for m_idx in [1, 3, 5, 7]:
				view.draw_line(Vector2(0, y + snap1m_px * float(m_idx)), Vector2(vp_size.x, y + snap1m_px * float(m_idx)), sub1m_grid_col, 1.0)
		if sub_px >= 6.0:
			view.draw_line(Vector2(0, y + sub_px), Vector2(vp_size.x, y + sub_px), sub16_grid_col, 1.0)
			view.draw_line(Vector2(0, y + sub_px * 3.0), Vector2(vp_size.x, y + sub_px * 3.0), sub16_grid_col, 1.0)
		view.draw_line(Vector2(0, y + sub_px * 2.0), Vector2(vp_size.x, y + sub_px * 2.0), half_grid_col, 1.0)
		view.draw_line(Vector2(0, y), Vector2(vp_size.x, y), main_grid_col, 1.3)
		y += step_px

	# 4. Draw structural pillars (4x4m) and pass-through Lift shafts on intermediate floors
	for k in mem.keys():
		var ks := String(k)
		if ks.begins_with("__pil_") and int(mem[k].get("floor", 0)) == cur_floor:
			var pp: Vector2 = mem[k]["pos_f"]
			var prect := Rect2(view._world_f_to_screen(pp), Vector2(0.5 * step_px, 0.5 * step_px))
			view.draw_rect(prect, Color(0.28, 0.32, 0.38, 0.96), true)
			view.draw_rect(prect, Color.html("#FAB757"), false, 2.0)
			view.draw_line(prect.position, prect.end, Color(1, 1, 1, 0.35), 1.2)
			view.draw_line(Vector2(prect.end.x, prect.position.y), Vector2(prect.position.x, prect.end.y), Color(1, 1, 1, 0.35), 1.2)

	for bid in view.blocks.keys():
		var b: Dictionary = view.blocks[bid]
		if String(b.get("b_name", "")) == "lift_in":
			var fl_a := int(b.get("floor", 0))
			var fl_b := int(b.get("target_floor", fl_a))
			if cur_floor > mini(fl_a, fl_b) and cur_floor < maxi(fl_a, fl_b):
				var s_rect := Rect2(view._world_f_to_screen(b["pos_f"]), GridPlannerView.LIFT_SIZE_F * step_px)
				view.draw_rect(s_rect, Color(0.20, 0.16, 0.08, 0.88), true)
				view.draw_rect(s_rect, Color.GOLD, false, 2.0)
				view.draw_line(s_rect.position, s_rect.end, Color(1, 0.85, 0.2, 0.55), 1.5)
				view.draw_line(Vector2(s_rect.end.x, s_rect.position.y), Vector2(s_rect.position.x, s_rect.end.y), Color(1, 0.85, 0.2, 0.55), 1.5)
				if cam_zoom >= 0.5:
					var sh_txt := i18n.tf("grid_lift_thru_tag", [fl_a, fl_b])
					view.draw_string(font, s_rect.position + Vector2(-8, -4), sh_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.GOLD)

	# Brush preview for foundation / pillar / splitter / merger / lift tool under cursor
	if view.current_tool == GridPlannerView.ToolMode.FOUNDATION:
		var h_tp := Vector2(floorf(view.last_mouse_world_f.x), floorf(view.last_mouse_world_f.y))
		var h_rect := Rect2(view._world_f_to_screen(h_tp), Vector2(step_px, step_px))
		view.draw_rect(h_rect, Color(0.3, 0.85, 1.0, 0.25), true)
		view.draw_rect(h_rect, Color.AQUAMARINE, false, 2.0)
	elif view.current_tool == GridPlannerView.ToolMode.PILLAR:
		var h_pp := Vector2(snappedf(view.last_mouse_world_f.x - 0.25, 0.5), snappedf(view.last_mouse_world_f.y - 0.25, 0.5))
		var h_rect := Rect2(view._world_f_to_screen(h_pp), Vector2(0.5 * step_px, 0.5 * step_px))
		view.draw_rect(h_rect, Color(1.0, 0.75, 0.25, 0.35), true)
		view.draw_rect(h_rect, Color.GOLD, false, 2.0)
	elif view.current_tool in [GridPlannerView.ToolMode.SPLITTER, GridPlannerView.ToolMode.MERGER]:
		_draw_logistics_placement_preview(font, step_px)
	elif view.current_tool == GridPlannerView.ToolMode.LIFT:
		_draw_lift_placement_preview(font, step_px)

	# 5. Bounding box and CAD dimension lines for the active floor
	var bounds := view._get_on_grid_bounds()
	if bool(bounds["valid"]):
		var bp1 := view._world_f_to_screen(bounds["min_f"])
		var bp2 := view._world_f_to_screen(bounds["max_f"])
		var brect := Rect2(bp1, bp2 - bp1)
		view.draw_rect(brect, Color(0.2, 0.85, 0.95, 0.04), true)
		view.draw_rect(brect, Color(0.2, 0.85, 0.95, 0.75), false, 2.0)

		var span: Vector2 = (bounds["max_f"] - bounds["min_f"]).ceil()
		var dim_col := Color(0.45, 0.92, 1.0, 0.9)

		var top_y := bp1.y - 16.0
		view.draw_line(Vector2(bp1.x, top_y), Vector2(bp2.x, top_y), dim_col, 1.5)
		view.draw_line(Vector2(bp1.x, top_y - 5), Vector2(bp1.x, top_y + 5), dim_col, 1.5)
		view.draw_line(Vector2(bp2.x, top_y - 5), Vector2(bp2.x, top_y + 5), dim_col, 1.5)
		var w_txt := i18n.tf("grid_cad_width_fmt", [int(span.x), int(span.x) * 8])
		view.draw_string(font, Vector2(brect.get_center().x - 60, top_y - 5), w_txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, dim_col)

		var left_x := bp1.x - 14.0
		view.draw_line(Vector2(left_x, bp1.y), Vector2(left_x, bp2.y), dim_col, 1.5)
		view.draw_line(Vector2(left_x - 5, bp1.y), Vector2(left_x + 5, bp1.y), dim_col, 1.5)
		view.draw_line(Vector2(left_x - 5, bp2.y), Vector2(left_x + 5, bp2.y), dim_col, 1.5)
		var h_txt := i18n.tf("grid_cad_depth_fmt", [int(span.y), int(span.y) * 8])
		view.draw_string(font, Vector2(left_x - 68, brect.get_center().y + 4), h_txt, HORIZONTAL_ALIGNMENT_RIGHT, 62, 11, dim_col)

	# 6. Draw machine, splitter/merger, and lift blocks
	var unit_m := i18n.t("unit_per_min")
	var collisions := view._detect_collisions_on_current_floor()
	var hovered_port_overlays: Array[Dictionary] = []

	for bid in view.blocks.keys():
		var b: Dictionary = view.blocks[bid]
		if int(b.get("floor", 0)) != cur_floor:
			continue
		var pos_s := view._world_f_to_screen(b["pos_f"])
		var sz_f := view._get_effective_size_f(b)
		var sz_s := sz_f * step_px
		var rect := Rect2(pos_s, sz_s)
		var col: Color = b["color"]
		var border_col: Color = b.get("border_color", col.lightened(0.25))
		var is_offgrid := bool(b.get("exclude_from_footprint", false))
		var is_sel := view.selected_ids.has(bid)
		var is_hov = (bid == focus_id)
		var is_locked := bool(b.get("locked", false))
		var is_col := collisions.has(bid)
		var matches_filter := view.does_block_match_filter(String(bid))

		var alpha_mult := 1.0 if matches_filter else 0.18
		var bg_col := col.lightened(0.18) if (is_hov or is_sel) else col
		bg_col.a = (0.68 if is_offgrid else 0.93) * alpha_mult
		if is_col:
			bg_col = bg_col.lerp(Color(0.85, 0.12, 0.15, 0.95 * alpha_mult), 0.45)

		view.draw_rect(rect, bg_col, true)
		var b_width := 3.0 if (is_sel or is_hov or is_col) else (2.2 if is_locked else 1.8)
		var eff_border := Color.RED if is_col else (Color.html("#FAB757") if (is_sel or is_hov) else (Color.GOLD.darkened(0.15) if is_locked else border_col))
		if connected_in_sources.has(bid):
			eff_border = Color.SPRING_GREEN
			b_width = 2.6
		elif connected_out_targets.has(bid):
			eff_border = Color.html("#FF9E3B")
			b_width = 2.6
		eff_border.a *= alpha_mult
		view.draw_rect(rect, eff_border, false, b_width)

		var b_name := String(b.get("b_name", ""))
		var in_cnt := 1 if b_name == "splitter" else (3 if b_name == "merger" else int(b.get("in_ports", 0)))
		var out_cnt := 3 if b_name == "splitter" else (1 if b_name == "merger" else int(b.get("out_ports", 0)))
		var highlight_in = is_hov or connected_out_targets.has(bid) or (view.current_tool == GridPlannerView.ToolMode.BELT)
		var highlight_out = is_hov or connected_in_sources.has(bid) or (view.current_tool == GridPlannerView.ToolMode.BELT)

		for p_i in range(in_cnt):
			var p_info := get_block_port_info(b, rect, true, p_i)
			var pin_in: Vector2 = p_info["pos"]
			var pin_side: int = int(p_info["side"])
			var r_in := clampf((6.0 if highlight_in else 3.8) * cam_zoom, 2.8, 8.5)
			if highlight_in:
				view.draw_circle(pin_in, r_in + 3.2, Color(0.15, 0.95, 1.0, 0.35 * alpha_mult))
				view.draw_circle(pin_in, r_in, Color(0.25, 0.98, 1.0, alpha_mult))
				view.draw_arc(pin_in, r_in + 1.4, 0.0, TAU, 14, Color(1, 1, 1, alpha_mult), 1.5)
				if is_hov:
					hovered_port_overlays.append({"pos": pin_in, "side": pin_side, "is_in": true})
			else:
				view.draw_circle(pin_in, r_in, Color(0.48, 0.69, 0.83, alpha_mult))

		for p_o in range(out_cnt):
			var p_info := get_block_port_info(b, rect, false, p_o)
			var pin_out: Vector2 = p_info["pos"]
			var pin_side: int = int(p_info["side"])
			var r_out := clampf((6.0 if highlight_out else 3.8) * cam_zoom, 2.8, 8.5)
			if highlight_out:
				view.draw_circle(pin_out, r_out + 3.2, Color(1.0, 0.55, 0.1, 0.38 * alpha_mult))
				view.draw_circle(pin_out, r_out, Color(1.0, 0.62, 0.15, alpha_mult))
				view.draw_arc(pin_out, r_out + 1.4, 0.0, TAU, 14, Color(1, 1, 1, alpha_mult), 1.5)
				if is_hov:
					hovered_port_overlays.append({"pos": pin_out, "side": pin_side, "is_in": false})
			else:
				view.draw_circle(pin_out, r_out, Color(0.92, 0.49, 0.08, alpha_mult))

		var i_tex := db.get_icon_texture(String(b["main_item"]))
		var b_tex := db.get_icon_texture(b_name)
		var icon_sz := clampf(minf(sz_s.x, sz_s.y) * 0.45, 12.0, 42.0)
		var tex_to_draw := i_tex if i_tex != null else b_tex
		if tex_to_draw != null and sz_s.x >= 20.0:
			view.draw_texture_rect(tex_to_draw, Rect2(rect.get_center() - Vector2(icon_sz * 0.5, icon_sz * 0.5), Vector2(icon_sz, icon_sz)), false, Color(1, 1, 1, alpha_mult))

		var f_size := clampi(int(10.0 * cam_zoom), 8, 14)
		var max_title_w := maxf(16.0, sz_s.x - (22.0 if is_locked else 6.0))
		view.draw_string(font, rect.position + Vector2(4, f_size + 2), String(b["title"]), HORIZONTAL_ALIGNMENT_LEFT, max_title_w, f_size, Color(1, 1, 1, alpha_mult))

		if is_locked and not (b_name in ["lift_in", "lift_out"]) and sz_s.x >= 24.0:
			view.draw_string(font, Vector2(rect.end.x - 16.0, rect.position.y + f_size + 2), "🔒", HORIZONTAL_ALIGNMENT_RIGHT, 16.0, maxi(9, f_size), Color(1.0, 0.85, 0.25, alpha_mult))

		if is_col and sz_s.y >= 28.0:
			view.draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 4), i18n.t("grid_collision_warn"), HORIZONTAL_ALIGNMENT_LEFT, maxf(16.0, sz_s.x - 6.0), maxi(8, f_size - 1), Color(1.0, 1.0, 0.0, alpha_mult))
		elif sz_s.y >= 34.0:
			view.draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 4), String(b["sub"]), HORIZONTAL_ALIGNMENT_LEFT, maxf(16.0, sz_s.x - 6.0), maxi(8, f_size - 2), Color(0.88, 0.92, 0.98, 0.9 * alpha_mult))

	# 7. Draw unrouted schematic links and unrouted inter-floor lift indicators
	for w_idx in range(view.wire_links.size()):
		var wl: Dictionary = view.wire_links[w_idx]
		var f_id: String = wl["from_id"]
		var t_id: String = wl["to_id"]
		if not view.blocks.has(f_id) or not view.blocks.has(t_id):
			continue
		var sb: Dictionary = view.blocks[f_id]
		var db_blk: Dictionary = view.blocks[t_id]
		var sf := int(sb.get("floor", 0))
		var df := int(db_blk.get("floor", 0))
		if sf != cur_floor and df != cur_floor:
			continue

		# Hide both same-floor schematic wires AND automatic inter-floor lift icons once physically connected!
		if view.belt_builder != null and view.belt_builder.is_wire_link_routed(wl, cur_floor):
			continue

		var s_rect := Rect2(view._world_f_to_screen(sb["pos_f"]), view._get_effective_size_f(sb) * step_px)
		var d_rect := Rect2(view._world_f_to_screen(db_blk["pos_f"]), view._get_effective_size_f(db_blk) * step_px)
		var src_port_idx := int(wire_out_ports.get(w_idx, 0))
		var dst_port_idx := int(wire_in_ports.get(w_idx, 0))
		var s_info := get_block_port_info(sb, s_rect, false, src_port_idx)
		var d_info := get_block_port_info(db_blk, d_rect, true, dst_port_idx)
		var p1: Vector2 = s_info["pos"]
		var p2: Vector2 = d_info["pos"]
		var side1: int = int(s_info["side"])
		var side2: int = int(d_info["side"])

		var is_fb := bool(wl.get("is_feedback", false))
		var w_item := String(wl["item"])
		var w_col := Color.html("#76F5E8") if is_fb else db.get_item_color(w_item)

		var is_focus_wire := (focus_id != "" and (f_id == focus_id or t_id == focus_id))
		var wire_alpha := 1.0
		if view.filter_item_key != "" and w_item != view.filter_item_key:
			wire_alpha = 0.14
		elif focus_id != "" and not is_focus_wire:
			wire_alpha = 0.35

		if is_focus_wire:
			w_col = Color(0.25, 0.98, 1.0) if t_id == focus_id else Color(1.0, 0.68, 0.18)
		w_col.a = wire_alpha
		var w_thick := (3.6 if is_focus_wire else 2.2)

		if sf != df:
			var is_out_on_cur := (sf == cur_floor)
			var pin_pos := p1 if is_out_on_cur else p2
			var port_side := side1 if is_out_on_cur else side2
			var dir_vec := _side_to_dir_vec(port_side)

			var lift_sz_px := maxf(10.0, 0.25 * step_px)
			var lift_center := pin_pos + dir_vec * (lift_sz_px * 0.5 + 2.0 * cam_zoom)
			var l_rect := Rect2(lift_center - Vector2(lift_sz_px * 0.5, lift_sz_px * 0.5), Vector2(lift_sz_px, lift_sz_px))

			view.draw_line(pin_pos, lift_center, w_col, maxf(2.0, w_thick * cam_zoom), true)
			view.draw_rect(l_rect.grow(1.5), Color(0.05, 0.06, 0.09, 0.96 * wire_alpha), true)
			view.draw_rect(l_rect, w_col.darkened(0.55), true)
			view.draw_rect(l_rect, Color(1.0, 0.84, 0.0, wire_alpha), false, maxf(1.5, 2.0 * cam_zoom))

			var lift_tex := db.get_icon_texture(w_item)
			if lift_tex != null and lift_sz_px >= 11.0:
				var pad := maxf(2.0, lift_sz_px * 0.12)
				view.draw_texture_rect(lift_tex, l_rect.grow(-pad), false, Color(1, 1, 1, wire_alpha))

			if cam_zoom >= 0.45 and wire_alpha > 0.25:
				var other_fl := df if is_out_on_cur else sf
				var arrow_str := ("▲ P%d" % other_fl) if other_fl > cur_floor else ("▼ P%d" % other_fl)
				var lift_lbl := "%s (%s)" % [arrow_str, settings.fmt(float(wl["rate"]))]
				var lf_size := clampi(int(9.5 * cam_zoom), 8, 13)
				var lbl_pos := Vector2(l_rect.position.x - 4.0, l_rect.position.y - 4.0) if dir_vec.y <= 0 else Vector2(l_rect.position.x - 4.0, l_rect.end.y + lf_size + 2.0)
				view.draw_string(font, lbl_pos, lift_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lf_size, Color(1.0, 0.84, 0.0, wire_alpha))
			continue

		if is_fb:
			var loop_y := minf(p1.y, p2.y) - 32.0 * cam_zoom
			var c1 := Vector2(p1.x, loop_y) if (side1 % 2 == 1) else Vector2(p1.x + 12.0 * cam_zoom, loop_y)
			var c2 := Vector2(p2.x, loop_y)
			view.draw_dashed_line(p1, c1, w_col, w_thick, 6.0)
			view.draw_dashed_line(c1, c2, w_col, w_thick, 6.0)
			view.draw_dashed_line(c2, p2, w_col, w_thick, 6.0)
			if wire_alpha > 0.25:
				var mid_fb := (c1 + c2) * 0.5
				var fb_txt := i18n.tf("grid_loopback", [settings.fmt(float(wl["rate"]))])
				view.draw_string(font, mid_fb - Vector2(40, 5), fb_txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(0.5, 1.0, 0.83, wire_alpha))
		elif view.manhattan_wires:
			var is_vert1 := (side1 % 2 == 1)
			var is_vert2 := (side2 % 2 == 1)
			var mid := (p1 + p2) * 0.5

			if is_vert1 and not is_vert2:
				var corner := Vector2(p1.x, p2.y)
				view.draw_line(p1, corner, w_col, w_thick, true)
				view.draw_line(corner, p2, w_col, w_thick, true)
				mid = (corner + p2) * 0.5
			elif not is_vert1 and is_vert2:
				var corner := Vector2(p2.x, p1.y)
				view.draw_line(p1, corner, w_col, w_thick, true)
				view.draw_line(corner, p2, w_col, w_thick, true)
				mid = (p1 + corner) * 0.5
			elif is_vert1 and is_vert2:
				var mid_y := (p1.y + p2.y) * 0.5
				view.draw_line(p1, Vector2(p1.x, mid_y), w_col, w_thick, true)
				view.draw_line(Vector2(p1.x, mid_y), Vector2(p2.x, mid_y), w_col, w_thick, true)
				view.draw_line(Vector2(p2.x, mid_y), p2, w_col, w_thick, true)
				mid = Vector2((p1.x + p2.x) * 0.5, mid_y)
			else:
				var mid_x := (p1.x + p2.x) * 0.5
				view.draw_line(p1, Vector2(mid_x, p1.y), w_col, w_thick, true)
				view.draw_line(Vector2(mid_x, p1.y), Vector2(mid_x, p2.y), w_col, w_thick, true)
				view.draw_line(Vector2(mid_x, p2.y), p2, w_col, w_thick, true)
				mid = Vector2(mid_x, (p1.y + p2.y) * 0.5)

			if wire_alpha > 0.25:
				var lbl_c := w_col.lightened(0.28)
				lbl_c.a = wire_alpha
				view.draw_string(font, mid + Vector2(4, -3), "  %s%s" % [settings.fmt(float(wl["rate"])), unit_m], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lbl_c)
		else:
			view.draw_line(p1, p2, w_col, w_thick, true)
			if wire_alpha > 0.25:
				var mid := (p1 + p2) * 0.5
				var lbl_c := w_col.lightened(0.28)
				lbl_c.a = wire_alpha
				view.draw_string(font, mid + Vector2(4, -3), "  %s%s" % [settings.fmt(float(wl["rate"])), unit_m], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lbl_c)

	# 7A. Draw Physical 2m Conveyor Belts & Poles (and active routing preview)
	if view.belt_builder != null:
		view.belt_builder.draw_physical_belts(font, step_px, cur_floor, focus_id)

	# 7B. Draw floating IN / OUT directional badges on hovered block ports
	for po in hovered_port_overlays:
		_draw_hovered_port_badge(font, po["pos"], int(po["side"]), bool(po["is_in"]))

	# 8. Box Selection rectangle and CAD Ruler
	if view.is_box_selecting:
		var srect := Rect2(view.box_select_start_s, view.box_select_end_s - view.box_select_start_s).abs()
		view.draw_rect(srect, Color(0.25, 0.75, 1.0, 0.15), true)
		view.draw_rect(srect, Color(0.35, 0.85, 1.0, 0.9), false, 1.8)

	if view.is_measuring:
		var rp1 := view._world_f_to_screen(view.ruler_start_f)
		var rp2 := view._world_f_to_screen(view.ruler_end_f)
		view.draw_line(rp1, Vector2(rp2.x, rp1.y), Color(1.0, 0.85, 0.2, 0.7), 1.5)
		view.draw_line(Vector2(rp2.x, rp1.y), rp2, Color(1.0, 0.85, 0.2, 0.7), 1.5)
		view.draw_line(rp1, rp2, Color.GOLD, 2.5)
		view.draw_circle(rp1, 4.5, Color.GOLD)
		view.draw_circle(rp2, 4.5, Color.GOLD)

		var df := (view.ruler_end_f - view.ruler_start_f).abs()
		var dist_f := view.ruler_start_f.distance_to(view.ruler_end_f)
		var r_txt := i18n.tf("grid_ruler_fmt", [
			settings.fmt(df.x), settings.fmt(df.x * 8.0),
			settings.fmt(df.y), settings.fmt(df.y * 8.0),
			settings.fmt(dist_f * 8.0)
		])
		var r_mid := (rp1 + rp2) * 0.5 + Vector2(0, -14)
		var tw := font.get_string_size(r_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
		var r_box := Rect2(r_mid - Vector2(tw * 0.5, 18), Vector2(tw, 24))
		view.draw_rect(r_box, Color(0.06, 0.08, 0.12, 0.96), true)
		view.draw_rect(r_box, Color.GOLD, false, 1.8)
		view.draw_string(font, r_box.position + Vector2(8, 16), r_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.GOLD)

	if view.show_elevation:
		draw_elevation_panel(font)

func _draw_hovered_port_badge(font: Font, pin_pos: Vector2, side: int, is_in: bool) -> void:
	var txt := i18n.t("grid_port_in" if is_in else "grid_port_out")
	var col := Color(0.18, 0.95, 1.0) if is_in else Color(1.0, 0.62, 0.15)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
	var th := 16.0
	var offset := Vector2.ZERO
	match side % 4:
		0: offset = Vector2(10.0, -th * 0.5)
		1: offset = Vector2(-tw * 0.5, 10.0)
		2: offset = Vector2(-tw - 10.0, -th * 0.5)
		3: offset = Vector2(-tw * 0.5, -th - 10.0)

	var brect := Rect2(pin_pos + offset, Vector2(tw, th))
	view.draw_rect(brect, Color(0.05, 0.07, 0.11, 0.94), true)
	view.draw_rect(brect, col, false, 1.5)
	view.draw_string(font, brect.position + Vector2(5.0, 12.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

func _draw_logistics_placement_preview(font: Font, step_px: float) -> void:
	var is_sp := (view.current_tool == GridPlannerView.ToolMode.SPLITTER)
	var pos_f := view._snap_vec(view.last_mouse_world_f - GridPlannerView.SPLITTER_SIZE_F * 0.5)
	var rect := Rect2(view._world_f_to_screen(pos_f), GridPlannerView.SPLITTER_SIZE_F * step_px)
	var dummy_blk := {
		"b_name": "splitter" if is_sp else "merger",
		"rot": view.placement_rot,
		"in_ports": 1 if is_sp else 3,
		"out_ports": 3 if is_sp else 1
	}
	var bg_col := Color(0.95, 0.55, 0.15, 0.35) if is_sp else Color(0.35, 0.75, 1.0, 0.35)
	var border_col := Color.html("#EB7D15") if is_sp else Color.html("#7AB0D4")
	view.draw_rect(rect, bg_col, true)
	view.draw_rect(rect, border_col, false, 2.2)

	var in_cnt := 1 if is_sp else 3
	var out_cnt := 3 if is_sp else 1
	for i in range(in_cnt):
		var p_in := get_block_port_info(dummy_blk, rect, true, i)
		view.draw_circle(p_in["pos"], clampf(5.0 * view.cam_zoom, 3.0, 7.5), Color(0.25, 0.98, 1.0))
		_draw_hovered_port_badge(font, p_in["pos"], int(p_in["side"]), true)
	for i in range(out_cnt):
		var p_out := get_block_port_info(dummy_blk, rect, false, i)
		view.draw_circle(p_out["pos"], clampf(5.0 * view.cam_zoom, 3.0, 7.5), Color(1.0, 0.62, 0.15))
		_draw_hovered_port_badge(font, p_out["pos"], int(p_out["side"]), false)

func _draw_lift_placement_preview(font: Font, step_px: float) -> void:
	var pending_raw = view.get("pending_lift")
	var pending: Dictionary = pending_raw if (pending_raw is Dictionary) else {}
	var is_step_two := not pending.is_empty()

	var pos_f := view._snap_vec(view.last_mouse_world_f - GridPlannerView.LIFT_SIZE_F * 0.5)
	if is_step_two and pending.has("pos_f"):
		pos_f = pending["pos_f"]

	var rect := Rect2(view._world_f_to_screen(pos_f), GridPlannerView.LIFT_SIZE_F * step_px)
	var start_fl := int(pending.get("floor", view.current_floor)) if is_step_two else view.current_floor
	var valid_step_two := (not is_step_two) or (view.current_floor != start_fl)

	var bg_col := Color(0.95, 0.78, 0.15, 0.38) if valid_step_two else Color(0.95, 0.25, 0.25, 0.38)
	var border_col := Color.GOLD if valid_step_two else Color.SALMON
	view.draw_rect(rect, bg_col, true)
	view.draw_rect(rect, border_col, false, 2.4)

	var dummy_blk := {
		"b_name": "lift_out" if is_step_two else "lift_in",
		"rot": view.placement_rot,
		"in_ports": 0 if is_step_two else 1,
		"out_ports": 1 if is_step_two else 0
	}
	var p_info := get_block_port_info(dummy_blk, rect, not is_step_two, 0)
	var pin_col := Color(1.0, 0.62, 0.15) if is_step_two else Color(0.25, 0.98, 1.0)
	view.draw_circle(p_info["pos"], clampf(5.5 * view.cam_zoom, 3.5, 8.0), pin_col)
	_draw_hovered_port_badge(font, p_info["pos"], int(p_info["side"]), not is_step_two)

	var status_txt := ""
	if not is_step_two:
		status_txt = "🛗 LPM = Wejście (P%d)" % view.current_floor
	elif view.current_floor == start_fl:
		status_txt = "⚠ Zmień piętro (PgUp / PgDn)!"
	else:
		status_txt = "🛗 LPM = Wyjście (P%d ➔ P%d)" % [start_fl, view.current_floor]

	var tw := font.get_string_size(status_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
	var lbl_rect := Rect2(rect.get_center() + Vector2(-tw * 0.5, -rect.size.y * 0.5 - 26.0), Vector2(tw, 20.0))
	view.draw_rect(lbl_rect, Color(0.05, 0.07, 0.11, 0.95), true)
	view.draw_rect(lbl_rect, border_col, false, 1.6)
	view.draw_string(font, lbl_rect.position + Vector2(6.0, 14.0), status_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, border_col)

func draw_elevation_panel(font: Font) -> void:
	var panel_w := 320.0
	var panel_h := 240.0
	var prect := Rect2(view.size.x - panel_w - 14.0, 62.0, panel_w, panel_h)
	view.draw_rect(prect, Color(0.07, 0.09, 0.13, 0.95), true)
	view.draw_rect(prect, Color(0.3, 0.75, 0.95, 0.85), false, 1.8)
	view.draw_string(font, prect.position + Vector2(12, 22), i18n.tf("grid_elev_title", [view.current_floor]), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 20, 13, Color.AQUAMARINE)

	var unique_b: Dictionary = {}
	var min_h := INF
	var min_name := ""
	var max_h := 0.0
	var max_name := ""

	for bid in view.blocks.keys():
		var b: Dictionary = view.blocks[bid]
		if int(b.get("floor", 0)) != view.current_floor or bool(b.get("exclude_from_footprint", false)):
			continue
		var bkey := String(b["b_name"])
		if bkey in ["lift_in", "lift_out"]:
			continue
		var h := db.get_building_height_m(bkey)
		var bdisp := db.get_building_display_name(bkey, String(b["title"]))
		unique_b[bkey] = {"h": h, "name": bdisp, "col": b["color"]}
		if h < min_h:
			min_h = h
			min_name = bdisp
		if h > max_h:
			max_h = h
			max_name = bdisp

	if unique_b.is_empty():
		view.draw_string(font, prect.position + Vector2(14, 120), i18n.t("grid_elev_empty"), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 28, 12, Color(0.7, 0.75, 0.8, 0.7))
		return

	var walls_needed := int(ceilf((max_h + 2.0) / 4.0))
	var ceil_m := walls_needed * 4
	view.draw_string(font, prect.position + Vector2(12, 42), i18n.tf("grid_elev_lowest", [min_name, int(min_h)]), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 24, 11, Color.LIGHT_SKY_BLUE)
	view.draw_string(font, prect.position + Vector2(12, 58), i18n.tf("grid_elev_highest", [max_name, int(max_h)]), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 24, 11, Color.GOLD)
	view.draw_string(font, prect.position + Vector2(12, 74), i18n.tf("grid_elev_clearance", [ceil_m, walls_needed]), HORIZONTAL_ALIGNMENT_LEFT, panel_w - 24, 11, Color.SPRING_GREEN)

	var chart_top := prect.position.y + 88.0
	var chart_bot := prect.end.y - 22.0
	var chart_h := chart_bot - chart_top
	var max_scale_m := maxf(float(ceil_m), 16.0)

	var m_step := 8
	while m_step <= int(max_scale_m):
		var ly := chart_bot - (float(m_step) / max_scale_m) * chart_h
		view.draw_line(Vector2(prect.position.x + 34, ly), Vector2(prect.end.x - 12, ly), Color(1, 1, 1, 0.14), 1.0)
		view.draw_string(font, Vector2(prect.position.x + 8, ly + 4), "%dm" % m_step, HORIZONTAL_ALIGNMENT_LEFT, 26, 9, Color(0.7, 0.75, 0.85))
		m_step += 8

	var ceil_y := chart_bot - (float(ceil_m) / max_scale_m) * chart_h
	view.draw_dashed_line(Vector2(prect.position.x + 34, ceil_y), Vector2(prect.end.x - 12, ceil_y), Color.SPRING_GREEN, 1.5, 5.0)
	view.draw_line(Vector2(prect.position.x + 34, chart_bot), Vector2(prect.end.x - 12, chart_bot), Color.WHITE, 1.5)

	var bkeys := unique_b.keys()
	var n_bars := bkeys.size()
	var avail_w := panel_w - 54.0
	var bar_w := clampf(avail_w / float(maxi(1, n_bars)) - 6.0, 12.0, 42.0)

	for i in range(n_bars):
		var item: Dictionary = unique_b[bkeys[i]]
		var bh := (float(item["h"]) / max_scale_m) * chart_h
		var bx := prect.position.x + 40.0 + float(i) * (bar_w + 6.0)
		var brect := Rect2(Vector2(bx, chart_bot - bh), Vector2(bar_w, bh))
		var bcol: Color = item["col"]
		view.draw_rect(brect, bcol.lightened(0.15), true)
		view.draw_rect(brect, Color.WHITE, false, 1.0)
		view.draw_string(font, Vector2(bx, chart_bot - bh - 3), "%dm" % int(item["h"]), HORIZONTAL_ALIGNMENT_CENTER, bar_w, 9, Color.WHITE)
		view.draw_string(font, Vector2(bx, chart_bot + 12), String(item["name"]).left(5), HORIZONTAL_ALIGNMENT_CENTER, bar_w + 4, 9, Color(0.85, 0.9, 1.0))

func get_port_screen_pos(rect: Rect2, rot: int, is_input: bool) -> Vector2:
	return get_multi_port_screen_pos(rect, rot, is_input, 0, 1)

func get_multi_port_screen_pos(rect: Rect2, rot: int, is_input: bool, port_idx: int, total_ports: int) -> Vector2:
	var dir := (rot + (2 if is_input else 0)) % 4
	var t := float(port_idx + 1) / float(maxi(1, total_ports) + 1)
	return _get_wall_point(rect, dir, t)
