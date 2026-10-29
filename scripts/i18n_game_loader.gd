class_name I18nGameLoader
extends RefCounted

const SCAN_FOLDERS := [
	"res://data/i18n",
	"res://data/i18n/game",
	"res://data/locales"
]

const LANGUAGE_NAMES := {
	"en": "English (en)",
	"en-US": "English US (en-US)",
	"en-GB": "English UK (en-GB)",
	"en-CA": "English CA (en-CA)",
	"en-AU": "English AU (en-AU)",
	"en-AE": "English AE (en-AE)",
	"pl": "Polski (pl)",
	"de": "Deutsch (de)",
	"fr": "Français (fr)",
	"es-ES": "Español España (es-ES)",
	"es-419": "Español Latinoamérica (es-419)",
	"it": "Italiano (it)",
	"pt-BR": "Português Brasil (pt-BR)",
	"pt-PT": "Português Portugal (pt-PT)",
	"cs": "Čeština (cs)",
	"sk": "Slovenčina (sk)",
	"hu": "Magyar (hu)",
	"ro": "Română (ro)",
	"bg": "Български (bg)",
	"uk": "Українська (uk)",
	"ru": "Русский (ru)",
	"sr-Cyrl": "Српски (sr-Cyrl)",
	"sr-Latn": "Srpski (sr-Latn)",
	"hr": "Hrvatski (hr)",
	"el": "Ελληνικά (el)",
	"tr": "Türkçe (tr)",
	"nl": "Nederlands (nl)",
	"da": "Dansk (da)",
	"sv": "Svenska (sv)",
	"no": "Norsk (no)",
	"fi": "Suomi (fi)",
	"et": "Eesti (et)",
	"lv": "Latviešu (lv)",
	"lt": "Lietuvių (lt)",
	"ca": "Català (ca)",
	"eo": "Esperanto (eo)",
	"ia-001": "Interlingua (ia-001)",
	"ie": "Interlingue (ie)",
	"io": "Ido (io)",
	"vo": "Volapük (vo)",
	"kw": "Kernewek (kw)",
	"lb": "Lëtzebuergesch (lb)",
	"mt": "Malti (mt)",
	"af": "Afrikaans (af)",
	"vun": "Kyivunjo (vun)",
	"ar": "العربية (ar)",
	"fa": "فارسی (fa)",
	"he": "עברית (he)",
	"hi": "हिन्दी (hi)",
	"th": "ไทย (th)",
	"vi": "Tiếng Việt (vi)",
	"id": "Bahasa Indonesia (id)",
	"ja": "日本語 (ja)",
	"ko": "한국어 (ko)",
	"zh-Hans": "简体中文 (zh-Hans)",
	"zh-Hant": "繁體中文 (zh-Hant)"
}

# Maps internal AppDB building keys/names to exact Satisfactory localization keys
const BUILDING_KEY_TO_GAME_EN := {
	"miner": "Miner Mk.1",
	"Miner": "Miner Mk.1",
	"miner-mk1": "Miner Mk.1",
	"Miner MK1": "Miner Mk.1",
	"miner-mk2": "Miner Mk.2",
	"Miner MK2": "Miner Mk.2",
	"miner-mk3": "Miner Mk.3",
	"Miner MK3": "Miner Mk.3",
	"oil-pump": "Oil Extractor",
	"Oil Pump": "Oil Extractor",
	"water-extractor": "Water Extractor",
	"resource-well-extractor": "Resource Well Extractor",
	"smelter": "Smelter",
	"smelting": "Smelter",
	"foundry": "Foundry",
	"alloying": "Foundry",
	"constructor": "Constructor",
	"crafting": "Constructor",
	"crafting1": "Constructor",
	"assembler": "Assembler",
	"assembling": "Assembler",
	"manufacturer": "Manufacturer",
	"manufacturing": "Manufacturer",
	"oil-refinery": "Refinery",
	"oil-refining": "Refinery",
	"Oil Refinery": "Refinery",
	"packager": "Packager",
	"packaging": "Packager",
	"blender": "Blender",
	"blending": "Blender",
	"accelerator": "Particle Accelerator",
	"hadron-colliding": "Particle Accelerator",
	"Hadron Collider": "Particle Accelerator",
	"converter": "Converter",
	"converting": "Converter",
	"quantum-encoder": "Quantum Encoder",
	"quantum-encoding": "Quantum Encoder",
	"biomass-burner": "Biomass Burner",
	"coal-generator": "Coal-Powered Generator",
	"Coal Generator": "Coal-Powered Generator",
	"fuel-generator": "Fuel-Powered Generator",
	"Fuel Generator": "Fuel-Powered Generator",
	"nuclear-power-plant": "Nuclear Power Plant",
	"nuke-reacting": "Nuclear Power Plant",
	"alien-power-augmenter": "Alien Power Augmenter",
	"geothermal-generator": "Geothermal Generator",
	"splitter": "Conveyor Splitter",
	"merger": "Conveyor Merger",
	"awesome-sink": "AWESOME Sink",
	"dimensional-depot": "Dimensional Depot",
	"storage-container": "Storage Container",
	"truck-station": "Truck Station",
	"train-station": "Train Station",
	"drone-port": "Drone Port",
	"Logistics": "Logistics"
}

# Maps internal item keys/names to exact Satisfactory localization keys
const ITEM_KEY_TO_GAME_EN := {
	"screw": "Screws",
	"Screw": "Screws",
	"sam": "SAM",
	"sam-ore": "SAM",
	"SAM Ore": "SAM",
	"em-control-rod": "Electromagnetic Control Rod",
	"blue-slug": "Blue Power Slug",
	"green-power-slug": "Blue Power Slug",
	"blue-power-slug": "Blue Power Slug",
	"yellow-slug": "Yellow Power Slug",
	"yellow-power-slug": "Yellow Power Slug",
	"purple-slug": "Purple Power Slug",
	"purple-power-slug": "Purple Power Slug",
	"biofuel": "Solid Biofuel",
	"solid-biofuel": "Solid Biofuel",
	"hard-drive": "Hard Drive",
	"mercer-sphere": "Mercer Sphere",
	"somersloop": "Somersloop",
	"power-shard": "Power Shard",
	"plasma-spitter-remains": "Spitter Remains"
}

const RECIPE_NAME_ALIASES := {
	"Cast Screw": "Cast Screws",
	"Steel Screw": "Steel Screws",
	"Electrode - Aluminum Scrap": "Electrode Aluminum Scrap",
	"Rigour Motor": "Rigor Motor",
	"Plasma Spitter Protein": "Spitter Protein"
}

var available_languages: Array[String] = []
var lang_file_paths: Dictionary = {}
var loaded_game_dicts: Dictionary = {}
var loaded_lower_dicts: Dictionary = {}

func scan_available_languages() -> void:
	available_languages.clear()
	lang_file_paths.clear()

	for folder in SCAN_FOLDERS:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				var clean := fname.trim_suffix(".import").trim_suffix(".remap")
				if clean.get_extension().to_lower() == "json":
					var code := clean.get_basename()
					if not code.begins_with("i18n_template"):
						var full_path = folder.trim_suffix("/") + "/" + clean
						lang_file_paths[code] = full_path
						if not (code in available_languages):
							available_languages.append(code)
			fname = dir.get_next()
		dir.list_dir_end()

	# Ensure default 'en' and 'pl' are always present in the list
	if not ("pl" in available_languages):
		available_languages.push_front("pl")
	if not ("en" in available_languages) and not ("en-US" in available_languages):
		available_languages.push_front("en")

	available_languages.sort_custom(func(a: String, b: String):
		var priority := ["en", "en-US", "en-GB", "pl", "de", "fr", "es-ES"]
		var ia := priority.find(a)
		var ib := priority.find(b)
		if ia != -1 and ib != -1:
			return ia < ib
		if ia != -1:
			return true
		if ib != -1:
			return false
		return get_language_display_name(a) < get_language_display_name(b)
	)

func get_language_display_name(lang_code: String) -> String:
	return String(LANGUAGE_NAMES.get(lang_code, lang_code))

func ensure_language_loaded(lang_code: String) -> void:
	if loaded_game_dicts.has(lang_code):
		return
	loaded_game_dicts[lang_code] = {}
	loaded_lower_dicts[lang_code] = {}

	var path := String(lang_file_paths.get(lang_code, ""))
	if path == "" and lang_code == "en" and lang_file_paths.has("en-US"):
		path = String(lang_file_paths["en-US"])
	if path == "" or not FileAccess.file_exists(path):
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return

	var flat_dict: Dictionary = {}
	var lower_dict: Dictionary = {}

	# Support both flat game dictionaries {"Crude Oil": "Ropa naftowa"} and structured dictionaries
	if parsed.has("ui") and parsed["ui"] is Dictionary:
		for sec in ["buildings", "items", "recipes"]:
			if parsed.has(sec) and parsed[sec] is Dictionary:
				for k in parsed[sec].keys():
					var val := String(parsed[sec][k])
					flat_dict[String(k)] = val
					lower_dict[String(k).to_lower()] = val
	else:
		for k in parsed.keys():
			if parsed[k] is String:
				var ks := String(k)
				var val := String(parsed[k])
				flat_dict[ks] = val
				lower_dict[ks.to_lower()] = val

	loaded_game_dicts[lang_code] = flat_dict
	loaded_lower_dicts[lang_code] = lower_dict

func lookup_raw(lang_code: String, en_key: String) -> String:
	if en_key == "":
		return ""
	ensure_language_loaded(lang_code)
	var d: Dictionary = loaded_game_dicts.get(lang_code, {})
	if d.has(en_key):
		return String(d[en_key])
	var ld: Dictionary = loaded_lower_dicts.get(lang_code, {})
	var k_low := en_key.to_lower()
	if ld.has(k_low):
		return String(ld[k_low])
	return ""

func translate_building(lang_code: String, b_key_or_name: String, fallback_en: String) -> String:
	var fb := fallback_en if fallback_en != "" else b_key_or_name
	if lang_code.begins_with("en"):
		return fb

	var candidates: Array[String] = []
	if BUILDING_KEY_TO_GAME_EN.has(b_key_or_name):
		candidates.append(String(BUILDING_KEY_TO_GAME_EN[b_key_or_name]))
	if BUILDING_KEY_TO_GAME_EN.has(fb):
		candidates.append(String(BUILDING_KEY_TO_GAME_EN[fb]))
	candidates.append(fb)
	candidates.append(b_key_or_name)

	for c in candidates:
		var res := lookup_raw(lang_code, c)
		if res != "":
			return res
	return ""

func translate_item(lang_code: String, item_key: String, fallback_en: String) -> String:
	var fb := fallback_en if fallback_en != "" else item_key.replace("-", " ").capitalize()
	if lang_code.begins_with("en"):
		return fb

	var candidates: Array[String] = []
	if ITEM_KEY_TO_GAME_EN.has(item_key):
		candidates.append(String(ITEM_KEY_TO_GAME_EN[item_key]))
	if ITEM_KEY_TO_GAME_EN.has(fb):
		candidates.append(String(ITEM_KEY_TO_GAME_EN[fb]))
	candidates.append(fb)
	if not fb.ends_with("s"):
		candidates.append(fb + "s")
	elif fb.length() > 2:
		candidates.append(fb.trim_suffix("s"))
	candidates.append(item_key.replace("-", " ").capitalize())

	for c in candidates:
		var res := lookup_raw(lang_code, c)
		if res != "":
			return res
	return ""

func translate_recipe(lang_code: String, rec_id: String, raw_en_name: String) -> String:
	if lang_code.begins_with("en"):
		return raw_en_name

	var is_alt := raw_en_name.begins_with("Alternate:") or rec_id.begins_with("alt-") or rec_id.begins_with("alternate-")
	var core_name := raw_en_name.trim_prefix("Alternate:").strip_edges()
	if RECIPE_NAME_ALIASES.has(core_name):
		core_name = String(RECIPE_NAME_ALIASES[core_name])

	var candidates: Array[String] = [raw_en_name]
	if is_alt:
		candidates.append("Alternate: " + core_name)
		if not core_name.ends_with("s"):
			candidates.append("Alternate: " + core_name + "s")
		else:
			candidates.append("Alternate: " + core_name.trim_suffix("s"))
	candidates.append(core_name)
	if ITEM_KEY_TO_GAME_EN.has(core_name):
		candidates.append(String(ITEM_KEY_TO_GAME_EN[core_name]))
	if not core_name.ends_with("s"):
		candidates.append(core_name + "s")
	elif core_name.length() > 2:
		candidates.append(core_name.trim_suffix("s"))

	for c in candidates:
		var res := lookup_raw(lang_code, c)
		if res != "":
			return res
	return ""
