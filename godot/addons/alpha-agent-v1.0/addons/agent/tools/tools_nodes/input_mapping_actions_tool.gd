@tool
class_name InputMappingActionsTool
extends AgentToolBase

## 输入映射操作工具
## 支持对项目输入映射进行添加、修改、删除操作
## 会直接写入 project.godot 文件，导致项目配置变更

func _get_tool_name() -> String:
	return "input_mapping_actions"

func _get_tool_short_description() -> String:
	return "对输入映射进行增删改操作。"

func _get_tool_description() -> String:
	return """对项目的输入映射进行增删改操作，会直接写入 project.godot 文件。
支持键盘按键和手柄按钮的添加。
- action=add: 向指定动作追加新的按键（不会清除已有的按键）
- action=modify: 替换指定动作的所有按键为新的按键
- action=remove: 删除指定的输入动作

常见按键码：
- Space=32, Enter=16777218, Escape=16777216
- A=65, B=66, C=67 ... Z=90
- 数字 0=48, 1=49 ... 9=57
- 小键盘 0=96, 1=97 ... 9=105
- F1=112, F2=113 ... F12=123

**注意**：此操作会修改 project.godot 文件，请谨慎使用。"""

func _get_tool_parameters() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"action": {
				"type": "string",
				"enum": ["add", "modify", "remove"],
				"description": "操作类型：add=追加按键, modify=替换全部, remove=删除动作"
			},
			"action_name": {
				"type": "string",
				"description": "输入动作名称，如 'jump', 'move_left', 'attack'"
			},
			"keycodes": {
				"type": "array",
				"items": {"type": "integer"},
				"description": "键盘按键码数组，如 [32, 87] 表示 Space 和 W 同时触发该动作。空数组表示不添加键盘按键。"
			},
			"joypad_buttons": {
				"type": "array",
				"items": {"type": "integer"},
				"description": "手柄按钮索引数组，如 [0, 1] 表示多个手柄按钮。空数组表示不添加手柄按钮。"
			},
			"deadzone": {
				"type": "number",
				"description": "死区值，范围 0.0-1.0，默认 0.5。越接近 1 表示需要更用力按下才能触发。",
				"default": 0.5
			}
		},
		"required": ["action", "action_name"]
	}

func _get_tool_readonly() -> bool:
	return false

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.PROJECT

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if json == null:
		return {"error": "参数解析失败，请检查参数格式是否正确。"}

	# 验证必需参数
	if not json.has("action") or not json.has("action_name"):
		return {"error": "缺少必需参数：action 和 action_name 都是必填的。"}

	var action = json.action
	var action_name = json.action_name

	# 验证动作名称的合法性
	if not _validate_action_name(action_name):
		return {"error": "动作名称不合法，只能包含字母、数字和下划线，且不能为空。"}

	match action:
		"add":
			return _add_input_mapping(json)
		"modify":
			return _modify_input_mapping(json)
		"remove":
			return _remove_input_mapping(action_name)
		_:
			return {"error": "未知的 action 值，只支持 add、modify、remove。"}


## 添加或追加输入映射
## 如果动作已存在，会在现有基础上追加新的按键
func _add_input_mapping(json: Dictionary) -> Dictionary:
	var action_name = json.action_name
	var deadzone = json.get("deadzone", 0.5)
	var keycodes = json.get("keycodes", [])
	var joypad_buttons = json.get("joypad_buttons", [])

	# 构建事件列表
	var events = []

	# 添加键盘按键事件
	for keycode in keycodes:
		var key_event = InputEventKey.new()
		key_event.physical_keycode = int(keycode)  # 物理键码（布局无关）
		events.append(key_event)

	# 添加手柄按钮事件
	for button_index in joypad_buttons:
		var joy_event = InputEventJoypadButton.new()
		joy_event.button_index = int(button_index)  # 确保是整数
		events.append(joy_event)

	# 如果没有添加任何事件，返回错误
	if events.size() == 0:
		return {"error": "add 操作至少需要提供一个 keycodes 或 joypad_buttons。"}

	# 获取现有配置（如果存在）
	var existing_config = null
	var existing_events = []
	if ProjectSettings.has_setting("input/" + action_name):
		existing_config = ProjectSettings.get_setting("input/" + action_name)
		if existing_config.has("events"):
			existing_events = existing_config.events
		if existing_config.has("deadzone"):
			deadzone = existing_config.deadzone

	# 合并事件列表（避免重复添加相同的按键）
	var merged_events = existing_events.duplicate()
	for new_event in events:
		if not _event_exists_in_list(merged_events, new_event):
			merged_events.append(new_event)

	# 保存配置
	var config = {
		"deadzone": deadzone,
		"events": merged_events
	}
	ProjectSettings.set_setting("input/" + action_name, config)
	ProjectSettings.save()

	# 构建返回信息
	var added_count = events.size()
	var total_count = merged_events.size()
	return {
		"success": true,
		"message": "成功为动作 '%s' 添加了 %d 个按键，现有 %d 个按键。\n提示：项目设置可能不会立即更新，请在编辑器菜单中选择【项目 -> 重新加载当前项目】以使更改生效。" % [action_name, added_count, total_count],
		"action_name": action_name,
		"added_events": _events_to_text_list(events),
		"total_events": _events_to_text_list(merged_events)
	}


## 修改输入映射
## 会替换指定动作的所有按键为新提供的按键
func _modify_input_mapping(json: Dictionary) -> Dictionary:
	var action_name = json.action_name
	var deadzone = json.get("deadzone", 0.5)
	var keycodes = json.get("keycodes", [])
	var joypad_buttons = json.get("joypad_buttons", [])

	# 检查动作是否存在
	if not ProjectSettings.has_setting("input/" + action_name):
		return {"error": "动作 '%s' 不存在，无法修改。请先使用 add 创建一个动作。" % action_name}

	# 构建新的事件列表
	var events = []

	# 添加键盘按键事件
	for keycode in keycodes:
		var key_event = InputEventKey.new()
		key_event.physical_keycode = int(keycode)  # 物理键码（布局无关）
		events.append(key_event)

	# 添加手柄按钮事件
	for button_index in joypad_buttons:
		var joy_event = InputEventJoypadButton.new()
		joy_event.button_index = int(button_index)  # 确保是整数
		events.append(joy_event)

	# 如果没有提供任何新事件，保留原有的 deadzone 但清空事件
	# 这种情况下应该给出警告
	if events.size() == 0:
		return {"error": "modify 操作需要提供 keycodes 或 joypad_buttons 中的至少一个。"}

	# 保存新配置
	var config = {
		"deadzone": deadzone,
		"events": events
	}
	ProjectSettings.set_setting("input/" + action_name, config)
	ProjectSettings.save()

	return {
		"success": true,
		"message": "成功修改动作 '%s'，替换为 %d 个按键。\n提示：项目设置可能不会立即更新，请在编辑器菜单中选择【项目 -> 重新加载当前项目】以使更改生效。" % [action_name, events.size()],
		"action_name": action_name,
		"new_events": _events_to_text_list(events)
	}


## 删除输入映射
## 移除指定的输入动作
func _remove_input_mapping(action_name: String) -> Dictionary:
	# 检查动作是否存在
	if not ProjectSettings.has_setting("input/" + action_name):
		return {"error": "动作 '%s' 不存在，无需删除。" % action_name}

	# 删除动作配置（设置为 null 即可删除）
	ProjectSettings.set_setting("input/" + action_name, null)
	ProjectSettings.save()

	return {
		"success": true,
		"message": "成功删除动作 '%s'。\n提示：项目设置可能不会立即更新，请在编辑器菜单中选择【项目 -> 重新加载当前项目】以使更改生效。" % action_name,
		"action_name": action_name
	}


## 验证动作名称的合法性
## 动作名称只能包含字母、数字和下划线，且不能为空
func _validate_action_name(action_name: String) -> bool:
	if action_name == "" or action_name.length() == 0:
		return false
	# 检查是否包含非法字符（只能包含字母、数字、下划线）
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
	var result = regex.search(action_name)
	return result != null


## 检查事件是否已存在于列表中
## 用于避免重复添加相同的按键
func _event_exists_in_list(event_list: Array, new_event: InputEvent) -> bool:
	for existing_event in event_list:
		if _events_are_equal(existing_event, new_event):
			return true
	return false


## 比较两个 InputEvent 是否相同
## 使用 get_class() 判断类型，避免直接访问 .type 属性
func _events_are_equal(event1: InputEvent, event2: InputEvent) -> bool:
	# 类型不同肯定不相等
	if event1.get_class() != event2.get_class():
		return false

	# 都是键盘按键
	if event1 is InputEventKey:
		var e1 = event1 as InputEventKey
		var e2 = event2 as InputEventKey
		return e1.keycode == e2.keycode and e1.physical_keycode == e2.physical_keycode

	# 都是手柄按钮
	if event1 is InputEventJoypadButton:
		var e1 = event1 as InputEventJoypadButton
		var e2 = event2 as InputEventJoypadButton
		return e1.button_index == e2.button_index

	# 都是鼠标按键
	if event1 is InputEventMouseButton:
		var e1 = event1 as InputEventMouseButton
		var e2 = event2 as InputEventMouseButton
		return e1.button_index == e2.button_index

	return false


## 将事件列表转换为可读文本列表
func _events_to_text_list(events: Array) -> Array:
	var text_list = []
	for event in events:
		if event is InputEventKey:
			text_list.append(event.as_text())
		elif event is InputEventJoypadButton:
			text_list.append("Joypad Button " + str(event.button_index))
		elif event is InputEventMouseButton:
			text_list.append("Mouse Button " + str(event.button_index))
	return text_list
