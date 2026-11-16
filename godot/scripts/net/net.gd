extends Node
## Autoload "Net": WebSocket connection to the Cloudflare match server.
## Works in the web export (itch.io) and in the Windows download.
## Override the server for local tests: godot -- --server=ws://127.0.0.1:8787/godot/ws

signal lobby_joined(info: Dictionary)
signal lobby_updated(info: Dictionary)
signal match_started(info: Dictionary)
signal message(data: Dictionary)
signal connection_lost(reason: String)
## The server refused this build; `url` is where to download the new one.
signal update_required(message: String, url: String)
## Online play needs a valid session (it expired or was never made).
signal login_required(message: String)

const SESSION_FILE := "user://session.cfg"
var session_token := ""
var profile: Dictionary = {} # name, xp, rank, nextRank, nextRankXp, rankXp, kills, botKills, wins, matches

const DEFAULT_SERVER := "wss://floral-haze-1c57.jaime66fla.workers.dev/godot/ws"
const NAME_FILE := "user://player_name.cfg"

var server_url := DEFAULT_SERVER
var socket: WebSocketPeer
var my_id := ""
var room := ""
var host_id := ""
var in_match := false
var start_info: Dictionary = {}
var update_url := ""
var _opened := false
var _outdated := false
var _consumer_ready := false
var _pending: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			server_url = arg.substr(9)
	var config := ConfigFile.new()
	if config.load(SESSION_FILE) == OK:
		session_token = str(config.get_value("account", "token", ""))

# ------------------------------------------------------------- accounts ---

func is_logged_in() -> bool:
	return not session_token.is_empty() and not profile.is_empty()

func _api_url(path: String) -> String:
	return server_url.replace("wss://", "https://").replace("ws://", "http://").replace("/godot/ws", "/godot") + path

## HTTP call to the account API. Returns {"status": int, "data": Dictionary}.
func _api(path: String, body: Dictionary = {}, method: int = HTTPClient.METHOD_POST) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not session_token.is_empty():
		headers.append("Authorization: Bearer " + session_token)
	var error := request.request(_api_url(path), headers, method, JSON.stringify(body) if method == HTTPClient.METHOD_POST else "")
	if error != OK:
		request.queue_free()
		return {"status": 0, "data": {"error": "Não foi possível conectar ao servidor."}}
	var result: Array = await request.request_completed
	request.queue_free()
	var status: int = result[1]
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if status == 0 or result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "data": {"error": "Sem conexão com o servidor. Verifique sua internet."}}
	return {"status": status, "data": parsed if typeof(parsed) == TYPE_DICTIONARY else {}}

func _store_session(token: String) -> void:
	session_token = token
	var config := ConfigFile.new()
	config.set_value("account", "token", token)
	config.save(SESSION_FILE)

## Create an account or log in. Returns "" on success, or an error message.
func authenticate(account_name: String, password: String, create: bool) -> String:
	session_token = ""
	var response := await _api("/register" if create else "/login", {"name": account_name.strip_edges(), "password": password})
	var data: Dictionary = response["data"]
	if response["status"] in [200, 201] and data.has("token"):
		_store_session(str(data["token"]))
		profile = data.get("profile", {})
		return ""
	return str(data.get("error", "Não foi possível entrar."))

## Reload the profile with the saved session. Returns "" on success.
func refresh_profile() -> String:
	if session_token.is_empty():
		return "Sem sessão."
	var response := await _api("/me", {}, HTTPClient.METHOD_GET)
	if response["status"] == 200:
		profile = response["data"].get("profile", {})
		return ""
	if response["status"] == 401:
		logout()
	return str(response["data"].get("error", "Não foi possível carregar o perfil."))

func logout() -> void:
	leave()
	session_token = ""
	profile = {}
	var config := ConfigFile.new()
	config.set_value("account", "token", "")
	config.save(SESSION_FILE)

## Rank table shared with the server (data/ranks.json).
static func rank_table() -> Dictionary:
	var file := FileAccess.open("res://data/ranks.json", FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}

## Game version from project.godot (application/config/version), e.g. "0.1.0".
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## Comparable build number: 0.1.0 -> 100, 1.2.3 -> 10203. The server rejects
## builds below its GODOT_MIN_BUILD.
static func build_number() -> int:
	var parts := game_version().split(".")
	var build := 0
	for i in range(3):
		build = build * 100 + (int(parts[i]) if i < parts.size() else 0)
	return build

func load_name() -> String:
	var config := ConfigFile.new()
	if config.load(NAME_FILE) == OK:
		return str(config.get_value("player", "name", ""))
	return ""

func save_name(value: String) -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", value)
	config.save(NAME_FILE)

func find_match(player_name: String) -> Error:
	leave()
	socket = WebSocketPeer.new()
	_opened = false
	_outdated = false
	var clean := player_name.strip_edges().left(16)
	if clean.is_empty():
		clean = "Operador"
	# The session token identifies the account (name and XP come from the server).
	socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + session_token])
	return socket.connect_to_url(server_url + "?name=" + clean.uri_encode() + "&v=" + str(build_number()))

func is_online() -> bool:
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func send(data: Dictionary) -> void:
	if is_online():
		socket.send_text(JSON.stringify(data))

func leave() -> void:
	if socket != null:
		socket.close(1000, "saiu")
	socket = null
	my_id = ""
	room = ""
	host_id = ""
	in_match = false
	start_info = {}
	_consumer_ready = false
	_pending.clear()

## The match scene calls this once it can handle messages; buffered ones are replayed.
func attach_consumer() -> void:
	_consumer_ready = true
	var queued := _pending.duplicate()
	_pending.clear()
	for data in queued:
		message.emit(data)

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state != WebSocketPeer.STATE_CONNECTING:
		_opened = _opened or state == WebSocketPeer.STATE_OPEN
		# Drain even while closing: the server's last message explains why.
		while socket != null and socket.get_available_packet_count() > 0:
			var parsed = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				_handle(parsed)
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		var reason := socket.get_close_reason()
		var was_open := _opened
		socket = null
		if _outdated:
			return # update_required was already emitted
		if not was_open:
			reason = "Não foi possível conectar ao servidor."
		elif reason.is_empty():
			reason = "Conexão encerrada."
		connection_lost.emit(reason)

func _handle(data: Dictionary) -> void:
	match str(data.get("t", "")):
		"outdated":
			_outdated = true
			update_url = str(data.get("url", ""))
			update_required.emit(str(data.get("message", "Atualização disponível.")), update_url)
			return
		"auth":
			_outdated = true # closing right after; the menu shows the login screen
			login_required.emit(str(data.get("message", "Entre na sua conta para jogar online.")))
			return
		"profile":
			profile = data.get("profile", profile)
		"welcome":
			my_id = str(data["id"])
			room = str(data.get("room", ""))
			lobby_joined.emit(data)
			return
		"lobby":
			lobby_updated.emit(data)
			return
		"start":
			start_info = data
			host_id = str(data.get("host", ""))
			in_match = true
			_consumer_ready = false
			match_started.emit(data)
			return
		"host":
			host_id = str(data.get("id", ""))
	if in_match and not _consumer_ready:
		_pending.append(data)
	else:
		message.emit(data)
