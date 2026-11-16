@tool
class_name GetInputMappingsTool
extends AgentToolBase

## 获取项目中所有已配置的输入映射工具
## 用于查询当前项目已定义的所有输入动作及其绑定的按键/手柄按钮

func _get_tool_name() -> String:
	return "get_input_mappings"

func _get_tool_short_description() -> String:
	return "获取项目的输入映射配置。"

func _get_tool_description() -> String:
	return """获取当前项目中所有已配置的输入映射信息。
返回每个输入动作的名称、绑定的按键/手柄按钮以及死区值。
读取的是 project.godot 文件中的 input/ 配置。
此工具为只读操作，不会修改任何项目文件。"""

func _get_tool_parameters() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"include_ui": {
				"type": "boolean",
				"description": "是否包含 ui_* 系统输入事件（如 ui_accept, ui_cancel 等编辑器内置事件），默认 false 不包含。",
				"default": false
			}
		},
		"required": []
	}

func _get_tool_readonly() -> bool:
	return true

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.QUERY

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	var include_ui = false
	if json != null and json.has("include_ui"):
		include_ui = json.include_ui

	var input_mappings = _collect_all_input_mappings(include_ui)
	return {
		"success": true,
		"input_mappings": input_mappings,
		"total_count": input_mappings.size()
	}


## 收集项目中所有输入映射的核心函数
## 遍历 ProjectSettings 中所有以 "input/" 开头的配置项
## 解析每个输入动作的事件列表和死区值
## 参数 include_ui: 是否包含 ui_* 系统输入事件
## 返回值：Dictionary，键为动作名称，值为包含 deadzone 和 events 的字典
func _collect_all_input_mappings(include_ui: bool = false) -> Dictionary:
	var mappings = {}

	# 获取所有项目属性，遍历查找 input/ 开头的配置
	var property_list = ProjectSettings.get_property_list()
	for prop in property_list:
		if not prop.name.begins_with("input/"):
			continue

		# 提取动作名称（去掉 "input/" 前缀）
		var action_name = prop.name.replace("input/", "")

		# 跳过内部字段（events 和 deadzone 本身）
		if action_name == "events" or action_name == "deadzone":
			continue

		# 默认过滤掉 ui_* 系统输入事件
		if not include_ui and action_name.begins_with("ui_"):
			continue

		# 获取该动作的配置
		var action_config = ProjectSettings.get_setting(prop.name)
		if action_config == null:
			continue

		# 提取死区值，默认 0.5
		var deadzone = 0.5
		if action_config.has("deadzone"):
			deadzone = action_config.deadzone

		# 提取事件列表并转换为可读字符串
		var events = []
		if action_config.has("events"):
			for event in action_config.events:
				var event_text = _convert_input_event_to_text(event)
				if event_text != "":
					events.append(event_text)

		mappings[action_name] = {
			"deadzone": deadzone,
			"events": events,
			"event_count": events.size()
		}

	return mappings


## 将 InputEvent 转换为可读文本
## 支持 InputEventKey（键盘按键）、InputEventJoypadButton（手柄按钮）、InputEventMouseButton（鼠标按键）
## 返回值：String，如 "Space"、"KeyA"、"Joypad Button 0"、"Mouse Button 1"
func _convert_input_event_to_text(event: InputEvent) -> String:
	# 处理键盘按键事件
	if event is InputEventKey:
		# 忽略 Shift/Ctrl/Alt 等修饰键的独立按下
		if event.keycode == 0 and event.physical_keycode == 0:
			return ""
		# 使用 as_text() 获取可读按键名称
		var key_name = event.as_text()
		# 过滤掉修饰键前缀，得到干净的按键名
		key_name = key_name.replace("Shift + ", "").replace("Ctrl + ", "").replace("Alt + ", "")
		return key_name

	# 处理手柄按钮事件
	elif event is InputEventJoypadButton:
		return "Joypad Button " + str(event.button_index)

	# 处理鼠标按键事件
	elif event is InputEventMouseButton:
		var button_names = {
			MOUSE_BUTTON_LEFT: "Left Click",
			MOUSE_BUTTON_RIGHT: "Right Click",
			MOUSE_BUTTON_MIDDLE: "Middle Click",
			MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
			MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
			MOUSE_BUTTON_WHEEL_LEFT: "Wheel Left",
			MOUSE_BUTTON_WHEEL_RIGHT: "Wheel Right",
			MOUSE_BUTTON_XBUTTON1: "X Button 1",
			MOUSE_BUTTON_XBUTTON2: "X Button 2"
		}
		if button_names.has(event.button_index):
			return button_names[event.button_index]
		return "Mouse Button " + str(event.button_index)

	# 其他类型的事件（如手柄摇杆、鼠标移动）暂不处理
	return ""