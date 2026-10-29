class_name GridBeltBuilder
extends RefCounted

# Satisfactory exact dimensions in Foundation units (1 Foundation = 8m)
const SNAP_1M_F := 0.125        # 1m grid snap (1/8 of a foundation)
const BELT_WIDTH_F := 0.25      # 2m physical belt width (4 belts per foundation)
const LIFT_SIZE_F := Vector2(0.25, 0.25) # 2m x 2m physical Conveyor Lift footprint
const TURN_RADIUS_F := 0.25     # 2m minimum 90-degree turning radius
const PORT_STUB_F := 0.25       # 2m straight lead-out / lead-in at machine ports
const PORT_SNAP_DIST_F := 0.42  # Snap radius to machine/splitter/lift ports

var TIER_COLORS := {
	1: Color.html("#B8C2CC"), # Mk.1 (60/m)   - Iron Plate
	2: Color.html("#5CC8FF"), # Mk.2 (120/m)  - Reinforced Iron Plate
	3: Color.html("#E87846"), # Mk.3 (270/m)  - Steel Beam
	4: Color.html("#FAD457"), # Mk.4 (480/m)  - Encased Industrial Beam
	5: Color.html("#88FFEE"), # Mk.5 (780/m)  - Alclad Aluminum Sheet
	6: Color.html("#FF66EE"), # Mk.6 (1200/m) - Ficsite Trigon / Time Crystal
	7: Color.html("#FF3333")  # Overload (>1200/m)
}

var view: GridPlannerView
var db: AppDB
var settings: AppSettings
var i18n: AppI18n

var belt_build_mode: String = "straight"
var manual_pole_dir: int = -1
var belt_id_counter: int = 1

var active_belt: Dictionary = {}
var pending_lift: Dictionary = {} # {pos_f: Vector2, start_floor: int, in_rot: int, out_rot: int}
var hovered_port: Dictionary = {}
var hovered_belt_id: String = ""
var _routed_pairs_cache: Dictionary = {}

func _init(p_view: GridPlannerView, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	view = p_view
	db = p_db
	settings = p_settings
	i18n = p_i18n

func get_active_belts_list() -> Array:
	if view.main_ctrl == null or not is_instance_valid(view.main_ctrl.active_graph):
		return []
	var gid: String = view.main_ctrl.active_graph.get_meta("graph_id", "world")
	if not view.saved_belts.has(gid):
		view.saved_belts[gid] = []
	return view.saved_belts[gid]

func snap_1m(pos_f: Vector2) -> Vector2:
	return Vector2(snappedf(pos_f.x, SNAP_1M_F), snappedf(pos_f.y, SNAP_1M_F))

func toggle_build_mode() -> void:
	belt_build_mode = "curve" if belt_build_mode == "straight" else "straight"
	view._update_belt_mode_button()
	view.queue_redraw()

func rotate_pole_direction() -> void:
	if manual_pole_dir == -1:
		manual_pole_dir = 0
	else:
		manual_pole_dir = (manual_pole_dir + 1) % 4
	view.queue_redraw()

func cancel_active_belt() -> void:
	active_belt.clear()
	manual_pole_dir = -1
	view.queue_redraw()

func cancel_pending_lift() -> void:
	pending_lift.clear()
	view.queue_redraw()

func remove_belts_for_block(bid: String) -> void:
	var list := get_active_belts_list()
	for i in range(list.size() - 1, -1, -1):
		var b: Dictionary = list[i]
		if String(b.get("from_id", "")) == bid or String(b.get("to_id", "")) == bid:
			list.remove_at(i)

func get_belt_tier_visuals(rate: float, item_key: String = "") -> Dictionary:
	if rate <= 0.0001:
		return {"tier": 1, "arrows": 1, "color": Color(0.65, 0.72, 0.80), "label": "Mk.1", "over": false}
	if item_key != "" and db.is_item_fluid(item_key):
		if rate <= 300.01:
			return {"tier": 1, "arrows": 1, "color": Color.html("#E87846"), "label": "Pipe Mk.1", "over": false}
		elif rate <= 600.01:
			return {"tier": 2, "arrows": 2, "color": Color.html("#88FFEE"), "label": "Pipe Mk.2", "over": false}
		return {"tier": 3, "arrows": 3, "color": TIER_COLORS[7], "label": "OVER", "over": true}

	var limits := [60.0, 120.0, 270.0, 480.0, 780.0, 1200.0]
	for idx in range(limits.size()):
		if rate <= limits[idx] + 0.01:
			var t_num := idx + 1
			return {
				"tier": t_num,
				"arrows": t_num,
				"color": TIER_COLORS[t_num],
				"label": "Mk.%d" % t_num,
				"over": false
			}
	return {"tier": 7, "arrows": 6, "color": TIER_COLORS[7], "label": "OVER", "over": true}

func _is_logistics_node(b_name: String) -> bool:
	return b_name in ["splitter", "merger", "lift_in", "lift_out"]

func _get_block_port_supply(bid: String, port_idx: int) -> Dictionary:
	if not view.blocks.has(bid):
		return {"rate": 0.0, "item": ""}
	var b: Dictionary = view.blocks[bid]
	var b_name := String(b.get("b_name", ""))
	if _is_logistics_node(b_name):
		return {"rate": 0.0, "item": String(b.get("main_item", ""))}

	var g = view.main_ctrl.active_graph if view.main_ctrl != null else null
	var n_name := String(b.get("node_name", ""))
	if is_instance_valid(g) and n_name != "":
		var g_node := g.get_node_or_null(NodePath(n_name)) as GraphNode
		if is_instance_valid(g_node):
			var total_instances := 0
			for other_id in view.blocks.keys():
				if String(view.blocks[other_id].get("node_name", "")) == n_name:
					total_instances += 1
			total_instances = maxi(1, total_instances)
			var out_r = view.main_ctrl.solver.get_node_output_rate(g_node, port_idx) / float(total_instances)
			var out_it = view.main_ctrl.solver.get_node_output_item(g_node, port_idx)
			if out_it == "":
				out_it = String(b.get("main_item", ""))
			return {"rate": out_r, "item": out_it}

	var sum_r := 0.0
	var it := String(b.get("main_item", ""))
	for wl in view.wire_links:
		if String(wl["from_id"]) == bid:
			sum_r += float(wl.get("rate", 0.0))
			if it == "" and String(wl.get("item", "")) != "":
				it = String(wl["item"])
	return {"rate": sum_r, "item": it}

func _get_block_port_demand(bid: String, port_idx: int) -> float:
	if not view.blocks.has(bid):
		return 0.0
	var b: Dictionary = view.blocks[bid]
	var b_name := String(b.get("b_name", ""))
	if _is_logistics_node(b_name):
		return 0.0

	var g = view.main_ctrl.active_graph if view.main_ctrl != null else null
	var n_name := String(b.get("node_name", ""))
	if is_instance_valid(g) and n_name != "":
		var g_node := g.get_node_or_null(NodePath(n_name)) as GraphNode
		if is_instance_valid(g_node):
			var total_instances := 0
			for other_id in view.blocks.keys():
				if String(view.blocks[other_id].get("node_name", "")) == n_name:
					total_instances += 1
			total_instances = maxi(1, total_instances)
			return view.main_ctrl.solver.get_node_input_demand(g, g_node, port_idx) / float(total_instances)

	var sum_d := 0.0
	for wl in view.wire_links:
		if String(wl["to_id"]) == bid:
			sum_d += float(wl.get("rate", 0.0))
	return sum_d

# Multi-floor solver: propagates demand and supply across belts, Mergers, Splitters, and Conveyor Lifts across all floors
func solve_physical_belt_network(_cur_floor: int = 0) -> void:
	var list := get_active_belts_list()
	_routed_pairs_cache.clear()
	if list.is_empty():
		return

	var valid_belts: Array[Dictionary] = []
	var out_belts_by_block: Dictionary = {}
	var in_belts_by_block: Dictionary = {}
	var adj: Dictionary = {}

	for belt in list:
		var f_id := String(belt.get("from_id", ""))
		var t_id := String(belt.get("to_id", ""))
		if not view.blocks.has(f_id) or not view.blocks.has(t_id):
			continue
		valid_belts.append(belt)
		if not out_belts_by_block.has(f_id):
			out_belts_by_block[f_id] = []
		out_belts_by_block[f_id].append(belt)
		if not in_belts_by_block.has(t_id):
			in_belts_by_block[t_id] = []
		in_belts_by_block[t_id].append(belt)

		if not adj.has(f_id):
			adj[f_id] = []
		if not (t_id in adj[f_id]):
			adj[f_id].append(t_id)

	# Include inter-floor Lift links (lift_in -> lift_out) in adjacency graph
	for bid in view.blocks.keys():
		var blk: Dictionary = view.blocks[bid]
		if String(blk.get("b_name", "")) == "lift_in":
			var p_id := String(blk.get("partner_id", ""))
			if p_id != "" and view.blocks.has(p_id):
				if not adj.has(bid):
					adj[bid] = []
				if not (p_id in adj[bid]):
					adj[bid].append(p_id)

	# 1. Build reachability cache across all floors (hides schematic wires & lift icons when physically routed)
	for start_id in adj.keys():
		var visited: Dictionary = {start_id: true}
		var queue: Array[String] = [start_id]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			for nxt in adj.get(cur, []):
				if not visited.has(nxt):
					visited[nxt] = true
					_routed_pairs_cache["%s->%s" % [start_id, nxt]] = true
					var nxt_b_name := String(view.blocks[nxt].get("b_name", ""))
					if _is_logistics_node(nxt_b_name):
						queue.append(nxt)

	# 2. Backward pass: propagate downstream machine demands through Splitters, Mergers, and Lifts
	var belt_demand: Dictionary = {}
	for belt in valid_belts:
		var b_id := String(belt["id"])
		var t_id := String(belt["to_id"])
		var t_blk: Dictionary = view.blocks[t_id]
		var tb_name := String(t_blk.get("b_name", ""))
		if not _is_logistics_node(tb_name):
			belt_demand[b_id] = _get_block_port_demand(t_id, int(belt.get("to_port", 0)))
		else:
			belt_demand[b_id] = 0.0

	for _pass in range(16):
		for bid in view.blocks.keys():
			var blk: Dictionary = view.blocks[bid]
			var b_name := String(blk.get("b_name", ""))
			if not _is_logistics_node(b_name):
				continue
			if b_name == "lift_in":
				var p_id := String(blk.get("partner_id", ""))
				var in_b: Array = in_belts_by_block.get(bid, [])
				var out_b: Array = out_belts_by_block.get(p_id, [])
				if in_b.is_empty():
					continue
				var lift_dem := 0.0
				for ob in out_b:
					lift_dem += float(belt_demand.get(String(ob["id"]), 0.0))
				var share := lift_dem / float(in_b.size())
				for ib in in_b:
					belt_demand[String(ib["id"])] = share
			elif b_name in ["splitter", "merger"]:
				var in_b: Array = in_belts_by_block.get(bid, [])
				var out_b: Array = out_belts_by_block.get(bid, [])
				if in_b.is_empty():
					continue
				var total_down_dem := 0.0
				for ob in out_b:
					total_down_dem += float(belt_demand.get(String(ob["id"]), 0.0))
				var share_dem := total_down_dem / float(in_b.size())
				for ib in in_b:
					belt_demand[String(ib["id"])] = share_dem

	# 3. Forward pass: propagate supply from Producer Machines through Mergers, Splitters, and Lifts
	for belt in valid_belts:
		var f_id := String(belt["from_id"])
		var f_blk: Dictionary = view.blocks[f_id]
		var fb_name := String(f_blk.get("b_name", ""))
		if not _is_logistics_node(fb_name):
			var sup := _get_block_port_supply(f_id, int(belt.get("from_port", 0)))
			var out_list_same_port: Array = []
			for ob in out_belts_by_block.get(f_id, []):
				if int(ob.get("from_port", 0)) == int(belt.get("from_port", 0)):
					out_list_same_port.append(ob)
			var div := float(maxi(1, out_list_same_port.size()))
			belt["rate"] = float(sup["rate"]) / div
			if String(sup["item"]) != "":
				belt["item"] = String(sup["item"])

	for _pass in range(16):
		for bid in view.blocks.keys():
			var blk: Dictionary = view.blocks[bid]
			var b_name := String(blk.get("b_name", ""))
			if not _is_logistics_node(b_name):
				continue

			if b_name == "lift_in":
				var p_id := String(blk.get("partner_id", ""))
				if p_id == "" or not view.blocks.has(p_id):
					continue
				var partner_blk: Dictionary = view.blocks[p_id]
				var in_b: Array = in_belts_by_block.get(bid, [])
				var out_b: Array = out_belts_by_block.get(p_id, [])
				var lift_flow := 0.0
				var lift_item := ""
				for ib in in_b:
					lift_flow += float(ib.get("rate", 0.0))
					if lift_item == "" and String(ib.get("item", "")) != "":
						lift_item = String(ib["item"])
				if lift_item != "":
					blk["main_item"] = lift_item
					partner_blk["main_item"] = lift_item
					var pal := db.get_item_palette(lift_item)
					blk["color"] = pal["header"]
					blk["border_color"] = pal["border"]
					partner_blk["color"] = pal["header"]
					partner_blk["border_color"] = pal["border"]
				if not out_b.is_empty():
					var per_out := lift_flow / float(out_b.size())
					for ob in out_b:
						ob["rate"] = per_out
						if lift_item != "":
							ob["item"] = lift_item
				continue

			if b_name == "lift_out":
				continue

			var in_b: Array = in_belts_by_block.get(bid, [])
			var out_b: Array = out_belts_by_block.get(bid, [])
			var total_in_flow := 0.0
			var detected_item := ""

			for ib in in_b:
				total_in_flow += float(ib.get("rate", 0.0))
				if detected_item == "" and String(ib.get("item", "")) != "":
					detected_item = String(ib["item"])

			if detected_item != "":
				blk["main_item"] = detected_item
				var pal := db.get_item_palette(detected_item)
				blk["color"] = pal["header"]
				blk["border_color"] = pal["border"]

			if out_b.is_empty():
				continue

			if b_name == "merger":
				var per_out := total_in_flow / float(out_b.size())
				for ob in out_b:
					ob["rate"] = per_out
					if detected_item != "":
						ob["item"] = detected_item
			elif b_name == "splitter":
				var demanded_outs: Array[Dictionary] = []
				var open_outs: Array[Dictionary] = []
				var sum_known_demand := 0.0

				for ob in out_b:
					if detected_item != "":
						ob["item"] = detected_item
					var d := float(belt_demand.get(String(ob["id"]), 0.0))
					if d > 0.0001:
						demanded_outs.append(ob)
						sum_known_demand += d
					else:
						open_outs.append(ob)

				if demanded_outs.is_empty():
					var even_flow := total_in_flow / float(out_b.size())
					for ob in out_b:
						ob["rate"] = even_flow
				elif open_outs.is_empty():
					for ob in demanded_outs:
						var d := float(belt_demand.get(String(ob["id"]), 0.0))
						ob["rate"] = total_in_flow * (d / sum_known_demand)
				else:
					if total_in_flow <= sum_known_demand + 0.0001:
						for ob in demanded_outs:
							var d := float(belt_demand.get(String(ob["id"]), 0.0))
							ob["rate"] = total_in_flow * (d / sum_known_demand)
						for ob in open_outs:
							ob["rate"] = 0.0
					else:
						for ob in demanded_outs:
							ob["rate"] = float(belt_demand.get(String(ob["id"]), 0.0))
						var rem_flow := maxf(0.0, total_in_flow - sum_known_demand)
						var per_open := rem_flow / float(open_outs.size())
						for ob in open_outs:
							ob["rate"] = per_open

func is_wire_link_routed(wl: Dictionary, _floor_idx: int) -> bool:
	var f_id := String(wl.get("from_id", ""))
	var t_id := String(wl.get("to_id", ""))
	if _routed_pairs_cache.has("%s->%s" % [f_id, t_id]):
		return true

	# Hide schematic wire or automatic inter-floor lift icon as soon as both machines have physical belts attached
	var f_has_out := false
	var t_has_in := false
	for belt in get_active_belts_list():
		var bf := String(belt.get("from_id", ""))
		var bt := String(belt.get("to_id", ""))
		if bf == f_id and bt == t_id:
			return true
		if bf == f_id:
			f_has_out = true
		if bt == t_id:
			t_has_in = true
	return f_has_out and t_has_in

# ==========================================
# COLLISION DETECTION FOR BELTS & LIFTS
# ==========================================
func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	if Geometry2D.segment_intersects_segment(a, b, tl, tr) != null:
		return true
	if Geometry2D.segment_intersects_segment(a, b, tr, br) != null:
		return true
	if Geometry2D.segment_intersects_segment(a, b, br, bl) != null:
		return true
	if Geometry2D.segment_intersects_segment(a, b, bl, tl) != null:
		return true
	return false

func is_belt_path_colliding(world_pts: PackedVector2Array, floor_idx: int, ignore_from_id: String, ignore_to_id: String, ignore_belt_id: String = "") -> bool:
	if world_pts.size() < 2:
		return false

	# 1. Check against all machine/splitter/merger/lift blocks on this floor
	for bid in view.blocks.keys():
		var ks := String(bid)
		var b: Dictionary = view.blocks[ks]
		var b_fl := int(b.get("floor", 0))
		var is_on_floor := (b_fl == floor_idx)

		# Also check if a multi-floor Lift shaft passes through this floor!
		if not is_on_floor and String(b.get("b_name", "")) == "lift_in":
			var t_fl := int(b.get("target_floor", b_fl))
			if floor_idx >= mini(b_fl, t_fl) and floor_idx <= maxi(b_fl, t_fl):
				is_on_floor = true

		if not is_on_floor:
			continue

		var rect_f := Rect2(b["pos_f"], view._get_effective_size_f(b)).grow(-0.04)
		for i in range(world_pts.size() - 1):
			# Allow first and last stub segments to exit/enter the connected source/destination block
			if (ks == ignore_from_id and i <= 1) or (ks == ignore_to_id and i >= world_pts.size() - 3):
				continue
			if _segment_intersects_rect(world_pts[i], world_pts[i + 1], rect_f):
				return true

	# 2. Check against other physical belts on the same floor
	var list := get_active_belts_list()
	for other_b in list:
		if int(other_b.get("floor", 0)) != floor_idx:
			continue
		var ob_id := String(other_b.get("id", ""))
		if ob_id == ignore_belt_id:
			continue
		var other_pts := build_full_belt_world_points(other_b)
		if other_pts.size() < 2:
			continue
		var shares_endpoint := (
			String(other_b.get("from_id", "")) in [ignore_from_id, ignore_to_id]
			or String(other_b.get("to_id", "")) in [ignore_from_id, ignore_to_id]
		)
		for i in range(world_pts.size() - 1):
			var a1 := world_pts[i]
			var a2 := world_pts[i + 1]
			for j in range(other_pts.size() - 1):
				if shares_endpoint and ((i == 0 and j == 0) or (i == world_pts.size() - 2 and j == other_pts.size() - 2)):
					continue
				var b1 := other_pts[j]
				var b2 := other_pts[j + 1]
				var inter = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
				if inter != null:
					return true
	return false

func is_lift_shaft_colliding(pos_f: Vector2, floor_a: int, floor_b: int) -> bool:
	var min_fl := mini(floor_a, floor_b)
	var max_fl := maxi(floor_a, floor_b)
	var lift_rect := Rect2(pos_f, LIFT_SIZE_F).grow(-0.02)

	# 1. Check blocks across all floors between floor_a and floor_b (inclusive)
	for bid in view.blocks.keys():
		var b: Dictionary = view.blocks[bid]
		var b_fl := int(b.get("floor", 0))
		var b_name := String(b.get("b_name", ""))
		var overlaps_floor := (b_fl >= min_fl and b_fl <= max_fl)
		if not overlaps_floor and b_name == "lift_in":
			var other_min := mini(b_fl, int(b.get("target_floor", b_fl)))
			var other_max := maxi(b_fl, int(b.get("target_floor", b_fl)))
			overlaps_floor = (maxi(min_fl, other_min) <= mini(max_fl, other_max))
		if not overlaps_floor:
			continue
		var b_rect := Rect2(b["pos_f"], view._get_effective_size_f(b)).grow(-0.02)
		if lift_rect.intersects(b_rect):
			return true

	# 2. Check belts on all floors in range [min_fl .. max_fl]
	for belt in get_active_belts_list():
		var b_fl := int(belt.get("floor", 0))
		if b_fl < min_fl or b_fl > max_fl:
			continue
		var pts := build_full_belt_world_points(belt)
		for i in range(pts.size() - 1):
			if _segment_intersects_rect(pts[i], pts[i + 1], lift_rect):
				return true

	return false

func refresh_attached_belt_endpoints() -> void:
	var list := get_active_belts_list()
	var step_px := GridPlannerView.PX_PER_FOUNDATION * view.cam_zoom
	for belt in list:
		var f_id := String(belt.get("from_id", ""))
		var t_id := String(belt.get("to_id", ""))
		if view.blocks.has(f_id):
			var sb: Dictionary = view.blocks[f_id]
			var s_rect := Rect2(view._world_f_to_screen(sb["pos_f"]), view._get_effective_size_f(sb) * step_px)
			var s_info := view.renderer.get_block_port_info(sb, s_rect, false, int(belt.get("from_port", 0)))
			belt["from_pos_f"] = view._screen_to_world_f(s_info["pos"])
			belt["from_side"] = int(s_info["side"])
			belt["floor"] = int(sb.get("floor", 0))
		if view.blocks.has(t_id):
			var db_blk: Dictionary = view.blocks[t_id]
			var d_rect := Rect2(view._world_f_to_screen(db_blk["pos_f"]), view._get_effective_size_f(db_blk) * step_px)
			var d_info := view.renderer.get_block_port_info(db_blk, d_rect, true, int(belt.get("to_port", 0)))
			belt["to_pos_f"] = view._screen_to_world_f(d_info["pos"])
			belt["to_side"] = int(d_info["side"])

func pick_port_at(world_f: Vector2) -> Dictionary:
	var step_px := GridPlannerView.PX_PER_FOUNDATION * view.cam_zoom
	var best_port := {}
	var best_dist := PORT_SNAP_DIST_F

	for bid in view.blocks.keys():
		var b: Dictionary = view.blocks[bid]
		if int(b.get("floor", 0)) != view.current_floor:
			continue
		var rect_s := Rect2(view._world_f_to_screen(b["pos_f"]), view._get_effective_size_f(b) * step_px)
		var b_name := String(b.get("b_name", ""))
		var in_cnt := 1 if b_name == "splitter" else (3 if b_name == "merger" else int(b.get("in_ports", 0)))
		var out_cnt := 3 if b_name == "splitter" else (1 if b_name == "merger" else int(b.get("out_ports", 0)))

		for p_o in range(out_cnt):
			var info := view.renderer.get_block_port_info(b, rect_s, false, p_o)
			var pf := view._screen_to_world_f(info["pos"])
			var d := world_f.distance_to(pf)
			if d < best_dist:
				best_dist = d
				best_port = {
					"block_id": String(bid),
					"is_input": false,
					"port_idx": p_o,
					"pos_f": pf,
					"side": int(info["side"])
				}

		for p_i in range(in_cnt):
			var info := view.renderer.get_block_port_info(b, rect_s, true, p_i)
			var pf := view._screen_to_world_f(info["pos"])
			var d := world_f.distance_to(pf)
			if d < best_dist:
				best_dist = d
				best_port = {
					"block_id": String(bid),
					"is_input": true,
					"port_idx": p_i,
					"pos_f": pf,
					"side": int(info["side"])
				}

	return best_port

func pick_belt_at(world_f: Vector2) -> String:
	var list := get_active_belts_list()
	var hit_dist_f := BELT_WIDTH_F * 0.75
	for i in range(list.size() - 1, -1, -1):
		var belt: Dictionary = list[i]
		if int(belt.get("floor", 0)) != view.current_floor:
			continue
		var pts := build_full_belt_world_points(belt)
		for j in range(pts.size() - 1):
			var closest := Geometry2D.get_closest_point_to_segment(world_f, pts[j], pts[j + 1])
			if closest.distance_to(world_f) <= hit_dist_f:
				return String(belt.get("id", ""))
	return ""

func handle_belt_tool_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var wf := view._screen_to_world_f(event.position)
		hovered_port = pick_port_at(wf)
		if active_belt.is_empty():
			hovered_belt_id = pick_belt_at(wf) if hovered_port.is_empty() else ""
		else:
			hovered_belt_id = ""
		view.queue_redraw()
		return false

	if event is InputEventMouseButton and event.pressed:
		var wf := view._screen_to_world_f(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			var port := pick_port_at(wf)
			if active_belt.is_empty():
				if not port.is_empty():
					var b: Dictionary = view.blocks[port["block_id"]]
					var sup := _get_block_port_supply(String(port["block_id"]), int(port["port_idx"]))
					active_belt = {
						"start_block_id": port["block_id"],
						"start_is_input": bool(port["is_input"]),
						"start_port": int(port["port_idx"]),
						"start_pos_f": port["pos_f"],
						"start_side": int(port["side"]),
						"item": String(sup["item"]) if String(sup["item"]) != "" else String(b.get("main_item", "")),
						"rate": float(sup["rate"]),
						"waypoints": []
					}
					manual_pole_dir = -1
					view.queue_redraw()
					return true
			else:
				if not port.is_empty() and port["block_id"] != active_belt["start_block_id"] and bool(port["is_input"]) != bool(active_belt["start_is_input"]):
					_finalize_active_belt(port)
					return true
				var pole_pos := snap_1m(wf)
				var pole_dir := _infer_pole_dir(pole_pos)
				var wps: Array = active_belt["waypoints"]
				wps.append({"pos_f": pole_pos, "dir": pole_dir})
				manual_pole_dir = -1
				view.queue_redraw()
				return true

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not active_belt.is_empty():
				var wps: Array = active_belt["waypoints"]
				if not wps.is_empty():
					wps.pop_back()
				else:
					active_belt.clear()
				manual_pole_dir = -1
				view.queue_redraw()
				return true
			else:
				var hit_belt := pick_belt_at(wf)
				if hit_belt != "":
					_delete_belt_by_id(hit_belt)
					return true

	return false

func _infer_pole_dir(target_pos_f: Vector2) -> int:
	if manual_pole_dir != -1:
		return manual_pole_dir
	var prev_pos: Vector2 = active_belt["start_pos_f"]
	var wps: Array = active_belt.get("waypoints", [])
	if not wps.is_empty():
		prev_pos = wps[wps.size() - 1]["pos_f"]
	var d := target_pos_f - prev_pos
	if absf(d.x) >= absf(d.y):
		return 0 if d.x >= 0.0 else 2
	return 1 if d.y >= 0.0 else 3

func _finalize_active_belt(end_port: Dictionary) -> void:
	var start_is_in := bool(active_belt["start_is_input"])
	var from_id: String = String(end_port["block_id"] if start_is_in else active_belt["start_block_id"])
	var to_id: String = String(active_belt["start_block_id"] if start_is_in else end_port["block_id"])
	var from_port: int = int(end_port["port_idx"] if start_is_in else active_belt["start_port"])
	var to_port: int = int(active_belt["start_port"] if start_is_in else end_port["port_idx"])
	var from_pos: Vector2 = end_port["pos_f"] if start_is_in else active_belt["start_pos_f"]
	var to_pos: Vector2 = active_belt["start_pos_f"] if start_is_in else end_port["pos_f"]
	var from_side: int = int(end_port["side"] if start_is_in else active_belt["start_side"])
	var to_side: int = int(active_belt["start_side"] if start_is_in else end_port["side"])

	var wps: Array = (active_belt["waypoints"] as Array).duplicate(true)
	if start_is_in:
		wps.reverse()
		for wp in wps:
			wp["dir"] = (int(wp["dir"]) + 2) % 4

	var candidate_belt := {
		"from_pos_f": from_pos,
		"from_side": from_side,
		"to_pos_f": to_pos,
		"to_side": to_side,
		"mode": belt_build_mode,
		"waypoints": wps
	}
	var candidate_pts := build_full_belt_world_points(candidate_belt)
	# Block finalizing belt if it collides with machines, lifts, or other belts
	if is_belt_path_colliding(candidate_pts, view.current_floor, from_id, to_id):
		return

	var sup := _get_block_port_supply(from_id, from_port)
	var item_key := String(sup["item"])
	var flow_rate := float(sup["rate"])
	if item_key == "" and view.blocks.has(to_id):
		item_key = String(view.blocks[to_id].get("main_item", ""))

	var list := get_active_belts_list()
	for i in range(list.size() - 1, -1, -1):
		var old_b: Dictionary = list[i]
		if String(old_b.get("from_id", "")) == from_id and int(old_b.get("from_port", 0)) == from_port and String(old_b.get("to_id", "")) == to_id and int(old_b.get("to_port", 0)) == to_port:
			list.remove_at(i)

	belt_id_counter += 1
	list.append({
		"id": "belt_%d_%d" % [Time.get_ticks_msec(), belt_id_counter],
		"floor": view.current_floor,
		"from_id": from_id,
		"from_port": from_port,
		"from_pos_f": from_pos,
		"from_side": from_side,
		"to_id": to_id,
		"to_port": to_port,
		"to_pos_f": to_pos,
		"to_side": to_side,
		"item": item_key,
		"rate": flow_rate,
		"mode": belt_build_mode,
		"waypoints": wps
	})

	active_belt.clear()
	manual_pole_dir = -1
	solve_physical_belt_network(view.current_floor)
	view.queue_redraw()
	if view.main_ctrl.autosave_mgr != null:
		view.main_ctrl.autosave_mgr.notify_interaction()

func _delete_belt_by_id(belt_id: String) -> void:
	var list := get_active_belts_list()
	for i in range(list.size() - 1, -1, -1):
		if String(list[i].get("id", "")) == belt_id:
			list.remove_at(i)
			hovered_belt_id = ""
			solve_physical_belt_network(view.current_floor)
			view.queue_redraw()
			if view.main_ctrl.autosave_mgr != null:
				view.main_ctrl.autosave_mgr.notify_interaction()
			return

func _side_vec(side: int) -> Vector2:
	match side % 4:
		0: return Vector2.RIGHT
		1: return Vector2.DOWN
		2: return Vector2.LEFT
		_: return Vector2.UP

func build_segment_world_points(p1: Vector2, dir1: int, p2: Vector2, dir2: int, mode: String, is_start_port: bool, is_end_port: bool) -> PackedVector2Array:
	var v1 := _side_vec(dir1)
	var v2 := _side_vec(dir2)

	if mode == "curve":
		var pts := PackedVector2Array()
		var dist := p1.distance_to(p2)
		var handle_len := clampf(dist * 0.45, 0.25, 2.5)
		var c1 := p1 + v1 * handle_len
		var c2 := p2 - v2 * handle_len
		var steps := maxi(12, int(dist * 10.0))
		for s in range(steps + 1):
			var t := float(s) / float(steps)
			var omt := 1.0 - t
			var pt := (omt * omt * omt) * p1 + (3.0 * omt * omt * t) * c1 + (3.0 * omt * t * t) * c2 + (t * t * t) * p2
			pts.append(pt)
		return pts

	var stub1 := PORT_STUB_F if is_start_port else 0.0
	var stub2 := PORT_STUB_F if is_end_port else 0.0
	var dist_total := p1.distance_to(p2)
	if dist_total < 0.6:
		stub1 = minf(stub1, dist_total * 0.25)
		stub2 = minf(stub2, dist_total * 0.25)

	var a := p1 + v1 * stub1
	var b := p2 - v2 * stub2

	var corners: Array[Vector2] = [p1]
	if stub1 > 0.001:
		corners.append(a)

	var is_horiz1 := (dir1 % 2 == 0)
	var is_horiz2 := (dir2 % 2 == 0)

	if is_horiz1 != is_horiz2:
		var corner := Vector2(b.x, a.y) if is_horiz1 else Vector2(a.x, b.y)
		corners.append(corner)
	else:
		if is_horiz1:
			var mid_x := snap_1m((a + b) * 0.5).x
			if (b.x - a.x) * v1.x < 0.0:
				var detour_y := a.y + (1.0 if b.y >= a.y else -1.0) * maxf(0.5, absf(b.y - a.y) * 0.5)
				corners.append(Vector2(a.x, detour_y))
				corners.append(Vector2(b.x, detour_y))
			elif absf(a.y - b.y) > 0.01:
				corners.append(Vector2(mid_x, a.y))
				corners.append(Vector2(mid_x, b.y))
		else:
			var mid_y := snap_1m((a + b) * 0.5).y
			if (b.y - a.y) * v1.y < 0.0:
				var detour_x := a.x + (1.0 if b.x >= a.x else -1.0) * maxf(0.5, absf(b.x - a.x) * 0.5)
				corners.append(Vector2(detour_x, a.y))
				corners.append(Vector2(detour_x, b.y))
			elif absf(a.x - b.x) > 0.01:
				corners.append(Vector2(a.x, mid_y))
				corners.append(Vector2(b.x, mid_y))

	if stub2 > 0.001:
		corners.append(b)
	corners.append(p2)

	var clean: Array[Vector2] = []
	for pt in corners:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(pt) > 0.005:
			clean.append(pt)

	var simp: Array[Vector2] = []
	for i in range(clean.size()):
		if i > 0 and i < clean.size() - 1:
			var d_prev := (clean[i] - clean[i - 1]).normalized()
			var d_next := (clean[i + 1] - clean[i]).normalized()
			if d_prev.dot(d_next) > 0.995:
				continue
		simp.append(clean[i])

	return _fillet_polyline_2m_radius(simp)

func _fillet_polyline_2m_radius(poly: Array[Vector2]) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.size() <= 2:
		for p in poly:
			out.append(p)
		return out

	out.append(poly[0])
	for i in range(1, poly.size() - 1):
		var p_prev := poly[i - 1]
		var p_cur := poly[i]
		var p_next := poly[i + 1]

		var v_in := p_cur - p_prev
		var v_out := p_next - p_cur
		var len_in := v_in.length()
		var len_out := v_out.length()
		if len_in < 0.02 or len_out < 0.02:
			out.append(p_cur)
			continue

		var dir_in := v_in / len_in
		var dir_out := v_out / len_out
		var r := minf(TURN_RADIUS_F, minf(len_in * 0.45, len_out * 0.45))
		if r < 0.02 or absf(dir_in.dot(dir_out)) > 0.98:
			out.append(p_cur)
			continue

		var arc_start := p_cur - dir_in * r
		var arc_end := p_cur + dir_out * r
		var arc_steps := 6
		for s in range(arc_steps + 1):
			var t := float(s) / float(arc_steps)
			var omt := 1.0 - t
			var pt := (omt * omt) * arc_start + (2.0 * omt * t) * p_cur + (t * t) * arc_end
			out.append(pt)

	out.append(poly[poly.size() - 1])
	return out

func build_full_belt_world_points(belt: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cur_pos: Vector2 = belt["from_pos_f"]
	var cur_dir: int = int(belt["from_side"])
	var mode := String(belt.get("mode", "straight"))
	var wps: Array = belt.get("waypoints", [])

	for i in range(wps.size()):
		var wp: Dictionary = wps[i]
		var wp_pos: Vector2 = wp["pos_f"]
		var wp_dir: int = int(wp["dir"])
		var seg := build_segment_world_points(cur_pos, cur_dir, wp_pos, wp_dir, mode, i == 0, false)
		for j in range(seg.size()):
			if i > 0 and j == 0:
				continue
			pts.append(seg[j])
		cur_pos = wp_pos
		cur_dir = wp_dir

	var to_pos: Vector2 = belt["to_pos_f"]
	var into_to_dir := (int(belt["to_side"]) + 2) % 4
	var last_seg := build_segment_world_points(cur_pos, cur_dir, to_pos, into_to_dir, mode, wps.is_empty(), true)
	for j in range(last_seg.size()):
		if not wps.is_empty() and j == 0:
			continue
		pts.append(last_seg[j])

	return pts

func draw_physical_belts(font: Font, step_px: float, cur_floor: int, focus_id: String) -> void:
	refresh_attached_belt_endpoints()
	solve_physical_belt_network(cur_floor)
	var list := get_active_belts_list()
	var unit_m := i18n.t("unit_per_min")

	for belt in list:
		if int(belt.get("floor", 0)) != cur_floor:
			continue
		var world_pts := build_full_belt_world_points(belt)
		if world_pts.size() < 2:
			continue

		var f_id := String(belt.get("from_id", ""))
		var t_id := String(belt.get("to_id", ""))
		var item_key := String(belt.get("item", ""))
		var rate := float(belt.get("rate", 0.0))
		var b_id := String(belt.get("id", ""))
		var has_col := is_belt_path_colliding(world_pts, cur_floor, f_id, t_id, b_id)

		var is_hov_belt := (b_id == hovered_belt_id)
		var is_focus_belt := is_hov_belt or (focus_id != "" and (f_id == focus_id or t_id == focus_id))
		var alpha := 1.0
		if view.filter_item_key != "" and item_key != view.filter_item_key:
			alpha = 0.15
		elif focus_id != "" and not is_focus_belt:
			alpha = 0.40

		var item_col := db.get_item_color(item_key) if item_key != "" else Color.html("#7AB0D4")
		_draw_single_belt_track(font, world_pts, belt.get("waypoints", []), item_key, item_col, alpha, is_focus_belt, is_hov_belt or has_col, rate, unit_m, step_px, false, has_col)

	if view.current_tool == GridPlannerView.ToolMode.BELT:
		_draw_belt_tool_overlay(font, step_px)

func _draw_single_belt_track(font: Font, world_pts: PackedVector2Array, waypoints: Array, item_key: String, item_col: Color, alpha: float, is_highlighted: bool, is_hovered: bool, rate: float, unit_m: String, step_px: float, is_preview: bool, is_colliding: bool = false) -> void:
	var screen_pts := PackedVector2Array()
	for wp in world_pts:
		screen_pts.append(view._world_f_to_screen(wp))

	var tier_vis := get_belt_tier_visuals(rate, item_key)
	var num_arrows := int(tier_vis["arrows"])
	var tier_col: Color = tier_vis["color"]
	var is_over := bool(tier_vis["over"])

	var belt_px := maxf(6.0, BELT_WIDTH_F * step_px)
	var border_col := Color.RED if (is_colliding or (is_hovered and view.current_tool == GridPlannerView.ToolMode.BELT) or is_over) else (Color.html("#FAB757") if is_highlighted else Color(0.06, 0.08, 0.11))
	border_col.a = alpha * (0.85 if is_preview else 0.96)

	var rail_col := Color(0.55, 0.12, 0.12, alpha * 0.9) if is_colliding else Color(0.18, 0.22, 0.28, alpha * (0.75 if is_preview else 0.95))
	var inner_col := Color(0.85, 0.15, 0.15, alpha * 0.9) if is_colliding else (item_col.darkened(0.32) if not is_highlighted else item_col.darkened(0.12))
	inner_col.a = alpha * (0.75 if is_preview else 0.94)

	view.draw_polyline(screen_pts, border_col, belt_px + 2.5, true)
	view.draw_polyline(screen_pts, rail_col, belt_px, true)
	view.draw_polyline(screen_pts, inner_col, belt_px * 0.66, true)

	var cluster_spacing_px := maxf(24.0, 0.48 * step_px)
	var accum := cluster_spacing_px * 0.5
	var chev_half := clampf(belt_px * 0.26, 2.5, 7.5)
	var sub_gap := clampf(3.3 * view.cam_zoom, 2.2, 5.2)
	var chev_col := Color.YELLOW if is_colliding else tier_col
	chev_col.a = alpha * 0.98
	var shadow_col := Color(0.03, 0.04, 0.06, alpha * 0.85)
	var line_w := maxf(1.4, 1.8 * view.cam_zoom)

	for i in range(screen_pts.size() - 1):
		var a := screen_pts[i]
		var b := screen_pts[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.5:
			continue
		var dir := (b - a) / seg_len
		var norm := Vector2(-dir.y, dir.x)
		while accum <= seg_len:
			var center_pt := a + dir * accum
			var start_offset := -float(num_arrows - 1) * 0.5 * sub_gap
			for c_idx in range(num_arrows):
				var tip := center_pt + dir * (start_offset + float(c_idx) * sub_gap + chev_half * 0.4)
				var tail_l := tip - dir * chev_half + norm * chev_half
				var tail_r := tip - dir * chev_half - norm * chev_half
				view.draw_line(tail_l, tip, shadow_col, line_w + 1.4, true)
				view.draw_line(tail_r, tip, shadow_col, line_w + 1.4, true)
				view.draw_line(tail_l, tip, chev_col, line_w, true)
				view.draw_line(tail_r, tip, chev_col, line_w, true)
			accum += cluster_spacing_px
		accum -= seg_len

	var pole_r := clampf(0.08 * step_px, 3.5, 8.0)
	for wp in waypoints:
		var wp_s := view._world_f_to_screen(wp["pos_f"])
		view.draw_rect(Rect2(wp_s - Vector2(pole_r, pole_r), Vector2(pole_r * 2.0, pole_r * 2.0)), Color(0.12, 0.15, 0.20, alpha), true)
		view.draw_rect(Rect2(wp_s - Vector2(pole_r, pole_r), Vector2(pole_r * 2.0, pole_r * 2.0)), Color(0.95, 0.68, 0.22, alpha), false, 1.6)

	if is_colliding:
		var mid_pos := screen_pts[screen_pts.size() / 2]
		var warn_txt := i18n.t("grid_belt_collision_warn")
		var tw := font.get_string_size(warn_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
		var b_rect := Rect2(mid_pos - Vector2(tw * 0.5, 10.0), Vector2(tw, 20.0))
		view.draw_rect(b_rect, Color(0.25, 0.04, 0.04, 0.96), true)
		view.draw_rect(b_rect, Color.RED, false, 1.8)
		view.draw_string(font, b_rect.position + Vector2(6.0, 14.0), warn_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.YELLOW)
	elif (view.cam_zoom >= 0.52 or is_highlighted) and rate > 0.001 and alpha > 0.3:
		var mid_idx := screen_pts.size() / 2
		var mid_pos := screen_pts[mid_idx]
		var txt := "%s%s • %s" % [settings.fmt(rate), unit_m, String(tier_vis["label"])]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
		var b_rect := Rect2(mid_pos - Vector2(tw * 0.5, 8.5), Vector2(tw, 17.0))
		view.draw_rect(b_rect, Color(0.05, 0.07, 0.11, 0.92 * alpha), true)
		view.draw_rect(b_rect, tier_col, false, 1.4)
		view.draw_string(font, b_rect.position + Vector2(5.0, 12.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tier_col.lightened(0.15))

func _draw_belt_tool_overlay(font: Font, step_px: float) -> void:
	var guides := _collect_connection_guides(step_px)
	for g in guides:
		var src_s: Vector2 = g["src_screen"]
		var dst_s: Vector2 = g["dst_screen"]
		var src_rect: Rect2 = g["src_rect"]
		var dst_rect: Rect2 = g["dst_rect"]
		var item_col: Color = g["color"]
		var is_routed: bool = bool(g["is_routed"])
		var guide_alpha := 0.32 if is_routed else 0.95

		view.draw_rect(src_rect.grow(3.0), Color(0.2, 0.95, 1.0, 0.75 * guide_alpha), false, 2.5)
		view.draw_rect(dst_rect.grow(4.0), Color(1.0, 0.78, 0.15, 0.90 * guide_alpha), false, 3.0)
		view.draw_rect(dst_rect.grow(1.0), Color(1.0, 0.78, 0.15, 0.12 * guide_alpha), true)

		var guide_col := Color(1.0, 0.84, 0.2, 0.82 * guide_alpha) if not is_routed else Color(0.5, 0.8, 0.6, 0.35)
		view.draw_dashed_line(src_s, dst_s, guide_col, 2.2, 8.0)

		var dist := src_s.distance_to(dst_s)
		if dist > 36.0:
			var dir := (dst_s - src_s) / dist
			var norm := Vector2(-dir.y, dir.x)
			var mid := (src_s + dst_s) * 0.5
			view.draw_line(mid - dir * 8.0 + norm * 6.0, mid + dir * 4.0, guide_col, 2.4, true)
			view.draw_line(mid - dir * 8.0 - norm * 6.0, mid + dir * 4.0, guide_col, 2.4, true)

		var r_pin := clampf(9.0 * view.cam_zoom, 5.5, 14.0)
		view.draw_circle(src_s, r_pin + 3.0, Color(0.15, 0.95, 1.0, 0.28 * guide_alpha))
		view.draw_arc(src_s, r_pin, 0.0, TAU, 18, Color(0.2, 0.95, 1.0, guide_alpha), 2.2)

		view.draw_circle(dst_s, r_pin + 5.0, Color(1.0, 0.75, 0.1, 0.32 * guide_alpha))
		view.draw_arc(dst_s, r_pin + 2.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.2, guide_alpha), 2.5)
		view.draw_arc(dst_s, maxf(3.0, r_pin - 2.5), 0.0, TAU, 16, item_col.lightened(0.3), 2.0)

		if not is_routed or not active_belt.is_empty():
			var from_lbl := i18n.t("grid_belt_from_tag")
			var to_lbl := "%s: %s" % [i18n.t("grid_belt_to_tag"), String(g["label"])]
			_draw_port_guide_badge(font, src_s, int(g["src_side"]), from_lbl, Color(0.2, 0.95, 1.0, guide_alpha))
			_draw_port_guide_badge(font, dst_s, int(g["dst_side"]), to_lbl, Color(1.0, 0.82, 0.2, guide_alpha))

	var cur_wf := snap_1m(view.last_mouse_world_f)
	var cur_dir := _infer_pole_dir(cur_wf) if not active_belt.is_empty() else (manual_pole_dir if manual_pole_dir != -1 else 0)

	if not hovered_port.is_empty():
		var hp_s := view._world_f_to_screen(hovered_port["pos_f"])
		var hp_col := Color.SPRING_GREEN if not bool(hovered_port["is_input"]) else Color.AQUAMARINE
		view.draw_circle(hp_s, clampf(8.5 * view.cam_zoom, 5.0, 14.0), Color(hp_col.r, hp_col.g, hp_col.b, 0.35))
		view.draw_arc(hp_s, clampf(9.0 * view.cam_zoom, 5.5, 15.0), 0.0, TAU, 18, hp_col, 2.2)
	else:
		var cs := view._world_f_to_screen(cur_wf)
		var pr := clampf(0.08 * step_px, 4.0, 9.0)
		view.draw_rect(Rect2(cs - Vector2(pr, pr), Vector2(pr * 2.0, pr * 2.0)), Color(0.95, 0.75, 0.2, 0.35), true)
		view.draw_rect(Rect2(cs - Vector2(pr, pr), Vector2(pr * 2.0, pr * 2.0)), Color.GOLD, false, 2.0)
		var d_vec := _side_vec(cur_dir)
		view.draw_line(cs, cs + d_vec * (pr * 2.6), Color.GOLD, 2.2, true)

	if not active_belt.is_empty():
		var start_is_in := bool(active_belt["start_is_input"])
		var end_pos := cur_wf
		var end_side := (cur_dir + 2) % 4
		var target_bid := ""
		if not hovered_port.is_empty() and hovered_port["block_id"] != active_belt["start_block_id"]:
			end_pos = hovered_port["pos_f"]
			end_side = int(hovered_port["side"])
			target_bid = String(hovered_port["block_id"])

		var f_id := target_bid if start_is_in else String(active_belt["start_block_id"])
		var t_id := String(active_belt["start_block_id"]) if start_is_in else target_bid

		var preview_belt := {
			"from_pos_f": end_pos if start_is_in else active_belt["start_pos_f"],
			"from_side": end_side if start_is_in else int(active_belt["start_side"]),
			"to_pos_f": active_belt["start_pos_f"] if start_is_in else end_pos,
			"to_side": int(active_belt["start_side"]) if start_is_in else end_side,
			"mode": belt_build_mode,
			"waypoints": (active_belt["waypoints"] as Array).duplicate(true)
		}
		if start_is_in:
			preview_belt["waypoints"].reverse()

		var pts := build_full_belt_world_points(preview_belt)
		var has_col := is_belt_path_colliding(pts, view.current_floor, f_id, t_id)
		var item_k := String(active_belt.get("item", ""))
		var prev_rate := float(active_belt.get("rate", 60.0))
		var p_col := db.get_item_color(item_k) if item_k != "" else Color.AQUAMARINE
		_draw_single_belt_track(font, pts, preview_belt["waypoints"], item_k, p_col, 0.9, true, false, prev_rate, i18n.t("unit_per_min"), step_px, true, has_col)

func _collect_connection_guides(step_px: float) -> Array[Dictionary]:
	var out_guides: Array[Dictionary] = []
	var cur_floor := view.current_floor
	var port_assignments := view.renderer._compute_wire_port_assignments(step_px)
	var wire_out_ports: Dictionary = port_assignments["out_ports"]
	var wire_in_ports: Dictionary = port_assignments["in_ports"]

	var filter_block_id := ""
	var filter_is_input := false
	var filter_port_idx := -1
	var has_specific_port := false

	if not active_belt.is_empty():
		filter_block_id = String(active_belt["start_block_id"])
		filter_is_input = bool(active_belt["start_is_input"])
		filter_port_idx = int(active_belt["start_port"])
		has_specific_port = true
	elif not hovered_port.is_empty():
		filter_block_id = String(hovered_port["block_id"])
		filter_is_input = bool(hovered_port["is_input"])
		filter_port_idx = int(hovered_port["port_idx"])
		has_specific_port = true
	elif view.hovered_id != "":
		filter_block_id = view.hovered_id

	if filter_block_id == "":
		return out_guides

	var exact_matches: Array[Dictionary] = []
	var block_matches: Array[Dictionary] = []

	for w_idx in range(view.wire_links.size()):
		var wl: Dictionary = view.wire_links[w_idx]
		var f_id := String(wl["from_id"])
		var t_id := String(wl["to_id"])
		if not view.blocks.has(f_id) or not view.blocks.has(t_id):
			continue
		var sb: Dictionary = view.blocks[f_id]
		var db_blk: Dictionary = view.blocks[t_id]
		if int(sb.get("floor", 0)) != cur_floor or int(db_blk.get("floor", 0)) != cur_floor:
			continue

		var src_port_idx := int(wire_out_ports.get(w_idx, 0))
		var dst_port_idx := int(wire_in_ports.get(w_idx, 0))

		var is_block_match := false
		var is_exact_port_match := false
		if has_specific_port:
			if not filter_is_input and f_id == filter_block_id:
				is_block_match = true
				if src_port_idx == filter_port_idx:
					is_exact_port_match = true
			elif filter_is_input and t_id == filter_block_id:
				is_block_match = true
				if dst_port_idx == filter_port_idx:
					is_exact_port_match = true
		else:
			if f_id == filter_block_id or t_id == filter_block_id:
				is_block_match = true

		if not is_block_match:
			continue

		var s_rect := Rect2(view._world_f_to_screen(sb["pos_f"]), view._get_effective_size_f(sb) * step_px)
		var d_rect := Rect2(view._world_f_to_screen(db_blk["pos_f"]), view._get_effective_size_f(db_blk) * step_px)
		var s_info := view.renderer.get_block_port_info(sb, s_rect, false, src_port_idx)
		var d_info := view.renderer.get_block_port_info(db_blk, d_rect, true, dst_port_idx)

		var src_pos_s: Vector2 = s_info["pos"]
		var src_side: int = int(s_info["side"])
		var dst_pos_s: Vector2 = d_info["pos"]
		var dst_side: int = int(d_info["side"])
		if not active_belt.is_empty():
			if not filter_is_input and f_id == filter_block_id:
				src_pos_s = view._world_f_to_screen(active_belt["start_pos_f"])
				src_side = int(active_belt["start_side"])
			elif filter_is_input and t_id == filter_block_id:
				dst_pos_s = view._world_f_to_screen(active_belt["start_pos_f"])
				dst_side = int(active_belt["start_side"])

		var item_k := String(wl.get("item", ""))
		var item_name := db.get_item_display_name(item_k) if item_k != "" else String(db_blk.get("title", ""))
		var rate_str := "%s%s" % [settings.fmt(float(wl.get("rate", 0.0))), i18n.t("unit_per_min")]
		var entry := {
			"src_screen": src_pos_s,
			"dst_screen": dst_pos_s,
			"src_side": src_side,
			"dst_side": dst_side,
			"src_rect": s_rect,
			"dst_rect": d_rect,
			"color": db.get_item_color(item_k) if item_k != "" else Color.AQUAMARINE,
			"label": "%s (%s)" % [item_name, rate_str],
			"is_routed": is_wire_link_routed(wl, cur_floor)
		}
		if is_exact_port_match:
			exact_matches.append(entry)
		block_matches.append(entry)

	return exact_matches if not exact_matches.is_empty() else block_matches

func _draw_port_guide_badge(font: Font, pin_pos: Vector2, side: int, txt: String, col: Color) -> void:
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
	var th := 18.0
	var offset := Vector2.ZERO
	match side % 4:
		0: offset = Vector2(12.0, -th * 0.5)
		1: offset = Vector2(-tw * 0.5, 12.0)
		2: offset = Vector2(-tw - 12.0, -th * 0.5)
		3: offset = Vector2(-tw * 0.5, -th - 12.0)

	var brect := Rect2(pin_pos + offset, Vector2(tw, th))
	view.draw_rect(brect, Color(0.04, 0.06, 0.10, 0.95), true)
	view.draw_rect(brect, col, false, 1.8)
	view.draw_string(font, brect.position + Vector2(6.0, 13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
