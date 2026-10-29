class_name GridPlannerView
extends Control

const PX_PER_FOUNDATION := 64.0
const SPLITTER_SIZE_F := Vector2(0.5, 0.5)
const LIFT_SIZE_F := Vector2(0.25, 0.25)
const SPLITTER_NODE_KINDS := ["splitter", "even_splitter", "prop_splitter", "manual_splitter"]
const LEFT_DOCK_W := 154.0

enum ToolMode { SELECT = 0, FOUNDATION = 1, PILLAR = 2, RULER = 3, BELT = 4, SPLITTER = 5, MERGER = 6, LIFT = 7 }

var placement_rot: int = 0
var user_logistics_counter: int = 1
var belt_builder: GridBeltBuilder
var saved_belts: Dictionary = {}

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n
var balancer_gen: GridBalancerGenerator
var renderer: GridRenderer

var cam_offset := Vector2(-280, -160)
var cam_zoom := 1.0
var is_panning := false

var expand_individual_machines := true
var auto_generate_splitters := true
var manhattan_wires := true
var show_elevation := true
var show_ghost_floor := true
var snap_step := 0.25

var current_floor: int = 0
var floor_window_top: int = 4
var visible_floor_rows: int = 5
var current_tool: int = ToolMode.SELECT
var foundation_style: int = 1

var filter_item_key: String = ""

var blocks: Dictionary = {}
var saved_positions: Dictionary = {}
var wire_links: Array = []

var selected_ids: Dictionary = {}
var dragging_id: String = ""
var drag_start_world_f := Vector2.ZERO
var drag_initial_positions: Dictionary = {}
var hovered_id: String = ""

var is_box_selecting := false
var box_select_start_s := Vector2.ZERO
var box_select_end_s := Vector2.ZERO
var is_painting_tiles := false
var is_erasing_tiles := false
var is_measuring := false
var ruler_start_f := Vector2.ZERO
var ruler_end_f := Vector2.ZERO
var last_mouse_world_f := Vector2.ZERO

var top_bar: PanelContainer
var tools_dock: PanelContainer
var left_dock: PanelContainer
var floor_btns_vbox: VBoxContainer
var bottom_hud: PanelContainer
var hud_label: Label
var bounds_label: Label
var _ui_refs: Dictionary = {}
var _tool_btns: Array[Button] = []

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n
	balancer_gen = GridBalancerGenerator.new(self, db, i18n)
	renderer = GridRenderer.new(self, db, settings, i18n)
	belt_builder = GridBeltBuilder.new(self, db, settings, i18n)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_top = 40
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

	_build_overlay_toolbar()
	_build_left_tools_dock()
	_build_left_layer_dock()
	_build_bottom_hud()
	resized.connect(_layout_docks)

func _make_panel_style(bg: Color, border: Color, radius: int = 7) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _style_grid_button(btn: Button, is_toggle: bool = false, align_left: bool = false) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	if align_left:
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.16, 0.21, 0.28, 0.95)
	normal_sb.border_color = Color(0.32, 0.42, 0.56, 0.80)
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(5)
	normal_sb.content_margin_left = 8
	normal_sb.content_margin_right = 8
	normal_sb.content_margin_top = 4
	normal_sb.content_margin_bottom = 4

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.21, 0.27, 0.36, 0.98)
	hover_sb.border_color = Color.html("#FAB757")

	var pressed_sb := normal_sb.duplicate() as StyleBoxFlat
	if is_toggle:
		pressed_sb.bg_color = Color(0.05, 0.07, 0.10, 0.98)
		pressed_sb.border_color = Color.html("#FAB757")
		pressed_sb.set_border_width_all(2)
	else:
		pressed_sb.bg_color = Color(0.08, 0.11, 0.16, 0.98)
		pressed_sb.border_color = Color.AQUAMARINE

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_font_size_override("font_size", 12)

func _update_toggle_visual(btn: Button, active_color: Color = Color.GOLD, inactive_color: Color = Color(0.86, 0.90, 0.96)) -> void:
	if btn == null:
		return
	btn.modulate = active_color if btn.button_pressed else inactive_color

func _layout_docks() -> void:
	var top_h := 40.0
	if top_bar != null:
		# Stretch top_bar across the entire screen width
		top_bar.position = Vector2.ZERO
		top_bar.custom_minimum_size = Vector2(size.x, top_h)
		top_bar.size = Vector2(size.x, top_h)
		top_h = maxf(40.0, top_bar.size.y)

	var start_y := top_h + 10.0
	var avail_h := maxf(320.0, size.y - start_y - 10.0)
	var gap := 8.0
	var half_h := floorf((avail_h - gap) * 0.5)

	if tools_dock != null:
		tools_dock.position = Vector2(14.0, start_y)
		tools_dock.custom_minimum_size = Vector2(LEFT_DOCK_W, half_h)
		tools_dock.size = Vector2(LEFT_DOCK_W, half_h)

	if left_dock != null:
		left_dock.position = Vector2(14.0, start_y + half_h + gap)
		left_dock.custom_minimum_size = Vector2(LEFT_DOCK_W, half_h)
		left_dock.size = Vector2(LEFT_DOCK_W, half_h)

	var new_floor_rows := clampi(int((half_h - 92.0) / 30.0), 3, 8)
	if new_floor_rows != visible_floor_rows:
		visible_floor_rows = new_floor_rows
		_rebuild_floor_dock_buttons()

	if bottom_hud != null:
		bottom_hud.position = Vector2(14.0 + LEFT_DOCK_W + 10.0, start_y)

func _build_overlay_toolbar() -> void:
	top_bar = PanelContainer.new()
	top_bar.position = Vector2.ZERO
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	bar_sb.border_color = Color(0.25, 0.55, 0.78, 0.80)
	bar_sb.border_width_bottom = 1
	bar_sb.content_margin_left = 14
	bar_sb.content_margin_right = 14
	bar_sb.content_margin_top = 5
	bar_sb.content_margin_bottom = 5
	top_bar.add_theme_stylebox_override("panel", bar_sb)
	add_child(top_bar)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 6)
	top_bar.add_child(hbox)

	var auto_f_btn := Button.new()
	_style_grid_button(auto_f_btn, false)
	auto_f_btn.modulate = Color.LIGHT_SKY_BLUE
	auto_f_btn.pressed.connect(_auto_fill_foundations_on_current_floor)
	auto_f_btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			_clear_tiles_on_current_floor()
	)
	hbox.add_child(auto_f_btn)
	_ui_refs["auto_f_btn"] = auto_f_btn

	var align_x_btn := Button.new()
	_style_grid_button(align_x_btn, false)
	align_x_btn.modulate = Color.AQUAMARINE
	align_x_btn.pressed.connect(func(): _align_selected_blocks(true))
	hbox.add_child(align_x_btn)
	_ui_refs["align_x_btn"] = align_x_btn

	var align_y_btn := Button.new()
	_style_grid_button(align_y_btn, false)
	align_y_btn.modulate = Color.AQUAMARINE
	align_y_btn.pressed.connect(func(): _align_selected_blocks(false))
	hbox.add_child(align_y_btn)
	_ui_refs["align_y_btn"] = align_y_btn

	var lock_btn := Button.new()
	_style_grid_button(lock_btn, false)
	lock_btn.modulate = Color.GOLD
	lock_btn.pressed.connect(_toggle_lock_on_active_blocks)
	hbox.add_child(lock_btn)
	_ui_refs["lock_btn"] = lock_btn

	var filter_btn := Button.new()
	_style_grid_button(filter_btn, false)
	filter_btn.modulate = Color.LIGHT_SKY_BLUE
	filter_btn.pressed.connect(func():
		main_ctrl.open_item_picker(func(chosen_item: String):
			set_item_filter(chosen_item)
		)
	)
	filter_btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			set_item_filter("")
	)
	hbox.add_child(filter_btn)
	_ui_refs["filter_btn"] = filter_btn

	hbox.add_child(VSeparator.new())

	var snap_lbl := Label.new()
	hbox.add_child(snap_lbl)
	_ui_refs["snap_lbl"] = snap_lbl

	var snap_opt := OptionButton.new()
	for i in range(4):
		snap_opt.add_item("", i)
	snap_opt.selected = 0
	var steps: Array[float] = [0.25, 0.125, 0.5, 1.0]
	snap_opt.item_selected.connect(func(idx: int):
		snap_step = steps[idx]
		queue_redraw()
	)
	hbox.add_child(snap_opt)
	_ui_refs["snap_opt"] = snap_opt

	hbox.add_child(VSeparator.new())

	var mode_chk := Button.new()
	mode_chk.toggle_mode = true
	mode_chk.button_pressed = expand_individual_machines
	_style_grid_button(mode_chk, true)
	_update_toggle_visual(mode_chk, Color.AQUAMARINE)
	mode_chk.toggled.connect(func(v: bool):
		expand_individual_machines = v
		_update_toggle_visual(mode_chk, Color.AQUAMARINE)
		sync_from_graph(main_ctrl.active_graph)
	)
	hbox.add_child(mode_chk)
	_ui_refs["mode_chk"] = mode_chk

	var sp_chk := Button.new()
	sp_chk.toggle_mode = true
	sp_chk.button_pressed = auto_generate_splitters
	_style_grid_button(sp_chk, true)
	_update_toggle_visual(sp_chk, Color.AQUAMARINE)
	sp_chk.toggled.connect(func(v: bool):
		auto_generate_splitters = v
		_update_toggle_visual(sp_chk, Color.AQUAMARINE)
		sync_from_graph(main_ctrl.active_graph)
	)
	hbox.add_child(sp_chk)
	_ui_refs["sp_chk"] = sp_chk

	var wire_chk := Button.new()
	wire_chk.toggle_mode = true
	wire_chk.button_pressed = manhattan_wires
	_style_grid_button(wire_chk, true)
	_update_toggle_visual(wire_chk, Color.AQUAMARINE)
	wire_chk.toggled.connect(func(v: bool):
		manhattan_wires = v
		_update_toggle_visual(wire_chk, Color.AQUAMARINE)
		queue_redraw()
	)
	hbox.add_child(wire_chk)
	_ui_refs["wire_chk"] = wire_chk

	var elev_btn := Button.new()
	elev_btn.toggle_mode = true
	elev_btn.button_pressed = show_elevation
	_style_grid_button(elev_btn, true)
	_update_toggle_visual(elev_btn, Color.KHAKI)
	elev_btn.toggled.connect(func(v: bool):
		show_elevation = v
		_update_toggle_visual(elev_btn, Color.KHAKI)
		queue_redraw()
	)
	hbox.add_child(elev_btn)
	_ui_refs["elev_btn"] = elev_btn

	hbox.add_child(VSeparator.new())

	var auto_place_btn := Button.new()
	_style_grid_button(auto_place_btn, false)
	auto_place_btn.pressed.connect(func():
		var gid: String = main_ctrl.active_graph.get_meta("graph_id", "world")
		if saved_positions.has(gid):
			var g_mem: Dictionary = saved_positions[gid]
			var to_remove: Array[String] = []
			for k in g_mem.keys():
				var ks := String(k)
				if not bool(g_mem[k].get("locked", false)) and not ks.begins_with("__usr_"):
					to_remove.append(ks)
			for ks in to_remove:
				g_mem.erase(ks)
		sync_from_graph(main_ctrl.active_graph)
	)
	hbox.add_child(auto_place_btn)
	_ui_refs["auto_place_btn"] = auto_place_btn

	var bar_spacer := Control.new()
	bar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(bar_spacer)

	bounds_label = Label.new()
	bounds_label.modulate = Color.AQUAMARINE
	hbox.add_child(bounds_label)

func _build_left_tools_dock() -> void:
	tools_dock = PanelContainer.new()
	tools_dock.position = Vector2(14, 50)
	tools_dock.custom_minimum_size = Vector2(LEFT_DOCK_W, 220)
	tools_dock.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.09, 0.13, 0.96), Color(0.3, 0.75, 0.95, 0.85), 8))
	add_child(tools_dock)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	tools_dock.add_child(outer_vbox)

	var hdr_lbl := Label.new()
	hdr_lbl.modulate = Color.AQUAMARINE
	hdr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(hdr_lbl)
	_ui_refs["tools_hdr"] = hdr_lbl

	outer_vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var tools_vbox := VBoxContainer.new()
	tools_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(tools_vbox)

	# Vertical list of Build Tools [1..8]
	var t_keys := [
		"grid_tool_select", "grid_tool_found", "grid_tool_pillar",
		"grid_tool_ruler", "grid_tool_belt", "grid_tool_splitter",
		"grid_tool_merger", "grid_tool_lift"
	]
	for i in range(t_keys.size()):
		var tb := Button.new()
		tb.toggle_mode = true
		tb.button_pressed = (i == 0)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 26)
		_style_grid_button(tb, true, true)
		_update_toggle_visual(tb, Color.GOLD)
		var mode_idx := i
		tb.pressed.connect(func(): _set_tool_mode(mode_idx))
		tools_vbox.add_child(tb)
		_tool_btns.append(tb)
		_ui_refs[t_keys[i]] = tb

	var belt_mode_btn := Button.new()
	belt_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	belt_mode_btn.custom_minimum_size = Vector2(0, 26)
	_style_grid_button(belt_mode_btn, false, true)
	belt_mode_btn.modulate = Color.AQUAMARINE
	belt_mode_btn.pressed.connect(func(): belt_builder.toggle_build_mode())
	outer_vbox.add_child(belt_mode_btn)
	_ui_refs["belt_mode_btn"] = belt_mode_btn

func _build_left_layer_dock() -> void:
	left_dock = PanelContainer.new()
	left_dock.position = Vector2(14, 300)
	left_dock.custom_minimum_size = Vector2(LEFT_DOCK_W, 220)
	left_dock.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.09, 0.13, 0.96), Color(0.3, 0.75, 0.95, 0.85), 8))
	add_child(left_dock)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	left_dock.add_child(vbox)

	var hdr_row := HBoxContainer.new()
	var hdr_lbl := Label.new()
	hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_lbl.modulate = Color.AQUAMARINE
	hdr_row.add_child(hdr_lbl)
	_ui_refs["layers_hdr"] = hdr_lbl

	var sc_up := Button.new()
	sc_up.text = "▲"
	sc_up.custom_minimum_size = Vector2(24, 22)
	_style_grid_button(sc_up, false)
	sc_up.pressed.connect(func():
		floor_window_top = mini(25, floor_window_top + 1)
		_rebuild_floor_dock_buttons()
	)
	hdr_row.add_child(sc_up)

	var sc_dn := Button.new()
	sc_dn.text = "▼"
	sc_dn.custom_minimum_size = Vector2(24, 22)
	_style_grid_button(sc_dn, false)
	sc_dn.pressed.connect(func():
		floor_window_top = maxi(2, floor_window_top - 1)
		_rebuild_floor_dock_buttons()
	)
	hdr_row.add_child(sc_dn)

	vbox.add_child(hdr_row)
	vbox.add_child(HSeparator.new())

	floor_btns_vbox = VBoxContainer.new()
	floor_btns_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	floor_btns_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(floor_btns_vbox)

	vbox.add_child(HSeparator.new())

	var ghost_chk := Button.new()
	ghost_chk.toggle_mode = true
	ghost_chk.button_pressed = show_ghost_floor
	ghost_chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_grid_button(ghost_chk, true, true)
	_update_toggle_visual(ghost_chk, Color.LIGHT_SKY_BLUE)
	ghost_chk.toggled.connect(func(v: bool):
		show_ghost_floor = v
		_update_toggle_visual(ghost_chk, Color.LIGHT_SKY_BLUE)
		queue_redraw()
	)
	vbox.add_child(ghost_chk)
	_ui_refs["ghost_chk"] = ghost_chk

	var mv_row := HBoxContainer.new()
	mv_row.add_theme_constant_override("separation", 4)
	var mv_up_btn := Button.new()
	mv_up_btn.text = "⬆ +1"
	mv_up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_grid_button(mv_up_btn, false)
	mv_up_btn.pressed.connect(func(): _move_active_block_floor(1))
	mv_row.add_child(mv_up_btn)
	_ui_refs["mv_up_btn"] = mv_up_btn

	var mv_dn_btn := Button.new()
	mv_dn_btn.text = "⬇ -1"
	mv_dn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_grid_button(mv_dn_btn, false)
	mv_dn_btn.pressed.connect(func(): _move_active_block_floor(-1))
	mv_row.add_child(mv_dn_btn)
	_ui_refs["mv_dn_btn"] = mv_dn_btn

	vbox.add_child(mv_row)

func _build_bottom_hud() -> void:
	bottom_hud = PanelContainer.new()
	bottom_hud.position = Vector2(14.0 + LEFT_DOCK_W + 10.0, 50.0)
	bottom_hud.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.08, 0.12, 0.92), Color(0.25, 0.55, 0.78, 0.7), 6))
	add_child(bottom_hud)

	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 12)
	hud_label.modulate = Color(0.85, 0.94, 1.0)
	bottom_hud.add_child(hud_label)
	refresh_translations()
	call_deferred("_layout_docks")

func _sync_toolbar_toggle_states() -> void:
	if _ui_refs.has("mode_chk"):
		var b: Button = _ui_refs["mode_chk"]
		b.set_pressed_no_signal(expand_individual_machines)
		_update_toggle_visual(b, Color.AQUAMARINE)
	if _ui_refs.has("sp_chk"):
		var b: Button = _ui_refs["sp_chk"]
		b.set_pressed_no_signal(auto_generate_splitters)
		_update_toggle_visual(b, Color.AQUAMARINE)
	if _ui_refs.has("wire_chk"):
		var b: Button = _ui_refs["wire_chk"]
		b.set_pressed_no_signal(manhattan_wires)
		_update_toggle_visual(b, Color.AQUAMARINE)
	if _ui_refs.has("elev_btn"):
		var b: Button = _ui_refs["elev_btn"]
		b.set_pressed_no_signal(show_elevation)
		_update_toggle_visual(b, Color.KHAKI)
	if _ui_refs.has("ghost_chk"):
		var b: Button = _ui_refs["ghost_chk"]
		b.set_pressed_no_signal(show_ghost_floor)
		_update_toggle_visual(b, Color.LIGHT_SKY_BLUE)

func set_item_filter(item_key: String) -> void:
	filter_item_key = item_key
	_update_filter_button_visuals()
	queue_redraw()

func _toggle_quick_filter_on_hovered() -> void:
	var target_id := dragging_id if dragging_id != "" else hovered_id
	if target_id == "" and selected_ids.size() == 1:
		target_id = String(selected_ids.keys()[0])
	if target_id != "" and blocks.has(target_id):
		var m_item := String(blocks[target_id].get("main_item", ""))
		if m_item != "" and filter_item_key != m_item:
			set_item_filter(m_item)
			return
	set_item_filter("")

func _update_filter_button_visuals() -> void:
	if not _ui_refs.has("filter_btn"):
		return
	var f_btn: Button = _ui_refs["filter_btn"]
	f_btn.tooltip_text = i18n.t("grid_filter_tip")
	if filter_item_key == "":
		f_btn.text = i18n.t("grid_filter_all")
		f_btn.icon = null
		f_btn.modulate = Color.LIGHT_SKY_BLUE
	else:
		f_btn.text = i18n.tf("grid_filter_fmt", [db.get_item_display_name(filter_item_key)])
		f_btn.icon = db.get_icon_texture(filter_item_key)
		f_btn.expand_icon = true
		f_btn.modulate = db.get_item_color(filter_item_key).lightened(0.35)

func does_block_match_filter(bid: String) -> bool:
	if filter_item_key == "" or not blocks.has(bid):
		return true
	var b: Dictionary = blocks[bid]
	if String(b.get("main_item", "")) == filter_item_key:
		return true
	for wl in wire_links:
		if (wl["from_id"] == bid or wl["to_id"] == bid) and String(wl.get("item", "")) == filter_item_key:
			return true
	if main_ctrl != null and is_instance_valid(main_ctrl.active_graph):
		var n_name := String(b.get("node_name", ""))
		var g_node := main_ctrl.active_graph.get_node_or_null(NodePath(n_name)) as GraphNode
		if is_instance_valid(g_node) and String(g_node.get_meta("node_kind", "")) == "machine":
			var r_id := String(g_node.get_meta("recipe_id", ""))
			if db.recipes.has(r_id):
				var r_data: Dictionary = db.recipes[r_id]
				for inp in r_data.get("inputs", []):
					if String(inp["item"]) == filter_item_key:
						return true
				for outp in r_data.get("outputs", []):
					if String(outp["item"]) == filter_item_key:
						return true
	return false

func _toggle_lock_on_active_blocks() -> void:
	var targets: Array[String] = []
	if not selected_ids.is_empty():
		for sid in selected_ids.keys():
			if blocks.has(sid):
				targets.append(String(sid))
	elif hovered_id != "" and blocks.has(hovered_id):
		targets.append(hovered_id)
	if targets.is_empty():
		return

	var should_lock := false
	for tid in targets:
		if not bool(blocks[tid].get("locked", false)):
			should_lock = true
			break

	var mem := _get_active_mem()
	for tid in targets:
		blocks[tid]["locked"] = should_lock
		if mem.has(tid):
			mem[tid]["locked"] = should_lock
	if dragging_id != "" and should_lock:
		dragging_id = ""
		drag_initial_positions.clear()
	_update_hud_text()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func _set_tool_mode(mode_idx: int) -> void:
	if current_tool == ToolMode.FOUNDATION and mode_idx == ToolMode.FOUNDATION:
		foundation_style = (foundation_style % 3) + 1
	current_tool = mode_idx
	if current_tool != ToolMode.BELT and belt_builder != null:
		belt_builder.cancel_active_belt()
	if current_tool != ToolMode.LIFT and belt_builder != null:
		belt_builder.cancel_pending_lift()
	for i in range(_tool_btns.size()):
		_tool_btns[i].set_pressed_no_signal(i == current_tool)
		_update_toggle_visual(_tool_btns[i], Color.GOLD)
	_update_belt_mode_button()
	is_measuring = false
	_update_hud_text()
	queue_redraw()

func _update_belt_mode_button() -> void:
	if not _ui_refs.has("belt_mode_btn") or belt_builder == null:
		return
	var bm_btn: Button = _ui_refs["belt_mode_btn"]
	bm_btn.visible = (current_tool == ToolMode.BELT)
	bm_btn.text = i18n.t("grid_belt_mode_straight" if belt_builder.belt_build_mode == "straight" else "grid_belt_mode_curve")
	bm_btn.tooltip_text = i18n.t("grid_belt_mode_tip")

func _get_floor_stats(fl: int) -> Dictionary:
	var m_count := 0
	var max_h := 0.0
	for bid in blocks.keys():
		var b: Dictionary = blocks[bid]
		if int(b.get("floor", 0)) == fl and not bool(b.get("exclude_from_footprint", false)):
			m_count += 1
			var h := db.get_building_height_m(String(b["b_name"]))
			max_h = maxf(max_h, h)
	var ceil_m := int(ceilf((max_h + 2.0) / 4.0)) * 4 if m_count > 0 else 0
	return {"count": m_count, "ceil_m": ceil_m}

func _rebuild_floor_dock_buttons() -> void:
	if floor_btns_vbox == null:
		return
	for ch in floor_btns_vbox.get_children():
		ch.queue_free()
	var rows := maxi(3, visible_floor_rows)
	if current_floor > floor_window_top:
		floor_window_top = current_floor
	elif current_floor < floor_window_top - (rows - 1):
		floor_window_top = current_floor + (rows - 1)

	for fl in range(floor_window_top, floor_window_top - rows, -1):
		var stats := _get_floor_stats(fl)
		var cnt: int = stats["count"]
		var is_cur := (fl == current_floor)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = is_cur
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 26)
		_style_grid_button(btn, true, true)

		var fl_tag := "P%d" % fl if fl >= 0 else "B%d" % absi(fl)
		if cnt > 0:
			btn.text = "%s   •  %d  (%dm)" % [fl_tag, cnt, int(stats["ceil_m"])]
			btn.modulate = Color.GOLD if is_cur else Color.AQUAMARINE
		else:
			btn.text = "%s   —" % fl_tag
			btn.modulate = Color.GOLD if is_cur else Color(0.70, 0.76, 0.84, 0.80)

		var target_fl := fl
		btn.pressed.connect(func():
			current_floor = target_fl
			selected_ids.clear()
			_update_floor_ui()
		)
		floor_btns_vbox.add_child(btn)

func _update_floor_ui() -> void:
	_sync_toolbar_toggle_states()
	_rebuild_floor_dock_buttons()
	_update_bounds_summary()
	_update_hud_text()
	_layout_docks()
	queue_redraw()

func _move_active_block_floor(delta_fl: int) -> void:
	if current_tool == ToolMode.LIFT and belt_builder != null and not belt_builder.pending_lift.is_empty():
		current_floor = clampi(current_floor + delta_fl, -5, 25)
		_update_floor_ui()
		return

	var targets: Array[String] = []
	if not selected_ids.is_empty():
		for sid in selected_ids.keys():
			var ks := String(sid)
			if blocks.has(ks) and not bool(blocks[ks].get("locked", false)) and not ks.begins_with("__usr_lift_"):
				targets.append(ks)
	elif dragging_id != "" and blocks.has(dragging_id) and not bool(blocks[dragging_id].get("locked", false)) and not dragging_id.begins_with("__usr_lift_"):
		targets.append(dragging_id)
	elif hovered_id != "" and blocks.has(hovered_id) and not bool(blocks[hovered_id].get("locked", false)) and not hovered_id.begins_with("__usr_lift_"):
		targets.append(hovered_id)

	if targets.is_empty():
		current_floor = clampi(current_floor + delta_fl, -5, 25)
		_update_floor_ui()
		return

	var gid: String = main_ctrl.active_graph.get_meta("graph_id", "world")
	var new_fl := current_floor
	for tid in targets:
		var b: Dictionary = blocks[tid]
		new_fl = clampi(int(b.get("floor", 0)) + delta_fl, -5, 25)
		b["floor"] = new_fl
		if saved_positions.has(gid) and saved_positions[gid].has(tid):
			saved_positions[gid][tid]["floor"] = new_fl
	current_floor = new_fl
	_update_floor_ui()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func refresh_translations() -> void:
	if _ui_refs.is_empty():
		return
	if _ui_refs.has("tools_hdr"):
		_ui_refs["tools_hdr"].text = i18n.t("grid_tools_hdr")
	_ui_refs["grid_tool_select"].text = i18n.t("grid_tool_select")
	_ui_refs["grid_tool_found"].text = i18n.t("grid_tool_found")
	_ui_refs["grid_tool_pillar"].text = i18n.t("grid_tool_pillar")
	_ui_refs["grid_tool_ruler"].text = i18n.t("grid_tool_ruler")
	if _ui_refs.has("grid_tool_belt"):
		_ui_refs["grid_tool_belt"].text = i18n.t("grid_tool_belt")
	if _ui_refs.has("grid_tool_splitter"):
		_ui_refs["grid_tool_splitter"].text = i18n.t("grid_tool_splitter")
	if _ui_refs.has("grid_tool_merger"):
		_ui_refs["grid_tool_merger"].text = i18n.t("grid_tool_merger")
	if _ui_refs.has("grid_tool_lift"):
		_ui_refs["grid_tool_lift"].text = i18n.t("grid_tool_lift")
	_update_belt_mode_button()
	_ui_refs["auto_f_btn"].text = i18n.t("grid_auto_found_btn")
	_ui_refs["auto_f_btn"].tooltip_text = i18n.t("grid_auto_found_tip")
	_ui_refs["align_x_btn"].text = i18n.t("grid_align_x_btn")
	_ui_refs["align_x_btn"].tooltip_text = i18n.t("grid_align_x_tip")
	_ui_refs["align_y_btn"].text = i18n.t("grid_align_y_btn")
	_ui_refs["align_y_btn"].tooltip_text = i18n.t("grid_align_y_tip")
	if _ui_refs.has("lock_btn"):
		_ui_refs["lock_btn"].text = i18n.t("grid_lock_btn")
		_ui_refs["lock_btn"].tooltip_text = i18n.t("grid_lock_tip")
	_update_filter_button_visuals()
	_ui_refs["snap_lbl"].text = i18n.t("grid_snap")
	var snap_opt: OptionButton = _ui_refs["snap_opt"]
	snap_opt.set_item_text(0, i18n.t("grid_snap_0"))
	snap_opt.set_item_text(1, i18n.t("grid_snap_1"))
	snap_opt.set_item_text(2, i18n.t("grid_snap_2"))
	snap_opt.set_item_text(3, i18n.t("grid_snap_3"))
	_ui_refs["mode_chk"].text = i18n.t("grid_indiv_machines")
	_ui_refs["sp_chk"].text = i18n.t("grid_true_balancers")
	_ui_refs["wire_chk"].text = i18n.t("grid_manhattan")
	_ui_refs["elev_btn"].text = i18n.t("grid_elev_btn")
	_ui_refs["layers_hdr"].text = i18n.t("grid_layers_hdr")
	_ui_refs["ghost_chk"].text = i18n.t("grid_ghost_btn")
	_ui_refs["ghost_chk"].tooltip_text = i18n.t("grid_ghost_tip")
	_ui_refs["mv_up_btn"].tooltip_text = i18n.t("grid_move_up_tip")
	_ui_refs["mv_dn_btn"].tooltip_text = i18n.t("grid_move_dn_tip")
	_ui_refs["auto_place_btn"].text = i18n.t("grid_reset_btn")
	if visible and main_ctrl != null and is_instance_valid(main_ctrl.active_graph):
		sync_from_graph(main_ctrl.active_graph)
	else:
		_update_floor_ui()

func _snap_vec(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, snap_step), snappedf(v.y, snap_step))

func _get_active_mem() -> Dictionary:
	if main_ctrl == null or not is_instance_valid(main_ctrl.active_graph):
		return {}
	var gid: String = main_ctrl.active_graph.get_meta("graph_id", "world")
	if not saved_positions.has(gid):
		saved_positions[gid] = {}
	return saved_positions[gid]

func _paint_tile_at(world_f: Vector2, erase: bool) -> void:
	var mem := _get_active_mem()
	if current_tool == ToolMode.FOUNDATION:
		var tx := int(floorf(world_f.x))
		var ty := int(floorf(world_f.y))
		var key := "__tile_%d_%d_%d" % [current_floor, tx, ty]
		if erase:
			mem.erase(key)
		else:
			mem[key] = {"pos_f": Vector2(tx, ty), "rot": foundation_style, "floor": current_floor}
	elif current_tool == ToolMode.PILLAR:
		var px := snappedf(world_f.x - 0.25, 0.5)
		var py := snappedf(world_f.y - 0.25, 0.5)
		var key := "__pil_%d_%s_%s" % [current_floor, str(px), str(py)]
		if erase:
			mem.erase(key)
		else:
			mem[key] = {"pos_f": Vector2(px, py), "rot": 10, "floor": current_floor}
	_update_bounds_summary()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func _auto_fill_foundations_on_current_floor() -> void:
	var mem := _get_active_mem()
	var min_f := Vector2(INF, INF)
	var max_f := Vector2(-INF, -INF)
	var count := 0
	for bid in blocks.keys():
		var b: Dictionary = blocks[bid]
		if int(b.get("floor", 0)) != current_floor or bool(b.get("exclude_from_footprint", false)):
			continue
		count += 1
		var p: Vector2 = b["pos_f"]
		var sz := _get_effective_size_f(b)
		min_f.x = minf(min_f.x, floorf(p.x) - 1.0)
		min_f.y = minf(min_f.y, floorf(p.y) - 1.0)
		max_f.x = maxf(max_f.x, ceilf(p.x + sz.x) + 1.0)
		max_f.y = maxf(max_f.y, ceilf(p.y + sz.y) + 1.0)
	if count == 0:
		return
	for tx in range(int(min_f.x), int(max_f.x)):
		for ty in range(int(min_f.y), int(max_f.y)):
			var key := "__tile_%d_%d_%d" % [current_floor, tx, ty]
			if not mem.has(key):
				mem[key] = {"pos_f": Vector2(tx, ty), "rot": 1, "floor": current_floor}
	for corner in [Vector2(min_f.x, min_f.y), Vector2(max_f.x - 0.5, min_f.y), Vector2(min_f.x, max_f.y - 0.5), Vector2(max_f.x - 0.5, max_f.y - 0.5)]:
		var pkey := "__pil_%d_%s_%s" % [current_floor, str(corner.x), str(corner.y)]
		mem[pkey] = {"pos_f": corner, "rot": 10, "floor": current_floor}
	_update_bounds_summary()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func _clear_tiles_on_current_floor() -> void:
	var mem := _get_active_mem()
	var to_erase: Array[String] = []
	for k in mem.keys():
		var ks := String(k)
		if (ks.begins_with("__tile_") or ks.begins_with("__pil_")) and int(mem[k].get("floor", 0)) == current_floor:
			to_erase.append(ks)
	for ks in to_erase:
		mem.erase(ks)
	_update_bounds_summary()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func _align_selected_blocks(horizontal_row: bool) -> void:
	var sel_list: Array[String] = []
	for sid in selected_ids.keys():
		var ks := String(sid)
		if blocks.has(ks) and int(blocks[ks].get("floor", 0)) == current_floor and not bool(blocks[ks].get("locked", false)) and not ks.begins_with("__usr_lift_"):
			sel_list.append(ks)
	if sel_list.size() < 2:
		return
	var mem := _get_active_mem()
	if horizontal_row:
		sel_list.sort_custom(func(a, b): return blocks[a]["pos_f"].x < blocks[b]["pos_f"].x)
		var base_y: float = _snap_vec(blocks[sel_list[0]]["pos_f"]).y
		var cur_x: float = _snap_vec(blocks[sel_list[0]]["pos_f"]).x
		for sid in sel_list:
			var b: Dictionary = blocks[sid]
			var sz := _get_effective_size_f(b)
			var new_p := _snap_vec(Vector2(cur_x, base_y))
			b["pos_f"] = new_p
			mem[sid]["pos_f"] = new_p
			cur_x += sz.x + snap_step
	else:
		sel_list.sort_custom(func(a, b): return blocks[a]["pos_f"].y < blocks[b]["pos_f"].y)
		var base_x: float = _snap_vec(blocks[sel_list[0]]["pos_f"]).x
		var cur_y: float = _snap_vec(blocks[sel_list[0]]["pos_f"]).y
		for sid in sel_list:
			var b: Dictionary = blocks[sid]
			var sz := _get_effective_size_f(b)
			var new_p := _snap_vec(Vector2(base_x, cur_y))
			b["pos_f"] = new_p
			mem[sid]["pos_f"] = new_p
			cur_y += sz.y + snap_step
	_update_bounds_summary()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func sync_from_graph(g: GraphEdit) -> void:
	balancer_gen.sync_from_graph(g)

func _register_block(bid: String, n_name: String, title: String, sub: String, b_name: String, main_item: String, primary_col: Color, secondary_col: Color, dims: Vector2, def_pos: Vector2, mem: Dictionary, exclude_footprint: bool, def_floor: int = 0, in_ports: int = 1, out_ports: int = 1) -> void:
	var pos_f := def_pos
	var rot := 0
	var fl := def_floor
	var is_locked := false
	if mem.has(bid):
		pos_f = mem[bid]["pos_f"]
		rot = int(mem[bid]["rot"])
		fl = int(mem[bid].get("floor", def_floor))
		is_locked = bool(mem[bid].get("locked", false))
	else:
		mem[bid] = {"pos_f": pos_f, "rot": rot, "floor": fl, "locked": false}

	blocks[bid] = {
		"id": bid,
		"node_name": n_name,
		"title": title,
		"sub": sub,
		"b_name": b_name,
		"main_item": main_item,
		"color": primary_col,
		"border_color": secondary_col,
		"pos_f": pos_f,
		"base_size_f": dims,
		"rot": rot,
		"floor": fl,
		"locked": is_locked,
		"in_ports": in_ports,
		"out_ports": out_ports,
		"exclude_from_footprint": exclude_footprint
	}

func _get_effective_size_f(b: Dictionary) -> Vector2:
	var s: Vector2 = b["base_size_f"]
	return Vector2(s.y, s.x) if (int(b["rot"]) % 2 == 1) else s

func _get_on_grid_bounds() -> Dictionary:
	var min_f := Vector2(INF, INF)
	var max_f := Vector2(-INF, -INF)
	var count := 0
	var sp_count := 0
	for bid in blocks.keys():
		var b: Dictionary = blocks[bid]
		if int(b.get("floor", 0)) != current_floor:
			continue
		if bool(b.get("exclude_from_footprint", false)):
			continue
		count += 1
		if String(b["b_name"]) in ["splitter", "merger", "lift_in", "lift_out"]:
			sp_count += 1
		var p: Vector2 = b["pos_f"]
		var sz := _get_effective_size_f(b)
		min_f.x = minf(min_f.x, floorf(p.x))
		min_f.y = minf(min_f.y, floorf(p.y))
		max_f.x = maxf(max_f.x, ceilf(p.x + sz.x))
		max_f.y = maxf(max_f.y, ceilf(p.y + sz.y))

	var mem := _get_active_mem()
	for k in mem.keys():
		var ks := String(k)
		if ks.begins_with("__tile_") and int(mem[k].get("floor", 0)) == current_floor:
			count += 1
			var tp: Vector2 = mem[k]["pos_f"]
			min_f.x = minf(min_f.x, tp.x)
			min_f.y = minf(min_f.y, tp.y)
			max_f.x = maxf(max_f.x, tp.x + 1.0)
			max_f.y = maxf(max_f.y, tp.y + 1.0)
	return {"valid": count > 0, "min_f": min_f, "max_f": max_f, "splitters": sp_count}

func _update_bounds_summary() -> void:
	if bounds_label == null:
		return
	var info := _get_on_grid_bounds()
	if not bool(info["valid"]):
		bounds_label.text = i18n.t("grid_bounds_zero")
		return
	var span: Vector2 = (info["max_f"] - info["min_f"]).ceil()
	var area := int(span.x * span.y)
	bounds_label.text = i18n.tf("grid_bounds_fmt", [
		int(span.x), int(span.y), int(span.x) * 8, int(span.y) * 8, area, int(info["splitters"])
	])

func _update_hud_text() -> void:
	if hud_label == null:
		return
	if current_tool == ToolMode.LIFT and belt_builder != null and not belt_builder.pending_lift.is_empty():
		hud_label.text = i18n.t("grid_lift_step2_hint")
		return
	var sn := _snap_vec(last_mouse_world_f)
	var txt := i18n.tf("grid_hud_cursor", [
		settings.fmt(sn.x), settings.fmt(sn.x * 8.0),
		settings.fmt(sn.y), settings.fmt(sn.y * 8.0),
		current_floor, selected_ids.size()
	])
	var target_id := dragging_id if dragging_id != "" else hovered_id
	if target_id != "" and blocks.has(target_id):
		var b: Dictionary = blocks[target_id]
		var sz := _get_effective_size_f(b)
		var h_m := int(db.get_building_height_m(String(b["b_name"])))
		var lock_str := i18n.t("grid_locked_tag") if bool(b.get("locked", false)) else ""
		txt += i18n.tf("grid_hud_block", [
			String(b["title"]) + lock_str,
			settings.fmt(sz.x), settings.fmt(sz.y),
			settings.fmt(sz.x * 8.0), settings.fmt(sz.y * 8.0),
			h_m, int(b["rot"]) * 90
		])
	hud_label.text = txt

func _world_f_to_screen(pos_f: Vector2) -> Vector2:
	return (pos_f * PX_PER_FOUNDATION) * cam_zoom - cam_offset

func _screen_to_world_f(screen_pos: Vector2) -> Vector2:
	return (screen_pos + cam_offset) / (PX_PER_FOUNDATION * cam_zoom)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			_set_tool_mode(ToolMode.SELECT)
			accept_event()
		elif event.keycode == KEY_2:
			_set_tool_mode(ToolMode.FOUNDATION)
			accept_event()
		elif event.keycode == KEY_3:
			_set_tool_mode(ToolMode.PILLAR)
			accept_event()
		elif event.keycode == KEY_4:
			_set_tool_mode(ToolMode.RULER)
			accept_event()
		elif event.keycode == KEY_5 or event.keycode == KEY_B:
			_set_tool_mode(ToolMode.BELT)
			accept_event()
		elif event.keycode == KEY_6:
			_set_tool_mode(ToolMode.SPLITTER)
			accept_event()
		elif event.keycode == KEY_7:
			_set_tool_mode(ToolMode.MERGER)
			accept_event()
		elif event.keycode == KEY_8 or event.keycode == KEY_V:
			_set_tool_mode(ToolMode.LIFT)
			accept_event()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selected_user_blocks()
			accept_event()
		elif event.keycode == KEY_T and current_tool == ToolMode.BELT:
			belt_builder.toggle_build_mode()
			accept_event()
		elif event.keycode == KEY_ESCAPE:
			if current_tool == ToolMode.BELT and not belt_builder.active_belt.is_empty():
				belt_builder.cancel_active_belt()
				accept_event()
			elif current_tool == ToolMode.LIFT and not belt_builder.pending_lift.is_empty():
				belt_builder.cancel_pending_lift()
				_update_hud_text()
				accept_event()
		elif event.keycode == KEY_G:
			_align_selected_blocks(not event.shift_pressed)
			accept_event()
		elif event.keycode == KEY_L:
			_toggle_lock_on_active_blocks()
			accept_event()
		elif event.keycode == KEY_F and not event.ctrl_pressed:
			_toggle_quick_filter_on_hovered()
			accept_event()
		elif event.keycode == KEY_R:
			if current_tool == ToolMode.BELT and not belt_builder.active_belt.is_empty():
				belt_builder.rotate_pole_direction()
				accept_event()
				return
			if current_tool == ToolMode.LIFT and not belt_builder.pending_lift.is_empty():
				belt_builder.pending_lift["out_rot"] = (int(belt_builder.pending_lift.get("out_rot", 0)) + 1) % 4
				queue_redraw()
				accept_event()
				return
			if current_tool in [ToolMode.SPLITTER, ToolMode.MERGER, ToolMode.LIFT] and hovered_id == "":
				placement_rot = (placement_rot + 1) % 4
				queue_redraw()
				accept_event()
				return
			if not selected_ids.is_empty():
				for sid in selected_ids.keys():
					if blocks.has(sid):
						_rotate_block(String(sid))
			else:
				var target_id := dragging_id if dragging_id != "" else hovered_id
				if target_id != "" and blocks.has(target_id):
					_rotate_block(target_id)
			accept_event()
		elif event.keycode == KEY_PAGEUP:
			_move_active_block_floor(1)
			accept_event()
		elif event.keycode == KEY_PAGEDOWN:
			_move_active_block_floor(-1)
			accept_event()

func _rotate_block(bid: String) -> void:
	if not blocks.has(bid):
		return
	var b: Dictionary = blocks[bid]
	if bool(b.get("locked", false)):
		return
	b["rot"] = (int(b["rot"]) + 1) % 4
	var gid: String = main_ctrl.active_graph.get_meta("graph_id", "world")
	saved_positions[gid][bid]["rot"] = b["rot"]
	_update_bounds_summary()
	_update_hud_text()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func _handle_lift_click_at(world_f: Vector2) -> void:
	if belt_builder == null:
		return
	if belt_builder.pending_lift.is_empty():
		var pos_f := belt_builder.snap_1m(world_f - LIFT_SIZE_F * 0.5)
		if belt_builder.is_lift_shaft_colliding(pos_f, current_floor, current_floor):
			return
		belt_builder.pending_lift = {
			"pos_f": pos_f,
			"start_floor": current_floor,
			"in_rot": placement_rot,
			"out_rot": placement_rot
		}
		_update_hud_text()
		queue_redraw()
	else:
		var start_fl := int(belt_builder.pending_lift["start_floor"])
		if current_floor == start_fl:
			return
		var pos_f: Vector2 = belt_builder.pending_lift["pos_f"]
		if belt_builder.is_lift_shaft_colliding(pos_f, start_fl, current_floor):
			return
		var in_rot := int(belt_builder.pending_lift.get("in_rot", placement_rot))
		var out_rot := int(belt_builder.pending_lift.get("out_rot", placement_rot))
		var mem := _get_active_mem()
		user_logistics_counter += 1
		var uid := "%d_%d" % [Time.get_ticks_msec(), user_logistics_counter]
		var in_id := "__usr_lift_in_%s" % uid
		var out_id := "__usr_lift_out_%s" % uid

		mem[in_id] = {
			"pos_f": pos_f,
			"rot": in_rot,
			"floor": start_fl,
			"target_floor": current_floor,
			"partner_id": out_id,
			"locked": true
		}
		mem[out_id] = {
			"pos_f": pos_f,
			"rot": out_rot,
			"floor": current_floor,
			"target_floor": start_fl,
			"partner_id": in_id,
			"locked": true
		}
		belt_builder.pending_lift.clear()
		_restore_user_logistics_blocks(mem)
		_update_bounds_summary()
		_update_hud_text()
		queue_redraw()
		if main_ctrl.autosave_mgr != null:
			main_ctrl.autosave_mgr.notify_interaction()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_unhandled_key_input(event)
		return

	if event is InputEventMouseButton:
		var wf := _screen_to_world_f(event.position)
		last_mouse_world_f = wf
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)
			return
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			return

		if current_tool == ToolMode.LIFT:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_handle_lift_click_at(wf)
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				if not belt_builder.pending_lift.is_empty():
					belt_builder.cancel_pending_lift()
					_update_hud_text()
					return
				var hit_l := _pick_block_at(event.position)
				if hit_l != "" and _delete_user_logistics_block(hit_l):
					return
				placement_rot = (placement_rot + 1) % 4
				queue_redraw()
				return

		if current_tool in [ToolMode.SPLITTER, ToolMode.MERGER]:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_place_user_logistics_at(wf, current_tool == ToolMode.SPLITTER)
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				var hit_u := _pick_block_at(event.position)
				if hit_u != "" and _delete_user_logistics_block(hit_u):
					return
				placement_rot = (placement_rot + 1) % 4
				queue_redraw()
				return

		if current_tool == ToolMode.BELT:
			if belt_builder.handle_belt_tool_input(event):
				return
			if event.button_index == MOUSE_BUTTON_RIGHT:
				is_panning = event.pressed
			return

		if current_tool in [ToolMode.FOUNDATION, ToolMode.PILLAR]:
			if event.button_index == MOUSE_BUTTON_LEFT:
				is_painting_tiles = event.pressed
				if event.pressed:
					_paint_tile_at(wf, false)
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				is_erasing_tiles = event.pressed
				if event.pressed:
					_paint_tile_at(wf, true)
				return

		if current_tool == ToolMode.RULER:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					is_measuring = true
					ruler_start_f = _snap_vec(wf)
					ruler_end_f = ruler_start_f
				else:
					is_measuring = false
				queue_redraw()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				is_panning = event.pressed
				is_measuring = false
				queue_redraw()
				return

		# Cursor mode (SELECT)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if hovered_id != "" and blocks.has(hovered_id):
				_rotate_block(hovered_id)
			else:
				is_panning = true
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			is_panning = false
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := _pick_block_at(event.position)
				if hit != "":
					if event.shift_pressed or event.ctrl_pressed:
						if selected_ids.has(hit):
							selected_ids.erase(hit)
						else:
							selected_ids[hit] = true
					elif not selected_ids.has(hit):
						selected_ids.clear()
						selected_ids[hit] = true
					drag_start_world_f = wf
					drag_initial_positions.clear()
					for sid in selected_ids.keys():
						var ks := String(sid)
						if blocks.has(ks) and not bool(blocks[ks].get("locked", false)) and not ks.begins_with("__usr_lift_"):
							drag_initial_positions[ks] = blocks[ks]["pos_f"]
					dragging_id = hit if not drag_initial_positions.is_empty() else ""
				else:
					if not event.shift_pressed and not event.ctrl_pressed:
						selected_ids.clear()
					is_box_selecting = true
					box_select_start_s = event.position
					box_select_end_s = event.position
				_update_hud_text()
				queue_redraw()
			else:
				var was_dragging := (dragging_id != "")
				dragging_id = ""
				drag_initial_positions.clear()
				if is_box_selecting:
					is_box_selecting = false
					queue_redraw()
				if was_dragging and main_ctrl.autosave_mgr != null:
					main_ctrl.autosave_mgr.notify_interaction()

	elif event is InputEventMouseMotion:
		var wf := _screen_to_world_f(event.position)
		last_mouse_world_f = wf
		_update_hud_text()
		if is_panning:
			cam_offset -= event.relative
			queue_redraw()
		elif current_tool == ToolMode.BELT:
			belt_builder.handle_belt_tool_input(event)
			var h_b := _pick_block_at(event.position)
			if h_b != hovered_id:
				hovered_id = h_b
				queue_redraw()
		elif current_tool in [ToolMode.SPLITTER, ToolMode.MERGER, ToolMode.LIFT]:
			hovered_id = _pick_block_at(event.position)
			queue_redraw()
		elif is_painting_tiles:
			_paint_tile_at(wf, false)
		elif is_erasing_tiles:
			_paint_tile_at(wf, true)
		elif is_measuring:
			ruler_end_f = _snap_vec(wf)
			queue_redraw()
		elif is_box_selecting:
			box_select_end_s = event.position
			var sel_rect := Rect2(box_select_start_s, box_select_end_s - box_select_start_s).abs()
			for bid in blocks.keys():
				var b: Dictionary = blocks[bid]
				if int(b.get("floor", 0)) != current_floor:
					continue
				var b_rect := Rect2(_world_f_to_screen(b["pos_f"]), _get_effective_size_f(b) * PX_PER_FOUNDATION * cam_zoom)
				if sel_rect.intersects(b_rect):
					selected_ids[bid] = true
			_update_hud_text()
			queue_redraw()
		elif dragging_id != "" and not drag_initial_positions.is_empty():
			var delta_f := _snap_vec(wf - drag_start_world_f)
			var gid: String = main_ctrl.active_graph.get_meta("graph_id", "world")
			for sid in drag_initial_positions.keys():
				if blocks.has(sid) and not bool(blocks[sid].get("locked", false)):
					var new_p := _snap_vec((drag_initial_positions[sid] as Vector2) + delta_f)
					blocks[sid]["pos_f"] = new_p
					saved_positions[gid][sid]["pos_f"] = new_p
			_update_bounds_summary()
			queue_redraw()
		else:
			var h := _pick_block_at(event.position)
			if h != hovered_id:
				hovered_id = h
				queue_redraw()
			elif current_tool in [ToolMode.FOUNDATION, ToolMode.PILLAR]:
				queue_redraw()

func _zoom_at(mpos: Vector2, factor: float) -> void:
	var before := _screen_to_world_f(mpos)
	cam_zoom = clampf(cam_zoom * factor, 0.25, 3.5)
	cam_offset = (before * PX_PER_FOUNDATION) * cam_zoom - mpos
	queue_redraw()

func _pick_block_at(screen_pos: Vector2) -> String:
	var wf := _screen_to_world_f(screen_pos)
	var keys := blocks.keys()
	for i in range(keys.size() - 1, -1, -1):
		var bid: String = keys[i]
		var b: Dictionary = blocks[bid]
		if int(b.get("floor", 0)) != current_floor:
			continue
		var rect_f := Rect2(b["pos_f"], _get_effective_size_f(b))
		if rect_f.has_point(wf):
			return bid
	return ""

func _detect_collisions_on_current_floor() -> Dictionary:
	var colliding: Dictionary = {}
	var fl_blocks: Array[String] = []
	for bid in blocks.keys():
		var b: Dictionary = blocks[bid]
		if int(b.get("floor", 0)) == current_floor and not bool(b.get("exclude_from_footprint", false)):
			fl_blocks.append(String(bid))
	for i in range(fl_blocks.size()):
		var id_a := fl_blocks[i]
		var ra := Rect2(blocks[id_a]["pos_f"], _get_effective_size_f(blocks[id_a])).grow(-0.02)
		for j in range(i + 1, fl_blocks.size()):
			var id_b := fl_blocks[j]
			var rb := Rect2(blocks[id_b]["pos_f"], _get_effective_size_f(blocks[id_b])).grow(-0.02)
			if ra.intersects(rb):
				colliding[id_a] = true
				colliding[id_b] = true
	return colliding

func _restore_user_logistics_blocks(mem: Dictionary) -> void:
	var sp_idx := 1
	var mg_idx := 1
	for k in mem.keys():
		var ks := String(k)
		if ks.begins_with("__usr_sp_"):
			var entry: Dictionary = mem[k]
			var fl := int(entry.get("floor", 0))
			var p: Vector2 = entry.get("pos_f", Vector2.ZERO)
			_register_block(
				ks, ks, i18n.tf("grid_splitter_tag", [sp_idx, 3]), "4x4m",
				"splitter", "", Color.html("#3A2416"), Color.html("#EB7D15"),
				SPLITTER_SIZE_F, p, mem, false, fl, 1, 3
			)
			sp_idx += 1
		elif ks.begins_with("__usr_mg_"):
			var entry: Dictionary = mem[k]
			var fl := int(entry.get("floor", 0))
			var p: Vector2 = entry.get("pos_f", Vector2.ZERO)
			_register_block(
				ks, ks, i18n.tf("grid_merger_tag", [mg_idx]), "4x4m",
				"merger", "", Color.html("#1F2D42"), Color.html("#7AB0D4"),
				SPLITTER_SIZE_F, p, mem, false, fl, 3, 1
			)
			mg_idx += 1
		elif ks.begins_with("__usr_lift_in_"):
			var entry: Dictionary = mem[k]
			var fl := int(entry.get("floor", 0))
			var t_fl := int(entry.get("target_floor", fl + 1))
			var p_id := String(entry.get("partner_id", ks.replace("__usr_lift_in_", "__usr_lift_out_")))
			var p: Vector2 = entry.get("pos_f", Vector2.ZERO)
			_register_block(
				ks, ks, i18n.tf("grid_lift_in_tag", [t_fl]), "2x2m",
				"lift_in", "", Color.html("#3E2F14"), Color.GOLD,
				LIFT_SIZE_F, p, mem, false, fl, 1, 0
			)
			blocks[ks]["target_floor"] = t_fl
			blocks[ks]["partner_id"] = p_id
		elif ks.begins_with("__usr_lift_out_"):
			var entry: Dictionary = mem[k]
			var fl := int(entry.get("floor", 0))
			var t_fl := int(entry.get("target_floor", fl - 1))
			var p_id := String(entry.get("partner_id", ks.replace("__usr_lift_out_", "__usr_lift_in_")))
			var p: Vector2 = entry.get("pos_f", Vector2.ZERO)
			_register_block(
				ks, ks, i18n.tf("grid_lift_out_tag", [t_fl]), "2x2m",
				"lift_out", "", Color.html("#16382C"), Color.SPRING_GREEN,
				LIFT_SIZE_F, p, mem, false, fl, 0, 1
			)
			blocks[ks]["target_floor"] = t_fl
			blocks[ks]["partner_id"] = p_id

func _place_user_logistics_at(world_f: Vector2, is_splitter: bool) -> void:
	var mem := _get_active_mem()
	var pos_f := _snap_vec(world_f - SPLITTER_SIZE_F * 0.5)
	var new_rect := Rect2(pos_f, SPLITTER_SIZE_F).grow(-0.02)
	# Block placement if it collides with existing blocks on this floor
	for bid in blocks.keys():
		var b: Dictionary = blocks[bid]
		if int(b.get("floor", 0)) == current_floor and not bool(b.get("exclude_from_footprint", false)):
			var br := Rect2(b["pos_f"], _get_effective_size_f(b)).grow(-0.02)
			if new_rect.intersects(br):
				return

	user_logistics_counter += 1
	var prefix := "__usr_sp_" if is_splitter else "__usr_mg_"
	var bid := "%s%d_%d" % [prefix, Time.get_ticks_msec(), user_logistics_counter]
	mem[bid] = {
		"pos_f": pos_f,
		"rot": placement_rot,
		"floor": current_floor,
		"locked": false
	}
	_restore_user_logistics_blocks(mem)
	_update_bounds_summary()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()

func _delete_user_logistics_block(bid: String) -> bool:
	if not (bid.begins_with("__usr_sp_") or bid.begins_with("__usr_mg_") or bid.begins_with("__usr_lift_")):
		return false
	var mem := _get_active_mem()
	var partner_id := String(blocks.get(bid, {}).get("partner_id", ""))
	if partner_id == "" and mem.has(bid):
		partner_id = String(mem[bid].get("partner_id", ""))

	for target_id in [bid, partner_id]:
		if target_id == "":
			continue
		mem.erase(target_id)
		blocks.erase(target_id)
		selected_ids.erase(target_id)
		if hovered_id == target_id:
			hovered_id = ""
		if belt_builder != null:
			belt_builder.remove_belts_for_block(target_id)

	_update_bounds_summary()
	_update_hud_text()
	queue_redraw()
	if main_ctrl.autosave_mgr != null:
		main_ctrl.autosave_mgr.notify_interaction()
	return true

func _delete_selected_user_blocks() -> void:
	var to_del: Array[String] = []
	for sid in selected_ids.keys():
		var ks := String(sid)
		if ks.begins_with("__usr_sp_") or ks.begins_with("__usr_mg_") or ks.begins_with("__usr_lift_"):
			to_del.append(ks)
	if to_del.is_empty() and hovered_id != "":
		if hovered_id.begins_with("__usr_sp_") or hovered_id.begins_with("__usr_mg_") or hovered_id.begins_with("__usr_lift_"):
			to_del.append(hovered_id)
	for ks in to_del:
		_delete_user_logistics_block(ks)

func _draw() -> void:
	_layout_docks()
	renderer.draw_grid_view()
