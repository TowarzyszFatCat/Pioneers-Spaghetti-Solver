class_name AutosaveManager
extends RefCounted

const PROJECTS_DIR := "user://projects"
const AUTOSAVE_PROJECT_NAME := "autosave_latest.pss"
const BACKUP_PREFIX := "backup_auto_"
const MAX_BACKUPS := 3
const BACKUP_INTERVAL_SEC := 300.0 # 5 minutes
const DEBOUNCE_SEC := 0.35

var main_ctrl: GraphEdit
var serializer: ProjectSerializer
var backup_timer: Timer
var debounce_timer: Timer
var is_restoring_startup: bool = false

func _init(p_main: GraphEdit, p_serializer: ProjectSerializer) -> void:
	main_ctrl = p_main
	serializer = p_serializer

func setup_autosave_timer(parent_node: Node) -> void:
	# Debounce timer prevents freezing when recalculate_all() is called multiple times in a single frame
	debounce_timer = Timer.new()
	debounce_timer.wait_time = DEBOUNCE_SEC
	debounce_timer.one_shot = true
	debounce_timer.timeout.connect(_on_debounce_timeout)
	parent_node.add_child(debounce_timer)

	# 5-minute periodic backup timer
	backup_timer = Timer.new()
	backup_timer.wait_time = BACKUP_INTERVAL_SEC
	backup_timer.autostart = true
	backup_timer.timeout.connect(_on_backup_timer_timeout)
	parent_node.add_child(backup_timer)

func notify_interaction() -> void:
	if main_ctrl == null or main_ctrl.is_loading_project or is_restoring_startup:
		return
	if debounce_timer != null and debounce_timer.is_inside_tree():
		debounce_timer.start(DEBOUNCE_SEC)

func _on_debounce_timeout() -> void:
	if main_ctrl == null or main_ctrl.is_loading_project or is_restoring_startup:
		return
	_perform_autosave(AUTOSAVE_PROJECT_NAME)

func _on_backup_timer_timeout() -> void:
	if main_ctrl == null or main_ctrl.is_loading_project or is_restoring_startup:
		return
	_rotate_and_create_backup()

func _perform_autosave(filename: String) -> void:
	if serializer == null:
		return
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("projects"):
		dir.make_dir("projects")

	var full_path := "%s/%s" % [PROJECTS_DIR, filename]
	serializer.save_project_to_path(full_path, true)

func _rotate_and_create_backup() -> void:
	var dir := DirAccess.open(PROJECTS_DIR)
	if dir == null:
		return

	# Ensure the latest autosave file is up to date before rotating backups
	_perform_autosave(AUTOSAVE_PROJECT_NAME)

	# Shift backups: backup_auto_2.pss -> backup_auto_3.pss, backup_auto_1.pss -> backup_auto_2.pss
	for i in range(MAX_BACKUPS - 1, 0, -1):
		var src := "%s/%s%d.pss" % [PROJECTS_DIR, BACKUP_PREFIX, i]
		var dst := "%s/%s%d.pss" % [PROJECTS_DIR, BACKUP_PREFIX, i + 1]
		if FileAccess.file_exists(src):
			var d_access := DirAccess.open("user://")
			if d_access != null:
				if FileAccess.file_exists(dst):
					d_access.remove(dst)
				d_access.rename(src, dst)

	# Copy current autosave as backup_auto_1.pss
	var latest_path := "%s/%s" % [PROJECTS_DIR, AUTOSAVE_PROJECT_NAME]
	var first_backup_path := "%s/%s1.pss" % [PROJECTS_DIR, BACKUP_PREFIX]
	if FileAccess.file_exists(latest_path):
		var src_file := FileAccess.open(latest_path, FileAccess.READ)
		var dst_file := FileAccess.open(first_backup_path, FileAccess.WRITE)
		if src_file != null and dst_file != null:
			dst_file.store_string(src_file.get_as_text())
			dst_file.close()
			src_file.close()

func get_most_recent_save_path() -> String:
	var dir := DirAccess.open(PROJECTS_DIR)
	if dir == null:
		return ""

	var latest_path := ""
	var latest_time: int = -1

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() in ["pss", "json"]:
			var full_p := "%s/%s" % [PROJECTS_DIR, fname]
			var mod_time := int(FileAccess.get_modified_time(full_p))
			if mod_time > latest_time:
				latest_time = mod_time
				latest_path = full_p
		fname = dir.get_next()
	dir.list_dir_end()

	return latest_path

func load_most_recent_on_startup() -> void:
	if serializer == null:
		return
	var recent_save := get_most_recent_save_path()
	if recent_save == "":
		return
	is_restoring_startup = true
	await serializer.load_project_from_path(recent_save)
	# If the loaded file was an internal autosave/backup, keep current_file_path empty so Ctrl+S still asks for a project name
	var f_name := recent_save.get_file()
	if f_name == AUTOSAVE_PROJECT_NAME or f_name.begins_with(BACKUP_PREFIX):
		serializer.current_file_path = ""
		serializer._update_window_title()
	is_restoring_startup = false
