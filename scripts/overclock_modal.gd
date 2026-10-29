class_name OverclockModal
extends RefCounted

var main_ctrl: GraphEdit
var i18n: AppI18n
var win: Window
var oc_vbox: VBoxContainer
var active_node: GraphNode = null

func _init(p_main: GraphEdit, p_i18n: AppI18n) -> void:
	main_ctrl = p_main
	i18n = p_i18n

func build_window(parent_layer: CanvasLayer, theme_ref: Theme) -> Window:
	win = Window.new()
	win.theme = theme_ref
	win.title = i18n.t("oc_title")
	win.size = Vector2i(500, 300)
	win.visible = false
	win.close_requested.connect(func(): win.hide())
	parent_layer.add_child(win)
	
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	win.add_child(margin)
	
	oc_vbox = VBoxContainer.new()
	oc_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(oc_vbox)
	return win

func refresh_translations() -> void:
	if win and win.visible and is_instance_valid(active_node):
		open_for_node(active_node)
	elif win:
		win.title = i18n.t("oc_title")

func open_for_node(node: GraphNode) -> void:
	active_node = node
	for ch in oc_vbox.get_children():
		ch.queue_free()
	
	win.title = i18n.t("oc_title") + " — " + node.title
	var m := float(node.get_meta("machines"))
	var clk := float(node.get_meta("clock")) / 100.0
	var total_work := m * clk
	
	var m_power := maxf(1.0, ceilf(total_work))
	var clk_power := snappedf((total_work / m_power) * 100.0, 0.0001)
	_add_oc_row(
		i18n.t("oc_power"),
		"%dx @ %.4f%%" % [int(m_power), clk_power],
		"%.4f" % clk_power,
		node, m_power, clk_power
	)
	
	var full_m := int(floorf(total_work))
	var rem_clk := snappedf(fmod(total_work, 1.0) * 100.0, 0.0001)
	var prec_desc := "%dx @ 100.0000%%" % full_m if rem_clk < 0.0001 else ("%dx @ 100%%  +  1x @ %.4f%%" % [full_m, rem_clk])
	var copy_val := "%.4f" % (rem_clk if rem_clk >= 0.0001 else 100.0)
	_add_oc_row(
		i18n.t("oc_exact"),
		prec_desc,
		copy_val,
		node, total_work, 100.0
	)
	
	var m_space := maxf(1.0, ceilf(total_work / 2.5))
	var clk_space := snappedf((total_work / m_space) * 100.0, 0.0001)
	_add_oc_row(
		i18n.t("oc_space"),
		"%dx @ %.4f%%" % [int(m_space), clk_space],
		"%.4f" % clk_space,
		node, m_space, clk_space
	)
	
	if not win.visible:
		win.popup_centered()

func _add_oc_row(title: String, details: String, clip_num: String, node: GraphNode, apply_m: float, apply_clk: float) -> void:
	var box := VBoxContainer.new()
	var t_lbl := Label.new()
	t_lbl.text = title
	t_lbl.modulate = Color.LIGHT_SKY_BLUE
	box.add_child(t_lbl)
	
	var hbox := HBoxContainer.new()
	var d_lbl := Label.new()
	d_lbl.text = "   " + details
	d_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(d_lbl)
	
	var cp_btn := Button.new()
	cp_btn.text = "%s (%s)" % [i18n.t("copy_btn"), clip_num]
	cp_btn.pressed.connect(func(): DisplayServer.clipboard_set(clip_num))
	hbox.add_child(cp_btn)
	
	var ap_btn := Button.new()
	ap_btn.text = i18n.t("apply_btn")
	ap_btn.modulate = Color.LIGHT_GREEN
	ap_btn.pressed.connect(func():
		var spin: SpinBox = node.get_meta("spinbox")
		var clk_spin: SpinBox = node.get_meta("clk_spinbox")
		spin.value = apply_m
		clk_spin.value = apply_clk
		main_ctrl.recalculate_all()
		win.hide()
	)
	hbox.add_child(ap_btn)
	box.add_child(hbox)
	oc_vbox.add_child(box)
