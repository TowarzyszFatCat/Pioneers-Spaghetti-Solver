class_name NodeStyler
extends RefCounted

var main_ctrl: GraphEdit
var db: AppDB
var settings: AppSettings
var i18n: AppI18n

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n) -> void:
	main_ctrl = p_main
	db = p_db
	settings = p_settings
	i18n = p_i18n

func style_node_card(node: GraphNode, header_col: Color, border_col: Color, body_tint: Color = Color.TRANSPARENT) -> void:
	node.z_index = 2
	node.set_meta("base_header_col", header_col)
	node.set_meta("base_border_col", border_col)
	node.set_meta("base_body_tint", body_tint)

	var is_built := bool(node.get_meta("is_built", false))
	var is_locked := bool(node.get_meta("is_locked", false))
	var eff_header := header_col.darkened(0.35) if is_built else header_col
	var eff_border := Color.html("#4B8052") if is_built else border_col
	if is_locked:
		eff_border = Color.html("#E5B842")

	var panel_sb := StyleBoxFlat.new()
	var base_bg := Color(0.10, 0.11, 0.14, 0.96)
	if body_tint != Color.TRANSPARENT:
		base_bg = base_bg.lerp(Color(body_tint.r, body_tint.g, body_tint.b, 0.96), 0.16)
	if is_built:
		base_bg = base_bg.darkened(0.25)

	panel_sb.bg_color = base_bg
	panel_sb.border_color = eff_border
	panel_sb.set_border_width_all(3 if is_locked else 2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 8
	panel_sb.content_margin_right = 8
	panel_sb.content_margin_top = 8
	panel_sb.content_margin_bottom = 8
	node.add_theme_stylebox_override("panel", panel_sb)

	var sel_sb := panel_sb.duplicate() as StyleBoxFlat
	sel_sb.border_color = Color.html("#FAB757")
	sel_sb.set_border_width_all(4)
	node.add_theme_stylebox_override("panel_selected", sel_sb)

	var title_sb := StyleBoxFlat.new()
	title_sb.bg_color = eff_header
	title_sb.border_color = eff_border
	title_sb.border_width_top = 3 if is_locked else 2
	title_sb.border_width_left = 3 if is_locked else 2
	title_sb.border_width_right = 3 if is_locked else 2
	title_sb.border_width_bottom = 2
	title_sb.corner_radius_top_left = 8
	title_sb.corner_radius_top_right = 8
	title_sb.content_margin_left = 8
	title_sb.content_margin_right = 8
	title_sb.content_margin_top = 6
	title_sb.content_margin_bottom = 6
	node.add_theme_stylebox_override("titlebar", title_sb)

	var title_sel := title_sb.duplicate() as StyleBoxFlat
	title_sel.bg_color = eff_header.lightened(0.14)
	title_sel.border_color = Color.html("#FAB757")
	node.add_theme_stylebox_override("titlebar_selected", title_sel)

func style_swatch_button(btn: Button, swatch_col: Color) -> void:
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = swatch_col
	normal_sb.border_color = Color.WHITE if swatch_col.get_luminance() < 0.5 else Color(0.1, 0.1, 0.1)
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(4)
	normal_sb.content_margin_left = 5
	normal_sb.content_margin_right = 5
	normal_sb.content_margin_top = 1
	normal_sb.content_margin_bottom = 1

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.border_color = Color.html("#FAB757")
	hover_sb.set_border_width_all(2)

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)

	var txt_col := Color(0.08, 0.08, 0.1) if swatch_col.get_luminance() > 0.52 else Color.WHITE
	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", txt_col)
	btn.add_theme_color_override("font_pressed_color", txt_col)
	btn.add_theme_font_size_override("font_size", 10)

func style_header_icon_btn(btn: Button, bg_col: Color, border_col: Color, txt_col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1

	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = bg_col.lightened(0.18)
	hov.border_color = Color.html("#FAB757")

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", txt_col)
	btn.add_theme_color_override("font_pressed_color", txt_col)
	btn.add_theme_font_size_override("font_size", 11)

func set_node_locked_state(node: GraphNode, locked: bool) -> void:
	if not is_instance_valid(node):
		return
	node.set_meta("is_locked", locked)
	if node.has_meta("hdr_lock_btn"):
		var l_btn: Button = node.get_meta("hdr_lock_btn")
		if is_instance_valid(l_btn):
			l_btn.set_pressed_no_signal(locked)
			l_btn.text = "🔒" if locked else "🔓"
			if locked:
				style_header_icon_btn(l_btn, Color.html("#5A4214"), Color.GOLD, Color.GOLD)
			else:
				style_header_icon_btn(l_btn, Color(0.12, 0.14, 0.18, 0.85), Color(0.45, 0.5, 0.6, 0.7), Color(0.85, 0.88, 0.92))

	if node.has_meta("hdr_del_btn"):
		var d_btn: Button = node.get_meta("hdr_del_btn")
		if is_instance_valid(d_btn):
			d_btn.disabled = locked
			d_btn.modulate = Color(1, 1, 1, 0.35) if locked else Color.WHITE

	var title_hbox := node.get_titlebar_hbox()
	_set_controls_locked_recursive(node, locked, title_hbox)
	
	if node.has_meta("base_header_col"):
		style_node_card(
			node,
			node.get_meta("base_header_col"),
			node.get_meta("base_border_col"),
			node.get_meta("base_body_tint")
		)

func _set_controls_locked_recursive(root: Node, locked: bool, skip_node: Node) -> void:
	for ch in root.get_children():
		if ch == skip_node:
			continue
		if ch is SpinBox:
			(ch as SpinBox).editable = not locked
		elif ch is LineEdit:
			(ch as LineEdit).editable = not locked
		elif ch is OptionButton:
			(ch as OptionButton).disabled = locked
		elif ch is Button:
			# Allow entering a locked Factory sub-graph while keeping its settings locked
			var enter_btn = root.get_meta("enter_btn", null) if root is GraphNode else null
			if ch != enter_btn:
				(ch as Button).disabled = locked
		if ch.get_child_count() > 0:
			_set_controls_locked_recursive(ch, locked, skip_node)

func set_node_built_state(node: GraphNode, built: bool) -> void:
	node.set_meta("is_built", built)
	if node.has_meta("hdr_built_btn"):
		var b_btn: Button = node.get_meta("hdr_built_btn")
		if is_instance_valid(b_btn):
			b_btn.set_pressed_no_signal(built)
			b_btn.text = "✓" if built else "☐"
			if built:
				style_header_icon_btn(b_btn, Color.html("#2E6F40"), Color.html("#76F5E8"), Color.SPRING_GREEN)
			else:
				style_header_icon_btn(b_btn, Color(0.12, 0.14, 0.18, 0.85), Color(0.45, 0.5, 0.6, 0.7), Color(0.85, 0.88, 0.92))
	if node.has_meta("base_header_col"):
		style_node_card(
			node,
			node.get_meta("base_header_col"),
			node.get_meta("base_border_col"),
			node.get_meta("base_body_tint")
		)
	node.modulate = Color(0.82, 0.92, 0.85, 0.92) if built else Color.WHITE


func setup_node_header_controls(node: GraphNode, item_key: String, on_delete: Callable, allow_built_check: bool = true) -> void:
	var title_hbox := node.get_titlebar_hbox()
	if title_hbox == null:
		return
	title_hbox.add_theme_constant_override("separation", 5)
	if title_hbox.get_child_count() > 0 and title_hbox.get_child(0) is Label:
		var title_lbl := title_hbox.get_child(0) as Label
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.clip_text = true

	var lock_btn := Button.new()
	lock_btn.toggle_mode = true
	lock_btn.text = "🔓"
	lock_btn.custom_minimum_size = Vector2(24, 20)
	lock_btn.focus_mode = Control.FOCUS_NONE
	lock_btn.tooltip_text = i18n.t("lock_toggle_tooltip")
	style_header_icon_btn(lock_btn, Color(0.12, 0.14, 0.18, 0.85), Color(0.45, 0.5, 0.6, 0.7), Color(0.85, 0.88, 0.92))
	lock_btn.toggled.connect(func(v: bool):
		set_node_locked_state(node, v)
		main_ctrl.recalculate_all()
	)
	title_hbox.add_child(lock_btn)
	title_hbox.move_child(lock_btn, 0)
	node.set_meta("hdr_lock_btn", lock_btn)

	if allow_built_check:
		var built_btn := Button.new()
		built_btn.toggle_mode = true
		built_btn.text = "☐"
		built_btn.custom_minimum_size = Vector2(24, 20)
		built_btn.focus_mode = Control.FOCUS_NONE
		built_btn.tooltip_text = i18n.t("built_toggle_tooltip")
		style_header_icon_btn(built_btn, Color(0.12, 0.14, 0.18, 0.85), Color(0.45, 0.5, 0.6, 0.7), Color(0.85, 0.88, 0.92))
		built_btn.toggled.connect(func(v: bool):
			set_node_built_state(node, v)
			main_ctrl.recalculate_all()
		)
		title_hbox.add_child(built_btn)
		title_hbox.move_child(built_btn, 0)
		node.set_meta("hdr_built_btn", built_btn)

	if item_key != "":
		var btn_p := Button.new()
		btn_p.text = "HEX #1"
		btn_p.custom_minimum_size = Vector2(24, 20)
		btn_p.focus_mode = Control.FOCUS_NONE

		var btn_s := Button.new()
		btn_s.text = "HEX #2"
		btn_s.custom_minimum_size = Vector2(24, 20)
		btn_s.focus_mode = Control.FOCUS_NONE

		btn_p.pressed.connect(func():
			var hex_code: String = String(node.get_meta("hex_primary", "#FFFFFF"))
			DisplayServer.clipboard_set(hex_code)
			btn_p.text = "✓"
			node.get_tree().create_timer(0.6).timeout.connect(func():
				if is_instance_valid(btn_p):
					btn_p.text = "HEX #1"
			)
		)
		btn_s.pressed.connect(func():
			var hex_code: String = String(node.get_meta("hex_secondary", "#FFFFFF"))
			DisplayServer.clipboard_set(hex_code)
			btn_s.text = "✓"
			node.get_tree().create_timer(0.6).timeout.connect(func():
				if is_instance_valid(btn_s):
					btn_s.text = "HEX #2"
			)
		)
		title_hbox.add_child(btn_p)
		title_hbox.add_child(btn_s)
		node.set_meta("hdr_btn_p", btn_p)
		node.set_meta("hdr_btn_s", btn_s)
		node.set_meta("hdr_color_item", item_key)
		update_header_color_buttons(node, item_key)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size = Vector2(24, 20)
	del_btn.focus_mode = Control.FOCUS_NONE
	del_btn.tooltip_text = i18n.t("delete_node_tooltip")
	style_header_icon_btn(del_btn, Color(0.55, 0.14, 0.16, 0.92), Color.SALMON, Color.WHITE)
	del_btn.pressed.connect(func():
		if not bool(node.get_meta("is_locked", false)):
			on_delete.call()
	)
	title_hbox.add_child(del_btn)
	node.set_meta("hdr_del_btn", del_btn)

func update_header_color_buttons(node: GraphNode, item_key: String = "") -> void:
	if node.has_meta("hdr_lock_btn"):
		var l_btn: Button = node.get_meta("hdr_lock_btn")
		if is_instance_valid(l_btn):
			l_btn.tooltip_text = i18n.t("lock_toggle_tooltip")
	if node.has_meta("hdr_built_btn"):
		var b_btn: Button = node.get_meta("hdr_built_btn")
		if is_instance_valid(b_btn):
			b_btn.tooltip_text = i18n.t("built_toggle_tooltip")
	if node.has_meta("hdr_del_btn"):
		var d_btn: Button = node.get_meta("hdr_del_btn")
		if is_instance_valid(d_btn):
			d_btn.tooltip_text = i18n.t("delete_node_tooltip")
	if not node.has_meta("hdr_btn_p") or not node.has_meta("hdr_btn_s"):
		return
	var key := item_key if item_key != "" else String(node.get_meta("hdr_color_item", ""))
	if key == "":
		return
	node.set_meta("hdr_color_item", key)
	var pal := db.get_item_palette(key)
	var prim: Color = pal["primary"]
	var sec: Color = pal["secondary"]
	var hex_p := "#" + prim.to_html(false).to_upper()
	var hex_s := "#" + sec.to_html(false).to_upper()
	node.set_meta("hex_primary", hex_p)
	node.set_meta("hex_secondary", hex_s)

	var btn_p: Button = node.get_meta("hdr_btn_p")
	var btn_s: Button = node.get_meta("hdr_btn_s")
	if is_instance_valid(btn_p):
		style_swatch_button(btn_p, prim)
		btn_p.tooltip_text = i18n.tf("copy_prim_tooltip", [hex_p])
	if is_instance_valid(btn_s):
		style_swatch_button(btn_s, sec)
		btn_s.tooltip_text = i18n.tf("copy_sec_tooltip", [hex_s])


func apply_compact_mode(node: GraphNode, is_compact: bool, machine_compact_width: float = 175.0) -> void:
	if node.has_meta("_last_compact_state") and bool(node.get_meta("_last_compact_state")) == is_compact:
		return
	node.set_meta("_last_compact_state", is_compact)
	if node.has_meta("hdr_btn_p"):
		var bp: Button = node.get_meta("hdr_btn_p")
		if is_instance_valid(bp):
			bp.visible = not is_compact
	if node.has_meta("hdr_btn_s"):
		var bs: Button = node.get_meta("hdr_btn_s")
		if is_instance_valid(bs):
			bs.visible = not is_compact
	for meta_key in ["sep_row", "showcase_row", "ctrl_row", "action_row", "pwr_row", "plan_row"]:
		if node.has_meta(meta_key):
			var ctrl: Control = node.get_meta(meta_key)
			if is_instance_valid(ctrl):
				if meta_key == "pwr_row":
					ctrl.visible = (not is_compact) and settings.show_power
				else:
					ctrl.visible = not is_compact
	var kind := String(node.get_meta("node_kind", ""))
	if is_compact:
		var cw := machine_compact_width if kind in ["machine", "splitter", "even_splitter", "prop_splitter", "receiver", "transmitter", "container", "depot", "awesome_sink"] else 240.0
		node.custom_minimum_size = Vector2(cw, 0)
		node.size = Vector2(cw, 0)
	elif node.has_meta("fixed_width"):
		var fw := float(node.get_meta("fixed_width"))
		node.custom_minimum_size = Vector2(fw, 0)
		node.size = Vector2(fw, 0)

func create_icon_slot(key_or_name: String, slot_size: int = 36, custom_col: Color = Color.TRANSPARENT) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(slot_size, slot_size)
	var bg_col := Color(0.07, 0.08, 0.1, 0.95)
	var border_col := Color.WHITE
	if custom_col != Color.TRANSPARENT:
		bg_col = custom_col.darkened(0.65)
		bg_col.a = 0.95
		border_col = custom_col.lightened(0.2)
	elif db.items.has(key_or_name) or db.ITEM_PALETTE.has(key_or_name.to_lower()):
		var pal := db.get_item_palette(key_or_name)
		var prim: Color = pal["primary"]
		bg_col = prim.darkened(0.55) if prim.get_luminance() > 0.25 else prim.darkened(0.15)
		bg_col.a = 0.95
		border_col = pal["border"]
	else:
		var c := db.get_item_color(key_or_name)
		border_col = c.lightened(0.2)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(2 if slot_size >= 32 else 1)
	sb.set_corner_radius_all(6 if slot_size >= 32 else 4)
	frame.add_theme_stylebox_override("panel", sb)

	var tex := db.get_icon_texture(key_or_name)
	if tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = tex
		tex_rect.custom_minimum_size = Vector2(slot_size - 4, slot_size - 4)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(tex_rect)
		return frame

	var lbl := Label.new()
	var dname := db.get_item_display_name(key_or_name)
	var words := dname.split(" ")
	var initials := ""
	for w in words:
		if w.length() > 0 and initials.length() < 2:
			initials += w.substr(0, 1).to_upper()
	lbl.text = ("💧" if db.is_item_fluid(key_or_name) else initials)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.modulate = border_col.lightened(0.35)
	lbl.add_theme_font_size_override("font_size", 12 if slot_size >= 32 else 9)
	frame.add_child(lbl)
	return frame

func apply_item_button_visuals(btn: Button, item_key: String) -> void:
	btn.text = "  " + db.get_item_display_name(item_key)
	btn.icon = db.get_icon_texture(item_key)
	btn.expand_icon = true
	btn.modulate = db.get_item_color(item_key).lightened(0.25)
