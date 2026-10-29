class_name GraphVisualUpdater
extends RefCounted

var solver: FactorySolver
var db: AppDB
var settings: AppSettings
var i18n: AppI18n

func _init(p_solver: FactorySolver, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	solver = p_solver
	db = p_db
	settings = p_settings
	i18n = p_i18n

func update_visuals(g: GraphEdit) -> Dictionary:
	var graph_used_mw := 0.0
	var graph_gen_mw := 0.0
	var is_compact := settings.compact_ui
	var unit_m := "" if is_compact else i18n.t("unit_per_min")

	for ch in g.get_children():
		if not (is_instance_valid(ch) and not ch.is_queued_for_deletion() and ch is GraphNode and ch.has_meta("node_kind")):
			continue
		var node: GraphNode = ch
		var kind: String = node.get_meta("node_kind")
		var sup: Array = node.get_meta("last_supplied", [])

		if g.has_meta("main_ref") and is_instance_valid(g.get_meta("main_ref")):
			g.get_meta("main_ref").builder.apply_compact_mode(node, is_compact)
		if node.has_meta("hdr_built_btn"):
			(node.get_meta("hdr_built_btn") as Button).tooltip_text = i18n.t("built_toggle_tooltip")
		if node.has_meta("hdr_del_btn"):
			(node.get_meta("hdr_del_btn") as Button).tooltip_text = i18n.t("delete_node_tooltip")
		if node.has_meta("hdr_btn_p") and node.has_meta("hex_primary"):
			(node.get_meta("hdr_btn_p") as Button).tooltip_text = i18n.tf("copy_prim_tooltip", [String(node.get_meta("hex_primary"))])
		if node.has_meta("hdr_btn_s") and node.has_meta("hex_secondary"):
			(node.get_meta("hdr_btn_s") as Button).tooltip_text = i18n.tf("copy_sec_tooltip", [String(node.get_meta("hex_secondary"))])

		if kind == "machine":
			var r_id: String = node.get_meta("recipe_id")
			if not db.recipes.has(r_id):
				continue
			var data: Dictionary = db.recipes[r_id]
			var is_gen: bool = data.get("is_generator", false)
			var m := float(node.get_meta("machines"))
			var clk := float(node.get_meta("clock")) / 100.0
			var in_labels: Array = node.get_meta("in_labels")
			var out_labels: Array = node.get_meta("out_labels")

			if is_compact:
				node.title = "%sx" % settings.fmt(m)
			elif data.get("is_miner", false):
				var pur := float(node.get_meta("purity", 1.0))
				var p_tag := i18n.t("markers_pure_opt") if pur > 1.5 else (i18n.t("markers_impure_opt") if pur < 0.75 else i18n.t("markers_normal_opt"))
				node.title = "%s (%s)" % [String(data["title"]), p_tag]
			else:
				node.title = String(data["title"])

			if node.has_meta("rec_title_lbl"):
				(node.get_meta("rec_title_lbl") as Label).text = String(data.get("raw_name", data["title"]))
			if node.has_meta("b_lbl"):
				var cycle_s := float(data.get("time", 60.0))
				var b_disp := String(data["building_name"])
				if data.get("has_mk_tiers", false):
					var mk_lvl := int(node.get_meta("miner_mk", 1))
					b_disp = db.get_building_display_name("miner-mk%d" % mk_lvl, "Miner MK%d" % mk_lvl)
				(node.get_meta("b_lbl") as Label).text = "%s • %ss" % [b_disp, settings.fmt(cycle_s)]
			if node.has_meta("m_lbl"):
				(node.get_meta("m_lbl") as Label).text = i18n.t("machines")
			if node.has_meta("clk_lbl"):
				(node.get_meta("clk_lbl") as Label).text = i18n.t("clock")
			if node.has_meta("auto_s_btn"):
				var asb: Button = node.get_meta("auto_s_btn")
				asb.text = i18n.t("auto_sup")
				asb.tooltip_text = i18n.t("auto_sup_tooltip")
			if node.has_meta("auto_d_btn"):
				var adb: Button = node.get_meta("auto_d_btn")
				adb.text = i18n.t("auto_dem")
				adb.tooltip_text = i18n.t("auto_dem_tooltip")
			if node.has_meta("oc_btn"):
				var ocb: Button = node.get_meta("oc_btn")
				ocb.text = i18n.t("oc_helper")
				ocb.tooltip_text = i18n.t("oc_title")
			if node.has_meta("mk_opt"):
				(node.get_meta("mk_opt") as OptionButton).tooltip_text = i18n.t("miner_mk_tooltip")
			if node.has_meta("pur_opt"):
				var po: OptionButton = node.get_meta("pur_opt")
				po.set_item_text(0, i18n.t("purity_impure"))
				po.set_item_text(1, i18n.t("purity_normal"))
				po.set_item_text(2, i18n.t("purity_pure"))
				po.tooltip_text = i18n.t("purity_tooltip")
			if node.has_meta("sloop_opt"):
				(node.get_meta("sloop_opt") as OptionButton).tooltip_text = i18n.t("somersloop_tooltip")

			for i in range(data["inputs"].size()):
				var in_d: Dictionary = data["inputs"][i]
				var ikey: String = in_d["item"]
				var need := float(in_d["rate"]) * m * clk
				var s := float(sup[i]) if i < sup.size() else 0.0
				var lbl: Label = in_labels[i]
				lbl.custom_minimum_size.x = 38 if is_compact else 130
				if is_compact:
					lbl.text = settings.fmt(need)
				else:
					lbl.text = "%s: %s / %s%s" % [db.get_item_display_name(ikey), settings.fmt(s), settings.fmt(need), unit_m]
				lbl.modulate = Color.LIGHT_GREEN if s >= need - 0.005 else (Color.GOLD if s > 0.0 else Color.SALMON)

			for i in range(data["outputs"].size()):
				var out_d: Dictionary = data["outputs"][i]
				var okey: String = out_d["item"]
				var prod := solver.get_node_output_rate(node, i)
				var lbl: Label = out_labels[i]
				lbl.custom_minimum_size.x = 38 if is_compact else 130
				lbl.text = settings.fmt(prod) if is_compact else "%s: %s%s" % [db.get_item_display_name(okey), settings.fmt(prod), unit_m]
				lbl.modulate = db.get_item_color(okey).lightened(0.35)

			var pwr_row: Control = node.get_meta("pwr_row")
			var pwr_lbl: Label = node.get_meta("pwr_label")
			pwr_row.visible = settings.show_power and (not is_compact)
			if is_gen:
				var gen := solver._calc_power_generated(node)
				graph_gen_mw += gen
				pwr_lbl.text = "⚡ +%s MW" % settings.fmt(gen)
				pwr_lbl.modulate = Color.SPRING_GREEN
			else:
				var mw := solver._calc_power_consumed(node)
				graph_used_mw += mw
				pwr_lbl.text = "⚡ %s MW" % settings.fmt(mw)
				pwr_lbl.modulate = Color(0.95, 0.55, 1.0) if int(node.get_meta("somersloops", 0)) > 0 else Color.GOLD

		elif kind == "factory":
			var receivers: Array = node.get_meta("receivers", [])
			var transmitters: Array = node.get_meta("transmitters", [])
			var in_labels: Array = node.get_meta("in_labels", [])
			var out_labels: Array = node.get_meta("out_labels", [])

			for i in range(mini(in_labels.size(), receivers.size())):
				var raw_rx = receivers[i]
				if not is_instance_valid(raw_rx) or raw_rx.is_queued_for_deletion():
					continue
				var r_node := raw_rx as GraphNode
				var lbl: Label = in_labels[i]
				var ikey: String = r_node.get_meta("item")
				var s := float(sup[i]) if i < sup.size() else 0.0
				var int_d := float(r_node.get_meta("int_demand", 0.0))
				var need := int_d if int_d > 0.0 else float(r_node.get_meta("planned_rate", 60.0))
				lbl.text = settings.fmt(need) if is_compact else ("%s: %s / %s%s" % [db.get_item_display_name(ikey), settings.fmt(s), settings.fmt(need), unit_m])
				lbl.modulate = Color.LIGHT_GREEN if s >= need - 0.005 else (Color.GOLD if s > 0.0 else Color.SALMON)

			for i in range(mini(out_labels.size(), transmitters.size())):
				var raw_tx = transmitters[i]
				if not is_instance_valid(raw_tx) or raw_tx.is_queued_for_deletion():
					continue
				var tx_node := raw_tx as GraphNode
				var lbl: Label = out_labels[i]
				var okey: String = tx_node.get_meta("item")
				var prod := float(tx_node.get_meta("tx_rate", 0.0))
				var exp_out := float(tx_node.get_meta("planned_rate", 60.0))
				lbl.text = settings.fmt(prod) if is_compact else ("%s: %s / %s%s" % [db.get_item_display_name(okey), settings.fmt(prod), settings.fmt(exp_out), unit_m])
				lbl.modulate = Color.LIGHT_GREEN if prod >= exp_out - 0.005 else (Color.GOLD if prod > 0.0 else Color.SALMON)

		elif kind == "receiver":
			node.title = "📥" if is_compact else i18n.t("receiver_in")
			if node.has_meta("plan_label"):
				(node.get_meta("plan_label") as Label).text = i18n.t("planned_in")
			if node.has_meta("plan_spin"):
				(node.get_meta("plan_spin") as SpinBox).suffix = i18n.t("unit_per_min")
			var ikey: String = node.get_meta("item")
			if node.has_meta("item_btn"):
				(node.get_meta("item_btn") as Button).text = "  " + db.get_item_display_name(ikey)
			var lbl: Label = node.get_meta("flow_label")
			lbl.custom_minimum_size.x = 38 if is_compact else 180
			var out_r := solver.get_node_output_rate(node, 0)
			var int_d := float(node.get_meta("int_demand", 0.0))
			var target_r := int_d if int_d > 0.0 else float(node.get_meta("planned_rate", 60.0))
			lbl.text = settings.fmt(out_r) if is_compact else ("%s: %s / %s%s" % [db.get_item_display_name(ikey), settings.fmt(out_r), settings.fmt(target_r), unit_m])
			lbl.modulate = Color.LIGHT_GREEN if out_r >= target_r - 0.005 else Color.GOLD

		elif kind == "transmitter":
			node.title = "📤" if is_compact else i18n.t("transmitter_out")
			if node.has_meta("plan_label"):
				(node.get_meta("plan_label") as Label).text = i18n.t("planned_out")
			if node.has_meta("plan_spin"):
				(node.get_meta("plan_spin") as SpinBox).suffix = i18n.t("unit_per_min")
			var okey: String = node.get_meta("item")
			if node.has_meta("item_btn"):
				(node.get_meta("item_btn") as Button).text = "  " + db.get_item_display_name(okey)
			var lbl: Label = node.get_meta("flow_label")
			lbl.custom_minimum_size.x = 38 if is_compact else 180
			var tx_r := float(node.get_meta("tx_rate", 0.0))
			var exp_r := float(node.get_meta("planned_rate", 60.0))
			lbl.text = settings.fmt(tx_r) if is_compact else ("%s: %s / %s%s" % [db.get_item_display_name(okey), settings.fmt(tx_r), settings.fmt(exp_r), unit_m])
			lbl.modulate = Color.LIGHT_GREEN if tx_r >= exp_r - 0.005 else (Color.GOLD if tx_r > 0.0 else Color.SALMON)

		elif kind in FactorySolver.SINK_STORAGE_KINDS:
			var t_key := "container_node"
			var l_key := "store_rate_lbl"
			if kind == "awesome_sink":
				t_key = "awesome_sink_node"
				l_key = "sink_rate_lbl"
			elif kind == "depot":
				t_key = "depot_node"
				l_key = "depot_rate_lbl"
			node.title = i18n.t(t_key)
			if node.has_meta("plan_label"):
				(node.get_meta("plan_label") as Label).text = i18n.t(l_key)
			if node.has_meta("plan_spin"):
				(node.get_meta("plan_spin") as SpinBox).suffix = i18n.t("unit_per_min")
			var ikey: String = node.get_meta("item")
			if node.has_meta("item_btn"):
				(node.get_meta("item_btn") as Button).text = "  " + db.get_item_display_name(ikey)
			var s := float(sup[0]) if sup.size() > 0 else 0.0
			var target_r := float(node.get_meta("planned_rate", 60.0))
			var lbl: Label = node.get_meta("flow_label")
			lbl.custom_minimum_size.x = 38 if is_compact else 140
			if is_compact:
				lbl.text = settings.fmt(s)
			elif kind == "awesome_sink":
				var pts_unit := db.get_item_sink_points(ikey)
				var pts_min := s * float(pts_unit)
				lbl.text = i18n.tf("sink_inline_fmt", [db.get_item_display_name(ikey), settings.fmt(s), settings.fmt(target_r), unit_m, settings.fmt(pts_min)])
			else:
				lbl.text = "%s: %s / %s%s" % [db.get_item_display_name(ikey), settings.fmt(s), settings.fmt(target_r), unit_m]
			lbl.modulate = Color.LIGHT_GREEN if s >= target_r - 0.005 else (Color.GOLD if s > 0.0 else Color.SALMON)
			graph_used_mw += float(node.get_meta("power_mw", 0.0))

		elif kind in FactorySolver.STANDARD_SPLITTERS:
			if kind == "reroute":
				node.title = i18n.t("reroute_short")
				var ikey_r: String = node.get_meta("item")
				var s_r := float(sup[0]) if sup.size() > 0 else 0.0
				if node.has_meta("item_btn"):
					var ib: Button = node.get_meta("item_btn")
					ib.text = settings.fmt(s_r) if is_compact else ("%s%s" % [settings.fmt(s_r), unit_m])
					ib.tooltip_text = "%s: %s%s" % [db.get_item_display_name(ikey_r), settings.fmt(s_r), i18n.t("unit_per_min")]
			else:
				var t_key := "splitter_node"
				if kind == "even_splitter":
					t_key = "even_splitter_node"
				elif kind == "prop_splitter":
					t_key = "prop_splitter_node"
				node.title = "🔀" if is_compact else i18n.t(t_key)
				var ikey: String = node.get_meta("item")
				if node.has_meta("item_btn"):
					(node.get_meta("item_btn") as Button).text = "  " + db.get_item_display_name(ikey)
				var s := float(sup[0]) if sup.size() > 0 else 0.0
				var in_l: Label = node.get_meta("in_label")
				var out_l: Label = node.get_meta("out_label")
				in_l.text = settings.fmt(s) if is_compact else ("%s: %s%s" % [i18n.t("in_short"), settings.fmt(s), unit_m])
				out_l.text = settings.fmt(s) if is_compact else ("%s: %s%s" % [i18n.t("out_short"), settings.fmt(s), unit_m])

		elif kind == "manual_splitter":
			node.title = i18n.t("manual_splitter_node")
			var ikey: String = node.get_meta("item")
			if node.has_meta("item_btn"):
				(node.get_meta("item_btn") as Button).text = "  " + db.get_item_display_name(ikey)
			if node.has_meta("reset_btn"):
				(node.get_meta("reset_btn") as Button).tooltip_text = i18n.t("manual_reset_tooltip")
			var s := float(sup[0]) if sup.size() > 0 else 0.0
			var in_l: Label = node.get_meta("in_label")
			in_l.text = settings.fmt(s) if is_compact else ("%s: %s%s" % [i18n.t("in_short"), settings.fmt(s), unit_m])

			var out_spins: Array = node.get_meta("out_spins", [])
			var out_tags: Array = node.get_meta("out_tags", [])
			var ovr: Array = node.get_meta("manual_overrides", [false, false, false])
			var act: Array = node.get_meta("actual_out_rates", [0.0, 0.0, 0.0])
			var man_rts: Array = node.get_meta("manual_rates", [0.0, 0.0, 0.0])
			node.set_meta("updating_spins", true)
			for i in range(mini(3, out_spins.size())):
				var sp: SpinBox = out_spins[i]
				var tg: Label = out_tags[i]
				var is_ovr := bool(ovr[i])
				tg.text = i18n.tf("manual_out_fmt", [i + 1])
				tg.modulate = Color.GOLD if is_ovr else Color(0.75, 0.88, 1.0)
				sp.suffix = unit_m if is_ovr else (" (" + i18n.t("manual_auto_tag") + ")")
				if not is_ovr:
					sp.set_value_no_signal(snappedf(float(act[i]), 0.01))
				else:
					sp.set_value_no_signal(float(man_rts[i]))
			node.set_meta("updating_spins", false)

		elif kind in FactorySolver.TRANSPORT_STATIONS:
			node.title = i18n.t("truck_station_node" if kind == "truck_station" else "train_station_node")
			graph_used_mw += 20.0 if kind == "truck_station" else 50.0
			if node.has_meta("station_mode_btn"):
				var m_btn: Button = node.get_meta("station_mode_btn")
				if is_instance_valid(m_btn):
					var cur_m := String(node.get_meta("station_mode", "pingpong"))
					m_btn.text = i18n.t("station_mode_loop" if cur_m == "loop" else "station_mode_pingpong")
					m_btn.tooltip_text = i18n.t("station_mode_tooltip")
			if kind == "truck_station" and node.has_meta("fuel_status_lbl"):
				var f_lbl: Label = node.get_meta("fuel_status_lbl")
				if is_instance_valid(f_lbl):
					var f_sup := float(sup[0]) if sup.size() > 0 else 0.0
					var f_need := float(node.get_meta("fuel_rate", 15.0))
					f_lbl.text = "%s/%s" % [settings.fmt(f_sup), settings.fmt(f_need)]
					f_lbl.modulate = Color.LIGHT_GREEN if f_sup >= f_need - 0.005 else (Color.GOLD if f_sup > 0.0 else Color.SALMON)

			var out_items: Array = node.get_meta("station_out_items", [])
			var out_labels: Array = node.get_meta("station_out_labels", [])
			var total_in_dict: Dictionary = node.get_meta("station_total_in", {})
			var taken_dict: Dictionary = node.get_meta("station_taken", {})
			var left_dict: Dictionary = node.get_meta("station_leftover", {})
			for i in range(mini(out_items.size(), out_labels.size())):
				var ikey: String = String(out_items[i])
				var lbl: Label = out_labels[i]
				if not is_instance_valid(lbl):
					continue
				if ikey == "":
					lbl.text = i18n.t("station_empty_cargo")
					lbl.modulate = Color(1, 1, 1, 0.45)
					continue
				var lookup_key := ("%s#%d" % [ikey, i]) if (kind == "train_station" and total_in_dict.has("%s#%d" % [ikey, i])) else ikey
				var tot := float(total_in_dict.get(lookup_key, 0.0))
				var tkn := float(taken_dict.get(lookup_key, 0.0))
				var lft := float(left_dict.get(lookup_key, 0.0))
				if is_compact:
					lbl.text = "%s | -%s | =%s" % [settings.fmt(tot), settings.fmt(tkn), settings.fmt(lft)]
				else:
					lbl.text = i18n.tf("station_row_fmt", [
						db.get_item_display_name(ikey),
						settings.fmt(tot),
						settings.fmt(tkn),
						settings.fmt(lft),
						unit_m
					])
				lbl.modulate = db.get_item_color(ikey).lightened(0.35)

		node.tooltip_text = build_node_tooltip(node)

	return {"consumed": graph_used_mw, "generated": graph_gen_mw}

func build_node_tooltip(node: GraphNode) -> String:
	var kind := String(node.get_meta("node_kind", ""))
	var full_u := i18n.t("unit_per_min")
	var sup: Array = node.get_meta("last_supplied", [])
	var lines: Array[String] = []

	if kind == "machine":
		var r_id := String(node.get_meta("recipe_id", ""))
		if not db.recipes.has(r_id):
			return ""
		var data: Dictionary = db.recipes[r_id]
		var m := float(node.get_meta("machines", 1.0))
		var clk := float(node.get_meta("clock", 100.0))
		lines.append("⚙ %s" % String(data.get("title", r_id)))
		lines.append("%s %s  |  %s %s%%" % [i18n.t("machines"), settings.fmt(m), i18n.t("clock"), settings.fmt(clk)])
		if bool(data.get("is_generator", false)):
			lines.append("⚡ +%s MW" % settings.fmt(solver._calc_power_generated(node)))
		else:
			lines.append("⚡ %s MW" % settings.fmt(solver._calc_power_consumed(node)))
		var ins: Array = data.get("inputs", [])
		if not ins.is_empty():
			lines.append("── %s ──" % i18n.t("in_short"))
			for i in range(ins.size()):
				var ikey := String(ins[i]["item"])
				var need := float(ins[i]["rate"]) * m * (clk / 100.0)
				var s := float(sup[i]) if i < sup.size() else 0.0
				lines.append("  • %s: %s / %s%s" % [db.get_item_display_name(ikey), settings.fmt(s), settings.fmt(need), full_u])
		var outs: Array = data.get("outputs", [])
		if not outs.is_empty():
			lines.append("── %s ──" % i18n.t("out_short"))
			for i in range(outs.size()):
				var okey := String(outs[i]["item"])
				var prod := solver.get_node_output_rate(node, i)
				lines.append("  • %s: %s%s" % [db.get_item_display_name(okey), settings.fmt(prod), full_u])
	elif kind in FactorySolver.SINK_STORAGE_KINDS:
		var ikey := String(node.get_meta("item", ""))
		var s := float(sup[0]) if sup.size() > 0 else 0.0
		var target_r := float(node.get_meta("planned_rate", 60.0))
		lines.append(node.title)
		lines.append("• %s: %s / %s%s" % [db.get_item_display_name(ikey), settings.fmt(s), settings.fmt(target_r), full_u])
		if kind == "awesome_sink":
			var pts_u := db.get_item_sink_points(ikey)
			lines.append(i18n.tf("sink_pts_fmt", [settings.fmt(s * float(pts_u)), pts_u]))
	elif kind in FactorySolver.STANDARD_SPLITTERS or kind == "manual_splitter" or kind in ["receiver", "transmitter"]:
		var ikey := String(node.get_meta("item", ""))
		var flow := solver.get_node_output_rate(node, 0) if kind != "transmitter" else float(node.get_meta("tx_rate", 0.0))
		lines.append("%s • %s (%s%s)" % [node.title, db.get_item_display_name(ikey), settings.fmt(flow), full_u])

	return "\n".join(lines)
