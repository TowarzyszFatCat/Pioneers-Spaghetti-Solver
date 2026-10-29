class_name AppDB
extends RefCounted

const DATA_JSON_PATHS := ["res://data/data.json", "res://data.json"]
const STATIC_META_PATHS := ["res://data/static_game_data.json", "res://static_game_data.json"]
const LEGACY_RECIPES_PATH := "res://data/recipes.json"
const USER_RECIPES_PATH := "user://custom_recipes.json"
const MAPS_FOLDER := "res://data/maps"

var i18n: AppI18n
var items: Dictionary = {}
var item_order: Array[String] = []
var item_colors: Dictionary = {}
var item_palettes: Dictionary = {}
var icon_path_map: Dictionary = {}
var icon_cache: Dictionary = {}
var available_maps: Array[Dictionary] = []
var buildings: Dictionary = {}
var belts: Array = []
var pipes: Array = []
var recipes: Dictionary = {}

# Loaded dynamically from res://data/static_game_data.json
var VALID_FUELS: Array = []
var CUSTOM_RECIPE_BUILDINGS: Array = []
var ITEM_PALETTE: Dictionary = {}
var MINER_TIERS: Dictionary = {}
var OFFICIAL_BUILDING_POWER: Dictionary = {}
var BUILDING_META: Dictionary = {}
var AWESOME_POINTS: Dictionary = {}
var _power_generators_data: Dictionary = {}

func _init(p_i18n: AppI18n = null) -> void:
	i18n = p_i18n if p_i18n != null else AppI18n.new()
	_load_static_game_data()
	_build_icon_index()
	_scan_maps_folder()
	load_all()

func _load_static_game_data() -> void:
	for p in STATIC_META_PATHS:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f == null:
				continue
			var parsed = JSON.parse_string(f.get_as_text())
			if not (parsed is Dictionary):
				continue
			VALID_FUELS = parsed.get("valid_fuels", [])
			CUSTOM_RECIPE_BUILDINGS = parsed.get("custom_recipe_buildings", [])
			ITEM_PALETTE = parsed.get("item_palette", {})
			OFFICIAL_BUILDING_POWER = parsed.get("official_building_power", {})
			AWESOME_POINTS = parsed.get("awesome_points", {})
			_power_generators_data = parsed.get("power_generators", {})

			MINER_TIERS.clear()
			var raw_tiers: Dictionary = parsed.get("miner_tiers", {})
			for k in raw_tiers.keys():
				MINER_TIERS[int(String(k))] = raw_tiers[k]

			BUILDING_META.clear()
			var raw_meta: Dictionary = parsed.get("building_meta", {})
			for b_key in raw_meta.keys():
				var entry: Dictionary = (raw_meta[b_key] as Dictionary).duplicate(true)
				var sf = entry.get("size_f", [1.5, 1.5])
				if sf is Array and sf.size() >= 2:
					entry["size_f"] = Vector2(float(sf[0]), float(sf[1]))
				elif not (sf is Vector2):
					entry["size_f"] = Vector2(1.5, 1.5)
				BUILDING_META[b_key] = entry
			return

func is_item_fuel(item_key: String) -> bool:
	return item_key.to_lower() in VALID_FUELS

func get_building_height_m(building_key: String) -> float:
	if BUILDING_META.has(building_key):
		return float(BUILDING_META[building_key].get("height_m", 8.0))
	return 8.0

func _scan_maps_folder() -> void:
	available_maps.clear()
	for folder in [MAPS_FOLDER, "res://"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				var clean := fname.trim_suffix(".import")
				var ext := clean.get_extension().to_lower()
				if ext in ["png", "jpg", "jpeg", "webp"]:
					var full_p = folder.trim_suffix("/") + "/" + clean
					var exists := false
					for m in available_maps:
						if m["path"] == full_p:
							exists = true
							break
					if not exists:
						available_maps.append({"name": clean, "path": full_p})
			fname = dir.get_next()
		dir.list_dir_end()
	available_maps.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["name"].to_lower() == "world_map.png":
			return true
		if b["name"].to_lower() == "world_map.png":
			return false
		return a["name"] < b["name"]
	)

func get_default_map_path() -> String:
	if FileAccess.file_exists("res://data/maps/world_map.png") or ResourceLoader.exists("res://data/maps/world_map.png"):
		return "res://data/maps/world_map.png"
	if not available_maps.is_empty():
		return String(available_maps[0]["path"])
	return "res://world_map.png"

func _build_icon_index() -> void:
	icon_path_map.clear()
	for folder in ["res://icons", "res://data/icons", "res://assets/icons", "res://assets", "res://"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				var clean_name := fname.trim_suffix(".import")
				var ext := clean_name.get_extension().to_lower()
				if ext in ["png", "webp", "svg"]:
					var base_key := clean_name.get_basename().to_lower()
					var full_path = folder.trim_suffix("/") + "/" + clean_name
					if not icon_path_map.has(base_key):
						icon_path_map[base_key] = full_path
			fname = dir.get_next()
		dir.list_dir_end()

func load_all() -> void:
	items.clear()
	item_order.clear()
	item_colors.clear()
	item_palettes.clear()
	buildings.clear()
	recipes.clear()

	var loaded_data_json := false
	for p in DATA_JSON_PATHS:
		if FileAccess.file_exists(p):
			_load_satisfactory_data_json(p)
			loaded_data_json = true
			break
	if not loaded_data_json:
		_load_legacy_or_custom_json(LEGACY_RECIPES_PATH)
	_register_power_generators()
	_load_legacy_or_custom_json(USER_RECIPES_PATH)
	refresh_localized_texts()

func refresh_localized_texts() -> void:
	for r_id in recipes.keys():
		var r: Dictionary = recipes[r_id]
		var b_key: String = String(r.get("building_key", "constructor"))
		var b_en: String = String(r.get("building_name_en", r.get("building_name", "Constructor")))
		var raw_en: String = String(r.get("raw_name_en", r.get("raw_name", r_id)))
		var cat_en: String = String(r.get("category_en", r.get("category", "Custom")))
		var loc_b_name := i18n.t_building(b_key, b_en)
		var loc_cat := loc_b_name if cat_en == b_en else i18n.t_building(cat_en, cat_en)
		var loc_raw := i18n.t_recipe(r_id, raw_en)
		r["building_name"] = loc_b_name
		r["category"] = loc_cat
		var r_type: String = String(r.get("recipe_kind", "standard"))
		match r_type:
			"extract_mineral":
				var res_key: String = String(r["outputs"][0]["item"])
				var res_loc := get_item_display_name(res_key)
				r["raw_name"] = res_loc
				r["title"] = i18n.tf("miner_recipe_fmt", [loc_b_name, res_loc])
			"extract_oil":
				var res_key: String = String(r["outputs"][0]["item"])
				var res_loc := get_item_display_name(res_key)
				r["raw_name"] = res_loc
				r["title"] = i18n.tf("oil_recipe_fmt", [loc_b_name, res_loc])
			"extract_water":
				var res_key: String = String(r["outputs"][0]["item"])
				var res_loc := get_item_display_name(res_key)
				r["raw_name"] = res_loc
				r["title"] = i18n.tf("water_recipe_fmt", [loc_b_name, res_loc])
			"extract_well":
				var res_key: String = String(r["outputs"][0]["item"])
				var res_loc := get_item_display_name(res_key)
				r["raw_name"] = i18n.tf("well_suffix", [res_loc])
				r["title"] = i18n.tf("well_recipe_fmt", [loc_b_name, res_loc])
			"generator":
				var gen_mw := int(roundf(float(r.get("power_generated", 0.0))))
				var ins: Array = r.get("inputs", [])
				if not ins.is_empty():
					var fuel_key := String(ins[0]["item"])
					var fuel_loc := get_item_display_name(fuel_key)
					loc_raw = "%s (%d MW)" % [fuel_loc, gen_mw]
				elif gen_mw > 0:
					loc_raw = "%s (+%d MW)" % [loc_b_name, gen_mw]
				r["raw_name"] = loc_raw
				r["title"] = i18n.tf("gen_recipe_fmt", [loc_b_name, loc_raw])
			_:
				r["raw_name"] = loc_raw
				r["title"] = "%s • %s" % [loc_b_name, loc_raw]

func get_category_color(building_key: String, is_miner: bool = false, is_generator: bool = false) -> Color:
	if is_generator or building_key in ["biomass-burner", "coal-generator", "fuel-generator", "nuclear-power-plant", "alien-power-augmenter"]:
		return Color.html("#4B8052")
	if is_miner or building_key in ["miner-mk1", "miner-mk2", "miner-mk3", "oil-pump", "water-extractor", "resource-well-extractor"]:
		return Color.html("#E49246")
	match building_key:
		"smelter", "foundry":
			return Color.html("#B04A3E")
		"constructor", "assembler":
			return Color.html("#586F9B")
		"manufacturer", "packager":
			return Color.html("#7305C6")
		"oil-refinery", "blender":
			return Color.html("#4EADF1")
		"accelerator", "converter", "quantum-encoder":
			return Color.html("#DA7821")
	return Color.html("#596586")

func get_building_footprint_foundations(building_key: String) -> Vector2:
	if BUILDING_META.has(building_key):
		return BUILDING_META[building_key]["size_f"]
	return Vector2(1.5, 1.5)

func get_building_somersloop_slots(building_key: String) -> int:
	if buildings.has(building_key):
		return int(buildings[building_key].get("somersloop_slots", 0))
	return 0

func _load_satisfactory_data_json(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	belts = parsed.get("belts", [])
	pipes = parsed.get("pipes", [])
	for it in parsed.get("items", []):
		var k := String(it["key_name"])
		_register_item(k, String(it.get("name", k)), false, int(it.get("tier", 0)), int(it.get("stack_size", 100)))
	for fl in parsed.get("fluids", []):
		var k := String(fl["key_name"])
		_register_item(k, String(fl.get("name", k)), true, int(fl.get("tier", 0)), 500)

	var miners_list: Array = parsed.get("miners", [])
	for b in parsed.get("buildings", []):
		var b_key := String(b["key_name"])
		var cat := String(b.get("category", b_key))
		var pwr := float(b.get("power", 0.0))
		if pwr <= 0.0 and b.has("power_range"):
			var pr: Array = b["power_range"]
			if pr.size() == 2:
				pwr = (float(pr[0]) + float(pr[1])) * 0.5
		if OFFICIAL_BUILDING_POWER.has(b_key):
			pwr = float(OFFICIAL_BUILDING_POWER[b_key])
		var meta: Dictionary = BUILDING_META.get(b_key, {"foundations": 2.0, "cost": {}})
		var sloop_slots := int(b["somersloop_slots"]) if b.get("somersloop_slots") != null else 0
		var b_info := {
			"name": String(b["name"]),
			"key_name": b_key,
			"category": cat,
			"power": pwr,
			"somersloop_slots": sloop_slots,
			"foundations": float(meta["foundations"]),
			"cost": meta["cost"]
		}
		buildings[cat] = b_info
		buildings[b_key] = b_info

	for m in miners_list:
		var m_key := String(m["key_name"])
		var meta: Dictionary = BUILDING_META.get(m_key, {"foundations": 0.0, "cost": {}})
		var m_pwr := float(OFFICIAL_BUILDING_POWER.get(m_key, float(m.get("power", 5.0))))
		buildings[m_key] = {
			"name": String(m["name"]),
			"key_name": m_key,
			"category": String(m.get("category", "extraction")),
			"power": m_pwr,
			"base_rate": float(m.get("base_rate", 60.0)),
			"somersloop_slots": 0,
			"foundations": float(meta["foundations"]),
			"cost": meta["cost"]
		}

	for res in parsed.get("resources", []):
		var res_key := String(res["key_name"])
		var res_cat := String(res["category"])
		var res_name_en := String(items.get(res_key, {}).get("name", res_key))
		var rec_id := "extract_%s" % res_key
		if res_cat == "mineral":
			recipes[rec_id] = {
				"id": rec_id,
				"recipe_kind": "extract_mineral",
				"title": "",
				"raw_name": res_name_en,
				"raw_name_en": res_name_en,
				"category": "Extraction",
				"category_en": "Extraction",
				"building_key": "miner-mk1",
				"building_name": "Miner",
				"building_name_en": "Miner",
				"power": 5.0,
				"power_generated": 0.0,
				"somersloop_slots": 0,
				"time": 60.0,
				"is_alternate": false,
				"is_miner": true,
				"has_mk_tiers": true,
				"is_generator": false,
				"inputs": [],
				"outputs": [{"item": res_key, "amount": 60.0, "rate": 60.0}]
			}
		elif res_cat == "oil":
			recipes[rec_id] = {
				"id": rec_id,
				"recipe_kind": "extract_oil",
				"title": "",
				"raw_name": res_name_en,
				"raw_name_en": res_name_en,
				"category": "Extraction",
				"category_en": "Extraction",
				"building_key": "oil-pump",
				"building_name": "Oil Extractor",
				"building_name_en": "Oil Extractor",
				"power": 40.0,
				"power_generated": 0.0,
				"somersloop_slots": 0,
				"time": 60.0,
				"is_alternate": false,
				"is_miner": true,
				"has_mk_tiers": false,
				"is_generator": false,
				"inputs": [],
				"outputs": [{"item": res_key, "amount": 120.0, "rate": 120.0}]
			}
		elif res_key == "water":
			recipes[rec_id] = {
				"id": rec_id,
				"recipe_kind": "extract_water",
				"title": "",
				"raw_name": res_name_en,
				"raw_name_en": res_name_en,
				"category": "Extraction",
				"category_en": "Extraction",
				"building_key": "water-extractor",
				"building_name": "Water Extractor",
				"building_name_en": "Water Extractor",
				"power": 20.0,
				"power_generated": 0.0,
				"somersloop_slots": 0,
				"time": 60.0,
				"is_alternate": false,
				"is_miner": true,
				"has_mk_tiers": false,
				"is_generator": false,
				"inputs": [],
				"outputs": [{"item": res_key, "amount": 120.0, "rate": 120.0}]
			}
		if res_key in ["water", "crude-oil", "nitrogen-gas"]:
			var well_id := "well_%s" % res_key
			recipes[well_id] = {
				"id": well_id,
				"recipe_kind": "extract_well",
				"title": "",
				"raw_name": "%s (Well)" % res_name_en,
				"raw_name_en": "%s (Well)" % res_name_en,
				"category": "Extraction",
				"category_en": "Extraction",
				"building_key": "resource-well-extractor",
				"building_name": "Resource Well Extractor",
				"building_name_en": "Resource Well Extractor",
				"power": 30.0,
				"power_generated": 0.0,
				"somersloop_slots": 0,
				"time": 60.0,
				"is_alternate": false,
				"is_miner": true,
				"has_mk_tiers": false,
				"is_generator": false,
				"inputs": [],
				"outputs": [{"item": res_key, "amount": 60.0, "rate": 60.0}]
			}

	for r in parsed.get("recipes", []):
		var r_key := String(r["key_name"])
		var r_name := String(r["name"])
		var r_cat := String(r.get("category", "crafting1"))
		var cycle_time := maxf(0.0001, float(r.get("time", 1.0)))
		var cycles_per_min := 60.0 / cycle_time
		var b_info: Dictionary = buildings.get(r_cat, {"name": r_cat.capitalize(), "key_name": r_cat, "power": 15.0, "somersloop_slots": 0})
		var pwr := float(b_info["power"])
		if r.has("power_range"):
			var pr: Array = r["power_range"]
			if pr.size() == 2:
				pwr = (float(pr[0]) + float(pr[1])) * 0.5
		var ins: Array = []
		for ing in r.get("ingredients", []):
			var ikey := String(ing[0])
			var amt := float(ing[1])
			ensure_item_color(ikey)
			ins.append({"item": ikey, "amount": amt, "rate": amt * cycles_per_min})
		var outs: Array = []
		for prod in r.get("products", []):
			var okey := String(prod[0])
			var amt := float(prod[1])
			ensure_item_color(okey)
			outs.append({"item": okey, "amount": amt, "rate": amt * cycles_per_min})
		var is_nuke := (r_cat == "nuke-reacting" or String(b_info["key_name"]) == "nuclear-power-plant")
		var is_alt := r_key.begins_with("alt-") or r_name.begins_with("Alternate:")
		var cat_en := "Power Generation" if is_nuke else String(b_info["name"])
		recipes[r_key] = {
			"id": r_key,
			"recipe_kind": "standard",
			"title": "",
			"raw_name": r_name,
			"raw_name_en": r_name,
			"category": cat_en,
			"category_en": cat_en,
			"building_key": String(b_info["key_name"]),
			"building_name": String(b_info["name"]),
			"building_name_en": String(b_info["name"]),
			"power": 0.0 if is_nuke else pwr,
			"power_generated": 2500.0 if is_nuke else 0.0,
			"somersloop_slots": int(b_info.get("somersloop_slots", 0)),
			"time": cycle_time,
			"is_alternate": is_alt,
			"is_miner": false,
			"has_mk_tiers": false,
			"is_generator": is_nuke,
			"inputs": ins,
			"outputs": outs
		}

func _register_power_generators() -> void:
	var gen_buildings: Array = _power_generators_data.get("buildings", [])
	for gb in gen_buildings:
		var gkey: String = gb["key"]
		var meta: Dictionary = BUILDING_META.get(gkey, {"foundations": 4.0, "cost": {}})
		if not buildings.has(gkey):
			buildings[gkey] = {
				"name": gb["name"],
				"key_name": gkey,
				"category": "power",
				"power": 0.0,
				"somersloop_slots": 0,
				"foundations": float(meta["foundations"]),
				"cost": meta["cost"]
			}
	var gen_recipes: Array = _power_generators_data.get("recipes", [])
	for gr in gen_recipes:
		var r_id: String = gr["id"]
		if recipes.has(r_id):
			continue
		var cpm := 60.0 / float(gr["time"])
		var ins: Array = []
		for ing in gr["in"]:
			var ikey := String(ing[0])
			var amt := float(ing[1])
			ensure_item_color(ikey)
			ins.append({"item": ikey, "amount": amt, "rate": amt * cpm})
		var outs: Array = []
		for prod in gr["out"]:
			var okey := String(prod[0])
			var amt := float(prod[1])
			ensure_item_color(okey)
			outs.append({"item": okey, "amount": amt, "rate": amt * cpm})
		recipes[r_id] = {
			"id": r_id,
			"recipe_kind": "generator",
			"title": "",
			"raw_name": gr["name"],
			"raw_name_en": gr["name"],
			"category": "Power Generation",
			"category_en": "Power Generation",
			"building_key": gr["b_key"],
			"building_name": gr["b_name"],
			"building_name_en": gr["b_name"],
			"power": 0.0,
			"power_generated": float(gr["mw"]),
			"somersloop_slots": 0,
			"time": float(gr["time"]),
			"is_alternate": false,
			"is_miner": false,
			"has_mk_tiers": false,
			"is_generator": true,
			"inputs": ins,
			"outputs": outs
		}

func _load_legacy_or_custom_json(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	if parsed.has("item_colors"):
		for item_name in parsed["item_colors"].keys():
			_register_item(item_name, item_name, false, 0, 100, Color.html(String(parsed["item_colors"][item_name])))
	var rec_dict: Dictionary = parsed.get("recipes", parsed)
	for r_id in rec_dict.keys():
		if r_id == "item_colors":
			continue
		var r: Dictionary = rec_dict[r_id]
		var cycle_time := maxf(0.0001, float(r.get("time", 60.0)))
		var cycles_per_min := 60.0 / cycle_time
		var ins: Array = []
		for entry in r.get("inputs", []):
			var ikey := String(entry["item"])
			ensure_item_color(ikey)
			var rate := float(entry.get("rate", float(entry.get("amount", 1.0)) * cycles_per_min))
			var amt := float(entry.get("amount", rate / cycles_per_min))
			ins.append({"item": ikey, "amount": amt, "rate": rate})
		var outs: Array = []
		for entry in r.get("outputs", []):
			var okey := String(entry["item"])
			ensure_item_color(okey)
			var rate := float(entry.get("rate", float(entry.get("amount", 1.0)) * cycles_per_min))
			var amt := float(entry.get("amount", rate / cycles_per_min))
			outs.append({"item": okey, "amount": amt, "rate": rate})
		var cat := String(r.get("category_en", r.get("category", "Custom")))
		var b_key := String(r.get("building_key", "constructor"))
		var raw_en := String(r.get("raw_name_en", r.get("raw_name", r.get("title", r_id))))
		recipes[r_id] = {
			"id": r_id,
			"recipe_kind": "custom",
			"title": raw_en,
			"raw_name": raw_en,
			"raw_name_en": raw_en,
			"category": cat,
			"category_en": cat,
			"building_key": b_key,
			"building_name": cat,
			"building_name_en": cat,
			"power": float(r.get("power", 15.0)),
			"power_generated": float(r.get("power_generated", 0.0)),
			"somersloop_slots": get_building_somersloop_slots(b_key),
			"time": cycle_time,
			"is_alternate": String(r_id).begins_with("alt_"),
			"is_miner": ins.is_empty() and float(r.get("power_generated", 0.0)) <= 0.0,
			"has_mk_tiers": ins.is_empty() and float(r.get("power_generated", 0.0)) <= 0.0,
			"is_generator": float(r.get("power_generated", 0.0)) > 0.0,
			"is_custom": String(r_id).begins_with("custom_") or path == USER_RECIPES_PATH,
			"inputs": ins,
			"outputs": outs
		}

func _build_palette_for_key(key_name: String, is_fluid: bool, custom_col: Color = Color.TRANSPARENT) -> Dictionary:
	var k_norm := key_name.to_lower().replace(" ", "-")
	var prim: Color
	var sec: Color
	if ITEM_PALETTE.has(k_norm):
		var pair: Array = ITEM_PALETTE[k_norm]
		prim = Color.html(String(pair[0]))
		sec = Color.html(String(pair[1]))
	elif custom_col != Color.TRANSPARENT:
		prim = custom_col
		sec = custom_col.darkened(0.35)
	else:
		var hue := fmod(absf(float(k_norm.hash())) * 0.137, 1.0)
		prim = Color.from_hsv(hue, 0.55 if is_fluid else 0.68, 0.88)
		sec = Color.from_hsv(fmod(hue + 0.08, 1.0), 0.65, 0.52)

	var lum_p := prim.get_luminance()
	var lum_s := sec.get_luminance()
	var wire_col := prim
	if lum_p < 0.14 and lum_s >= 0.14:
		wire_col = sec
	elif lum_s > lum_p and sec.s > prim.s + 0.15 and lum_s > 0.18:
		wire_col = sec
	if wire_col.get_luminance() < 0.15:
		wire_col = wire_col.lightened(0.38)

	var header_col := prim
	var border_col := sec
	if lum_s < 0.08 and lum_p >= 0.15:
		header_col = prim.darkened(0.42)
		border_col = prim
	elif lum_p > 0.55 and lum_s < 0.35:
		header_col = sec.darkened(0.15)
		border_col = prim
	else:
		header_col = prim.darkened(0.15) if lum_p > 0.35 else prim
		border_col = sec if lum_s >= 0.16 else wire_col
	return {
		"primary": prim,
		"secondary": sec,
		"wire": wire_col,
		"header": header_col,
		"border": border_col
	}

func _register_item(key_name: String, disp_name: String, is_fluid: bool, tier: int, stack: int, custom_col: Color = Color.TRANSPARENT) -> void:
	var pal := _build_palette_for_key(key_name, is_fluid, custom_col)
	items[key_name] = {
		"key_name": key_name,
		"name": disp_name,
		"is_fluid": is_fluid,
		"tier": tier,
		"stack_size": stack,
		"color": pal["wire"],
		"primary_color": pal["primary"],
		"secondary_color": pal["secondary"]
	}
	if not item_colors.has(key_name):
		item_order.append(key_name)
	item_colors[key_name] = pal["wire"]
	item_palettes[key_name] = pal

func ensure_item_color(item_key: String) -> void:
	if not items.has(item_key):
		_register_item(item_key, item_key.replace("-", " ").capitalize(), false, 0, 100)

func get_item_display_name(item_key: String) -> String:
	var en_name := String(items[item_key]["name"]) if items.has(item_key) else item_key.replace("-", " ").capitalize()
	return i18n.t_item(item_key, en_name)

func get_building_display_name(b_key: String, fallback: String = "") -> String:
	var en_name := fallback
	if en_name == "" and buildings.has(b_key):
		en_name = String(buildings[b_key]["name"])
	return i18n.t_building(b_key, en_name if en_name != "" else b_key)

func is_item_fluid(item_key: String) -> bool:
	if items.has(item_key):
		return bool(items[item_key]["is_fluid"])
	return false

func get_item_type(item_key: String) -> int:
	var idx := item_order.find(item_key)
	return idx if idx != -1 else 0

func get_item_color(item_key: String) -> Color:
	if not item_colors.has(item_key):
		ensure_item_color(item_key)
	return item_colors.get(item_key, Color.WHITE)

func get_item_palette(item_key: String) -> Dictionary:
	if item_key == "":
		return {
			"primary": Color(0.18, 0.22, 0.28),
			"secondary": Color(0.45, 0.58, 0.72),
			"wire": Color(0.55, 0.7, 0.85),
			"header": Color(0.15, 0.18, 0.24),
			"border": Color(0.45, 0.58, 0.72)
		}
	if not item_palettes.has(item_key):
		ensure_item_color(item_key)
	return item_palettes[item_key]

func get_item_primary_color(item_key: String) -> Color:
	return get_item_palette(item_key)["primary"]

func get_item_secondary_color(item_key: String) -> Color:
	return get_item_palette(item_key)["secondary"]

func get_min_logistics_tier(item_key: String, rate: float) -> Dictionary:
	if rate <= 0.0001:
		return {"label": i18n.t("logistics_idle"), "over": false}
	if is_item_fluid(item_key):
		if rate <= 300.01:
			return {"label": i18n.t("pipe_mk1"), "over": false}
		elif rate <= 600.01:
			return {"label": i18n.t("pipe_mk2"), "over": false}
		var pipes_needed := int(ceilf(rate / 600.0))
		return {"label": i18n.tf("pipe_over", [pipes_needed]), "over": true}
	else:
		var tiers := [
			{"rate": 60.0, "key": "belt_mk1"},
			{"rate": 120.0, "key": "belt_mk2"},
			{"rate": 270.0, "key": "belt_mk3"},
			{"rate": 480.0, "key": "belt_mk4"},
			{"rate": 780.0, "key": "belt_mk5"},
			{"rate": 1200.0, "key": "belt_mk6"}
		]
		for t in tiers:
			if rate <= float(t["rate"]) + 0.01:
				return {"label": i18n.t(String(t["key"])), "over": false}
		var belts_needed := int(ceilf(rate / 1200.0))
		return {"label": i18n.tf("belt_over", [belts_needed]), "over": true}

func get_icon_texture(key_or_name: String) -> Texture2D:
	if key_or_name == "":
		return null
	if icon_cache.has(key_or_name):
		return icon_cache[key_or_name]
	var en_item_name := String(items[key_or_name]["name"]).to_lower() if items.has(key_or_name) else key_or_name.to_lower()
	if buildings.has(key_or_name):
		en_item_name = String(buildings[key_or_name]["name"]).to_lower()
	var k_low := key_or_name.to_lower()
	var candidates: Array[String] = [
		en_item_name,
		k_low,
		en_item_name.replace(" mk1", "").replace(" mk2", "").replace(" mk3", ""),
		k_low.replace("-", " "),
		k_low.replace(" ", "-")
	]
	for c in candidates:
		if icon_path_map.has(c):
			var tex := load(icon_path_map[c]) as Texture2D
			icon_cache[key_or_name] = tex
			return tex
	icon_cache[key_or_name] = null
	return null

func get_custom_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	for k in recipes.keys():
		var ks := String(k)
		if ks.begins_with("custom_") or bool(recipes[k].get("is_custom", false)):
			out.append(ks)
	return out

func add_custom_recipe(cat: String, title: String, power: float, cycle_time: float, inputs: Array, outputs: Array, existing_id: String = "", b_key: String = "manufacturer") -> String:
	var rec_id := existing_id if existing_id != "" else ("custom_" + str(Time.get_ticks_msec()))
	var t := maxf(0.1, cycle_time)
	var cpm := 60.0 / t
	for e in inputs:
		e["rate"] = float(e.get("amount", 1.0)) * cpm
	for e in outputs:
		e["rate"] = float(e.get("amount", 1.0)) * cpm
	var clean_b_key := b_key if b_key != "" else "manufacturer"
	var b_en_name := String(buildings.get(clean_b_key, {}).get("name", cat if cat != "" else "Custom"))
	var clean_cat := cat if cat != "" else b_en_name
	recipes[rec_id] = {
		"id": rec_id,
		"recipe_kind": "custom",
		"category": clean_cat,
		"category_en": clean_cat,
		"building_key": clean_b_key,
		"building_name": b_en_name,
		"building_name_en": b_en_name,
		"title": title,
		"raw_name": title,
		"raw_name_en": title,
		"power": maxf(0.0, power),
		"power_generated": maxf(0.0, -power) if power < 0.0 else 0.0,
		"somersloop_slots": get_building_somersloop_slots(clean_b_key),
		"time": t,
		"is_alternate": false,
		"is_miner": inputs.is_empty() and power >= 0.0,
		"has_mk_tiers": false,
		"is_generator": power < 0.0,
		"is_custom": true,
		"inputs": inputs,
		"outputs": outputs
	}
	refresh_localized_texts()
	save_custom_recipes_to_disk()
	return rec_id

func delete_custom_recipe(rec_id: String) -> void:
	if recipes.has(rec_id):
		recipes.erase(rec_id)
		save_custom_recipes_to_disk()

func save_custom_recipes_to_disk() -> void:
	var custom_only: Dictionary = {}
	for k in get_custom_recipe_ids():
		custom_only[k] = recipes[k]
	var f := FileAccess.open(USER_RECIPES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"recipes": custom_only}, "\t"))

func get_item_sink_points(item_key: String) -> int:
	if is_item_fluid(item_key):
		return 0
	return int(AWESOME_POINTS.get(item_key.to_lower(), 1))
