extends GraphEdit

var i18n: AppI18n
var settings: AppSettings
var db: AppDB
var builder: NodeBuilder
var solver: FactorySolver
var grid_planner: GridPlannerView
var tools: PlannerTools
var custom_recipes_mgr: CustomRecipeManager
var oc_modal: OverclockModal
var shopping_modal: ShoppingListModal
var production_modal: ProductionModal
var sharp_theme: Theme
var serializer: ProjectSerializer
var autosave_mgr: AutosaveManager

# Extracted helper modules
var wire_handler: WireInputHandler
var undo_mgr: UndoClipboardManager
var popups: SearchPopups
var balancer: AutoBalancer
var topbar: TopBarUI

var is_loading_project: bool = false
var map_markers: SaveImporter
var map_markers_window: Window
var map_bound_tl: GraphNode = null
var map_bound_br: GraphNode = null

var ui_layer: CanvasLayer
var top_panel: PanelContainer
var bottom_panel: PanelContainer
var sub_graph_holder: Control
var solid_bg: ColorRect
var hint_label: Label

var active_graph: GraphEdit
var factory_graphs: Dictionary = {}
var factory_nodes: Dictionary = {}
var factory_parents: Dictionary = {}
var settings_window: Window
var belt_margin_slider: HSlider
var checked_shopping_items: Dictionary = {}

var pending_spawn_pos := Vector2.ZERO
var pending_from_node: StringName = &""
var pending_from_port: int = -1
var pending_to_node: StringName = &""
var pending_to_port: int = -1
var pending_filter_item: String = ""
var pending_is_reverse: bool = false

var map_texture: Texture2D = null
var _last_scroll := Vector2.ZERO
var _last_zoom := 1.0
var _last_vp_size := Vector2.ZERO

# Proxy getters for WireOverlay compatibility
var _dragging_wp_graph: GraphEdit:
	get:
		return wire_handler._dragging_wp_graph if wire_handler != null else null

var _dragging_wp_key: String:
	get:
		return wire_handler._dragging_wp_key if wire_handler != null else ""

var _dragging_wp_idx: int:
	get:
		return wire_handler._dragging_wp_idx if wire_handler != null else -1

func _ready() -> void:
	_setup_sharp_window_and_font()
	i18n = AppI18n.new()
	db = AppDB.new(i18n)
	settings = AppSettings.new(i18n, db)
	builder = NodeBuilder.new(self, db, settings, i18n)
	solver = FactorySolver.new(db, settings, i18n)
	tools = PlannerTools.new(self, db, settings, i18n, builder, solver)
	custom_recipes_mgr = CustomRecipeManager.new(self, db, settings, i18n, builder)
	oc_modal = OverclockModal.new(self, i18n)
	shopping_modal = ShoppingListModal.new(self, db, i18n, builder)
	production_modal = ProductionModal.new(self, db, settings, i18n, builder)

	wire_handler = WireInputHandler.new(self)
	undo_mgr = UndoClipboardManager.new(self)
	popups = SearchPopups.new(self)
	balancer = AutoBalancer.new(self)
	topbar = TopBarUI.new(self)

	settings.settings_changed.connect(_on_settings_changed)
	settings.map_image_selected.connect(_load_external_map_image)
	_try_load_project_world_map()

	active_graph = self
	_setup_graph_edit(self, "world")
	_setup_map_bounds()

	topbar.build_ui_layer()
	ui_layer = topbar.ui_layer
	top_panel = topbar.top_panel
	bottom_panel = topbar.bottom_panel
	sub_graph_holder = topbar.sub_graph_holder
	solid_bg = topbar.solid_bg
	hint_label = topbar.hint_label

	popups.build_search_popup(ui_layer, sharp_theme)
	popups.build_item_picker_popup(ui_layer, sharp_theme)

	grid_planner = GridPlannerView.new(self, db, settings, i18n)
	grid_planner.theme = sharp_theme
	grid_planner.z_index = 50
	ui_layer.add_child(grid_planner)

	settings_window = settings.build_window(ui_layer)
	settings_window.theme = sharp_theme
	custom_recipes_mgr.build_window(ui_layer, sharp_theme)
	oc_modal.build_window(ui_layer, sharp_theme)
	shopping_modal.build_window(ui_layer, sharp_theme)
	belt_margin_slider = shopping_modal.belt_margin_slider
	production_modal.build_window(ui_layer, sharp_theme)
	tools.build_all_windows(ui_layer, sharp_theme)

	map_markers = SaveImporter.new(self, db, settings, i18n)
	map_markers_window = map_markers.build_window(ui_layer, sharp_theme)
	serializer = ProjectSerializer.new(self, db, settings, i18n, builder)
	serializer.build_dialogs(ui_layer, sharp_theme)

	# Configure glass transparency once only on top-level modal windows
	_apply_glass_to_existing_subwindows()

	autosave_mgr = AutosaveManager.new(self, serializer)
	autosave_mgr.setup_autosave_timer(self)

	get_tree().root.size_changed.connect(_sync_window_layout)
	_sync_window_layout()
	recalculate_all()
	autosave_mgr.load_most_recent_on_startup()

func _setup_map_bounds() -> void:
	map_bound_tl = GraphNode.new()
	map_bound_tl.name = "_MapBoundTL"
	map_bound_tl.title = ""
	map_bound_tl.modulate = Color(1, 1, 1, 0.0)
	map_bound_tl.self_modulate = Color(1, 1, 1, 0.0)
	map_bound_tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_bound_tl.selectable = false
	map_bound_tl.draggable = false
	map_bound_tl.resizable = false
	map_bound_tl.custom_minimum_size = Vector2(1, 1)
	map_bound_tl.size = Vector2(1, 1)
	add_child(map_bound_tl)

	map_bound_br = GraphNode.new()
	map_bound_br.name = "_MapBoundBR"
	map_bound_br.title = ""
	map_bound_br.modulate = Color(1, 1, 1, 0.0)
	map_bound_br.self_modulate = Color(1, 1, 1, 0.0)
	map_bound_br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_bound_br.selectable = false
	map_bound_br.draggable = false
	map_bound_br.resizable = false
	map_bound_br.custom_minimum_size = Vector2(1, 1)
	map_bound_br.size = Vector2(1, 1)
	add_child(map_bound_br)
	_update_map_bounds()

func _update_map_bounds() -> void:
	var tex_size := Vector2(8192.0, 8192.0)
	if map_texture != null:
		tex_size = map_texture.get_size()
	var scaled_size := tex_size * settings.map_scale
	if is_instance_valid(map_bound_tl):
		map_bound_tl.position_offset = Vector2.ZERO
	if is_instance_valid(map_bound_br):
		map_bound_br.position_offset = scaled_size

func _setup_sharp_window_and_font() -> void:
	var win := get_window()
	win.unresizable = false
	win.min_size = Vector2i(800, 500)
	get_viewport().gui_embed_subwindows = true
	ProjectSettings.set_setting("gui/fonts/dynamic_fonts/use_oversampling", false)
	TextServerManager.get_primary_interface().font_set_global_oversampling(1.0)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var default_f := ThemeDB.fallback_font
	if default_f != null:
		if "oversampling" in default_f:
			default_f.oversampling = 1.0
		if "subpixel_positioning" in default_f:
			default_f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	sharp_theme = Theme.new()
	sharp_theme.default_font_size = 13
	_build_glass_ui_theme(sharp_theme)
	get_tree().root.theme = sharp_theme
	theme = sharp_theme

func _apply_glass_to_existing_subwindows() -> void:
	if ui_layer == null:
		return
	for ch in ui_layer.get_children():
		if ch is Window:
			var w := ch as Window
			w.transparent = true
			w.transparent_bg = true
			if sharp_theme != null:
				w.theme = sharp_theme
			_soften_subwindow_tree_recursive(w)

func _soften_subwindow_tree_recursive(root: Node) -> void:
	if root is PanelContainer or root is Panel:
		var ctrl := root as Control
		if ctrl.has_theme_stylebox_override("panel"):
			var sb := ctrl.get_theme_stylebox("panel")
			if sb is StyleBoxFlat:
				var flat := sb as StyleBoxFlat
				flat.shadow_size = 0
				flat.shadow_color = Color.TRANSPARENT
				if flat.bg_color.a > 0.65:
					flat.bg_color.a = 0.65
	for ch in root.get_children():
		_soften_subwindow_tree_recursive(ch)

func _build_glass_ui_theme(t: Theme) -> void:
	# 1. Embedded Window
	var win_sb := StyleBoxFlat.new()
	win_sb.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	win_sb.border_color = Color(0.20, 0.27, 0.38, 0.98)
	win_sb.set_border_width_all(2)
	win_sb.border_width_top = 30
	win_sb.set_corner_radius_all(8)
	win_sb.expand_margin_top = 30
	win_sb.expand_margin_left = 2
	win_sb.expand_margin_right = 2
	win_sb.expand_margin_bottom = 2
	win_sb.shadow_size = 0
	win_sb.shadow_color = Color.TRANSPARENT

	var win_unfocused_sb := win_sb.duplicate() as StyleBoxFlat
	win_unfocused_sb.bg_color = Color(0.07, 0.09, 0.12, 0.9)
	win_unfocused_sb.border_color = Color(0.15, 0.19, 0.27, 0.9)

	t.set_stylebox("embedded_border", "Window", win_sb)
	t.set_stylebox("embedded_unfocused_border", "Window", win_unfocused_sb)
	t.set_color("title_color", "Window", Color(0.95, 0.97, 1.0))
	t.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	t.set_constant("title_outline_size", "Window", 0)
	t.set_constant("title_height", "Window", 28)

	# Clear opaque default panel on AcceptDialog / ConfirmationDialog / FileDialog
	var empty_dialog_sb := StyleBoxEmpty.new()
	t.set_stylebox("panel", "AcceptDialog", empty_dialog_sb)

	# Default translucent glass for generic Panels
	var glass_panel_sb := StyleBoxFlat.new()
	glass_panel_sb.bg_color = Color(0.10, 0.12, 0.17, 0.95)
	glass_panel_sb.border_color = Color(0.28, 0.38, 0.52, 0.9)
	glass_panel_sb.set_border_width_all(1)
	glass_panel_sb.set_corner_radius_all(6)
	glass_panel_sb.content_margin_left = 8
	glass_panel_sb.content_margin_right = 8
	glass_panel_sb.content_margin_top = 6
	glass_panel_sb.content_margin_bottom = 6
	glass_panel_sb.shadow_size = 0
	t.set_stylebox("panel", "Panel", glass_panel_sb)
	t.set_stylebox("panel", "PanelContainer", glass_panel_sb)

	# 2. PopupPanel & PopupMenu
	var popup_sb := StyleBoxFlat.new()
	popup_sb.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	popup_sb.border_color = Color(0.32, 0.46, 0.64, 0.95)
	popup_sb.set_border_width_all(2)
	popup_sb.set_corner_radius_all(8)
	popup_sb.content_margin_left = 10
	popup_sb.content_margin_right = 10
	popup_sb.content_margin_top = 10
	popup_sb.content_margin_bottom = 10
	popup_sb.shadow_size = 0
	popup_sb.shadow_color = Color.TRANSPARENT
	t.set_stylebox("panel", "PopupPanel", popup_sb)
	t.set_stylebox("panel", "PopupMenu", popup_sb)

	var menu_hover_sb := StyleBoxFlat.new()
	menu_hover_sb.bg_color = Color(0.18, 0.26, 0.38, 0.85)
	menu_hover_sb.border_color = Color.html("#FAB757")
	menu_hover_sb.set_border_width_all(1)
	menu_hover_sb.set_corner_radius_all(5)
	t.set_stylebox("hover", "PopupMenu", menu_hover_sb)

	# 3. TooltipPanel
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	tip_sb.border_color = Color.html("#FAB757")
	tip_sb.set_border_width_all(1)
	tip_sb.set_corner_radius_all(6)
	tip_sb.content_margin_left = 8
	tip_sb.content_margin_right = 8
	tip_sb.content_margin_top = 5
	tip_sb.content_margin_bottom = 5
	tip_sb.shadow_size = 0
	t.set_stylebox("panel", "TooltipPanel", tip_sb)
	t.set_color("font_color", "TooltipLabel", Color(0.95, 0.97, 1.0))

	# 4. Buttons & OptionButtons
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.14, 0.18, 0.24, 0.95)
	btn_normal.border_color = Color(0.32, 0.42, 0.55, 0.9)
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(6)
	btn_normal.content_margin_left = 10
	btn_normal.content_margin_right = 10
	btn_normal.content_margin_top = 5
	btn_normal.content_margin_bottom = 5

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.20, 0.26, 0.35, 0.88)
	btn_hover.border_color = Color.html("#FAB757")

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	btn_pressed.border_color = Color.AQUAMARINE
	btn_pressed.set_border_width_all(2)

	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.09, 0.10, 0.13, 0.45)
	btn_disabled.border_color = Color(0.22, 0.25, 0.30, 0.40)

	for ctrl_type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", ctrl_type, btn_normal)
		t.set_stylebox("hover", ctrl_type, btn_hover)
		t.set_stylebox("pressed", ctrl_type, btn_pressed)
		t.set_stylebox("disabled", ctrl_type, btn_disabled)
		t.set_stylebox("focus", ctrl_type, btn_hover)

	# 5. CheckBox
	var chk_normal := StyleBoxFlat.new()
	chk_normal.bg_color = Color(0.11, 0.14, 0.19, 0.65)
	chk_normal.border_color = Color(0.25, 0.33, 0.44, 0.65)
	chk_normal.set_border_width_all(1)
	chk_normal.set_corner_radius_all(6)
	chk_normal.content_margin_left = 8
	chk_normal.content_margin_right = 8
	chk_normal.content_margin_top = 5
	chk_normal.content_margin_bottom = 5

	var chk_hover := chk_normal.duplicate() as StyleBoxFlat
	chk_hover.bg_color = Color(0.16, 0.20, 0.28, 0.80)
	chk_hover.border_color = Color.html("#FAB757")

	var chk_pressed := chk_normal.duplicate() as StyleBoxFlat
	chk_pressed.bg_color = Color(0.12, 0.20, 0.27, 0.82)
	chk_pressed.border_color = Color(0.35, 0.82, 0.95, 0.85)

	t.set_stylebox("normal", "CheckBox", chk_normal)
	t.set_stylebox("hover", "CheckBox", chk_hover)
	t.set_stylebox("pressed", "CheckBox", chk_pressed)
	t.set_stylebox("hover_pressed", "CheckBox", chk_hover)

	# 6. LineEdit & SpinBox input fields
	var edit_normal := StyleBoxFlat.new()
	edit_normal.bg_color = Color(0.06, 0.08, 0.11, 0.78)
	edit_normal.border_color = Color(0.28, 0.38, 0.50, 0.80)
	edit_normal.set_border_width_all(1)
	edit_normal.set_corner_radius_all(5)
	edit_normal.content_margin_left = 8
	edit_normal.content_margin_right = 8
	edit_normal.content_margin_top = 4
	edit_normal.content_margin_bottom = 4

	var edit_focus := edit_normal.duplicate() as StyleBoxFlat
	edit_focus.bg_color = Color(0.08, 0.11, 0.16, 0.90)
	edit_focus.border_color = Color.html("#FAB757")
	edit_focus.set_border_width_all(2)

	t.set_stylebox("normal", "LineEdit", edit_normal)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("read_only", "LineEdit", btn_disabled)

	# 7. Sliders
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.06, 0.08, 0.12, 0.80)
	slider_bg.border_color = Color(0.28, 0.36, 0.48, 0.75)
	slider_bg.set_border_width_all(1)
	slider_bg.set_corner_radius_all(4)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4

	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = Color(0.28, 0.72, 0.95, 0.85)
	slider_fill.set_corner_radius_all(4)
	slider_fill.content_margin_top = 4
	slider_fill.content_margin_bottom = 4

	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

func _sync_window_layout() -> void:
	var vp_size := get_viewport_rect().size
	var top_h := TopBarUI.TOP_BAR_H
	var bot_h := TopBarUI.BOTTOM_BAR_H
	var work_h := maxf(100.0, vp_size.y - top_h - bot_h)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	position = Vector2(0.0, top_h)
	size = Vector2(vp_size.x, work_h)

	if top_panel:
		top_panel.position = Vector2.ZERO
		top_panel.size = Vector2(vp_size.x, top_h)
	if bottom_panel:
		bottom_panel.position = Vector2(0.0, vp_size.y - bot_h)
		bottom_panel.size = Vector2(vp_size.x, bot_h)
	if sub_graph_holder:
		sub_graph_holder.position = Vector2(0.0, top_h)
		sub_graph_holder.size = Vector2(vp_size.x, work_h)
	if solid_bg and sub_graph_holder:
		solid_bg.size = sub_graph_holder.size
	for fid in factory_graphs.keys():
		if is_instance_valid(factory_graphs[fid]):
			factory_graphs[fid].position = Vector2.ZERO
			factory_graphs[fid].size = sub_graph_holder.size
	if grid_planner:
		grid_planner.position = Vector2(0.0, top_h)
		grid_planner.size = Vector2(vp_size.x, work_h)
		grid_planner.queue_redraw()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if popups != null and popups.is_any_popup_visible():
		return
	if (custom_recipes_mgr and custom_recipes_mgr.win and custom_recipes_mgr.win.visible) or (settings_window and settings_window.visible):
		return
	if tools != null and ((tools.chain_win and tools.chain_win.visible) or (tools.nav_win and tools.nav_win.visible) or (tools.alert_win and tools.alert_win.visible)):
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is SpinBox:
		return

	if grid_planner != null and grid_planner.visible:
		grid_planner._unhandled_key_input(event)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		undo_mgr.delete_selected_nodes()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_L and not event.ctrl_pressed:
		undo_mgr.toggle_lock_selected_nodes()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed:
		if event.keycode == KEY_G:
			group_selected_to_factory()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F and tools != null:
			tools.open_navigator_window()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			undo_mgr.copy_selected_nodes()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_V:
			undo_mgr.paste_copied_nodes()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z:
			if event.shift_pressed:
				undo_mgr.perform_redo()
			else:
				undo_mgr.perform_undo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y:
			undo_mgr.perform_redo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S and serializer != null:
			serializer.prompt_save_project(event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_O and serializer != null:
			serializer.prompt_load_project()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_N and serializer != null:
			serializer.prompt_new_project()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var vp_sz := get_viewport_rect().size
	if vp_sz != _last_vp_size:
		_last_vp_size = vp_sz
		_sync_window_layout()
	if active_graph == self and (scroll_offset != _last_scroll or zoom != _last_zoom):
		_last_scroll = scroll_offset
		_last_zoom = zoom
		queue_redraw()
	elif active_graph != null and active_graph != self:
		var want_grid := active_graph.zoom >= 0.25
		if active_graph.show_grid != want_grid:
			active_graph.show_grid = want_grid

# Delegation wrappers for external modules
func _push_undo_state() -> void:
	if undo_mgr != null:
		undo_mgr.push_undo_state()
	if autosave_mgr != null:
		autosave_mgr.notify_interaction()

func open_item_picker(callback: Callable, only_fuels: bool = false) -> void:
	if popups != null:
		popups.open_item_picker(callback, only_fuels)

func auto_balance_node(g: GraphEdit, node: GraphNode) -> void:
	if balancer != null:
		balancer.auto_balance_node(g, node)

func auto_balance_node_to_demand(g: GraphEdit, node: GraphNode) -> void:
	if balancer != null:
		balancer.auto_balance_node_to_demand(g, node)

func auto_balance_chain_upstream(g: GraphEdit, start_node: GraphNode) -> void:
	if balancer != null:
		balancer.auto_balance_chain_upstream(g, start_node)

func auto_balance_chain_downstream(g: GraphEdit, start_node: GraphNode) -> void:
	if balancer != null:
		balancer.auto_balance_chain_downstream(g, start_node)

func group_selected_to_factory() -> void:
	if balancer != null:
		balancer.group_selected_to_factory()

func _try_load_project_world_map() -> void:
	var default_path := db.get_default_map_path()
	var candidates: Array[String] = [
		default_path,
		"res://data/maps/world_map.png",
		"res://data/maps/world_map.jpg",
		"res://data/maps/world_map.webp",
		"res://world_map.png"
	]
	for m in db.available_maps:
		var mp := String(m["path"])
		if not candidates.has(mp):
			candidates.append(mp)
	for candidate in candidates:
		if _load_map_from_any_path(candidate):
			break

func _load_external_map_image(path: String) -> void:
	_load_map_from_any_path(path)

func _load_map_from_any_path(path: String) -> bool:
	if path == "":
		return false
	if ResourceLoader.exists(path):
		var res_tex := load(path) as Texture2D
		if res_tex != null:
			map_texture = res_tex
			_update_map_bounds()
			queue_redraw()
			return true
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			map_texture = ImageTexture.create_from_image(img)
			_update_map_bounds()
			queue_redraw()
			return true
	return false

func _draw() -> void:
	if active_graph != self:
		return
	if settings.show_map and map_texture != null:
		var tex_size: Vector2 = map_texture.get_size() * settings.map_scale
		var world_rect := Rect2(Vector2.ZERO, tex_size)
		var screen_pos: Vector2 = world_rect.position * zoom - scroll_offset
		var screen_size: Vector2 = world_rect.size * zoom
		draw_texture_rect(map_texture, Rect2(screen_pos, screen_size), false, Color(1, 1, 1, settings.map_opacity))
	if map_markers != null:
		map_markers.draw_markers_on_map(self)

func _refresh_valid_connection_types(g: GraphEdit) -> void:
	var count := maxi(256, db.item_order.size() + 16)
	for i in range(count):
		g.add_valid_connection_type(i, i)
		g.add_valid_connection_type(i, NodeBuilder.CARGO_ANY_PORT_TYPE)
		if i < db.item_order.size() and db.is_item_fuel(db.item_order[i]):
			g.add_valid_connection_type(i, NodeBuilder.FUEL_PORT_TYPE)
	g.add_valid_connection_type(NodeBuilder.STATION_LINK_PORT_TYPE, NodeBuilder.STATION_LINK_PORT_TYPE)

func _setup_graph_edit(g: GraphEdit, graph_id: String) -> void:
	g.theme = sharp_theme
	g.right_disconnects = true
	g.show_grid = (graph_id != "world")
	g.minimap_enabled = false
	g.zoom_min = 0.05
	g.zoom_max = 1.0
	g.set_meta("graph_id", graph_id)
	g.set_meta("main_ref", self)
	g.set_meta("wire_waypoints", {})
	_refresh_valid_connection_types(g)

	# Disable Godot's internal _connections_layer and hide HScrollBar/VScrollBar completely
	var empty_sb := StyleBoxEmpty.new()
	var empty_tex := ImageTexture.new()
	for internal_ch in g.get_children(true):
		var cname := String(internal_ch.name).to_lower()
		if cname.contains("connection"):
			if internal_ch is CanvasItem:
				internal_ch.visible = false
			internal_ch.process_mode = Node.PROCESS_MODE_DISABLED
		elif internal_ch is ScrollBar:
			var sbar := internal_ch as ScrollBar
			sbar.modulate = Color(1, 1, 1, 0.0)
			sbar.self_modulate = Color(1, 1, 1, 0.0)
			sbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sbar.focus_mode = Control.FOCUS_NONE
			sbar.custom_minimum_size = Vector2.ZERO
			sbar.scale = Vector2.ZERO
			for sb_key in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed", "increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
				sbar.add_theme_stylebox_override(sb_key, empty_sb)
			for ic_key in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
				sbar.add_theme_icon_override(ic_key, empty_tex)

	var wire_layer := WireOverlay.WireLayer.new(g, self)
	g.add_child(wire_layer)
	var overlay := WireOverlay.WireBadgeOverlay.new(g, self, wire_layer)
	g.add_child(overlay)

	g.gui_input.connect(func(ev: InputEvent):
		wire_handler.handle_graph_wire_input(g, ev)
	)
	g.end_node_move.connect(func():
		if autosave_mgr != null:
			autosave_mgr.notify_interaction()
	)
	var menu_box := g.get_menu_hbox()
	if menu_box:
		menu_box.position = Vector2(14, 52)
	g.node_selected.connect(func(_node: Node):
		var fo := get_viewport().gui_get_focus_owner()
		if fo is LineEdit or fo is SpinBox:
			fo.release_focus()
	)
	g.connection_request.connect(func(fn: StringName, fp: int, tn: StringName, tp: int):
		if fn == tn:
			return
		for c in g.get_connection_list():
			if c.get("from_node", c.get("from", "")) == fn and int(c["from_port"]) == fp and c.get("to_node", c.get("to", "")) == tn and int(c["to_port"]) == tp:
				return
		var src := g.get_node_or_null(NodePath(fn)) as GraphNode
		var dst := g.get_node_or_null(NodePath(tn)) as GraphNode
		if not src or not dst:
			return
		var src_item := solver.get_node_output_item(src, fp)
		var dst_kind: String = dst.get_meta("node_kind", "")
		if dst_kind == "truck_station" and tp == 0:
			if not db.is_item_fuel(src_item):
				return
			dst.set_meta("fuel_item", src_item)
			builder.rebuild_transport_station_rows(g, dst)
		if dst_kind == "reroute" and src_item != "" and src_item != "__station_route__":
			builder.set_reroute_node_item(dst, src_item)
		var target_tp := tp
		if dst_kind == "train_station" and tp < int(dst.get_meta("platforms_count", 1)) and src_item != "" and src_item != "__station_route__":
			var plat_items: Dictionary = {}
			for c in g.get_connection_list():
				if c.get("to_node", c.get("to", "")) == tn:
					var c_tp := int(c["to_port"])
					var c_src := g.get_node_or_null(NodePath(String(c.get("from_node", c.get("from", ""))))) as GraphNode
					if c_src:
						var c_it := solver.get_node_output_item(c_src, int(c["from_port"]))
						if c_it != "" and c_it != "__station_route__":
							plat_items[c_tp] = c_it
			if plat_items.has(target_tp) and plat_items[target_tp] != src_item:
				var found_plat := -1
				var p_cnt := int(dst.get_meta("platforms_count", 1))
				for p_idx in range(p_cnt):
					if not plat_items.has(p_idx) or plat_items[p_idx] == src_item:
						found_plat = p_idx
						break
				if found_plat == -1 and p_cnt < 12:
					found_plat = p_cnt
					dst.set_meta("platforms_count", p_cnt + 1)
					builder.rebuild_transport_station_rows(g, dst)
				if found_plat != -1:
					target_tp = found_plat
				else:
					return
		_push_undo_state()
		g.connect_node(fn, fp, tn, target_tp)
		if settings.auto_balance_on_connect and dst_kind == "machine":
			auto_balance_node(g, dst)
		recalculate_all()
	)
	g.disconnection_request.connect(func(fn: StringName, fp: int, tn: StringName, tp: int):
		_push_undo_state()
		var w_key := "%s:%d->%s:%d" % [fn, fp, tn, tp]
		if g.has_meta("wire_waypoints"):
			(g.get_meta("wire_waypoints") as Dictionary).erase(w_key)
		g.disconnect_node(fn, fp, tn, tp)
		recalculate_all()
	)
	g.popup_request.connect(func(at_pos: Vector2):
		active_graph = g
		pending_from_node = &""
		pending_from_port = -1
		pending_to_node = &""
		pending_to_port = -1
		pending_filter_item = ""
		pending_is_reverse = false
		pending_spawn_pos = (at_pos + g.scroll_offset) / g.zoom
		popups.open_search_popup()
	)
	g.connection_to_empty.connect(func(fn: StringName, fp: int, rel_pos: Vector2):
		active_graph = g
		var src := g.get_node_or_null(NodePath(fn)) as GraphNode
		if not src:
			return
		var out_item := solver.get_node_output_item(src, fp)
		if out_item == "":
			return
		pending_from_node = fn
		pending_from_port = fp
		pending_to_node = &""
		pending_to_port = -1
		pending_filter_item = out_item
		pending_is_reverse = false
		pending_spawn_pos = (rel_pos + g.scroll_offset) / g.zoom
		popups.open_search_popup()
	)
	g.connection_from_empty.connect(func(tn: StringName, tp: int, rel_pos: Vector2):
		active_graph = g
		var dst := g.get_node_or_null(NodePath(tn)) as GraphNode
		if not dst:
			return
		var in_item := solver.get_node_input_item(dst, tp)
		if in_item == "":
			return
		pending_from_node = &""
		pending_from_port = -1
		pending_to_node = tn
		pending_to_port = tp
		pending_filter_item = in_item
		pending_is_reverse = true
		pending_spawn_pos = (rel_pos + g.scroll_offset) / g.zoom - Vector2(380, 0)
		popups.open_search_popup()
	)

func _on_recipe_selected(recipe_id: String, matched_port: int) -> void:
	_push_undo_state()
	var new_node := builder.spawn_machine(active_graph, recipe_id, pending_spawn_pos)
	if not pending_is_reverse and pending_from_node != &"" and matched_port != -1:
		active_graph.connect_node(pending_from_node, pending_from_port, new_node.name, matched_port)
		if settings.auto_balance_on_connect:
			auto_balance_node(active_graph, new_node)
	elif pending_is_reverse and pending_to_node != &"" and matched_port != -1:
		active_graph.connect_node(new_node.name, matched_port, pending_to_node, pending_to_port)
		auto_balance_node_to_demand(active_graph, new_node)
	pending_from_node = &""
	pending_to_node = &""
	recalculate_all()

func _on_special_selected(stype: String) -> void:
	_push_undo_state()
	var def_item := db.item_order[0] if not db.item_order.is_empty() else "iron-ore"
	var filter_or_def := pending_filter_item if pending_filter_item != "" else def_item
	if stype == "factory":
		builder.spawn_factory(active_graph, pending_spawn_pos)
	elif stype == "receiver":
		if active_graph != self:
			var rx := builder.spawn_io_node(active_graph, "receiver", filter_or_def, pending_spawn_pos)
			if pending_is_reverse and pending_to_node != &"":
				active_graph.connect_node(rx.name, 0, pending_to_node, pending_to_port)
	elif stype == "transmitter":
		if active_graph != self:
			var tx := builder.spawn_io_node(active_graph, "transmitter", filter_or_def, pending_spawn_pos)
			if not pending_is_reverse and pending_from_node != &"":
				active_graph.connect_node(pending_from_node, pending_from_port, tx.name, 0)
	elif stype == "reroute":
		var rr := builder.spawn_reroute_node(active_graph, filter_or_def, pending_spawn_pos)
		if not pending_is_reverse and pending_from_node != &"":
			active_graph.connect_node(pending_from_node, pending_from_port, rr.name, 0)
		elif pending_is_reverse and pending_to_node != &"":
			active_graph.connect_node(rr.name, 0, pending_to_node, pending_to_port)
	elif stype in ["splitter", "even_splitter", "prop_splitter"]:
		var sp := builder.spawn_splitter(active_graph, filter_or_def, pending_spawn_pos, stype)
		if not pending_is_reverse and pending_from_node != &"":
			active_graph.connect_node(pending_from_node, pending_from_port, sp.name, 0)
		elif pending_is_reverse and pending_to_node != &"":
			active_graph.connect_node(sp.name, 0, pending_to_node, pending_to_port)
	elif stype == "manual_splitter":
		var msp := builder.spawn_manual_splitter(active_graph, filter_or_def, pending_spawn_pos)
		if not pending_is_reverse and pending_from_node != &"":
			active_graph.connect_node(pending_from_node, pending_from_port, msp.name, 0)
		elif pending_is_reverse and pending_to_node != &"":
			active_graph.connect_node(msp.name, 0, pending_to_node, pending_to_port)
	elif stype in ["truck_station", "train_station"]:
		var st := builder.spawn_transport_station(active_graph, stype, filter_or_def, pending_spawn_pos)
		if not pending_is_reverse and pending_from_node != &"":
			var src_n := active_graph.get_node_or_null(NodePath(pending_from_node)) as GraphNode
			var is_route_wire = (src_n != null and src_n.get_meta("node_kind", "") in ["truck_station", "train_station"] and pending_from_port == solver.get_station_link_out_port(src_n))
			if is_route_wire:
				active_graph.connect_node(pending_from_node, pending_from_port, st.name, solver.get_station_link_in_port(st))
			else:
				var target_in_port := 1 if stype == "truck_station" else 0
				active_graph.connect_node(pending_from_node, pending_from_port, st.name, target_in_port)
	elif stype in ["awesome_sink", "depot", "container"]:
		var st_node := builder.spawn_storage_sink_node(active_graph, stype, filter_or_def, pending_spawn_pos)
		if not pending_is_reverse and pending_from_node != &"":
			active_graph.connect_node(pending_from_node, pending_from_port, st_node.name, 0)
		elif stype == "container" and pending_is_reverse and pending_to_node != &"":
			active_graph.connect_node(st_node.name, 0, pending_to_node, pending_to_port)
	pending_from_node = &""
	pending_to_node = &""
	recalculate_all()

func toggle_workspace_mode() -> void:
	var to_grid := not grid_planner.visible
	grid_planner.visible = to_grid
	_sync_window_layout()
	var is_world := (active_graph == self)
	var cur_fid := "" if is_world else String(active_graph.get_meta("graph_id", ""))
	if topbar != null:
		topbar.update_workspace_mode_button(to_grid)
		topbar.update_navigation_state(is_world, cur_fid, to_grid)
	if to_grid:
		recalculate_all()
		grid_planner.sync_from_graph(active_graph)

func create_factory_sub_graph(fid: String, parent_graph_id: String = "world") -> GraphEdit:
	var f_graph := GraphEdit.new()
	f_graph.theme = sharp_theme
	f_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f_graph.visible = false
	_setup_graph_edit(f_graph, fid)
	sub_graph_holder.add_child(f_graph)
	factory_graphs[fid] = f_graph
	factory_parents[fid] = parent_graph_id
	_sync_window_layout()
	return f_graph

func enter_factory(fid: String) -> void:
	if not factory_graphs.has(fid):
		return
	for ch in get_children():
		if ch is GraphNode and ch.has_meta("node_kind"):
			ch.visible = false
	for id_key in factory_graphs.keys():
		factory_graphs[id_key].visible = (id_key == fid)
	sub_graph_holder.visible = true
	active_graph = factory_graphs[fid]
	if topbar != null:
		topbar.update_navigation_state(false, fid, grid_planner != null and grid_planner.visible)
	_sync_window_layout()
	if grid_planner.visible:
		grid_planner.sync_from_graph(active_graph)
	queue_redraw()

func navigate_up() -> void:
	if active_graph == self:
		return
	var cur_fid: String = active_graph.get_meta("graph_id", "world")
	var parent_id: String = factory_parents.get(cur_fid, "world")
	if parent_id == "world" or not factory_graphs.has(parent_id):
		return_to_world_map()
	else:
		enter_factory(parent_id)

func return_to_world_map() -> void:
	sub_graph_holder.visible = false
	for id_key in factory_graphs.keys():
		factory_graphs[id_key].visible = false
	for ch in get_children():
		if ch is GraphNode:
			ch.visible = true
	active_graph = self
	if topbar != null:
		topbar.update_navigation_state(true, "", grid_planner != null and grid_planner.visible)
	_sync_window_layout()
	recalculate_all()
	if grid_planner.visible:
		grid_planner.sync_from_graph(active_graph)
	queue_redraw()

func open_overclock_helper(node: GraphNode) -> void:
	if oc_modal:
		oc_modal.open_for_node(node)

func recalculate_all() -> void:
	if is_loading_project:
		return
	var pwr: Dictionary = solver.solve_all(self, factory_graphs, factory_nodes)
	if topbar != null:
		topbar.update_power_and_alerts(pwr)
	if tools != null:
		if tools.alert_win and tools.alert_win.visible:
			tools.refresh_alerts()
		if tools.nav_win and tools.nav_win.visible:
			tools.refresh_navigator()
	if shopping_modal and shopping_modal.win and shopping_modal.win.visible:
		shopping_modal.refresh()
	if production_modal and production_modal.win and production_modal.win.visible:
		production_modal.refresh()
	if grid_planner and grid_planner.visible:
		grid_planner.sync_from_graph(active_graph)
	if is_instance_valid(active_graph):
		for ch in active_graph.get_children():
			if ch is WireOverlay.WireLayer:
				ch._last_hash = 0
				ch.queue_redraw()
			elif ch is WireOverlay.WireBadgeOverlay:
				ch.queue_redraw()
	if autosave_mgr != null:
		autosave_mgr.notify_interaction()

func remove_node_connections(g: GraphEdit, node_name: StringName) -> void:
	var wps: Dictionary = g.get_meta("wire_waypoints", {})
	for conn in g.get_connection_list():
		var fn: StringName = conn.get("from_node", conn.get("from", ""))
		var tn: StringName = conn.get("to_node", conn.get("to", ""))
		var fp := int(conn["from_port"])
		var tp := int(conn["to_port"])
		if fn == node_name or tn == node_name:
			wps.erase("%s:%d->%s:%d" % [fn, fp, tn, tp])
			g.disconnect_node(fn, fp, tn, tp)

func delete_graph_node(g: GraphEdit, node: GraphNode) -> void:
	if not is_instance_valid(node):
		return
	var kind: String = node.get_meta("node_kind", "")
	var gid: String = g.get_meta("graph_id", "world")
	remove_node_connections(g, node.name)
	g.remove_child(node)
	node.queue_free()
	if (kind == "receiver" or kind == "transmitter") and gid != "world":
		if factory_nodes.has(gid):
			var f_node: GraphNode = factory_nodes[gid]
			var parent_id: String = f_node.get_meta("parent_graph_id", "world")
			var parent_g: GraphEdit = self if parent_id == "world" else factory_graphs.get(parent_id, self)
			remove_node_connections(parent_g, f_node.name)
		builder.sync_factory_ports(gid)
	recalculate_all()

func delete_factory_recursive(fid: String, parent_graph: GraphEdit, f_node: GraphNode) -> void:
	if factory_graphs.has(fid):
		var fg: GraphEdit = factory_graphs[fid]
		for ch in fg.get_children():
			if ch is GraphNode and ch.get_meta("node_kind", "") == "factory":
				delete_factory_recursive(ch.get_meta("factory_id"), fg, ch)
		fg.queue_free()
		factory_graphs.erase(fid)
		factory_nodes.erase(fid)
		factory_parents.erase(fid)
	delete_graph_node(parent_graph, f_node)

func _on_settings_changed() -> void:
	db.refresh_localized_texts()
	_update_map_bounds()
	_refresh_valid_connection_types(self)
	for fid in factory_graphs.keys():
		if is_instance_valid(factory_graphs[fid]):
			_refresh_valid_connection_types(factory_graphs[fid])
	if topbar:
		topbar.refresh_translations()
	if tools:
		tools.refresh_translations()
	if serializer:
		serializer.refresh_translations()
	if custom_recipes_mgr:
		custom_recipes_mgr.refresh_translations()
	if shopping_modal:
		shopping_modal.refresh_translations()
	if production_modal:
		production_modal.refresh_translations()
	if oc_modal:
		oc_modal.refresh_translations()
	if grid_planner:
		grid_planner.refresh_translations()
	if map_markers:
		map_markers.refresh_translations()
	if popups:
		popups.refresh_translations()
	recalculate_all()
	queue_redraw()
