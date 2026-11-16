@tool
class_name LittleHelperLLMClient
extends Node

signal response_received(text: String)
signal request_failed(error_message: String)
signal status_changed(is_busy: bool, message: String)

const SETTINGS_FILE_PATH := "user://little_helper_settings.cfg"

var _http_request: HTTPRequest = null
var _history: Array[Dictionary] = [] # Array of {"role": "user"|"assistant", "content": "..."}
var _current_provider: int = 0

func _init() -> void:
	name = "LittleHelperLLMClient"


func _ready() -> void:
	if not _http_request:
		_http_request = HTTPRequest.new()
		_http_request.name = "HTTPRequest"
		add_child(_http_request)
		_http_request.request_completed.connect(_on_request_completed)


func clear_history() -> void:
	_history.clear()


func send_chat(user_prompt: String) -> void:
	if not _http_request:
		_http_request = HTTPRequest.new()
		_http_request.name = "HTTPRequest"
		add_child(_http_request)
		_http_request.request_completed.connect(_on_request_completed)
	
	var settings := _load_settings()
	var provider: int = settings.get("provider", 0)
	_current_provider = provider
	var model: String = settings.get("model", "gpt-4o")
	var api_key: String = settings.get("api_key", "").strip_edges()
	var endpoint: String = settings.get("endpoint", "").strip_edges()
	var temperature: float = float(settings.get("temperature", 0.7))
	
	# Validate API key (Ollama does not require an API key)
	if provider != 4 and api_key.is_empty():
		var p_name := _get_provider_name(provider)
		request_failed.emit("No API key configured for %s. Click the Settings gear icon to set your API key." % p_name)
		return
	
	status_changed.emit(true, "Thinking...")
	
	# Append to history
	_history.append({"role": "user", "content": user_prompt})
	# Limit history to last 10 messages
	if _history.size() > 10:
		_history = _history.slice(_history.size() - 10)
	
	var sys_prompt := _build_system_prompt()
	var headers: PackedStringArray = []
	var body_dict: Dictionary = {}
	var url: String = endpoint
	
	match provider:
		0, 3, 5: # OpenAI, DeepSeek, Custom / Compatible
			headers.append("Content-Type: application/json")
			if not api_key.is_empty():
				headers.append("Authorization: Bearer " + api_key)
			
			var msgs := [{"role": "system", "content": sys_prompt}]
			for m in _history:
				msgs.append(m)
			
			body_dict = {
				"model": model,
				"messages": msgs,
				"temperature": temperature
			}
			if url.is_empty():
				url = "https://api.openai.com/v1/chat/completions" if provider == 0 else "https://api.deepseek.com/v1/chat/completions"
		
		1: # Anthropic (Claude)
			headers.append("Content-Type: application/json")
			headers.append("x-api-key: " + api_key)
			headers.append("anthropic-version: 2023-06-01")
			
			var msgs := []
			for m in _history:
				msgs.append({"role": m["role"], "content": m["content"]})
			
			body_dict = {
				"model": model,
				"system": sys_prompt,
				"messages": msgs,
				"max_tokens": 2048,
				"temperature": temperature
			}
			if url.is_empty():
				url = "https://api.anthropic.com/v1/messages"
		
		2: # Google Gemini
			headers.append("Content-Type: application/json")
			if url.is_empty() or not url.contains(":generateContent"):
				url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [model, api_key]
			elif not url.contains("key="):
				url += ("&key=" if url.contains("?") else "?key=") + api_key
			
			var contents := []
			for m in _history:
				var g_role := "model" if m["role"] == "assistant" else "user"
				contents.append({
					"role": g_role,
					"parts": [{"text": m["content"]}]
				})
			
			body_dict = {
				"systemInstruction": {
					"parts": [{"text": sys_prompt}]
				},
				"contents": contents,
				"generationConfig": {
					"temperature": temperature
				}
			}
		
		4: # Ollama (Local)
			headers.append("Content-Type: application/json")
			if url.is_empty():
				url = "http://localhost:11434/api/chat"
			
			# If using native Ollama /api/chat endpoint
			if url.ends_with("/api/chat"):
				var msgs := [{"role": "system", "content": sys_prompt}]
				for m in _history:
					msgs.append(m)
				body_dict = {
					"model": model,
					"messages": msgs,
					"stream": false,
					"options": {"temperature": temperature}
				}
			else:
				# Ollama OpenAI-compatible endpoint (/v1/chat/completions)
				var msgs := [{"role": "system", "content": sys_prompt}]
				for m in _history:
					msgs.append(m)
				body_dict = {
					"model": model,
					"messages": msgs,
					"temperature": temperature
				}
	
	var json_body := JSON.stringify(body_dict)
	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		status_changed.emit(false, "")
		request_failed.emit("Failed to send HTTP request (error code %d). Check network/endpoint." % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	status_changed.emit(false, "")
	
	if result != HTTPRequest.RESULT_SUCCESS:
		var err_str := "HTTP request failed (result %d)." % result
		request_failed.emit(err_str)
		return
	
	var body_text := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		var err_msg := "API Error %d: %s" % [response_code, _extract_error_detail(body_text)]
		request_failed.emit(err_msg)
		return
	
	var json := JSON.new()
	var parse_err := json.parse(body_text)
	if parse_err != OK:
		request_failed.emit("Failed to parse API JSON response: %s" % json.get_error_message())
		return
	
	var data = json.get_data()
	if not data is Dictionary:
		request_failed.emit("Unexpected response format from API.")
		return
	
	var reply_text := _extract_reply_text(data, _current_provider)
	if reply_text.is_empty():
		request_failed.emit("Received empty response from LLM.")
		return
	
	_history.append({"role": "assistant", "content": reply_text})
	response_received.emit(reply_text)


func _extract_reply_text(data: Dictionary, provider: int) -> String:
	match provider:
		0, 3, 5: # OpenAI, DeepSeek, Custom
			if data.has("choices") and data["choices"] is Array and not data["choices"].is_empty():
				var choice = data["choices"][0]
				if choice is Dictionary and choice.has("message"):
					return choice["message"].get("content", "")
		1: # Anthropic
			if data.has("content") and data["content"] is Array:
				for block in data["content"]:
					if block is Dictionary and block.get("type") == "text":
						return block.get("text", "")
		2: # Gemini
			if data.has("candidates") and data["candidates"] is Array and not data["candidates"].is_empty():
				var candidate = data["candidates"][0]
				if candidate is Dictionary and candidate.has("content"):
					var c_content = candidate["content"]
					if c_content is Dictionary and c_content.has("parts") and c_content["parts"] is Array:
						var parts: Array = c_content["parts"]
						var text_accum := ""
						for p in parts:
							if p is Dictionary and p.has("text"):
								text_accum += p["text"]
						return text_accum
		4: # Ollama
			if data.has("message") and data["message"] is Dictionary:
				return data["message"].get("content", "")
			elif data.has("choices") and data["choices"] is Array and not data["choices"].is_empty():
				var choice = data["choices"][0]
				if choice is Dictionary and choice.has("message"):
					return choice["message"].get("content", "")
	
	# Generic fallback lookup
	if data.has("text"):
		return str(data["text"])
	if data.has("response"):
		return str(data["response"])
	return ""


func _extract_error_detail(body_text: String) -> String:
	var json := JSON.new()
	if json.parse(body_text) == OK and json.get_data() is Dictionary:
		var d: Dictionary = json.get_data()
		if d.has("error"):
			var err = d["error"]
			if err is Dictionary and err.has("message"):
				return str(err["message"])
			return str(err)
		elif d.has("detail"):
			return str(d["detail"])
	return body_text.substr(0, 160)


func _build_system_prompt() -> String:
	var ver := Engine.get_version_info().get("string", "4.x")
	var active_scene_info := ""
	if Engine.is_editor_hint() and EditorInterface != null:
		if EditorInterface.has_method("get_edited_scene_root"):
			var root := EditorInterface.get_edited_scene_root()
			if is_instance_valid(root):
				active_scene_info = "\nActive scene: '%s' (%s) at %s." % [
					root.name,
					root.get_class(),
					root.scene_file_path if root.scene_file_path else "unsaved"
				]
	
	return "You are LittleHelper, an AI pair programmer embedded directly in the Godot 4 editor dock.\nEngine: Godot %s.%s\nProvide helpful, accurate, and idiomatic GDScript 2.0 advice. Format code blocks using ```gdscript." % [ver, active_scene_info]


func _get_provider_name(provider: int) -> String:
	match provider:
		0: return "OpenAI"
		1: return "Anthropic Claude"
		2: return "Google Gemini"
		3: return "DeepSeek"
		4: return "Ollama"
		_: return "Custom Provider"


func _load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_FILE_PATH)
	if err == OK:
		return {
			"provider": int(cfg.get_value("llm", "provider", 0)),
			"model": str(cfg.get_value("llm", "model", "gpt-4o")),
			"api_key": str(cfg.get_value("llm", "api_key", "")),
			"endpoint": str(cfg.get_value("llm", "endpoint", "")),
			"temperature": float(cfg.get_value("llm", "temperature", 0.7))
		}
	return {
		"provider": 0,
		"model": "gpt-4o",
		"api_key": "",
		"endpoint": "https://api.openai.com/v1/chat/completions",
		"temperature": 0.7
	}

