class_name StationRouteSolver
extends RefCounted

func solve_station_routes(g: GraphEdit, nodes: Dictionary, station_local_in: Dictionary, demanded_out: Dictionary, station_links: Array[Dictionary], wire_flows: Dictionary) -> void:
	var station_names: Array = station_local_in.keys()
	if station_names.is_empty():
		return

	var visited: Dictionary = {}
	for st_name in station_names:
		if visited.has(st_name):
			continue
		var comp: Array[StringName] = []
		var queue: Array[StringName] = [st_name]
		visited[st_name] = true
		while not queue.is_empty():
			var cur: StringName = queue.pop_front()
			comp.append(cur)
			for lnk in station_links:
				if lnk["from"] == cur and not visited.has(lnk["to"]):
					visited[lnk["to"]] = true
					queue.append(lnk["to"])
				elif lnk["to"] == cur and not visited.has(lnk["from"]):
					visited[lnk["from"]] = true
					queue.append(lnk["from"])

		var ordered: Array[StringName] = []
		var in_deg_map: Dictionary = {}
		for sn in comp:
			in_deg_map[sn] = 0
		for lnk in station_links:
			if lnk["from"] in comp and lnk["to"] in comp:
				in_deg_map[lnk["to"]] = int(in_deg_map[lnk["to"]]) + 1

		var start_node: StringName = comp[0]
		for sn in comp:
			if int(in_deg_map[sn]) == 0:
				start_node = sn
				break

		var cur_n: StringName = start_node
		while cur_n != &"" and not (cur_n in ordered):
			ordered.append(cur_n)
			var next_n: StringName = &""
			for lnk in station_links:
				if lnk["from"] == cur_n and not (lnk["to"] in ordered):
					next_n = lnk["to"]
					break
			cur_n = next_n

		for sn in comp:
			if not (sn in ordered):
				ordered.append(sn)

		var is_train_route := (String(nodes[ordered[0]].get_meta("node_kind")) == "train_station")
		var route_sum := 0.0
		var route_item_types := 0

		if is_train_route:
			var max_plats := 1
			for sn in ordered:
				max_plats = maxi(max_plats, int(nodes[sn].get_meta("platforms_count", 1)))

			var plat_total_rate: Array[float] = []
			var plat_item_key: Array[String] = []
			plat_total_rate.resize(max_plats)
			plat_total_rate.fill(0.0)
			plat_item_key.resize(max_plats)
			plat_item_key.fill("")

			for sn in ordered:
				var bp: Dictionary = station_local_in[sn]["by_plat"]
				for p_idx in bp.keys():
					var idx := int(p_idx)
					if idx < max_plats:
						var p_info: Dictionary = bp[p_idx]
						var it_name := String(p_info["item"])
						if it_name != "":
							if plat_item_key[idx] == "" or plat_item_key[idx] == it_name:
								plat_item_key[idx] = it_name
								plat_total_rate[idx] += float(p_info["rate"])

			for r in plat_total_rate:
				route_sum += r
			for ik in plat_item_key:
				if ik != "":
					route_item_types += 1

			# Step 1: Calculate how much each station takes and how much remains globally on the route
			var plat_rem := plat_total_rate.duplicate()
			var taken_per_station: Dictionary = {}
			var avail_before_station: Dictionary = {}
			for sn in ordered:
				taken_per_station[sn] = {}
				avail_before_station[sn] = {}
				var st_node: GraphNode = nodes[sn]
				var p_cnt := int(st_node.get_meta("platforms_count", 1))
				var dem_arr: Array = demanded_out[sn]
				for p_idx in range(p_cnt):
					var avail_now: float = plat_rem[p_idx]
					var dem := float(dem_arr[p_idx]) if p_idx < dem_arr.size() else 0.0
					var taken := clampf(dem, 0.0, avail_now)
					plat_rem[p_idx] = maxf(0.0, avail_now - taken)
					taken_per_station[sn][p_idx] = taken
					avail_before_station[sn][p_idx] = avail_now

			# Step 2: Assign calculated rates to station metadata
			for sn in ordered:
				var st_node: GraphNode = nodes[sn]
				var p_cnt := int(st_node.get_meta("platforms_count", 1))
				var cur_items: Array = st_node.get_meta("station_out_items", [])
				var new_items: Array = []
				var st_total_view: Dictionary = {}
				var st_avail_view: Dictionary = {}
				var st_taken: Dictionary = {}
				var st_leftover: Dictionary = {}
				for p_idx in range(p_cnt):
					var ikey := plat_item_key[p_idx] if p_idx < plat_item_key.size() else ""
					new_items.append(ikey)
					if ikey != "":
						var slot_key := "%s#%d" % [ikey, p_idx]
						var tkn: float = float(taken_per_station[sn].get(p_idx, 0.0))
						var global_free: float = plat_rem[p_idx]
						st_total_view[slot_key] = plat_total_rate[p_idx]
						st_avail_view[slot_key] = tkn + global_free
						st_taken[slot_key] = tkn
						st_leftover[slot_key] = global_free
				st_node.set_meta("station_total_in", st_total_view)
				st_node.set_meta("station_avail", st_avail_view)
				st_node.set_meta("station_taken", st_taken)
				st_node.set_meta("station_leftover", st_leftover)
				if cur_items != new_items:
					st_node.set_meta("station_out_items", new_items)
					if g.has_meta("main_ref") and is_instance_valid(g.get_meta("main_ref")):
						g.get_meta("main_ref").builder.rebuild_transport_station_rows(g, st_node)
		else:
			var route_total_pool: Dictionary = {}
			for sn in ordered:
				var loc: Dictionary = station_local_in[sn]["by_item"]
				for ik in loc.keys():
					route_total_pool[ik] = float(route_total_pool.get(ik, 0.0)) + float(loc[ik])

			for ik in route_total_pool.keys():
				route_sum += float(route_total_pool[ik])
			route_item_types = route_total_pool.size()

			var remaining_pool := route_total_pool.duplicate()
			var all_route_items: Array = route_total_pool.keys()
			all_route_items.sort()

			var taken_per_station: Dictionary = {}
			for sn in ordered:
				taken_per_station[sn] = {}
				var st_node: GraphNode = nodes[sn]
				var cur_items: Array = st_node.get_meta("station_out_items", [])
				var dem_arr: Array = demanded_out[sn]
				for ikey in all_route_items:
					var avail_now := float(remaining_pool.get(ikey, 0.0))
					var old_port := cur_items.find(ikey)
					var dem := float(dem_arr[old_port]) if (old_port != -1 and old_port < dem_arr.size()) else 0.0
					var taken := clampf(dem, 0.0, avail_now)
					remaining_pool[ikey] = maxf(0.0, avail_now - taken)
					taken_per_station[sn][ikey] = taken

			for sn in ordered:
				var st_node: GraphNode = nodes[sn]
				var cur_items: Array = st_node.get_meta("station_out_items", [])
				var new_items := all_route_items.duplicate()
				for conn in g.get_connection_list():
					var fn: StringName = conn.get("from_node", conn.get("from", ""))
					var fp := int(conn["from_port"])
					if fn == sn and fp < cur_items.size():
						var old_it := String(cur_items[fp])
						if old_it != "" and not (old_it in new_items):
							new_items.append(old_it)
				new_items.sort()

				var st_total_view: Dictionary = {}
				var st_avail_view: Dictionary = {}
				var st_taken: Dictionary = {}
				var st_leftover: Dictionary = {}
				for ikey in new_items:
					var tot_route := float(route_total_pool.get(ikey, 0.0))
					var tkn := float(taken_per_station[sn].get(ikey, 0.0))
					var global_free := float(remaining_pool.get(ikey, 0.0))
					st_total_view[ikey] = tot_route
					st_avail_view[ikey] = tkn + global_free
					st_taken[ikey] = tkn
					st_leftover[ikey] = global_free

				st_node.set_meta("station_total_in", st_total_view)
				st_node.set_meta("station_avail", st_avail_view)
				st_node.set_meta("station_taken", st_taken)
				st_node.set_meta("station_leftover", st_leftover)
				if cur_items != new_items:
					st_node.set_meta("station_out_items", new_items)
					if g.has_meta("main_ref") and is_instance_valid(g.get_meta("main_ref")):
						g.get_meta("main_ref").builder.rebuild_transport_station_rows(g, st_node)

		for lnk in station_links:
			if lnk["from"] in comp:
				var w_key := "%s:%d->%s:%d" % [lnk["from"], lnk["fp"], lnk["to"], lnk["tp"]]
				wire_flows[w_key] = {
					"rate": route_sum,
					"item": "__station_route__",
					"is_station_link": true,
					"item_count": route_item_types
				}
