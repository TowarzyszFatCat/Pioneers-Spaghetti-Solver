class_name AppI18n
extends RefCounted

signal language_changed(new_lang: String)

const USER_I18N_TEMPLATE := "user://i18n_template.json"
const HUMAN_VERIFIED_LANGS := ["en", "en-us", "en-gb", "pl", "pl-pl"]

var current_lang: String = "en"
var game_loader: I18nGameLoader
var _ui_dicts_cache: Dictionary = {}
var _active_ui_dict: Dictionary = {}
var _is_en_active: bool = false

func _init() -> void:
	game_loader = I18nGameLoader.new()
	game_loader.scan_available_languages()
	_scan_ui_dictionaries()
	_refresh_active_lang_cache()
	load_external_translations()

func _scan_ui_dictionaries() -> void:
	_ui_dicts_cache.clear()
	var script_ref := I18nUIDefaults as Script
	if script_ref == null:
		return
	var cmap: Dictionary = script_ref.get_script_constant_map()
	for const_name in cmap.keys():
		var cname := String(const_name)
		if cname.begins_with("UI_") and cmap[const_name] is Dictionary:
			var lang_suffix := cname.trim_prefix("UI_").to_lower().replace("_", "-")
			_ui_dicts_cache[lang_suffix] = cmap[const_name]

func _resolve_ui_dict_for_lang(lang_code: String) -> Dictionary:
	if _ui_dicts_cache.is_empty():
		_scan_ui_dictionaries()
	var norm := lang_code.to_lower().replace("_", "-")
	if _ui_dicts_cache.has(norm):
		return _ui_dicts_cache[norm]
	var prefix := norm.split("-")[0]
	if _ui_dicts_cache.has(prefix):
		return _ui_dicts_cache[prefix]
	for k in _ui_dicts_cache.keys():
		if String(k).split("-")[0] == prefix:
			return _ui_dicts_cache[k]
	return {}

func _refresh_active_lang_cache() -> void:
	_is_en_active = current_lang.to_lower().begins_with("en")
	_active_ui_dict = I18nUIDefaults.UI_EN if _is_en_active else _resolve_ui_dict_for_lang(current_lang)

func get_available_languages() -> Array[String]:
	var list: Array[String] = game_loader.available_languages.duplicate()
	if _ui_dicts_cache.is_empty():
		_scan_ui_dictionaries()
	for ui_code in _ui_dicts_cache.keys():
		var code_str := String(ui_code)
		var found := false
		for existing in list:
			if existing.to_lower().split("-")[0] == code_str.split("-")[0]:
				found = true
				break
		if not found:
			list.append(code_str)
	return list

func get_language_display_name(lang_code: String) -> String:
	return game_loader.get_language_display_name(lang_code)

func is_ai_translation(lang_code: String) -> bool:
	var norm := lang_code.to_lower().replace("_", "-")
	var prefix := norm.split("-")[0]
	return not (norm in HUMAN_VERIFIED_LANGS or prefix in HUMAN_VERIFIED_LANGS)

func get_language_completion_info(lang_code: String, _db_ref = null) -> Dictionary:
	var norm := lang_code.to_lower().replace("_", "-")
	var prefix := norm.split("-")[0]
	var total_ui := maxi(1, I18nUIDefaults.UI_EN.size())
	var ui_pct := 0

	if prefix == "en":
		ui_pct = 100
	else:
		var ui_dict := _resolve_ui_dict_for_lang(lang_code)
		if not ui_dict.is_empty():
			var translated_cnt := 0
			for k in ui_dict.keys():
				if I18nUIDefaults.UI_EN.has(k) and String(ui_dict[k]).strip_edges() != "":
					translated_cnt += 1
			ui_pct = clampi(int(roundf((float(translated_cnt) / float(total_ui)) * 100.0)), 0, 100)

	var has_game_file := ( prefix == "en" or (lang_code in game_loader.available_languages) )
	if not has_game_file:
		for av in game_loader.available_languages:
			if av.to_lower().split("-")[0] == prefix:
				has_game_file = true
				break
	var game_pct := 100 if has_game_file else 0
	var overall_pct := int(roundf(float(ui_pct) * 0.5 + float(game_pct) * 0.5))

	return {
		"ui_pct": ui_pct,
		"game_pct": game_pct,
		"overall_pct": overall_pct,
		"is_ai": is_ai_translation(lang_code)
	}

func get_language_option_label(lang_code: String, db_ref = null) -> String:
	var base_name := get_language_display_name(lang_code)
	var info := get_language_completion_info(lang_code, db_ref)
	var ui_p := int(info["ui_pct"])
	var game_p := int(info["game_pct"])
	var ai_tag := " 🤖 [AI]" if bool(info["is_ai"]) else " ✓"
	var ui_lbl := t("lang_ui_short")
	var game_lbl := t("lang_game_short")
	return "%s%s  —  %s: %d%% | %s: %d%%" % [base_name, ai_tag, ui_lbl, ui_p, game_lbl, game_p]

func set_language(lang: String) -> void:
	var target_lang := lang
	var avail := get_available_languages()
	if not (target_lang in avail):
		if target_lang == "en" and ("en-US" in avail):
			target_lang = "en-US"
		else:
			var pref := target_lang.to_lower().split("-")[0]
			for a in avail:
				if a.to_lower().split("-")[0] == pref:
					target_lang = a
					break
	game_loader.ensure_language_loaded(target_lang)
	var changed := (current_lang != target_lang)
	current_lang = target_lang
	_refresh_active_lang_cache()
	if changed:
		language_changed.emit(current_lang)

func t(key: String) -> String:
	if not _is_en_active:
		if key.begins_with("belt_mk") and key.length() == 8:
			var mk_num := key.right(1)
			var g_belt := game_loader.lookup_raw(current_lang, "Conveyor Belt Mk.%s" % mk_num)
			if g_belt != "":
				return g_belt
		elif key in ["pipe_mk1", "pipe_mk2"]:
			var mk_num := key.right(1)
			var g_pipe := game_loader.lookup_raw(current_lang, "Pipeline Mk.%s" % mk_num)
			if g_pipe != "":
				return g_pipe

		if _active_ui_dict.has(key):
			var val := String(_active_ui_dict[key])
			if val != "":
				return val

	return String(I18nUIDefaults.UI_EN.get(key, key))

func tf(key: String, args: Array) -> String:
	return t(key) % args

func t_building(b_key_or_name: String, fallback: String = "") -> String:
	var fb := fallback if fallback != "" else b_key_or_name
	if _is_en_active:
		return fb
	var game_trans := game_loader.translate_building(current_lang, b_key_or_name, fb)
	if game_trans != "":
		return game_trans
	return fb

func t_item(item_key: String, fallback: String = "") -> String:
	var fb := fallback if fallback != "" else item_key.replace("-", " ").capitalize()
	if _is_en_active:
		return fb
	var game_trans := game_loader.translate_item(current_lang, item_key, fb)
	if game_trans != "":
		return game_trans
	return fb

func t_recipe(rec_id: String, raw_en_name: String) -> String:
	if _is_en_active:
		return raw_en_name

	var game_trans := game_loader.translate_recipe(current_lang, rec_id, raw_en_name)
	if game_trans != "":
		return game_trans

	if raw_en_name.begins_with("Alternate:"):
		var core_name := raw_en_name.trim_prefix("Alternate:").strip_edges()
		var clean_id := rec_id.trim_prefix("alt-").trim_prefix("alternate-")
		var trans_core := _translate_recipe_core(clean_id, core_name)
		return t("alt_prefix") + trans_core
	return _translate_recipe_core(rec_id, raw_en_name)

func _translate_recipe_core(rec_id: String, core_en_name: String) -> String:
	var game_core := game_loader.translate_recipe(current_lang, rec_id, core_en_name)
	if game_core != "":
		return game_core

	var slug := core_en_name.to_lower().replace(" ", "-")
	var item_trans := game_loader.translate_item(current_lang, slug, core_en_name)
	if item_trans != "":
		return item_trans

	if core_en_name.begins_with("Unpackage "):
		var fluid_en := core_en_name.trim_prefix("Unpackage ").strip_edges()
		var fluid_slug := fluid_en.to_lower().replace(" ", "-")
		return tf("unpackage_prefix", [t_item(fluid_slug, fluid_en)])
	if core_en_name.begins_with("Packaged "):
		var fluid_en := core_en_name.trim_prefix("Packaged ").strip_edges()
		var fluid_slug := fluid_en.to_lower().replace(" ", "-")
		return tf("packaged_prefix", [t_item(fluid_slug, fluid_en)])
	if core_en_name.begins_with("Biomass (") and core_en_name.ends_with(")"):
		var inner_en := core_en_name.trim_prefix("Biomass (").trim_suffix(")")
		var inner_slug := inner_en.to_lower().replace(" ", "-")
		return tf("biomass_fmt", [t_item(inner_slug, inner_en)])
	return core_en_name

func load_external_translations() -> void:
	_scan_ui_dictionaries()
	_refresh_active_lang_cache()
	game_loader.ensure_language_loaded(current_lang)

func export_translation_template(db_ref) -> String:
	var cur_ui: Dictionary = I18nUIDefaults.UI_EN.duplicate()
	var lang_dict := _resolve_ui_dict_for_lang(current_lang)
	if not lang_dict.is_empty():
		cur_ui.merge(lang_dict, true)

	var out_buildings: Dictionary = {}
	var out_items: Dictionary = {}
	var out_recipes: Dictionary = {}
	if db_ref != null:
		for b_key in db_ref.buildings.keys():
			var b_en := String(db_ref.buildings[b_key].get("name", b_key))
			out_buildings[b_key] = t_building(b_key, b_en)
		for i_key in db_ref.items.keys():
			var i_en := String(db_ref.items[i_key].get("name", i_key))
			out_items[i_key] = t_item(i_key, i_en)
		for r_id in db_ref.recipes.keys():
			var r: Dictionary = db_ref.recipes[r_id]
			var raw_en := String(r.get("raw_name_en", r.get("raw_name", r_id)))
			out_recipes[r_id] = t_recipe(r_id, raw_en)

	var payload := {
		"lang": current_lang,
		"ui": cur_ui,
		"buildings": out_buildings,
		"items": out_items,
		"recipes": out_recipes
	}
	var template_path := "user://i18n_template_%s.json" % current_lang.replace("-", "_")
	var f := FileAccess.open(template_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload, "\t"))
	return ProjectSettings.globalize_path(template_path)
