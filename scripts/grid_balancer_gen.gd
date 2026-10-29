class_name GridBalancerGenerator
extends RefCounted

var view: GridPlannerView
var db: AppDB
var i18n: AppI18n

func _init(p_view: GridPlannerView, p_db: AppDB, p_i18n: AppI18n) -> void:
	view = p_view
	db = p_db
	i18n = p_i18n

func _gcd(a: int, b: int) -> int:
	var x := absi(a)
	var y := absi(b)
	while y != 0:
		var t := x % y
		x = y
		y = t
	return maxi(1, x)

func find_balancer_factors(target_n: int) -> Dictionary:
	if target_n <= 1:
		return {"m": 1, "factors": [], "feedback": 0}
	var best_m := 999999
	var best_a := 0
	var best_b := 0
	var p3 := 1
	for b in range(7):
		var p2 := 1
		for a in range(10):
			var m := p2 * p3
			if m >= target_n:
				if m < best_m or (m == best_m and b < best_b):
					best_m = m
					best_a = a
					best_b = b
				break
			p2 *= 2
		p3 *= 3
	var factors: Array[int] = []
	for _i in range(best_a):
		factors.append(2)
	for _i in range(best_b):
		factors.append(3)
	return {"m": best_m, "factors": factors, "feedback": best_m - target_n}

func sync_from_graph(g: GraphEdit) -> void:
	view.blocks.clear()
	view.wire_links.clear()
	if not is_instance_valid(g):
		return

	var gid: String = g.get_meta("graph_id", "world")
	if not view.saved_positions.has(gid):
		view.saved_positions[gid] = {}
	var mem: Dictionary = view.saved_positions[gid]

	var node_to_block_ids: Dictionary = {}
	var cursor_x := 0.0
	var offgrid_left_y := 0.0
	var offgrid_right_y := 0.0

	var graph_nodes: Array[GraphNode] = []
	for ch in g.get_children():
		if is_instance_valid(ch) and not ch.is_queued_for_deletion() and ch is GraphNode and ch.has_meta("node_kind"):
			graph_nodes.append(ch)
	graph_nodes.sort_custom(func(a: GraphNode, b: GraphNode): return a.position_offset.x < b.position_offset.x)

	var all_conns := g.get_connection_list()
	var virtual_splitter_nodes: Dictionary = {}
	if view.auto_generate_splitters:
		for ch in graph_nodes:
			var k := String(ch.get_meta("node_kind"))
			if k in GridPlannerView.SPLITTER_NODE_KINDS or k == "reroute":
				var has_in := false
				var has_out := false
				for c in all_conns:
					if String(c.get("to_node", c.get("to", ""))) == String(ch.name):
						has_in = true
					if String(c.get("from_node", c.get("from", ""))) == String(ch.name):
						has_out = true
				if has_in and has_out:
					virtual_splitter_nodes[String(ch.name)] = ch

	for ch in graph_nodes:
		var kind: String = ch.get_meta("node_kind")
		var n_name := String(ch.name)
		node_to_block_ids[n_name] = []

		if kind == "machine":
			var r_id: String = ch.get_meta("recipe_id")
			if not db.recipes.has(r_id):
				continue
			var data: Dictionary = db.recipes[r_id]
			var is_miner: bool = data.get("is_miner", false)
			var b_key: String = data.get("building_key", "constructor")
			var b_name: String = data.get("building_name", data["category"])
			if data.get("has_mk_tiers", false):
				var mk_lvl := clampi(int(ch.get_meta("miner_mk", 1)), 1, 3)
				b_key = "miner-mk%d" % mk_lvl
				b_name = db.get_building_display_name(b_key, "Miner MK%d" % mk_lvl)
			var main_item: String = data["outputs"][0]["item"] if data["outputs"].size() > 0 else (data["inputs"][0]["item"] if data["inputs"].size() > 0 else "")
			var pal := db.get_item_palette(main_item)
			var dims: Vector2 = db.get_building_footprint_foundations(b_key)
			var count := maxi(1, int(ceilf(float(ch.get_meta("machines")))))
			var in_cnt: int = data["inputs"].size()
			var out_cnt: int = data["outputs"].size()

			if is_miner:
				for idx in range(count):
					var bid := "%s#%d" % [n_name, idx]
					var def_pos := view._snap_vec(Vector2(-5.0, offgrid_left_y))
					offgrid_left_y += dims.y + 1.0
					view._register_block(bid, n_name, "⛏ %s #%d" % [b_name, idx + 1], i18n.t("grid_offgrid_dep"), b_key, main_item, pal["header"], pal["border"], dims, def_pos, mem, true, 0, 0, 1)
					node_to_block_ids[n_name].append(bid)
			elif view.expand_individual_machines:
				for idx in range(count):
					var bid := "%s#%d" % [n_name, idx]
					var def_pos := view._snap_vec(Vector2(cursor_x, idx * (dims.y + 0.75)))
					view._register_block(bid, n_name, "%s #%d" % [b_name, idx + 1], data.get("raw_name", ""), b_key, main_item, pal["header"], pal["border"], dims, def_pos, mem, false, 0, in_cnt, out_cnt)
					node_to_block_ids[n_name].append(bid)
				cursor_x += dims.x + 5.5
			else:
				var bid := "%s#group" % n_name
				var grouped_dims := Vector2(dims.x, dims.y * float(count))
				var def_pos := view._snap_vec(Vector2(cursor_x, 0.0))
				view._register_block(bid, n_name, "%dx %s" % [count, b_name], data.get("raw_name", ""), b_key, main_item, pal["header"], pal["border"], grouped_dims, def_pos, mem, false, 0, in_cnt, out_cnt)
				node_to_block_ids[n_name].append(bid)
				cursor_x += grouped_dims.x + 5.5

		elif kind == "receiver":
			var bid := "%s#0" % n_name
			var item_key: String = ch.get_meta("item", "")
			var pal := db.get_item_palette(item_key)
			var def_pos := view._snap_vec(Vector2(-5.0, offgrid_left_y))
			offgrid_left_y += 2.0
			view._register_block(bid, n_name, i18n.t("grid_rx_short"), i18n.t("grid_offgrid_in"), "receiver", item_key, pal["header"], pal["border"], Vector2(1.0, 1.0), def_pos, mem, true, 0, 0, 1)
			node_to_block_ids[n_name].append(bid)

		elif kind == "transmitter":
			var bid := "%s#0" % n_name
			var item_key: String = ch.get_meta("item", "")
			var pal := db.get_item_palette(item_key)
			var def_pos := view._snap_vec(Vector2(maxf(4.0, cursor_x + 2.0), offgrid_right_y))
			offgrid_right_y += 2.0
			view._register_block(bid, n_name, i18n.t("grid_tx_short"), i18n.t("grid_offgrid_out"), "transmitter", item_key, pal["header"], pal["border"], Vector2(1.0, 1.0), def_pos, mem, true, 0, 1, 0)
			node_to_block_ids[n_name].append(bid)

		elif kind in GridPlannerView.SPLITTER_NODE_KINDS or kind == "reroute":
			if not virtual_splitter_nodes.has(n_name):
				var bid := "%s#0" % n_name
				var item_key: String = ch.get_meta("item", "")
				var pal := db.get_item_palette(item_key)
				var def_pos := view._snap_vec(Vector2(cursor_x, 0.0))
				cursor_x += 2.0
				view._register_block(bid, n_name, i18n.t("grid_sp_short"), "4m x 4m", "splitter", item_key, pal["header"], pal["border"], GridPlannerView.SPLITTER_SIZE_F, def_pos, mem, false, 0, 1, 3)
				node_to_block_ids[n_name].append(bid)

		elif kind in ["awesome_sink", "depot", "container"]:
			var bid := "%s#0" % n_name
			var item_key: String = ch.get_meta("item", "")
			var pal := db.get_item_palette(item_key)
			var b_key := "awesome-sink" if kind == "awesome_sink" else ("dimensional-depot" if kind == "depot" else "storage-container")
			var short_key := "grid_sink_short" if kind == "awesome_sink" else ("grid_depot_short" if kind == "depot" else "grid_cont_short")
			var dims: Vector2 = db.get_building_footprint_foundations(b_key)
			var def_pos := view._snap_vec(Vector2(cursor_x, 0.0))
			cursor_x += dims.x + 2.0
			view._register_block(bid, n_name, i18n.t(short_key), db.get_item_display_name(item_key), b_key, item_key, pal["header"], pal["border"], dims, def_pos, mem, false, 0, 1, 1 if kind == "container" else 0)
			node_to_block_ids[n_name].append(bid)

		elif kind in ["truck_station", "train_station"]:
			var bid := "%s#0" % n_name
			var b_key := "truck-station" if kind == "truck_station" else "train-station"
			var short_key := "grid_truck_short" if kind == "truck_station" else "grid_train_short"
			var dims: Vector2 = db.get_building_footprint_foundations(b_key)
			var st_in_cnt := 2 if kind == "truck_station" else int(ch.get_meta("platforms_count", 1))
			var st_out_cnt := maxi(1, (ch.get_meta("station_out_items", []) as Array).size())
			if kind == "train_station":
				dims.y = maxf(dims.y, float(st_in_cnt) * 2.0)
			var def_pos := view._snap_vec(Vector2(cursor_x, 0.0))
			cursor_x += dims.x + 3.0
			view._register_block(bid, n_name, i18n.t(short_key), ch.title, b_key, "", Color.html("#2D3248"), Color.html("#EB7D15"), dims, def_pos, mem, false, 0, st_in_cnt, st_out_cnt)
			node_to_block_ids[n_name].append(bid)

		elif kind == "factory":
			var bid := "%s#0" % n_name
			var def_pos := view._snap_vec(Vector2(cursor_x, 0.0))
			cursor_x += 6.0
			var f_in_cnt := (ch.get_meta("in_items", []) as Array).size()
			var f_out_cnt := (ch.get_meta("out_items", []) as Array).size()
			view._register_block(
				bid, n_name, ch.title, i18n.t("sub_factory_name"),
				"factory", "", Color.html("#2D3248"), Color.html("#7AB0D4"),
				Vector2(4.0, 4.0), def_pos, mem, false, 0, f_in_cnt, f_out_cnt
			)
			node_to_block_ids[n_name].append(bid)

	var wire_flows: Dictionary = g.get_meta("wire_flows", {})
	var out_deg: Dictionary = {}
	var in_deg: Dictionary = {}
	var raw_edges: Array[Dictionary] = []

	for conn in all_conns:
		var fn := String(conn.get("from_node", conn.get("from", "")))
		var tn := String(conn.get("to_node", conn.get("to", "")))
		var fp := int(conn["from_port"])
		var tp := int(conn["to_port"])
		if virtual_splitter_nodes.has(fn) or virtual_splitter_nodes.has(tn):
			continue
		if not node_to_block_ids.has(fn) or not node_to_block_ids.has(tn):
			continue
		var w_key := "%s:%d->%s:%d" % [fn, fp, tn, tp]
		var w_info: Dictionary = wire_flows.get(w_key, {"rate": 0.0, "item": ""})
		var skey := "%s:%d" % [fn, fp]
		var dkey := "%s:%d" % [tn, tp]
		out_deg[skey] = int(out_deg.get(skey, 0)) + 1
		in_deg[dkey] = int(in_deg.get(dkey, 0)) + 1
		raw_edges.append({
			"fn": fn, "fp": fp, "tn": tn, "tp": tp,
			"skey": skey, "dkey": dkey,
			"rate": float(w_info["rate"]), "item": String(w_info["item"])
		})

	var groups: Dictionary = {}
	for e in raw_edges:
		var g_key: String = e["dkey"] if (int(in_deg.get(e["dkey"], 0)) > 1 and int(out_deg.get(e["skey"], 0)) == 1) else e["skey"]
		if not groups.has(g_key):
			groups[g_key] = {"owner": e["fn"], "srcs": [], "dsts": [], "flow": 0.0, "item": ""}
		var grp: Dictionary = groups[g_key]
		for sid in node_to_block_ids[e["fn"]]:
			if not sid in grp["srcs"]:
				grp["srcs"].append(sid)
		for did in node_to_block_ids[e["tn"]]:
			if not did in grp["dsts"]:
				grp["dsts"].append(did)
		grp["flow"] = float(grp["flow"]) + float(e["rate"])
		if String(grp["item"]) == "" and String(e["item"]) != "":
			grp["item"] = String(e["item"])

	for sp_name in virtual_splitter_nodes.keys():
		var sp_node: GraphNode = virtual_splitter_nodes[sp_name]
		var sp_item := String(sp_node.get_meta("item", ""))
		var grp_srcs: Array = []
		var grp_dsts: Array = []
		var grp_flow := 0.0

		var queue_in: Array[String] = [sp_name]
		var vis_in: Dictionary = {sp_name: true}
		while not queue_in.is_empty():
			var cur_sp: String = queue_in.pop_front()
			for c in all_conns:
				var c_fn := String(c.get("from_node", c.get("from", "")))
				var c_tn := String(c.get("to_node", c.get("to", "")))
				if c_tn == cur_sp:
					if virtual_splitter_nodes.has(c_fn):
						if not vis_in.has(c_fn):
							vis_in[c_fn] = true
							queue_in.append(c_fn)
					elif node_to_block_ids.has(c_fn):
						for sid in node_to_block_ids[c_fn]:
							if not (sid in grp_srcs):
								grp_srcs.append(sid)

		var queue_out: Array[String] = [sp_name]
		var vis_out: Dictionary = {sp_name: true}
		while not queue_out.is_empty():
			var cur_sp: String = queue_out.pop_front()
			for c in all_conns:
				var c_fn := String(c.get("from_node", c.get("from", "")))
				var c_tn := String(c.get("to_node", c.get("to", "")))
				var c_fp := int(c["from_port"])
				var c_tp := int(c["to_port"])
				if c_fn == cur_sp:
					if virtual_splitter_nodes.has(c_tn):
						if not vis_out.has(c_tn):
							vis_out[c_tn] = true
							queue_out.append(c_tn)
					elif node_to_block_ids.has(c_tn):
						for did in node_to_block_ids[c_tn]:
							if not (did in grp_dsts):
								grp_dsts.append(did)
						var wk := "%s:%d->%s:%d" % [c_fn, c_fp, c_tn, c_tp]
						var wi: Dictionary = wire_flows.get(wk, {"rate": 0.0, "item": sp_item})
						grp_flow += float(wi["rate"])

		if not grp_srcs.is_empty() and not grp_dsts.is_empty():
			var g_key := "vsp_%s" % sp_name
			groups[g_key] = {
				"owner": sp_name,
				"srcs": grp_srcs,
				"dsts": grp_dsts,
				"flow": grp_flow,
				"item": sp_item
			}

	for g_key in groups.keys():
		var grp: Dictionary = groups[g_key]
		var all_srcs: Array = grp["srcs"]
		var all_dsts: Array = grp["dsts"]
		var total_flow := float(grp["flow"])
		var item_key := String(grp["item"])
		var S := all_srcs.size()
		var D := all_dsts.size()
		if S == 0 or D == 0:
			continue

		all_srcs.sort_custom(func(a, b): return view.blocks[a]["pos_f"].y < view.blocks[b]["pos_f"].y)
		all_dsts.sort_custom(func(a, b): return view.blocks[b]["pos_f"].y > view.blocks[a]["pos_f"].y)

		if not view.auto_generate_splitters:
			var pairs := maxi(S, D)
			for i in range(pairs):
				view.wire_links.append({
					"from_id": all_srcs[i % S],
					"to_id": all_dsts[i % D],
					"item": item_key,
					"rate": total_flow / float(pairs),
					"is_feedback": false
				})
			continue

		var lanes := _gcd(S, D)
		var s_per_lane := S / lanes
		var d_per_lane := D / lanes
		var flow_per_lane := total_flow / float(lanes)

		for lane in range(lanes):
			var sub_srcs := all_srcs.slice(lane * s_per_lane, (lane + 1) * s_per_lane)
			var sub_dsts := all_dsts.slice(lane * d_per_lane, (lane + 1) * d_per_lane)
			build_single_balancer_lane(
				"%s_L%d" % [g_key.replace(":", "_"), lane],
				String(grp["owner"]),
				sub_srcs,
				sub_dsts,
				flow_per_lane,
				item_key,
				mem
			)

	view._restore_user_logistics_blocks(mem)
	view._update_floor_ui()

func build_single_balancer_lane(lane_key: String, owner_node: String, sub_srcs: Array, sub_dsts: Array, lane_flow: float, item_key: String, mem: Dictionary) -> void:
	var s := sub_srcs.size()
	var d := sub_dsts.size()
	if s == 1 and d == 1:
		view.wire_links.append({
			"from_id": sub_srcs[0],
			"to_id": sub_dsts[0],
			"item": item_key,
			"rate": lane_flow,
			"is_feedback": false
		})
		return

	var pal := db.get_item_palette(item_key)
	var lane_floor := int(view.blocks[sub_srcs[0]].get("floor", 0))
	var src_right_x := -INF
	for sid in sub_srcs:
		var sb: Dictionary = view.blocks[sid]
		src_right_x = maxf(src_right_x, sb["pos_f"].x + view._get_effective_size_f(sb).x)

	var dst_left_x := INF
	var dst_min_y := INF
	var dst_max_y := -INF
	for did in sub_dsts:
		var db_blk: Dictionary = view.blocks[did]
		dst_left_x = minf(dst_left_x, db_blk["pos_f"].x)
		dst_min_y = minf(dst_min_y, db_blk["pos_f"].y)
		dst_max_y = maxf(dst_max_y, db_blk["pos_f"].y)

	var bus_source_id: String = sub_srcs[0]
	var cur_x := src_right_x + 0.75

	if s > 1:
		var layer: Array[Dictionary] = []
		for sid in sub_srcs:
			layer.append({
				"id": sid,
				"rate": lane_flow / float(s),
				"y": view.blocks[sid]["pos_f"].y + view._get_effective_size_f(view.blocks[sid]).y * 0.5
			})
		var m_stage := 0
		var m_counter := 1
		while layer.size() > 1:
			var next_layer: Array[Dictionary] = []
			var i := 0
			var n := layer.size()
			while i < n:
				var rem := n - i
				var grp := 2
				if rem == 3 or (rem >= 5 and rem % 3 == 0):
					grp = 3
				elif rem == 1:
					next_layer.append(layer[i])
					i += 1
					continue
				var sum_rate := 0.0
				var sum_y := 0.0
				var inputs_slice := layer.slice(i, i + grp)
				for inp in inputs_slice:
					sum_rate += float(inp["rate"])
					sum_y += float(inp["y"])
				var avg_y := sum_y / float(grp)
				var m_id := "auto_merger_%s_%d_%d" % [lane_key, m_stage, m_counter]
				m_counter += 1
				var m_pos := view._snap_vec(Vector2(cur_x + m_stage * 1.0, avg_y - 0.25))
				# Every physical Merger has 3 inputs (Left, Back, Right) and 1 output (Front)
				view._register_block(
					m_id, owner_node, i18n.tf("grid_merger_tag", [m_counter - 1]), "4x4m",
					"merger", item_key, pal["header"], pal["border"], GridPlannerView.SPLITTER_SIZE_F,
					m_pos, mem, false, lane_floor, 3, 1
				)
				for inp in inputs_slice:
					view.wire_links.append({
						"from_id": inp["id"],
						"to_id": m_id,
						"item": item_key,
						"rate": float(inp["rate"]),
						"is_feedback": false
					})
				next_layer.append({"id": m_id, "rate": sum_rate, "y": m_pos.y + 0.25})
				i += grp
			layer = next_layer
			m_stage += 1
		bus_source_id = layer[0]["id"]

	if d == 1:
		view.wire_links.append({
			"from_id": bus_source_id,
			"to_id": sub_dsts[0],
			"item": item_key,
			"rate": lane_flow,
			"is_feedback": false
		})
		return

	var bal_info := find_balancer_factors(d)
	var M: int = int(bal_info["m"])
	var factors: Array = bal_info["factors"]
	var fb_count: int = int(bal_info["feedback"])
	var num_stages := factors.size()
	var leaf_rate := lane_flow / float(d)
	var root_in_flow := float(M) * leaf_rate

	var tree_root_source := bus_source_id
	var feedback_merger_id := ""
	var start_tree_x := dst_left_x - float(num_stages) * 1.25
	var center_y := (dst_min_y + dst_max_y) * 0.5

	if fb_count > 0:
		feedback_merger_id = "auto_fb_merger_%s" % lane_key
		var fb_pos := view._snap_vec(Vector2(start_tree_x - 1.25, center_y - 0.25))
		view._register_block(
			feedback_merger_id, owner_node, i18n.t("grid_bal_m"), i18n.t("grid_loop_in"),
			"merger", item_key, pal["header"], Color.html("#76F5E8"), GridPlannerView.SPLITTER_SIZE_F,
			fb_pos, mem, false, lane_floor, 3, 1
		)
		view.wire_links.append({
			"from_id": bus_source_id,
			"to_id": feedback_merger_id,
			"item": item_key,
			"rate": lane_flow,
			"is_feedback": false
		})
		tree_root_source = feedback_merger_id

	var current_branches: Array[Dictionary] = [
		{"from_id": tree_root_source, "rate": root_in_flow, "y": center_y}
	]
	var sp_counter := 1
	for stage_idx in range(num_stages):
		var factor: int = int(factors[stage_idx])
		var next_branches: Array[Dictionary] = []
		var num_splitters := current_branches.size()
		var stage_x := start_tree_x + stage_idx * 1.25
		for b_idx in range(num_splitters):
			var br: Dictionary = current_branches[b_idx]
			var sp_y := float(br["y"])
			if num_splitters > 1:
				var t_ratio := float(b_idx) / float(num_splitters - 1)
				sp_y = lerpf(dst_min_y + 0.25, dst_max_y + 0.25, t_ratio)
			var sp_id := "auto_splitter_%s_%d_%d" % [lane_key, stage_idx, sp_counter]
			sp_counter += 1
			var sp_pos := view._snap_vec(Vector2(stage_x, sp_y - 0.25))
			# Every physical Splitter has 1 input (Back) and 3 outputs (Left, Front, Right)
			view._register_block(
				sp_id, owner_node, i18n.tf("grid_splitter_tag", [sp_counter - 1, factor]), "4x4m",
				"splitter", item_key, pal["header"], pal["border"], GridPlannerView.SPLITTER_SIZE_F,
				sp_pos, mem, false, lane_floor, 1, 3
			)
			view.wire_links.append({
				"from_id": br["from_id"],
				"to_id": sp_id,
				"item": item_key,
				"rate": float(br["rate"]),
				"is_feedback": false
			})
			var child_rate := float(br["rate"]) / float(factor)
			var spread := maxf(1.0, (dst_max_y - dst_min_y) / float(num_splitters * factor))
			for k in range(factor):
				var offset_y := (float(k) - float(factor - 1) * 0.5) * spread
				next_branches.append({
					"from_id": sp_id,
					"rate": child_rate,
					"y": sp_pos.y + 0.25 + offset_y
				})
		current_branches = next_branches

	for i in range(current_branches.size()):
		var leaf: Dictionary = current_branches[i]
		if i < d:
			view.wire_links.append({
				"from_id": leaf["from_id"],
				"to_id": sub_dsts[i],
				"item": item_key,
				"rate": leaf_rate,
				"is_feedback": false
			})
		elif feedback_merger_id != "":
			view.wire_links.append({
				"from_id": leaf["from_id"],
				"to_id": feedback_merger_id,
				"item": item_key,
				"rate": leaf_rate,
				"is_feedback": true
			})
