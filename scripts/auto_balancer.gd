class_name AutoBalancer
extends RefCounted

var main_ctrl: GraphEdit

func _init(p_main: GraphEdit) -> void:
	main_ctrl = p_main

func auto_balance_node(_g: GraphEdit, node: GraphNode) -> void:
	if not is_instance_valid(node) or bool(node.get_meta("is_locked", false)):
		return
	main_ctrl.recalculate_all()
	var inputs: Array = main_ctrl.db.recipes[node.get_meta("recipe_id")]["inputs"]
	var supplied: Array = node.get_meta("last_supplied", [])
	var wired: Array = node.get_meta("last_has_wire", [])
	var clk := float(node.get_meta("clock")) / 100.0
	if inputs.is_empty() or supplied.size() < inputs.size():
		return
	var max_possible := INF
	var found_active_input := false
	for i in range(inputs.size()):
		var is_wired: bool = bool(wired[i]) if i < wired.size() else (float(supplied[i]) > 0.0)
		var base_rate := float(inputs[i]["rate"]) * clk
		if is_wired and float(supplied[i]) > 0.0001 and base_rate > 0.0:
			max_possible = minf(max_possible, float(supplied[i]) / base_rate)
			found_active_input = true
	if not found_active_input:
		for i in range(inputs.size()):
			var base_rate := float(inputs[i]["rate"]) * clk
			if float(supplied[i]) > 0.0001 and base_rate > 0.0:
				max_possible = minf(max_possible, float(supplied[i]) / base_rate)
				found_active_input = true
	if found_active_input and max_possible > 0.0 and max_possible != INF:
		var spin: SpinBox = node.get_meta("spinbox")
		spin.value = ceilf(max_possible) if main_ctrl.settings.ceil_machines else snappedf(max_possible, 0.0001)

func auto_balance_node_to_demand(_g: GraphEdit, node: GraphNode) -> void:
	if not is_instance_valid(node) or bool(node.get_meta("is_locked", false)):
		return
	main_ctrl.recalculate_all()
	var outputs: Array = main_ctrl.db.recipes[node.get_meta("recipe_id")]["outputs"]
	var demanded: Array = node.get_meta("last_demanded", [])
	var clk := float(node.get_meta("clock")) / 100.0
	var pur := float(node.get_meta("purity", 1.0))
	var mk_mult = main_ctrl.solver.get_miner_mk_mult(node)
	var sloop_mult = main_ctrl.solver.get_somersloop_mult(node)
	if outputs.is_empty() or demanded.is_empty():
		return
	var required_machines := 0.0
	for i in range(mini(outputs.size(), demanded.size())):
		var out_rate = float(outputs[i]["rate"]) * clk * pur * mk_mult * sloop_mult
		if out_rate > 0.0 and float(demanded[i]) > 0.0:
			required_machines = maxf(required_machines, float(demanded[i]) / out_rate)
	if required_machines > 0.0:
		var spin: SpinBox = node.get_meta("spinbox")
		spin.value = ceilf(required_machines) if main_ctrl.settings.ceil_machines else snappedf(required_machines, 0.0001)

func auto_balance_chain_upstream(g: GraphEdit, start_node: GraphNode) -> void:
	if not is_instance_valid(g) or not is_instance_valid(start_node):
		return
	main_ctrl._push_undo_state()
	main_ctrl.recalculate_all()
	var conns := g.get_connection_list()
	var queue: Array[GraphNode] = [start_node]
	var visited_steps: Dictionary = {}
	var guard := 0
	while not queue.is_empty() and guard < 250:
		guard += 1
		var cur: GraphNode = queue.pop_front()
		if not is_instance_valid(cur):
			continue
		for c in conns:
			var fn: StringName = c.get("from_node", c.get("from", ""))
			var tn: StringName = c.get("to_node", c.get("to", ""))
			if tn != cur.name:
				continue
			var src := g.get_node_or_null(NodePath(fn)) as GraphNode
			if not is_instance_valid(src) or src == start_node:
				continue
			var is_src_locked := bool(src.get_meta("is_locked", false))
			var skind := String(src.get_meta("node_kind", ""))
			if not is_src_locked:
				if skind == "machine":
					auto_balance_node_to_demand(g, src)
				elif skind == "receiver":
					main_ctrl.recalculate_all()
					var int_d := float(src.get_meta("int_demand", 0.0))
					if int_d > 0.0:
						src.set_meta("planned_rate", snappedf(int_d, 0.01))
						if src.has_meta("plan_spin"):
							(src.get_meta("plan_spin") as SpinBox).set_value_no_signal(snappedf(int_d, 0.01))
				else:
					main_ctrl.recalculate_all()
			else:
				main_ctrl.recalculate_all()
			var visits := int(visited_steps.get(src.name, 0))
			if visits < 6 and not (src in queue):
				visited_steps[src.name] = visits + 1
				queue.append(src)
	main_ctrl.recalculate_all()

func auto_balance_chain_downstream(g: GraphEdit, start_node: GraphNode) -> void:
	if not is_instance_valid(g) or not is_instance_valid(start_node):
		return
	main_ctrl._push_undo_state()
	main_ctrl.recalculate_all()
	var conns := g.get_connection_list()
	var queue: Array[GraphNode] = [start_node]
	var visited_steps: Dictionary = {}
	var guard := 0
	while not queue.is_empty() and guard < 250:
		guard += 1
		var cur: GraphNode = queue.pop_front()
		if not is_instance_valid(cur):
			continue
		for c in conns:
			var fn: StringName = c.get("from_node", c.get("from", ""))
			var tn: StringName = c.get("to_node", c.get("to", ""))
			if fn != cur.name:
				continue
			var dst := g.get_node_or_null(NodePath(tn)) as GraphNode
			if not is_instance_valid(dst) or dst == start_node:
				continue
			var is_dst_locked := bool(dst.get_meta("is_locked", false))
			var dkind := String(dst.get_meta("node_kind", ""))
			if not is_dst_locked:
				if dkind == "machine":
					auto_balance_node(g, dst)
				elif dkind in ["transmitter", "container", "depot", "awesome_sink"]:
					main_ctrl.recalculate_all()
					var sup: Array = dst.get_meta("last_supplied", [0.0])
					var s_val := float(sup[0]) if sup.size() > 0 else 0.0
					if s_val > 0.0:
						dst.set_meta("planned_rate", snappedf(s_val, 0.01))
						if dst.has_meta("plan_spin"):
							(dst.get_meta("plan_spin") as SpinBox).set_value_no_signal(snappedf(s_val, 0.01))
				else:
					main_ctrl.recalculate_all()
			else:
				main_ctrl.recalculate_all()
			var visits := int(visited_steps.get(dst.name, 0))
			if visits < 6 and not (dst in queue):
				visited_steps[dst.name] = visits + 1
				queue.append(dst)
	main_ctrl.recalculate_all()

func group_selected_to_factory() -> void:
	var g = main_ctrl.active_graph
	var builder = main_ctrl.builder
	var db = main_ctrl.db
	var solver = main_ctrl.solver
	var i18n = main_ctrl.i18n
	var groupable_kinds := ["machine", "splitter", "even_splitter", "prop_splitter", "manual_splitter", "reroute", "container", "depot", "awesome_sink"]
	var selected_nodes: Array[GraphNode] = []
	var selected_names: Dictionary = {}
	var center := Vector2.ZERO

	for ch in g.get_children():
		if ch is GraphNode and ch.selected and ch.get_meta("node_kind", "") in groupable_kinds:
			selected_nodes.append(ch)
			selected_names[ch.name] = ch
			center += ch.position_offset
	if selected_nodes.is_empty():
		return

	main_ctrl._push_undo_state()
	center /= float(selected_nodes.size())
	var f_node = builder.spawn_factory(g, center, i18n.t("sub_factory_name") if g != main_ctrl else i18n.t("grouped_factory_name"))
	var fid: String = f_node.get_meta("factory_id")
	var f_graph: GraphEdit = main_ctrl.factory_graphs[fid]
	var old_conns = g.get_connection_list()
	var name_map: Dictionary = {}

	for old_n in selected_nodes:
		var kind: String = old_n.get_meta("node_kind")
		var new_pos := old_n.position_offset - center + Vector2(300, 200)
		var new_n: GraphNode = null
		if kind == "machine":
			var r_id: String = old_n.get_meta("recipe_id")
			new_n = builder.spawn_machine(f_graph, r_id, new_pos)
			(new_n.get_meta("spinbox") as SpinBox).value = float(old_n.get_meta("machines"))
			(new_n.get_meta("clk_spinbox") as SpinBox).value = float(old_n.get_meta("clock"))
			var pur := float(old_n.get_meta("purity", 1.0))
			new_n.set_meta("purity", pur)
			if new_n.has_meta("pur_opt"):
				(new_n.get_meta("pur_opt") as OptionButton).selected = 0 if pur < 0.75 else (2 if pur > 1.5 else 1)
			var mk_lvl := int(old_n.get_meta("miner_mk", 1))
			new_n.set_meta("miner_mk", mk_lvl)
			if new_n.has_meta("mk_opt"):
				(new_n.get_meta("mk_opt") as OptionButton).selected = mk_lvl - 1
			if new_n.has_meta("b_lbl") and db.recipes[r_id].get("has_mk_tiers", false):
				(new_n.get_meta("b_lbl") as Label).text = "%s • 60s" % db.get_building_display_name("miner-mk%d" % mk_lvl, "Miner MK%d" % mk_lvl)
			var s_count := int(old_n.get_meta("somersloops", 0))
			new_n.set_meta("somersloops", s_count)
			if new_n.has_meta("sloop_opt"):
				(new_n.get_meta("sloop_opt") as OptionButton).selected = s_count
		elif kind == "reroute":
			new_n = builder.spawn_reroute_node(f_graph, String(old_n.get_meta("item", "iron-ore")), new_pos)
		elif kind in ["splitter", "even_splitter", "prop_splitter"]:
			new_n = builder.spawn_splitter(f_graph, String(old_n.get_meta("item", "iron-ore")), new_pos, kind)
		elif kind == "manual_splitter":
			new_n = builder.spawn_manual_splitter(f_graph, String(old_n.get_meta("item", "iron-ore")), new_pos)
			new_n.set_meta("manual_overrides", (old_n.get_meta("manual_overrides", [false, false, false]) as Array).duplicate())
			new_n.set_meta("manual_rates", (old_n.get_meta("manual_rates", [0.0, 0.0, 0.0]) as Array).duplicate())
		elif kind in ["container", "depot", "awesome_sink"]:
			new_n = builder.spawn_storage_sink_node(f_graph, kind, String(old_n.get_meta("item", "iron-ore")), new_pos)
			var p_rate := float(old_n.get_meta("planned_rate", 60.0))
			new_n.set_meta("planned_rate", p_rate)
			if new_n.has_meta("plan_spin"):
				(new_n.get_meta("plan_spin") as SpinBox).set_value_no_signal(p_rate)
		if new_n != null:
			builder.set_node_built_state(new_n, bool(old_n.get_meta("is_built", false)))
			builder.set_node_locked_state(new_n, bool(old_n.get_meta("is_locked", false)))
			name_map[old_n.name] = new_n

	var ext_in_conns: Array = []
	var ext_out_conns: Array = []
	var rx_by_item: Dictionary = {}
	var tx_by_item: Dictionary = {}
	var tx_rate_by_item: Dictionary = {}

	for c in old_conns:
		var fn: StringName = c.get("from_node", c.get("from", ""))
		var tn: StringName = c.get("to_node", c.get("to", ""))
		var fp := int(c["from_port"])
		var tp := int(c["to_port"])
		var f_in := selected_names.has(fn)
		var t_in := selected_names.has(tn)
		if f_in and t_in:
			f_graph.connect_node(name_map[fn].name, fp, name_map[tn].name, tp)
		elif not f_in and t_in:
			var dst_node: GraphNode = name_map[tn]
			var item_key = solver.get_node_input_item(dst_node, tp)
			var rx: GraphNode
			if rx_by_item.has(item_key):
				rx = rx_by_item[item_key]
			else:
				rx = builder.spawn_io_node(f_graph, "receiver", item_key, dst_node.position_offset - Vector2(340, 0))
				rx_by_item[item_key] = rx
			f_graph.connect_node(rx.name, 0, dst_node.name, tp)
			ext_in_conns.append({"from_node": fn, "from_port": fp, "rx": rx})
		elif f_in and not t_in:
			var src_node: GraphNode = name_map[fn]
			var item_key = solver.get_node_output_item(src_node, fp)
			var tx: GraphNode
			if tx_by_item.has(item_key):
				tx = tx_by_item[item_key]
			else:
				tx = builder.spawn_io_node(f_graph, "transmitter", item_key, src_node.position_offset + Vector2(380, 0))
				tx_by_item[item_key] = tx
				tx_rate_by_item[item_key] = 0.0
			var out_rate = solver.get_node_output_rate(src_node, fp)
			tx_rate_by_item[item_key] = float(tx_rate_by_item[item_key]) + out_rate
			if float(tx_rate_by_item[item_key]) > 0.0 and tx.has_meta("plan_spin"):
				(tx.get_meta("plan_spin") as SpinBox).value = float(tx_rate_by_item[item_key])
			f_graph.connect_node(src_node.name, fp, tx.name, 0)
			ext_out_conns.append({"to_node": tn, "to_port": tp, "tx": tx})

	for old_n in selected_nodes:
		main_ctrl.remove_node_connections(g, old_n.name)
		g.remove_child(old_n)
		old_n.queue_free()

	builder.sync_factory_ports(fid)
	await main_ctrl.get_tree().process_frame

	var receivers: Array = f_node.get_meta("receivers", [])
	var transmitters: Array = f_node.get_meta("transmitters", [])
	for ec in ext_in_conns:
		var port_idx := receivers.find(ec["rx"])
		if port_idx != -1 and g.has_node(NodePath(String(ec["from_node"]))):
			g.connect_node(ec["from_node"], ec["from_port"], f_node.name, port_idx)
	for ec in ext_out_conns:
		var port_idx := transmitters.find(ec["tx"])
		if port_idx != -1 and g.has_node(NodePath(String(ec["to_node"]))):
			g.connect_node(f_node.name, port_idx, ec["to_node"], ec["to_port"])

	main_ctrl.recalculate_all()
