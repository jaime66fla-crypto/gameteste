@tool
class_name EditAnimationTool
extends AgentToolBase

func _get_tool_name() -> String:
	return "edit_animation"

func _get_tool_short_description() -> String:
	return "编辑动画属性、管理轨道、管理关键帧"

func _get_tool_description() -> String:
	return "编辑动画属性（长度、循环模式等）、添加/编辑轨道、添加/编辑关键帧。"

func _get_tool_parameters() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"scene_path": {
				"type": "string",
				"description": "场景路径，以 res:// 开头"
			},
			"animation_player_path": {
				"type": "string",
				"description": "AnimationPlayer 节点路径"
			},
			"library_name": {
				"type": "string",
				"description": "动画库名称"
			},
			"animation_name": {
				"type": "string",
				"description": "目标动画名称"
			},
			"new_name": {
				"type": "string",
				"description": "可选。重命名动画"
			},
			"length": {
				"type": "number",
				"description": "可选。修改动画长度（秒）"
			},
			"loop_mode": {
				"type": "string",
				"description": "可选。循环模式：\"none\" / \"linear\" / \"pingpong\""
			},
			"step": {
				"type": "number",
				"description": "可选。修改时间轴步进值"
			},
			"track_actions": {
				"type": "array",
				"description": "可选。轨道操作列表",
				"items": {
					"type": "object",
					"properties": {
						"action": {
							"type": "string",
							"description": "\"add\" 或 \"edit\""
						},
						"track_index": {
							"type": "integer",
							"description": "编辑已有轨道时传入索引；新增时不传"
						},
						"track_type": {
							"type": "string",
							"description": "新增时指定：value/method/bezier/audio/animation/blend_shape/position_3d/rotation_3d/scale_3d"
						},
						"node_path": {
							"type": "string",
							"description": "轨道绑定的节点路径（相对 AnimationPlayer 的 root_node）"
						},
						"property": {
							"type": "string",
							"description": "value/bezier 类型轨道时指定属性名"
						}
					},
					"required": ["action"]
				}
			},
			"keyframe_actions": {
				"type": "array",
				"description": "可选。关键帧操作列表",
				"items": {
					"type": "object",
					"properties": {
						"action": {
							"type": "string",
							"description": "\"add\" 或 \"edit\""
						},
						"track_index": {
							"type": "integer",
							"description": "目标轨道索引"
						},
						"time": {
							"type": "number",
							"description": "关键帧时间位置（秒）"
						},
						"value": {
							"type": "string",
							"description": "关键帧值，使用 var_to_str 兼容格式"
						},
						"transition": {
							"type": "number",
							"description": "可选。过渡曲线时间，默认 1.0，仅 value 类型轨道"
						},
						"in_handle": {
							"type": "string",
							"description": "贝塞尔入控制手柄 Vector2 的 var_to_str 格式"
						},
						"out_handle": {
							"type": "string",
							"description": "贝塞尔出控制手柄 Vector2 的 var_to_str 格式"
						},
						"stream": {
							"type": "string",
							"description": "音频流资源路径（res://），仅 audio 类型轨道"
						},
						"start_offset": {
							"type": "number",
							"description": "音频起始偏移（秒），仅 audio 类型轨道"
						},
						"end_offset": {
							"type": "number",
							"description": "音频结束偏移（秒），仅 audio 类型轨道"
						},
						"animation": {
							"type": "string",
							"description": "引用的动画名称，仅 animation 类型轨道"
						}
					},
					"required": ["action", "track_index", "time"]
				}
			}
		},
		"required": ["scene_path", "animation_player_path", "library_name", "animation_name"]
	}

func _get_tool_readonly() -> bool:
	return false

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.SCENE

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if json == null or not json.has("scene_path") or not json.has("animation_player_path") or not json.has("library_name") or not json.has("animation_name"):
		return {"error": "调用失败。请检查参数是否正确。"}

	var scene_path = json.scene_path as String
	var anim_player_path = json.animation_player_path as String
	var library_name = json.library_name as String
	var animation_name = json.animation_name as String

	var anim_player = AgentToolUtils.get_target_node(scene_path, anim_player_path)
	if not anim_player:
		return {"error": "无法获取目标节点，请检查路径是否正确。"}

	if not anim_player is AnimationPlayer:
		return {"error": "目标节点不是 AnimationPlayer 类型。"}

	var library = anim_player.get_animation_library(library_name)
	if not library:
		return {"error": "动画库 '" + library_name + "' 不存在。"}

	var animation = library.get_animation(animation_name)
	if not animation:
		return {"error": "动画 '" + animation_name + "' 不存在。"}

	# ---- 阶段一：修改动画属性 ----
	if json.has("new_name"):
		var new_name = json.new_name as String
		if not new_name.is_empty():
			library.rename_animation(animation_name, new_name)
			animation_name = new_name

	if json.has("length"):
		animation.length = json.length as float

	if json.has("loop_mode"):
		var mode = _string_to_loop_mode(json.loop_mode as String)
		if mode == -1:
			return {"error": "无效的循环模式，应为 none/linear/pingpong。"}
		animation.loop_mode = mode

	if json.has("step"):
		animation.step = json.step as float

	# ---- 阶段二：处理轨道操作 ----
	if json.has("track_actions"):
		var track_actions = json.track_actions as Array
		for track_action in track_actions:
			var action = track_action.action as String
			match action:
				"add":
					var result = _add_track(animation, track_action, anim_player)
					if result.has("error"):
						return result
				"edit":
					var result = _edit_track(animation, track_action, anim_player)
					if result.has("error"):
						return result
				_:
					return {"error": "无效的轨道操作 action：'" + action + "'，应为 add/edit。"}

	# ---- 阶段三：处理关键帧操作 ----
	if json.has("keyframe_actions"):
		var keyframe_actions = json.keyframe_actions as Array
		for kf_action in keyframe_actions:
			var action = kf_action.action as String
			var track_idx = kf_action.track_index as int

			if track_idx < 0 or track_idx >= animation.get_track_count():
				return {"error": "关键帧操作：轨道索引 " + str(track_idx) + " 无效。"}

			var track_type = animation.track_get_type(track_idx)
			match action:
				"add":
					var result = _add_keyframe(animation, track_idx, track_type, kf_action)
					if result.has("error"):
						return result
				"edit":
					var result = _edit_keyframe(animation, track_idx, track_type, kf_action)
					if result.has("error"):
						return result
				_:
					return {"error": "无效的关键帧操作 action：'" + action + "'，应为 add/edit。"}

	return {"success": true, "message": "动画编辑完成。"}


# ---- 路径转换 ----

## 将场景根节点相对路径转换为 AnimationPlayer 的 root_node 相对路径
## 例如场景层级为 AnimTest/AnimationPlayer + AnimTest/Sprite2D，
## 传入 "Sprite2D" 场景根节点相对路径，root_node=AnimTest，返回 "Sprite2D"（不变）
## 如果 root_node 不是场景根节点，自动计算相对路径
static func _resolve_anim_root_path(anim_player: AnimationPlayer, raw_path: String) -> String:
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		return raw_path

	# 如果路径就是 "."，保持不动
	if raw_path == ".":
		return raw_path

	# 标准化场景根节点相对路径
	var normalized = AgentToolUtils.normalize_node_path(raw_path, scene_root.name)

	# 在场景中查找目标节点
	var target = scene_root.get_node(normalized)
	if not target:
		# 如果找不到，尝试直接用 raw_path 解析
		target = scene_root.get_node(raw_path)
	if not target:
		return raw_path

	# 获取 AnimationPlayer 的 root_node
	var root_node_path = anim_player.root_node
	var root = anim_player.get_node(root_node_path) if root_node_path else null
	if not root:
		return raw_path

	# 计算从 root_node 到目标节点的相对路径
	var relative = root.get_path_to(target)
	return str(relative)


# ---- 轨道操作 ----

static func _add_track(animation: Animation, track_action: Dictionary, anim_player: AnimationPlayer) -> Dictionary:
	if not track_action.has("track_type") or not track_action.has("node_path"):
		return {"error": "添加轨道需要提供 track_type 和 node_path。"}

	var track_type_str = track_action.track_type as String
	var track_type = _string_to_track_type(track_type_str)
	if track_type == -1:
		return {"error": "无效的轨道类型：'" + track_type_str + "'。"}

	var new_idx = animation.add_track(track_type)
	var raw = track_action.node_path as String
	var resolved = _resolve_anim_root_path(anim_player, raw)

	match track_type:
		Animation.TYPE_VALUE:
			var property = track_action.get("property", "")
			animation.track_set_path(new_idx, NodePath(resolved + ":" + property))
		Animation.TYPE_METHOD:
			animation.track_set_path(new_idx, NodePath(resolved))
		Animation.TYPE_BEZIER:
			var property = track_action.get("property", "")
			animation.track_set_path(new_idx, NodePath(resolved + ":" + property))
		_:
			animation.track_set_path(new_idx, NodePath(resolved))

	return {}

static func _edit_track(animation: Animation, track_action: Dictionary, anim_player: AnimationPlayer) -> Dictionary:
	if not track_action.has("track_index"):
		return {"error": "编辑轨道需要提供 track_index。"}

	var track_idx = track_action.track_index as int
	if track_idx < 0 or track_idx >= animation.get_track_count():
		return {"error": "编辑轨道：索引 " + str(track_idx) + " 无效。"}

	if track_action.has("node_path"):
		var raw = track_action.node_path as String
		var resolved = _resolve_anim_root_path(anim_player, raw)
		if track_action.has("property"):
			var property = track_action.property as String
			animation.track_set_path(track_idx, NodePath(resolved + ":" + property))
		else:
			animation.track_set_path(track_idx, NodePath(resolved))

	return {}


# ---- 关键帧操作 ----

static func _add_keyframe(animation: Animation, track_idx: int, track_type: int, kf_action: Dictionary) -> Dictionary:
	var time = kf_action.time as float

	match track_type:
		Animation.TYPE_VALUE, Animation.TYPE_METHOD:
			var value = str_to_var(kf_action.get("value", "null"))
			var transition = kf_action.get("transition", 1.0)
			animation.track_insert_key(track_idx, time, value, transition)

		Animation.TYPE_BEZIER:
			var value = float(kf_action.get("value", "0"))
			var in_handle = _parse_vector2(kf_action.get("in_handle", "(0, 0)"))
			var out_handle = _parse_vector2(kf_action.get("out_handle", "(0, 0)"))
			animation.bezier_track_insert_key(track_idx, time, value, in_handle, out_handle)

		Animation.TYPE_AUDIO:
			var stream_path = kf_action.get("stream", "")
			var stream = null
			if not stream_path.is_empty():
				stream = load(stream_path)
			var start_offset = kf_action.get("start_offset", 0.0)
			var end_offset = kf_action.get("end_offset", 0.0)
			animation.audio_track_insert_key(track_idx, time, stream, start_offset, end_offset)

		Animation.TYPE_ANIMATION:
			var anim_name = kf_action.get("animation", "")
			animation.animation_track_insert_key(track_idx, time, anim_name)

		Animation.TYPE_BLEND_SHAPE:
			var value = float(kf_action.get("value", "0"))
			animation.blend_shape_track_insert_key(track_idx, time, value)

		Animation.TYPE_POSITION_3D:
			var value = str_to_var(kf_action.get("value", "Vector3(0, 0, 0)"))
			animation.position_track_insert_key(track_idx, time, value)

		Animation.TYPE_ROTATION_3D:
			var value = str_to_var(kf_action.get("value", "Quaternion(0, 0, 0, 1)"))
			animation.rotation_track_insert_key(track_idx, time, value)

		Animation.TYPE_SCALE_3D:
			var value = str_to_var(kf_action.get("value", "Vector3(1, 1, 1)"))
			animation.scale_track_insert_key(track_idx, time, value)

		_:
			return {"error": "不支持的轨道类型：" + str(track_type)}

	return {}

static func _edit_keyframe(animation: Animation, track_idx: int, track_type: int, kf_action: Dictionary) -> Dictionary:
	var time = kf_action.time as float
	var key_idx = animation.track_find_key(track_idx, time, Animation.FIND_MODE_EXACT)
	if key_idx < 0:
		key_idx = _find_key_by_time(animation, track_idx, time)
	if key_idx < 0:
		return {"error": "未找到时间点为 " + str(time) + " 的关键帧。"}

	if kf_action.has("value"):
		var value: Variant
		match track_type:
			Animation.TYPE_BEZIER:
				value = float(kf_action.value)
			Animation.TYPE_BLEND_SHAPE:
				value = float(kf_action.value)
			_:
				value = str_to_var(kf_action.value)
		animation.track_set_key_value(track_idx, key_idx, value)

	if kf_action.has("transition") and track_type in [Animation.TYPE_VALUE, Animation.TYPE_METHOD]:
		animation.track_set_key_transition(track_idx, key_idx, kf_action.transition as float)

	if kf_action.has("time") and abs(kf_action.time - animation.track_get_key_time(track_idx, key_idx)) > 0.001:
		animation.track_set_key_time(track_idx, key_idx, kf_action.time)

	return {}


# ---- 辅助函数 ----

static func _string_to_track_type(type_str: String) -> int:
	match type_str:
		"value":
			return Animation.TYPE_VALUE
		"method":
			return Animation.TYPE_METHOD
		"bezier":
			return Animation.TYPE_BEZIER
		"audio":
			return Animation.TYPE_AUDIO
		"animation":
			return Animation.TYPE_ANIMATION
		"blend_shape":
			return Animation.TYPE_BLEND_SHAPE
		"position_3d":
			return Animation.TYPE_POSITION_3D
		"rotation_3d":
			return Animation.TYPE_ROTATION_3D
		"scale_3d":
			return Animation.TYPE_SCALE_3D
		_:
			return -1

static func _string_to_loop_mode(mode: String) -> int:
	match mode:
		"none":
			return Animation.LOOP_NONE
		"linear":
			return Animation.LOOP_LINEAR
		"pingpong":
			return Animation.LOOP_PINGPONG
		_:
			return -1

static func _parse_vector2(str_val: String) -> Vector2:
	var result = str_to_var(str_val)
	if result is Vector2:
		return result
	return Vector2.ZERO

static func _find_key_by_time(animation: Animation, track_idx: int, time: float) -> int:
	var count = animation.track_get_key_count(track_idx)
	for i in range(count):
		if abs(animation.track_get_key_time(track_idx, i) - time) < 0.001:
			return i
	return -1
