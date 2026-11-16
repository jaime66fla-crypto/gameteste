@tool
extends VBoxContainer

@onready var global_memory_container: VBoxContainer = %GlobalMemoryContainer
@onready var global_memory_item_container: VBoxContainer = %GlobalMemoryItemContainer
@onready var project_memory_container: VBoxContainer = %ProjectMemoryContainer
@onready var project_memory_item_container: VBoxContainer = %ProjectMemoryItemContainer
@onready var add_global_memory: Button = %AddGlobalMemory
@onready var add_project_memory: Button = %AddProjectMemory

@onready var global_memory_file: String = AlphaAgentPlugin.global_setting.memory_file

const MEMORY_ITEM = preload("uid://cr2sav6by4tal")
const CONFIG = preload("uid://b4bcww0bmnxt0")

var _did_load: bool = false
var _setting_ready_connected: bool = false
func _ready() -> void:
	visibility_changed.connect(on_visibility_changed)
	add_global_memory.pressed.connect(on_add_global_memory)
	add_project_memory.pressed.connect(on_add_project_memory)

	# 等待 setting_ready 后再加载和渲染记忆
	if not _setting_ready_connected:
		_setting_ready_connected = true
		AlphaAgentPlugin.global_setting.setting_ready.connect(_on_setting_ready, CONNECT_ONE_SHOT)

func _on_setting_ready():
	if visible:
		_try_render()

func _try_render():
	if not AlphaAgentPlugin.global_setting.setting_is_ready:
		return
	if not _did_load:
		_did_load = true
		load_from_project()
		load_from_global()
	clear_memory_nodes()
	add_memory_nodes()

func on_visibility_changed():
	if visible:
		_try_render()
	else:
		clear_memory_nodes()

func load_from_project():
	var CONFIG := load("uid://b4bcww0bmnxt0") as AgentConfig
	AlphaAgentPlugin.project_memory = CONFIG.memory

func load_from_global():
	var memory_string = FileAccess.get_file_as_string(global_memory_file)
	if FileAccess.get_open_error() != OK:
		memory_string = ""

	var json = []
	if memory_string != "":
		json = JSON.parse_string(memory_string)

	AlphaAgentPlugin.global_memory.assign(json)

func add_memory_nodes():
	for i in AlphaAgentPlugin.global_memory.size():
		var global_memory = AlphaAgentPlugin.global_memory[i]
		var item = MEMORY_ITEM.instantiate()
		global_memory_item_container.add_child(item)
		item.set_text(global_memory)
		item.remove.connect(on_remove_global_memory.bind(item))
		item.save.connect(on_save_global_memory.bind(item))

	for i in AlphaAgentPlugin.project_memory.size():
		var project_memory = AlphaAgentPlugin.project_memory[i]
		var item = MEMORY_ITEM.instantiate()
		project_memory_item_container.add_child(item)
		item.set_text(project_memory)
		item.remove.connect(on_remove_project_memory.bind(item))
		item.save.connect(on_save_project_memory.bind(item))

func on_remove_global_memory(node: Control):
	var index = node.get_index()
	AlphaAgentPlugin.global_memory.remove_at(index)
	node.queue_free()
	save_global_memory_file()

func save_global_memory_file():
	var file = FileAccess.open(global_memory_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(AlphaAgentPlugin.global_memory))
	file.close()

func on_remove_project_memory(node: Control):
	var index = node.get_index()
	AlphaAgentPlugin.project_memory.remove_at(index)
	node.queue_free()
	save_project_memory_file()

func save_project_memory_file():
	var CONFIG := load("uid://b4bcww0bmnxt0") as AgentConfig
	CONFIG.memory = AlphaAgentPlugin.project_memory
	ResourceSaver.save(CONFIG, "uid://b4bcww0bmnxt0")

func on_save_global_memory(content, item: Control):
	var index = item.get_index()
	AlphaAgentPlugin.global_memory[index] = content
	save_global_memory_file()

func on_save_project_memory(content, item: Control):
	var index = item.get_index()
	AlphaAgentPlugin.project_memory[index] = content
	save_project_memory_file()

func clear_memory_nodes():
	var global_memory_item_count = global_memory_item_container.get_child_count()
	for i in global_memory_item_count:
		global_memory_item_container.get_child(global_memory_item_count - 1 - i).queue_free()
	var project_memory_item_count = project_memory_item_container.get_child_count()
	for i in project_memory_item_count:
		project_memory_item_container.get_child(project_memory_item_count - 1 - i).queue_free()

func on_add_global_memory():
	var item := MEMORY_ITEM.instantiate() as AgentMemoryItem
	global_memory_item_container.add_child(item)
	AlphaAgentPlugin.global_memory.push_back("")
	item.set_text("")
	item.set_state(AgentMemoryItem.State.Edit)
	item.remove.connect(on_remove_global_memory.bind(item))
	item.save.connect(on_save_global_memory.bind(item))

func on_add_project_memory():
	var item = MEMORY_ITEM.instantiate()
	project_memory_item_container.add_child(item)
	AlphaAgentPlugin.project_memory.push_back("")
	item.set_text("")
	item.set_state(AgentMemoryItem.State.Edit)
	item.remove.connect(on_remove_project_memory.bind(item))
	item.save.connect(on_save_project_memory.bind(item))
