class_name PlannerTools
extends RefCounted

var chain_tool: AutoChainTool
var nav_tool: NavigatorTool
var alert_tool: AlertInspectorTool

var chain_win: Window:
	get:
		return chain_tool.win if chain_tool != null else null

var nav_win: Window:
	get:
		return nav_tool.win if nav_tool != null else null

var alert_win: Window:
	get:
		return alert_tool.win if alert_tool != null else null

func _init(p_main: GraphEdit, p_db: AppDB, p_settings: AppSettings, p_i18n: AppI18n, p_builder: NodeBuilder, _p_solver: FactorySolver) -> void:
	chain_tool = AutoChainTool.new(p_main, p_db, p_settings, p_i18n, p_builder)
	nav_tool = NavigatorTool.new(p_main, p_db, p_i18n, p_builder)
	alert_tool = AlertInspectorTool.new(p_main, p_db, p_settings, p_i18n, p_builder, nav_tool)

func build_all_windows(parent_layer: CanvasLayer, theme_ref: Theme) -> void:
	chain_tool.build_window(parent_layer, theme_ref)
	nav_tool.build_window(parent_layer, theme_ref)
	alert_tool.build_window(parent_layer, theme_ref)
	refresh_translations()

func refresh_translations() -> void:
	chain_tool.refresh_translations()
	nav_tool.refresh_translations()
	alert_tool.refresh_translations()

func open_chain_window() -> void:
	chain_tool.open_window()

func open_navigator_window() -> void:
	nav_tool.open_window()

func open_alert_window() -> void:
	alert_tool.open_window()

func jump_to_node(gid: String, node: GraphNode) -> void:
	nav_tool.jump_to_node(gid, node)

func refresh_navigator() -> void:
	nav_tool.refresh()

func scan_alerts() -> Dictionary:
	return alert_tool.scan_alerts()

func refresh_alerts() -> void:
	alert_tool.refresh()
