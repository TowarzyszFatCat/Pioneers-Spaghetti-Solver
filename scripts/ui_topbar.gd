class_name TopBarUI
extends RefCounted

const TOP_BAR_H := 40.0
const BOTTOM_BAR_H := 36.0

var main_ctrl: GraphEdit

var ui_layer: CanvasLayer
var top_panel: PanelContainer
var bottom_panel: PanelContainer
var sub_graph_holder: Control
var solid_bg: ColorRect
var hint_label: Label

# Top Bar controls
var new_proj_btn: Button
var save_proj_btn: Button
var load_proj_btn: Button

var back_btn: Button
var breadcrumb_label: Label
var top_map_btn: MenuButton
var markers_btn: Button

var chain_btn: Button
var nav_btn: Button
var production_btn: Button
var shopping_btn: Button
var add_recipe_btn: Button
var settings_btn: Button

# Bottom Bar controls
var alert_btn: Button
var power_pill: PanelContainer
var global_stats_label: Label
var compact_btn: Button
var group_btn: Button
var mode_toggle_btn: Button

var _selected_map_idx: int = 0

func _init(p_main: GraphEdit) -> void:
	main_ctrl = p_main

func _style_toolbar_button(btn: Button, pad_h: int = 7) -> void:
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.13, 0.16, 0.21, 0.92)
	normal_sb.border_color = Color(0.28, 0.35, 0.45, 0.75)
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(5)
	normal_sb.content_margin_left = pad_h
	normal_sb.content_margin_right = pad_h
	normal_sb.content_margin_top = 3
	normal_sb.content_margin_bottom = 3

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.19, 0.24, 0.32, 0.98)
	hover_sb.border_color = Color.html("#FAB757")

	var pressed_sb := normal_sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = Color(0.16, 0.28, 0.38, 0.98)
	pressed_sb.border_color = Color.AQUAMARINE

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_font_size_override("font_size", 12)
	btn.focus_mode = Control.FOCUS_NONE

func _make_vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(4, 20)
	sep.modulate = Color(1, 1, 1, 0.28)
	return sep

func build_ui_layer() -> void:
	var db = main_ctrl.db
	var settings = main_ctrl.settings
	var sharp_theme = main_ctrl.sharp_theme

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	main_ctrl.add_child(ui_layer)

	sub_graph_holder = Control.new()
	sub_graph_holder.theme = sharp_theme
	sub_graph_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_graph_holder.offset_top = TOP_BAR_H
	sub_graph_holder.offset_bottom = -BOTTOM_BAR_H
	sub_graph_holder.visible = false
	ui_layer.add_child(sub_graph_holder)

	solid_bg = ColorRect.new()
	solid_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	solid_bg.color = Color(0.09, 0.1, 0.12, 1.0)
	sub_graph_holder.add_child(solid_bg)

	# ==========================================
	# TOP BAR PANEL
	# ==========================================
	top_panel = PanelContainer.new()
	top_panel.theme = sharp_theme
	top_panel.z_index = 60
	top_panel.custom_minimum_size = Vector2(0, TOP_BAR_H)

	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = Color(0.07, 0.09, 0.12, 0.98)
	top_sb.border_color = Color(0.22, 0.30, 0.40, 0.85)
	top_sb.border_width_bottom = 1
	top_sb.content_margin_left = 8
	top_sb.content_margin_right = 8
	top_sb.content_margin_top = 4
	top_sb.content_margin_bottom = 4
	top_panel.add_theme_stylebox_override("panel", top_sb)
	ui_layer.add_child(top_panel)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 5)
	top_panel.add_child(top_hbox)

	# 1. File Actions (Left)
	new_proj_btn = Button.new()
	_style_toolbar_button(new_proj_btn, 6)
	new_proj_btn.custom_minimum_size = Vector2(30, 28)
	new_proj_btn.pressed.connect(func(): main_ctrl.serializer.prompt_new_project())
	top_hbox.add_child(new_proj_btn)

	save_proj_btn = Button.new()
	_style_toolbar_button(save_proj_btn, 6)
	save_proj_btn.custom_minimum_size = Vector2(30, 28)
	save_proj_btn.modulate = Color.LIGHT_GREEN
	save_proj_btn.pressed.connect(func(): main_ctrl.serializer.prompt_save_project(false))
	save_proj_btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			main_ctrl.serializer.prompt_save_project(true)
	)
	top_hbox.add_child(save_proj_btn)

	load_proj_btn = Button.new()
	_style_toolbar_button(load_proj_btn, 6)
	load_proj_btn.custom_minimum_size = Vector2(30, 28)
	load_proj_btn.modulate = Color.LIGHT_SKY_BLUE
	load_proj_btn.pressed.connect(func(): main_ctrl.serializer.prompt_load_project())
	top_hbox.add_child(load_proj_btn)

	top_hbox.add_child(_make_vsep())

	# 2. Navigation & Map (Left-Center)
	back_btn = Button.new()
	_style_toolbar_button(back_btn, 7)
	back_btn.modulate = Color.LIGHT_SKY_BLUE
	back_btn.visible = false
	back_btn.pressed.connect(main_ctrl.navigate_up)
	top_hbox.add_child(back_btn)

	breadcrumb_label = Label.new()
	breadcrumb_label.add_theme_font_size_override("font_size", 12)
	breadcrumb_label.modulate = Color(0.92, 0.96, 1.0)
	top_hbox.add_child(breadcrumb_label)

	if not db.available_maps.is_empty():
		top_map_btn = MenuButton.new()
		top_map_btn.flat = false
		_style_toolbar_button(top_map_btn, 6)
		top_map_btn.text = "🗺 ▾"
		top_map_btn.custom_minimum_size = Vector2(42, 28)
		top_map_btn.modulate = Color.LIGHT_SKY_BLUE
		var map_popup := top_map_btn.get_popup()
		map_popup.theme = sharp_theme
		for i in range(db.available_maps.size()):
			map_popup.add_radio_check_item("🗺 " + String(db.available_maps[i]["name"]), i)
		map_popup.set_item_checked(0, true)
		map_popup.index_pressed.connect(func(idx: int):
			_select_map_from_dropdown(idx)
		)
		top_hbox.add_child(top_map_btn)

	markers_btn = Button.new()
	_style_toolbar_button(markers_btn, 7)
	markers_btn.modulate = Color.SPRING_GREEN
	markers_btn.pressed.connect(func(): main_ctrl.map_markers_window.popup_centered())
	top_hbox.add_child(markers_btn)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(top_spacer)

	# 3. Planner Tools & Settings (Right)
	chain_btn = Button.new()
	_style_toolbar_button(chain_btn, 8)
	chain_btn.modulate = Color.VIOLET
	chain_btn.pressed.connect(func(): main_ctrl.tools.open_chain_window())
	top_hbox.add_child(chain_btn)

	nav_btn = Button.new()
	_style_toolbar_button(nav_btn, 8)
	nav_btn.modulate = Color.AQUAMARINE
	nav_btn.pressed.connect(func(): main_ctrl.tools.open_navigator_window())
	top_hbox.add_child(nav_btn)

	production_btn = Button.new()
	_style_toolbar_button(production_btn, 8)
	production_btn.modulate = Color.SPRING_GREEN
	production_btn.pressed.connect(func(): main_ctrl.production_modal.open_window())
	top_hbox.add_child(production_btn)

	shopping_btn = Button.new()
	_style_toolbar_button(shopping_btn, 8)
	shopping_btn.modulate = Color.KHAKI
	shopping_btn.pressed.connect(func(): main_ctrl.shopping_modal.open_window())
	top_hbox.add_child(shopping_btn)

	add_recipe_btn = Button.new()
	_style_toolbar_button(add_recipe_btn, 8)
	add_recipe_btn.pressed.connect(func(): main_ctrl.custom_recipes_mgr.open_window())
	top_hbox.add_child(add_recipe_btn)

	top_hbox.add_child(_make_vsep())

	settings_btn = Button.new()
	_style_toolbar_button(settings_btn, 7)
	settings_btn.custom_minimum_size = Vector2(32, 28)
	settings_btn.modulate = Color(0.9, 0.94, 1.0)
	settings_btn.pressed.connect(func(): main_ctrl.settings_window.popup_centered())
	top_hbox.add_child(settings_btn)

	# ==========================================
	# BOTTOM BAR PANEL
	# ==========================================
	bottom_panel = PanelContainer.new()
	bottom_panel.theme = sharp_theme
	bottom_panel.z_index = 60
	bottom_panel.custom_minimum_size = Vector2(0, BOTTOM_BAR_H)

	var bot_sb := StyleBoxFlat.new()
	bot_sb.bg_color = Color(0.07, 0.09, 0.12, 0.98)
	bot_sb.border_color = Color(0.22, 0.30, 0.40, 0.85)
	bot_sb.border_width_top = 1
	bot_sb.content_margin_left = 8
	bot_sb.content_margin_right = 8
	bot_sb.content_margin_top = 3
	bot_sb.content_margin_bottom = 3
	bottom_panel.add_theme_stylebox_override("panel", bot_sb)
	ui_layer.add_child(bottom_panel)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.add_theme_constant_override("separation", 6)
	bottom_panel.add_child(bot_hbox)

	# Bottom-Left: Alerts & Power Display
	alert_btn = Button.new()
	_style_toolbar_button(alert_btn, 8)
	alert_btn.modulate = Color.SPRING_GREEN
	alert_btn.pressed.connect(func(): main_ctrl.tools.open_alert_window())
	bot_hbox.add_child(alert_btn)

	power_pill = PanelContainer.new()
	var pwr_sb := StyleBoxFlat.new()
	pwr_sb.bg_color = Color(0.11, 0.13, 0.17, 0.95)
	pwr_sb.border_color = Color(0.35, 0.42, 0.52, 0.65)
	pwr_sb.set_border_width_all(1)
	pwr_sb.set_corner_radius_all(5)
	pwr_sb.content_margin_left = 8
	pwr_sb.content_margin_right = 8
	pwr_sb.content_margin_top = 2
	pwr_sb.content_margin_bottom = 2
	power_pill.add_theme_stylebox_override("panel", pwr_sb)
	bot_hbox.add_child(power_pill)

	global_stats_label = Label.new()
	global_stats_label.add_theme_font_size_override("font_size", 12)
	global_stats_label.modulate = Color.GOLD
	power_pill.add_child(global_stats_label)

	bot_hbox.add_child(_make_vsep())

	# Bottom-Center: Context Hint Label
	hint_label = Label.new()
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.clip_text = true
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.modulate = Color(0.78, 0.84, 0.92, 0.8)
	bot_hbox.add_child(hint_label)

	bot_hbox.add_child(_make_vsep())

	# Bottom-Right: Compact UI, Group to Factory, Grid Mode Toggle
	compact_btn = Button.new()
	_style_toolbar_button(compact_btn, 8)
	compact_btn.toggle_mode = true
	compact_btn.button_pressed = settings.compact_ui
	compact_btn.modulate = Color.LIGHT_SKY_BLUE
	compact_btn.toggled.connect(func(v: bool):
		settings.compact_ui = v
		settings.sync_ui_from_values()
		settings.save_settings()
		main_ctrl._on_settings_changed()
	)
	bot_hbox.add_child(compact_btn)

	group_btn = Button.new()
	_style_toolbar_button(group_btn, 8)
	group_btn.pressed.connect(main_ctrl.group_selected_to_factory)
	bot_hbox.add_child(group_btn)

	mode_toggle_btn = Button.new()
	_style_toolbar_button(mode_toggle_btn, 10)
	mode_toggle_btn.modulate = Color.AQUAMARINE
	mode_toggle_btn.pressed.connect(main_ctrl.toggle_workspace_mode)
	bot_hbox.add_child(mode_toggle_btn)

	refresh_translations()

func _select_map_from_dropdown(idx: int) -> void:
	var db = main_ctrl.db
	if idx < 0 or idx >= db.available_maps.size():
		return
	_selected_map_idx = idx
	if top_map_btn != null:
		var popup := top_map_btn.get_popup()
		for i in range(popup.item_count):
			popup.set_item_checked(i, i == idx)
		var m_name := String(db.available_maps[idx]["name"])
		top_map_btn.tooltip_text = "%s (%s)" % [main_ctrl.i18n.t("switch_map_tooltip"), m_name]
	main_ctrl._load_external_map_image(String(db.available_maps[idx]["path"]))

func build_breadcrumb_text(fid: String) -> String:
	var chain: Array[String] = []
	var cur := fid
	var guard := 0
	while cur != "world" and cur != "" and guard < 32:
		guard += 1
		if main_ctrl.factory_nodes.has(cur) and is_instance_valid(main_ctrl.factory_nodes[cur]):
			chain.push_front("🏭 " + String(main_ctrl.factory_nodes[cur].get_meta("custom_name")))
		cur = main_ctrl.factory_parents.get(cur, "world")
	chain.push_front(main_ctrl.i18n.t("world_map"))
	return " ▸ ".join(chain)

func update_navigation_state(is_world: bool, active_fid: String, is_grid_visible: bool) -> void:
	var i18n = main_ctrl.i18n
	breadcrumb_label.text = i18n.t("world_map") if is_world else build_breadcrumb_text(active_fid)
	back_btn.visible = not is_world
	if top_map_btn:
		top_map_btn.visible = is_world
	if markers_btn:
		markers_btn.visible = is_world
	if is_grid_visible:
		hint_label.text = i18n.t("grid_hint")
	else:
		hint_label.text = i18n.t("world_hint") if is_world else i18n.t("empty_factory_hint")

func update_workspace_mode_button(is_grid_visible: bool) -> void:
	var i18n = main_ctrl.i18n
	if is_grid_visible:
		mode_toggle_btn.text = i18n.t("schematic_mode_btn")
		mode_toggle_btn.modulate = Color.LIGHT_GREEN
	else:
		mode_toggle_btn.text = i18n.t("grid_mode_btn")
		mode_toggle_btn.modulate = Color.AQUAMARINE
	mode_toggle_btn.tooltip_text = i18n.t("mode_toggle_tooltip")

func update_power_and_alerts(pwr: Dictionary) -> void:
	var i18n = main_ctrl.i18n
	var settings = main_ctrl.settings

	if power_pill and global_stats_label:
		power_pill.visible = settings.show_power
		var gen := float(pwr["generated"])
		var use := float(pwr["consumed"])
		var net := float(pwr["net"])
		if gen > 0.0:
			var sign_str := "+" if net >= 0.0 else ""
			global_stats_label.text = i18n.tf("pwr_gen_use_net", [
				settings.fmt(gen), settings.fmt(use), sign_str, settings.fmt(net)
			])
			global_stats_label.modulate = Color.SPRING_GREEN if net >= 0.0 else Color.SALMON
		else:
			global_stats_label.text = i18n.tf("pwr_use_only", [settings.fmt(use)])
			global_stats_label.modulate = Color.GOLD

	if alert_btn != null and main_ctrl.tools != null:
		var res = main_ctrl.tools.scan_alerts()
		var cnt := int(res["total"])
		if cnt <= 0:
			alert_btn.text = i18n.t("alert_btn_ok")
			alert_btn.modulate = Color.SPRING_GREEN
		else:
			alert_btn.text = i18n.tf("alert_btn_warn", [cnt])
			alert_btn.modulate = Color.SALMON

func refresh_translations() -> void:
	var i18n = main_ctrl.i18n
	var settings = main_ctrl.settings
	var db = main_ctrl.db
	var is_grid = (main_ctrl.grid_planner != null and main_ctrl.grid_planner.visible)
	var is_world = (main_ctrl.active_graph == main_ctrl or main_ctrl.active_graph == null)

	if new_proj_btn:
		new_proj_btn.text = i18n.t("new_proj_btn")
		new_proj_btn.tooltip_text = i18n.t("new_proj_tooltip")
	if save_proj_btn:
		save_proj_btn.text = i18n.t("save_proj_btn")
		save_proj_btn.tooltip_text = i18n.t("save_proj_tooltip")
	if load_proj_btn:
		load_proj_btn.text = i18n.t("load_proj_btn")
		load_proj_btn.tooltip_text = i18n.t("load_proj_tooltip")

	if back_btn:
		back_btn.text = i18n.t("back_to_map")
		back_btn.tooltip_text = i18n.t("back_to_map_tooltip")
	if top_map_btn:
		top_map_btn.text = "🗺 ▾"
		var m_name := String(db.available_maps[_selected_map_idx]["name"]) if _selected_map_idx < db.available_maps.size() else ""
		top_map_btn.tooltip_text = ("%s (%s)" % [i18n.t("switch_map_tooltip"), m_name]) if m_name != "" else i18n.t("switch_map_tooltip")
	if markers_btn:
		markers_btn.text = i18n.t("map_markers_btn")
		markers_btn.tooltip_text = i18n.t("map_markers_tooltip")

	if mode_toggle_btn:
		update_workspace_mode_button(is_grid)
	if compact_btn:
		compact_btn.set_pressed_no_signal(settings.compact_ui)
		compact_btn.text = i18n.t("compact_btn")
		compact_btn.tooltip_text = i18n.t("compact_tooltip")
	if group_btn:
		group_btn.text = i18n.t("group_btn")
		group_btn.tooltip_text = i18n.t("group_tooltip")

	if chain_btn:
		chain_btn.text = i18n.t("chain_btn")
		chain_btn.tooltip_text = i18n.t("chain_btn_tooltip")
	if nav_btn:
		nav_btn.text = i18n.t("nav_btn")
		nav_btn.tooltip_text = i18n.t("nav_btn_tooltip")
	if production_btn:
		production_btn.text = i18n.t("prod_btn")
		production_btn.tooltip_text = i18n.t("prod_win_title")
	if shopping_btn:
		shopping_btn.text = i18n.t("shopping_btn")
		shopping_btn.tooltip_text = i18n.t("shop_title")
	if add_recipe_btn:
		add_recipe_btn.text = i18n.t("add_recipe_btn")
		add_recipe_btn.tooltip_text = i18n.t("custom_rec_win_title")

	if alert_btn:
		alert_btn.tooltip_text = i18n.t("alert_btn_tooltip")
	if settings_btn:
		settings_btn.text = i18n.t("settings_btn")
		settings_btn.tooltip_text = i18n.t("settings_win_title")

	var cur_fid := "" if is_world else String(main_ctrl.active_graph.get_meta("graph_id", ""))
	update_navigation_state(is_world, cur_fid, is_grid)
