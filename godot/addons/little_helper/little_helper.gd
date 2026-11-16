@tool
extends EditorPlugin

const DOCK_SCENE_PATH := "res://addons/little_helper/src/ui/little_helper_dock.tscn"

var dock_instance: Control = null
var bridge_server_instance: LittleHelperBridgeServer = null

func _enable_plugin() -> void:
	_mount_dock()
	_start_bridge_server()

func _disable_plugin() -> void:
	_stop_bridge_server()
	_unmount_dock()

func _enter_tree() -> void:
	if is_instance_valid(dock_instance):
		_unmount_dock()
	_mount_dock()
	_start_bridge_server()

func _exit_tree() -> void:
	_stop_bridge_server()
	_unmount_dock()

func _mount_dock() -> void:
	if is_instance_valid(dock_instance):
		return
	
	if not ResourceLoader.exists(DOCK_SCENE_PATH):
		push_error("[LittleHelper] Dock scene not found at %s" % DOCK_SCENE_PATH)
		return
	
	var dock_scene: PackedScene = load(DOCK_SCENE_PATH)
	if dock_scene == null or not dock_scene.can_instantiate():
		push_error("[LittleHelper] Failed to instantiate dock scene.")
		return
	
	var instance := dock_scene.instantiate()
	if not instance is Control:
		push_error("[LittleHelper] Root node of dock scene must be a Control.")
		instance.free()
		return
	
	dock_instance = instance
	dock_instance.name = "LittleHelper"
	
	if dock_instance.has_signal("settings_saved"):
		dock_instance.connect("settings_saved", _on_settings_saved)
	
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
	print_rich("[color=#66ccff][b][LittleHelper][/b][/color] Enabled and dock mounted.")

func _unmount_dock() -> void:
	if not is_instance_valid(dock_instance):
		dock_instance = null
		return
	
	if dock_instance.has_signal("settings_saved") and dock_instance.is_connected("settings_saved", _on_settings_saved):
		dock_instance.disconnect("settings_saved", _on_settings_saved)
	
	if dock_instance.is_inside_tree():
		remove_control_from_docks(dock_instance)
	
	dock_instance.free()
	dock_instance = null
	print_rich("[color=#ff9966][b][LittleHelper][/b][/color] Disabled and dock completely removed.")

func _start_bridge_server() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://little_helper_settings.cfg")
	var enabled := true
	var port := 9099
	if err == OK:
		enabled = bool(cfg.get_value("bridge", "enabled", true))
		port = int(cfg.get_value("bridge", "port", 9099))
	
	if not enabled:
		_stop_bridge_server()
		return
	
	if is_instance_valid(bridge_server_instance):
		if bridge_server_instance.active_port != port:
			bridge_server_instance.start_server(port)
		return
	
	bridge_server_instance = LittleHelperBridgeServer.new()
	bridge_server_instance.name = "LittleHelperBridgeServer"
	add_child(bridge_server_instance)
	bridge_server_instance.start_server(port)

func _stop_bridge_server() -> void:
	if is_instance_valid(bridge_server_instance):
		bridge_server_instance.stop_server()
		bridge_server_instance.queue_free()
		bridge_server_instance = null

func _on_settings_saved() -> void:
	_start_bridge_server()
