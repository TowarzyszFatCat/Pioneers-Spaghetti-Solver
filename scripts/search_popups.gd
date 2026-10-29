class_name SearchPopups
extends RefCounted

var main_ctrl: GraphEdit

var search_popup: PopupPanel
var search_input: LineEdit
var search_list: VBoxContainer
var cached_special_btns: Array[Dictionary] = []
var cached_cat_headers: Dictionary = {}
var cached_recipe_btns: Array[Dictionary] = []

var item_picker_popup: PopupPanel
var item_picker_input: LineEdit
var item_picker_list: VBoxContainer
var cached_item_btns: Array[Dictionary] = []
var pending_item_callback: Callable
var pending_item_only_fuels: bool = false

func _init(p_main: GraphEdit) -> void:
	main_ctrl = p_main

func is_any_popup_visible() -> bool:
	return (search_popup != null and search_popup.visible) or (item_picker_popup != null and item_picker_popup.visible)

func build_search_popup(parent_layer: CanvasLayer, theme_ref: Theme) -> void:
	search_popup = PopupPanel.new()
	search_popup.theme = theme_ref
	parent_layer.add_child(search_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	search_popup.add_child(vbox)

	search_input = LineEdit.new()
	search_input.placeholder_text = main_ctrl.i18n.t("search_placeholder")
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(func(q: String): filter_search_list(q))
	vbox.add_child(search_input)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(600, 400)
	vbox.add_child(scroll)

	search_list = VBoxContainer.new()
	search_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_list.add_theme_constant_override("separation", 3)
	scroll.add_child(search_list)

	# Build and preload all recipe buttons and icons on startup
	rebuild_search_cache()
	filter_search_list("")

func rebuild_search_cache() -> void:
	if search_list == null:
		return
	for ch in search_list.get_children():
		ch.queue_free()
	cached_special_btns.clear()
	cached_cat_headers.clear()
	cached_recipe_btns.clear()

	var specials := [
		{"type": "factory", "key": "factory_node"},
		{"type": "receiver", "key": "receiver_in"},
		{"type": "transmitter", "key": "transmitter_out"},
		{"type": "reroute", "key": "reroute_node"},
		{"type": "splitter", "key": "splitter_node"},
		{"type": "even_splitter", "key": "even_splitter_node"},
		{"type": "prop_splitter", "key": "prop_splitter_node"},
		{"type": "manual_splitter", "key": "manual_splitter_node"},
		{"type": "container", "key": "container_node"},
		{"type": "depot", "key": "depot_node"},
		{"type": "awesome_sink", "key": "awesome_sink_node"},
		{"type": "truck_station", "key": "truck_station_node"},
		{"type": "train_station", "key": "train_station_node"}
	]

	for sp in specials:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.modulate = Color.LIGHT_SKY_BLUE
		var stype: String = sp["type"]
		btn.text = "  " + main_ctrl.i18n.t(sp["key"])
		btn.pressed.connect(func():
			search_popup.hide()
			main_ctrl._on_special_selected(stype)
		)
		search_list.add_child(btn)
		cached_special_btns.append({"btn": btn, "type": stype, "key": sp["key"]})

	var current_cat := ""
	var db = main_ctrl.db
	for r_id in db.recipes.keys():
		var data: Dictionary = db.recipes[r_id]
		var cat: String = data["category"]
		var cat_en: String = String(data.get("category_en", cat))
		var b_key: String = data.get("building_key", "constructor")
		var is_gen: bool = data.get("is_generator", false)
		var cat_col = db.get_category_color(b_key, data.get("is_miner", false), is_gen)

		if cat_en != current_cat and not cached_cat_headers.has(cat_en):
			current_cat = cat_en
			var hdr := Label.new()
			hdr.text = "── " + cat.to_upper() + " ──"
			hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hdr.modulate = cat_col.lightened(0.35)
			search_list.add_child(hdr)
			cached_cat_headers[cat_en] = hdr

		var btn := Button.new()
		btn.text = "  " + String(data["title"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.modulate = cat_col.lightened(0.45) if not data.get("is_alternate", false) else Color(1.0, 0.88, 0.55)
		var main_item: String = data["outputs"][0]["item"] if data["outputs"].size() > 0 else (data["inputs"][0]["item"] if data["inputs"].size() > 0 else b_key)

		# Preload icon immediately during startup so the first right-click never lags
		var tex = db.get_icon_texture(main_item)
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true

		var rid_copy: String = r_id
		var raw_en: String = String(data.get("raw_name_en", ""))
		var entry := {
			"btn": btn,
			"r_id": rid_copy,
			"cat_en": cat_en,
			"search_str": (String(data["title"]) + " " + raw_en + " " + cat + " " + cat_en).to_lower(),
			"main_item": main_item,
			"icon_loaded": true,
			"matched_port": -1
		}
		btn.pressed.connect(func():
			search_popup.hide()
			main_ctrl._on_recipe_selected(rid_copy, int(entry["matched_port"]))
		)
		search_list.add_child(btn)
		cached_recipe_btns.append(entry)

func open_search_popup() -> void:
	search_input.text = ""
	filter_search_list("")
	var vp_size := main_ctrl.get_viewport_rect().size
	var pop_size := Vector2i(mini(430, int(vp_size.x * 0.85)), mini(450, int(vp_size.y * 0.8)))
	var mpos := Vector2i(main_ctrl.get_viewport().get_mouse_position())
	search_popup.popup(Rect2i(mpos, pop_size))
	search_input.grab_focus()

func filter_search_list(query: String) -> void:
	var q := query.strip_edges().to_lower()
	var is_world = (main_ctrl.active_graph == main_ctrl)
	var p_filter = main_ctrl.pending_filter_item
	var p_rev = main_ctrl.pending_is_reverse
	var db = main_ctrl.db

	# If custom recipes were added or removed, rebuild cache first
	if cached_recipe_btns.size() != db.recipes.size():
		rebuild_search_cache()

	for sp in cached_special_btns:
		var btn: Button = sp["btn"]
		var stype: String = sp["type"]
		var title = main_ctrl.i18n.t(sp["key"])
		btn.text = "  " + title
		var show := true
		if stype == "factory" and p_filter != "":
			show = false
		elif stype == "receiver" and (is_world or (p_filter != "" and not p_rev)):
			show = false
		elif stype == "transmitter" and (is_world or (p_filter != "" and p_rev)):
			show = false
		elif stype in ["awesome_sink", "depot"] and (p_filter != "" and p_rev):
			show = false
		if q != "" and not title.to_lower().contains(q):
			show = false
		btn.visible = show

	var visible_cats: Dictionary = {}
	for entry in cached_recipe_btns:
		var btn: Button = entry["btn"]
		var r_id: String = entry["r_id"]
		if not db.recipes.has(r_id):
			btn.visible = false
			continue
		var data: Dictionary = db.recipes[r_id]
		if not main_ctrl.settings.show_alternates and data.get("is_alternate", false):
			btn.visible = false
			continue
		var matched_port := -1
		if p_filter != "":
			var target_list: Array = data["outputs"] if p_rev else data["inputs"]
			for i in range(target_list.size()):
				if target_list[i]["item"] == p_filter:
					matched_port = i
					break
			if matched_port == -1:
				btn.visible = false
				continue
		if q != "" and not String(entry["search_str"]).contains(q):
			btn.visible = false
			continue
		entry["matched_port"] = matched_port
		btn.visible = true
		visible_cats[entry["cat_en"]] = true

	for cat_en in cached_cat_headers.keys():
		cached_cat_headers[cat_en].visible = visible_cats.has(cat_en)

func build_item_picker_popup(parent_layer: CanvasLayer, theme_ref: Theme) -> void:
	item_picker_popup = PopupPanel.new()
	item_picker_popup.theme = theme_ref
	parent_layer.add_child(item_picker_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	item_picker_popup.add_child(vbox)

	item_picker_input = LineEdit.new()
	item_picker_input.placeholder_text = main_ctrl.i18n.t("item_picker_placeholder")
	item_picker_input.clear_button_enabled = true
	item_picker_input.text_changed.connect(func(q: String): filter_item_picker(q))
	vbox.add_child(item_picker_input)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(340, 340)
	vbox.add_child(scroll)

	item_picker_list = VBoxContainer.new()
	item_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_picker_list.add_theme_constant_override("separation", 3)
	scroll.add_child(item_picker_list)

	var db = main_ctrl.db
	for ikey in db.item_order:
		var dname = db.get_item_display_name(ikey)
		var en_name := String(db.items.get(ikey, {}).get("name", ikey))
		var btn := Button.new()
		btn.text = "  " + dname
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.modulate = db.get_item_color(ikey).lightened(0.35)

		# Preload item icon immediately on startup
		var tex = db.get_icon_texture(ikey)
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true

		var k_copy = ikey
		var entry := {
			"btn": btn,
			"key": k_copy,
			"search_str": (dname + " " + en_name + " " + k_copy).to_lower(),
			"icon_loaded": true
		}
		btn.pressed.connect(func():
			item_picker_popup.hide()
			if pending_item_callback.is_valid():
				pending_item_callback.call(k_copy)
		)
		item_picker_list.add_child(btn)
		cached_item_btns.append(entry)

	filter_item_picker("")

func refresh_translations() -> void:
	if search_input:
		search_input.placeholder_text = main_ctrl.i18n.t("search_placeholder")
	var db = main_ctrl.db
	if cached_recipe_btns.size() != db.recipes.size():
		rebuild_search_cache()
	else:
		for sp in cached_special_btns:
			(sp["btn"] as Button).text = "  " + main_ctrl.i18n.t(sp["key"])
		for entry in cached_recipe_btns:
			var r_id: String = entry["r_id"]
			if not db.recipes.has(r_id):
				continue
			var data: Dictionary = db.recipes[r_id]
			var cat: String = String(data["category"])
			var cat_en: String = String(data.get("category_en", cat))
			var raw_en: String = String(data.get("raw_name_en", ""))
			(entry["btn"] as Button).text = "  " + String(data["title"])
			entry["search_str"] = (String(data["title"]) + " " + raw_en + " " + cat + " " + cat_en).to_lower()
			if cached_cat_headers.has(cat_en):
				(cached_cat_headers[cat_en] as Label).text = "── " + cat.to_upper() + " ──"

	if item_picker_input:
		item_picker_input.placeholder_text = main_ctrl.i18n.t("item_picker_placeholder")
	for entry in cached_item_btns:
		var ikey: String = entry["key"]
		var dname = db.get_item_display_name(ikey)
		var en_name := String(db.items.get(ikey, {}).get("name", ikey))
		(entry["btn"] as Button).text = "  " + dname
		entry["search_str"] = (dname + " " + en_name + " " + ikey).to_lower()

func open_item_picker(callback: Callable, only_fuels: bool = false) -> void:
	pending_item_callback = callback
	pending_item_only_fuels = only_fuels
	item_picker_input.text = ""
	filter_item_picker("")
	var mpos := Vector2i(main_ctrl.get_viewport().get_mouse_position())
	item_picker_popup.popup(Rect2i(mpos, Vector2i(360, 400)))
	item_picker_input.grab_focus()

func filter_item_picker(query: String) -> void:
	var q := query.strip_edges().to_lower()
	var db = main_ctrl.db
	for entry in cached_item_btns:
		var btn: Button = entry["btn"]
		var ikey: String = String(entry["key"])
		if pending_item_only_fuels and not db.is_item_fuel(ikey):
			btn.visible = false
			continue
		var vis := (q == "" or String(entry["search_str"]).contains(q))
		btn.visible = vis
