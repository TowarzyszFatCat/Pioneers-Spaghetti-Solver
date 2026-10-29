class_name FactorySolver
extends RefCounted

const SINK_STORAGE_KINDS := ["awesome_sink", "depot", "container"]
const TRANSPORT_STATIONS := ["truck_station", "train_station"]
const STANDARD_SPLITTERS := ["splitter", "even_splitter", "prop_splitter", "reroute"]

var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var route_solver: StationRouteSolver
var visual_updater: GraphVisualUpdater

func _init(p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	db = p_db
	settings = p_settings
	i18n = p_i18n
	route_solver = StationRouteSolver.new()
	visual_updater = GraphVisualUpdater.new(self, db, settings, i18n)

func solve_all(world_graph: GraphEdit, factory_graphs: Dictionary, factory_nodes: Dictionary) -> Dictionary:
	var passes := maxi(6, factory_graphs.size() + 4)
	for _pass in range(passes):
		_solve_graph(world_graph, factory_graphs)
		for fid in factory_graphs.keys():
			if is_instance_valid(factory_graphs[fid]):
				_solve_graph(factory_graphs[fid], factory_graphs)

	var world_pwr := visual_updater.update_visuals(world_graph)
	var total_used := float(world_pwr["consumed"])
	var total_gen := float(world_pwr["generated"])
	for fid in factory_graphs.keys():
		if is_instance_valid(factory_graphs[fid]):
			var fp := visual_updater.update_visuals(factory_graphs[fid])
			total_used += float(fp["consumed"])
			total_gen += float(fp["generated"])

	for fid in factory_nodes.keys():
		var f_node = factory_nodes[fid]
		if is_instance_valid(f_node) and factory_graphs.has(fid):
			var stats := _calc_factory_totals_recursive(fid, factory_graphs)
			var stats_lbl: Label = f_node.get_meta("stats_label")
			var enter_btn: Button = f_node.get_meta("enter_btn")
			enter_btn.text = i18n.t("enter_factory")
			if f_node.has_meta("empty_lbl") and is_instance_valid(f_node.get_meta("empty_lbl")):
				(f_node.get_meta("empty_lbl") as Label).text = i18n.t("empty_factory_io")
			var u_mw := float(stats["consumed"])
			var g_mw := float(stats["generated"])
			if g_mw > 0.0:
				stats_lbl.text = i18n.tf("factory_stats_gen", [settings.fmt(g_mw), settings.fmt(u_mw), stats["machines"]])
				stats_lbl.modulate = Color.SPRING_GREEN if g_mw >= u_mw else Color.GOLD
			else:
				stats_lbl.text = i18n.tf("factory_stats_use", [settings.fmt(u_mw), stats["machines"]])
				stats_lbl.modulate = Color.GOLD

	return {"consumed": total_used, "generated": total_gen, "net": total_gen - total_used}

func _calc_factory_totals_recursive(fid: String, factory_graphs: Dictionary) -> Dictionary:
	var used_mw := 0.0
	var gen_mw := 0.0
	var m_count := 0
	if not factory_graphs.has(fid) or not is_instance_valid(factory_graphs[fid]):
		return {"consumed": 0.0, "generated": 0.0, "machines": 0}
	var fg: GraphEdit = factory_graphs[fid]
	for ch in fg.get_children():
		if is_instance_valid(ch) and ch is GraphNode and ch.has_meta("node_kind"):
			var kind: String = ch.get_meta("node_kind")
			if kind == "machine":
				used_mw += _calc_power_consumed(ch)
				gen_mw += _calc_power_generated(ch)
				m_count += int(ceilf(float(ch.get_meta("machines"))))
			elif kind in ["awesome_sink", "depot"] or kind in TRANSPORT_STATIONS:
				used_mw += float(ch.get_meta("power_mw", 0.0))
			elif kind == "factory":
				var sub_fid: String = ch.get_meta("factory_id")
				var sub_stats := _calc_factory_totals_recursive(sub_fid, factory_graphs)
				used_mw += float(sub_stats["consumed"])
				gen_mw += float(sub_stats["generated"])
				m_count += int(sub_stats["machines"])
	return {"consumed": used_mw, "generated": gen_mw, "machines": m_count}

func get_station_link_in_port(node: GraphNode) -> int:
	if String(node.get_meta("node_kind")) == "truck_station":
		return 2
	return int(node.get_meta("platforms_count", 1))

func get_station_link_out_port(node: GraphNode) -> int:
	var out_items: Array = node.get_meta("station_out_items", [])
	return out_items.size()

func _compute_manual_splitter_outputs(g: GraphEdit, node: GraphNode) -> Array[float]:
	var sup: Array = node.get_meta("last_supplied", [0.0])
	var total_in := float(sup[0]) if sup.size() > 0 else 0.0
	var overrides: Array = node.get_meta("manual_overrides", [false, false, false])
	var man_rates: Array = node.get_meta("manual_rates", [0.0, 0.0, 0.0])
	var connected: Array[bool] = [false, false, false]
	var demands: Array[float] = [0.0, 0.0, 0.0]

	for conn in g.get_connection_list():
		var fn: StringName = conn.get("from_node", conn.get("from", ""))
		if fn == node.name:
			var fp := int(conn["from_port"])
			if fp >= 0 and fp < 3:
				connected[fp] = true
				var tn: StringName = conn.get("to_node", conn.get("to", ""))
				var tp := int(conn["to_port"])
				var dst := g.get_node_or_null(NodePath(tn)) as GraphNode
				if is_instance_valid(dst):
					demands[fp] += get_node_input_demand(g, dst, tp)

	var result: Array[float] = [0.0, 0.0, 0.0]
	var remaining := total_in
	for i in range(3):
		if connected[i] and bool(overrides[i]):
			var alloc := clampf(float(man_rates[i]), 0.0, remaining)
			result[i] = alloc
			remaining = maxf(0.0, remaining - alloc)

	var auto_indices: Array[int] = []
	var auto_demand_sum := 0.0
	for i in range(3):
		if connected[i] and not bool(overrides[i]):
			auto_indices.append(i)
			auto_demand_sum += demands[i]

	if not auto_indices.is_empty() and remaining > 0.0:
		for idx in auto_indices:
			if settings.equal_split_mode or auto_demand_sum <= 0.0001:
				result[idx] = remaining / float(auto_indices.size())
			else:
				result[idx] = remaining * (demands[idx] / auto_demand_sum)

	node.set_meta("actual_out_rates", result)
	return result

func _solve_graph(g: GraphEdit, factory_graphs: Dictionary) -> void:
	var nodes: Dictionary = {}
	var incoming: Dictionary = {}
	var has_incoming_wire: Dictionary = {}
	var demanded_out: Dictionary = {}
	var wire_flows: Dictionary = {}
	var station_local_in: Dictionary = {}
	var station_links: Array[Dictionary] = []

	for ch in g.get_children():
		if is_instance_valid(ch) and not ch.is_queued_for_deletion() and ch is GraphNode and ch.has_meta("node_kind"):
			nodes[ch.name] = ch
			var in_count := get_node_input_count(ch)
			var arr: Array[float] = []
			arr.resize(in_count)
			arr.fill(0.0)
			incoming[ch.name] = arr

			var w_arr: Array[bool] = []
			w_arr.resize(in_count)
			w_arr.fill(false)
			has_incoming_wire[ch.name] = w_arr

			var out_count := get_node_output_count(ch)
			var d_arr: Array[float] = []
			d_arr.resize(out_count)
			d_arr.fill(0.0)
			demanded_out[ch.name] = d_arr

			var k := String(ch.get_meta("node_kind"))
			if k == "manual_splitter":
				_compute_manual_splitter_outputs(g, ch)
			elif k in TRANSPORT_STATIONS:
				station_local_in[ch.name] = {"by_item": {}, "by_plat": {}}

	var outgoing_groups: Dictionary = {}
	for conn in g.get_connection_list():
		var f_node: StringName = conn.get("from_node", conn.get("from", ""))
		var t_node: StringName = conn.get("to_node", conn.get("to", ""))
		var f_port: int = int(conn["from_port"])
		var t_port: int = int(conn["to_port"])
		if not nodes.has(f_node) or not nodes.has(t_node):
			continue
		var key := "%s:%d" % [f_node, f_port]
		if not outgoing_groups.has(key):
			outgoing_groups[key] = []
		outgoing_groups[key].append({"to_node": t_node, "to_port": t_port})

	for key in outgoing_groups.keys():
		var parts := (key as String).split(":")
		var f_node := StringName(parts[0])
		var f_port := parts[1].to_int()
		var src_node: GraphNode = nodes[f_node]
		var src_kind: String = src_node.get_meta("node_kind")
		var targets: Array = outgoing_groups[key]
		var n_targets := targets.size()

		# Inter-station route link (bottom port)
		if src_kind in TRANSPORT_STATIONS and f_port == get_station_link_out_port(src_node):
			for t in targets:
				var dst_name: StringName = t["to_node"]
				var tp := int(t["to_port"])
				station_links.append({"from": f_node, "fp": f_port, "to": dst_name, "tp": tp})
			continue

		var total_out := get_node_output_rate(src_node, f_port)
		var out_item := get_node_output_item(src_node, f_port)
		var total_demand := 0.0
		var demands: Array[float] = []
		for t in targets:
			var dst_node: GraphNode = nodes[t["to_node"]]
			var d := get_node_input_demand(g, dst_node, int(t["to_port"]))
			demands.append(d)
			total_demand += d

		var src_dem_arr: Array = demanded_out[f_node]
		if f_port < src_dem_arr.size():
			src_dem_arr[f_port] = total_demand

		var use_equal_split := settings.equal_split_mode
		if src_kind == "even_splitter":
			use_equal_split = true
		elif src_kind == "prop_splitter" or src_kind in TRANSPORT_STATIONS:
			use_equal_split = false

		for i in range(n_targets):
			var t: Dictionary = targets[i]
			var share := 0.0
			if src_kind in TRANSPORT_STATIONS:
				# Stations distribute cargo proportionally to downstream demand up to available capacity
				if total_demand <= 0.0001:
					share = total_out / float(n_targets)
				elif total_demand <= total_out + 0.0001:
					share = demands[i]
				else:
					share = total_out * (demands[i] / total_demand)
			elif use_equal_split or total_demand <= 0.0001:
				share = total_out / float(n_targets)
			else:
				share = total_out * (demands[i] / total_demand)

			var dst_name: StringName = t["to_node"]
			var dst_node: GraphNode = nodes[dst_name]
			var dst_kind: String = dst_node.get_meta("node_kind")
			var tp := int(t["to_port"])
			var dst_arr: Array = incoming[dst_name]
			var w_arr: Array = has_incoming_wire[dst_name]
			if tp < dst_arr.size():
				dst_arr[tp] += share
				w_arr[tp] = true

			if dst_kind in TRANSPORT_STATIONS and out_item != "" and out_item != "__station_route__":
				if dst_kind == "truck_station" and tp == 1 and station_local_in.has(dst_name):
					var bi: Dictionary = station_local_in[dst_name]["by_item"]
					bi[out_item] = float(bi.get(out_item, 0.0)) + share
				elif dst_kind == "train_station" and tp >= 0 and tp < int(dst_node.get_meta("platforms_count", 1)) and station_local_in.has(dst_name):
					var bp: Dictionary = station_local_in[dst_name]["by_plat"]
					if not bp.has(tp):
						bp[tp] = {"item": out_item, "rate": 0.0}
					bp[tp]["item"] = out_item
					bp[tp]["rate"] = float(bp[tp]["rate"]) + share

			var w_key := "%s:%d->%s:%d" % [f_node, f_port, dst_name, tp]
			wire_flows[w_key] = {"rate": share, "item": out_item}

	route_solver.solve_station_routes(g, nodes, station_local_in, demanded_out, station_links, wire_flows)
	g.set_meta("wire_flows", wire_flows)

	for n_name in nodes.keys():
		var node: GraphNode = nodes[n_name]
		var sup: Array = incoming[n_name]
		var w_flags: Array = has_incoming_wire[n_name]
		var dem_arr: Array = demanded_out[n_name]
		node.set_meta("last_supplied", sup)
		node.set_meta("last_has_wire", w_flags)
		node.set_meta("last_demanded", dem_arr)

		var kind: String = node.get_meta("node_kind")
		if kind == "factory":
			var receivers: Array = node.get_meta("receivers", [])
			var fid: String = node.get_meta("factory_id")
			if factory_graphs.has(fid) and is_instance_valid(factory_graphs[fid]):
				var f_graph: GraphEdit = factory_graphs[fid]
				for i in range(receivers.size()):
					var raw_rx = receivers[i]
					if is_instance_valid(raw_rx) and not raw_rx.is_queued_for_deletion():
						var r_node := raw_rx as GraphNode
						var wired: bool = w_flags[i] if i < w_flags.size() else false
						r_node.set_meta("has_ext_wire", wired)
						r_node.set_meta("ext_supplied", sup[i] if i < sup.size() else 0.0)
						r_node.set_meta("int_demand", _sum_downstream_demand(f_graph, r_node.name, 0))
		elif kind == "transmitter":
			node.set_meta("tx_rate", sup[0] if sup.size() > 0 else 0.0)
		elif kind == "manual_splitter":
			_compute_manual_splitter_outputs(g, node)

func _sum_downstream_demand(g: GraphEdit, from_node_name: StringName, from_port: int) -> float:
	var total := 0.0
	for conn in g.get_connection_list():
		var fn: StringName = conn.get("from_node", conn.get("from", ""))
		var fp := int(conn["from_port"])
		if fn == from_node_name and fp == from_port:
			var tn: StringName = conn.get("to_node", conn.get("to", ""))
			var tp := int(conn["to_port"])
			var dst := g.get_node_or_null(NodePath(tn)) as GraphNode
			if is_instance_valid(dst):
				total += get_node_input_demand(g, dst, tp)
	return total

func get_somersloop_mult(node: GraphNode) -> float:
	var sloops := int(node.get_meta("somersloops", 0))
	var max_s := int(node.get_meta("max_somersloops", 0))
	if sloops <= 0 or max_s <= 0:
		return 1.0
	return 1.0 + (float(clampi(sloops, 0, max_s)) / float(max_s))

func get_miner_mk_mult(node: GraphNode) -> float:
	var r_id: String = node.get_meta("recipe_id", "")
	if not db.recipes.has(r_id) or not db.recipes[r_id].get("has_mk_tiers", false):
		return 1.0
	var mk := int(node.get_meta("miner_mk", 1))
	match mk:
		2: return 2.0
		3: return 4.0
		_: return 1.0

func get_node_input_count(node: GraphNode) -> int:
	var kind: String = node.get_meta("node_kind")
	if kind == "machine":
		return db.recipes[node.get_meta("recipe_id")]["inputs"].size()
	elif kind == "factory":
		return node.get_meta("in_items", []).size()
	elif kind == "truck_station":
		return 3
	elif kind == "train_station":
		return int(node.get_meta("platforms_count", 1)) + 1
	elif kind == "transmitter" or kind in STANDARD_SPLITTERS or kind == "manual_splitter" or kind in SINK_STORAGE_KINDS:
		return 1
	return 0

func get_node_output_count(node: GraphNode) -> int:
	var kind: String = node.get_meta("node_kind")
	if kind == "machine":
		return db.recipes[node.get_meta("recipe_id")]["outputs"].size()
	elif kind == "factory":
		return node.get_meta("out_items", []).size()
	elif kind in TRANSPORT_STATIONS:
		var out_items: Array = node.get_meta("station_out_items", [])
		return out_items.size() + 1
	elif kind == "manual_splitter":
		return 3
	elif kind == "receiver" or kind in STANDARD_SPLITTERS or kind == "container":
		return 1
	return 0

func get_node_input_item(node: GraphNode, port: int) -> String:
	var kind: String = node.get_meta("node_kind")
	if kind == "machine":
		var ins: Array = db.recipes[node.get_meta("recipe_id")]["inputs"]
		return ins[port]["item"] if port < ins.size() else ""
	elif kind == "factory":
		var ins: Array = node.get_meta("in_items", [])
		return ins[port] if port < ins.size() else ""
	elif kind == "transmitter" or kind in STANDARD_SPLITTERS or kind == "manual_splitter" or kind in SINK_STORAGE_KINDS:
		return node.get_meta("item", "")
	elif kind == "truck_station":
		if port == 0:
			return String(node.get_meta("fuel_item", "coal"))
		return ""
	return ""

func get_node_output_item(node: GraphNode, port: int) -> String:
	var kind: String = node.get_meta("node_kind")
	if kind == "machine":
		var outs: Array = db.recipes[node.get_meta("recipe_id")]["outputs"]
		return outs[port]["item"] if port < outs.size() else ""
	elif kind == "factory":
		var outs: Array = node.get_meta("out_items", [])
		return outs[port] if port < outs.size() else ""
	elif kind in TRANSPORT_STATIONS:
		var out_items: Array = node.get_meta("station_out_items", [])
		if port >= 0 and port < out_items.size():
			return String(out_items[port])
		return "__station_route__"
	elif kind == "receiver" or kind in STANDARD_SPLITTERS or kind == "manual_splitter" or kind == "container":
		return node.get_meta("item", "")
	return ""

func get_node_input_demand(g: GraphEdit, node: GraphNode, port: int) -> float:
	var kind: String = node.get_meta("node_kind")
	if kind == "machine":
		var ins: Array = db.recipes[node.get_meta("recipe_id")]["inputs"]
		if port >= ins.size():
			return 0.0
		var m := float(node.get_meta("machines"))
		var clk := float(node.get_meta("clock")) / 100.0
		return float(ins[port]["rate"]) * m * clk
	elif kind == "factory":
		var receivers: Array = node.get_meta("receivers", [])
		if port < receivers.size() and is_instance_valid(receivers[port]):
			var r_node: GraphNode = receivers[port]
			var int_d := float(r_node.get_meta("int_demand", 0.0))
			return int_d if int_d > 0.0 else float(r_node.get_meta("planned_rate", 60.0))
	elif kind == "truck_station":
		if port == 0:
			return float(node.get_meta("fuel_rate", 15.0))
		return 999999.0
	elif kind == "train_station":
		return 999999.0
	elif kind in STANDARD_SPLITTERS:
		return _sum_downstream_demand(g, node.name, 0)
	elif kind == "manual_splitter":
		var total_d := 0.0
		var ovr: Array = node.get_meta("manual_overrides", [false, false, false])
		var rts: Array = node.get_meta("manual_rates", [0.0, 0.0, 0.0])
		for p in range(3):
			var d_port := _sum_downstream_demand(g, node.name, p)
			if bool(ovr[p]):
				total_d += float(rts[p])
			else:
				total_d += d_port
		return total_d
	elif kind == "container":
		var down_d := _sum_downstream_demand(g, node.name, 0)
		return down_d if down_d > 0.0 else float(node.get_meta("planned_rate", 60.0))
	elif kind == "transmitter" or kind in ["awesome_sink", "depot"]:
		return float(node.get_meta("planned_rate", 60.0))
	return 0.0

func get_node_output_rate(node: GraphNode, port: int) -> float:
	var kind: String = node.get_meta("node_kind")
	if kind == "machine":
		var data: Dictionary = db.recipes[node.get_meta("recipe_id")]
		var outs: Array = data["outputs"]
		if port >= outs.size():
			return 0.0
		var m := float(node.get_meta("machines"))
		var clk := float(node.get_meta("clock")) / 100.0
		var pur := float(node.get_meta("purity", 1.0))
		var mk_mult := get_miner_mk_mult(node)
		var sloop_mult := get_somersloop_mult(node)
		var base_out := float(outs[port]["rate"]) * m * clk * pur * mk_mult * sloop_mult
		if settings.realistic_throttle and not data["inputs"].is_empty():
			var ins: Array = data["inputs"]
			var sup: Array = node.get_meta("last_supplied", [])
			var throttle := 1.0
			for i in range(mini(ins.size(), sup.size())):
				var need := float(ins[i]["rate"]) * m * clk
				if need > 0.0:
					throttle = minf(throttle, float(sup[i]) / need)
			base_out *= clampf(throttle, 0.0, 1.0)
		return base_out
	elif kind == "factory":
		var transmitters: Array = node.get_meta("transmitters", [])
		if port < transmitters.size() and is_instance_valid(transmitters[port]):
			return float(transmitters[port].get_meta("tx_rate", 0.0))
	elif kind in TRANSPORT_STATIONS:
		var out_items: Array = node.get_meta("station_out_items", [])
		var taken_dict: Dictionary = node.get_meta("station_taken", {})
		var avail_dict: Dictionary = node.get_meta("station_avail", node.get_meta("station_total_in", {}))
		if port >= 0 and port < out_items.size():
			var ikey: String = String(out_items[port])
			if ikey == "":
				return 0.0
			var lookup_key := ("%s#%d" % [ikey, port]) if (kind == "train_station" and avail_dict.has("%s#%d" % [ikey, port])) else ikey
			var tkn := float(taken_dict.get(lookup_key, 0.0))
			return tkn if tkn > 0.0 else float(avail_dict.get(lookup_key, 0.0))
		return 0.0
	elif kind == "receiver":
		if bool(node.get_meta("has_ext_wire", false)):
			return float(node.get_meta("ext_supplied", 0.0))
		return float(node.get_meta("planned_rate", 60.0))
	elif kind in STANDARD_SPLITTERS or kind == "container":
		var sup: Array = node.get_meta("last_supplied", [0.0])
		return float(sup[0]) if sup.size() > 0 else 0.0
	elif kind == "manual_splitter":
		var act: Array = node.get_meta("actual_out_rates", [0.0, 0.0, 0.0])
		return float(act[port]) if port < act.size() else 0.0
	return 0.0

func _calc_power_consumed(node: GraphNode) -> float:
	var r_id: String = node.get_meta("recipe_id")
	var data: Dictionary = db.recipes[r_id]
	if data.get("is_generator", false):
		return 0.0
	var base_mw := float(data.get("power", 4.0))
	if data.get("has_mk_tiers", false):
		var mk := int(node.get_meta("miner_mk", 1))
		base_mw = float(db.MINER_TIERS.get(mk, {"power": 5.0})["power"])
	var m := float(node.get_meta("machines"))
	if settings.ceil_machines:
		m = ceilf(m)
	var clk := float(node.get_meta("clock")) / 100.0
	var sloop_mult := get_somersloop_mult(node)
	return base_mw * m * (sloop_mult * sloop_mult) * pow(clk, 1.321928)

func _calc_power_generated(node: GraphNode) -> float:
	var r_id: String = node.get_meta("recipe_id")
	var data: Dictionary = db.recipes[r_id]
	if not data.get("is_generator", false):
		return 0.0
	var base_gen := float(data.get("power_generated", 0.0))
	var m := float(node.get_meta("machines"))
	var clk := float(node.get_meta("clock")) / 100.0
	var out_mw := base_gen * m * clk
	if settings.realistic_throttle and not data["inputs"].is_empty():
		var ins: Array = data["inputs"]
		var sup: Array = node.get_meta("last_supplied", [])
		var throttle := 1.0
		for i in range(mini(ins.size(), sup.size())):
			var need := float(ins[i]["rate"]) * m * clk
			if need > 0.0:
				throttle = minf(throttle, float(sup[i]) / need)
		out_mw *= clampf(throttle, 0.0, 1.0)
	return out_mw
