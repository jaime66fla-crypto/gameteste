@tool
class_name LittleHelperBridgeServer
extends Node

## Local TCP bridge server running inside the Godot editor.
## Listens on localhost (127.0.0.1) and handles JSON-RPC tool dispatch from external agents.

signal client_connected(client_id: int)
signal client_disconnected(client_id: int)

const DEFAULT_PORT := 9099
const MAX_PORT_ATTEMPTS := 10

static var instance: LittleHelperBridgeServer = null

var _server: TCPServer = null
var _clients: Array[Dictionary] = []
var _next_client_id: int = 1
var active_port: int = 0

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _init() -> void:
	_server = TCPServer.new()


func start_server(preferred_port: int = DEFAULT_PORT) -> bool:
	stop_server()
	
	var chosen_port := preferred_port
	var err := FAILED
	
	for i in range(MAX_PORT_ATTEMPTS):
		# Always bind to 127.0.0.1 (local loopback) for strict security
		err = _server.listen(chosen_port, "127.0.0.1")
		if err == OK:
			active_port = chosen_port
			print_rich("[color=#66ccff][b][LittleHelper][/b][/color] Bridge server listening on [u]127.0.0.1:%d[/u]" % active_port)
			return true
		chosen_port += 1
	
	push_warning("[LittleHelper] Failed to bind TCP server on ports %d-%d. Error code: %d" % [preferred_port, chosen_port - 1, err])
	active_port = 0
	return false


func stop_server() -> void:
	for client in _clients:
		var peer: StreamPeerTCP = client["peer"]
		if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
	_clients.clear()
	
	if _server and _server.is_listening():
		_server.stop()
	active_port = 0


func is_active() -> bool:
	return _server != null and _server.is_listening()


func _process(_delta: float) -> void:
	if not _server or not _server.is_listening():
		return
	
	# Accept pending incoming connections
	if _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			var cid := _next_client_id
			_next_client_id += 1
			_clients.append({
				"id": cid,
				"peer": peer,
				"buffer": ""
			})
			client_connected.emit(cid)
	
	# Poll active clients
	var to_remove := []
	for client in _clients:
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
			to_remove.append(client)
			continue
		
		if status == StreamPeerTCP.STATUS_CONNECTED:
			var bytes_avail := peer.get_available_bytes()
			if bytes_avail > 0:
				var chunk := peer.get_utf8_string(bytes_avail)
				client["buffer"] += chunk
				_process_client_buffer(client)
	
	for client in to_remove:
		var cid: int = client["id"]
		_clients.erase(client)
		client_disconnected.emit(cid)


func _process_client_buffer(client: Dictionary) -> void:
	var buffer: String = client["buffer"]
	while buffer.contains("\n"):
		var split_idx := buffer.find("\n")
		var line := buffer.substr(0, split_idx).strip_edges()
		buffer = buffer.substr(split_idx + 1)
		client["buffer"] = buffer
		
		if not line.is_empty():
			_handle_client_message(client, line)


func _handle_client_message(client: Dictionary, raw_message: String) -> void:
	var parsed = JSON.parse_string(raw_message)
	if not parsed is Dictionary:
		_send_response(client, {"error": "Invalid JSON payload", "raw": raw_message})
		return
	
	var msg: Dictionary = parsed
	var req_id = msg.get("id", null)
	
	# Standard MCP / JSON-RPC methods
	var method: String = msg.get("method", "")
	
	# Also support shorthand: {"tool": "...", "args": {...}}
	if method.is_empty() and msg.has("tool"):
		var tool_name: String = msg.get("tool", "")
		var tool_args: Dictionary = msg.get("args", {})
		var result := LittleHelperToolRegistry.execute_tool(tool_name, tool_args)
		_send_response(client, {
			"id": req_id,
			"result": result
		})
		return
	
	match method:
		"tools/list":
			var defs := LittleHelperToolRegistry.get_tool_definitions()
			_send_response(client, {
				"jsonrpc": "2.0",
				"id": req_id,
				"result": {
					"tools": defs
				}
			})
		
		"tools/call":
			var params: Dictionary = msg.get("params", {})
			var name: String = params.get("name", "")
			var arguments: Dictionary = params.get("arguments", {})
			var tool_result := LittleHelperToolRegistry.execute_tool(name, arguments)
			
			_send_response(client, {
				"jsonrpc": "2.0",
				"id": req_id,
				"result": {
					"content": [
						{
							"type": "text",
							"text": JSON.stringify(tool_result, "\t")
						}
					],
					"isError": tool_result.has("error")
				}
			})
		
		"ping":
			_send_response(client, {
				"jsonrpc": "2.0",
				"id": req_id,
				"result": {"status": "pong", "port": active_port}
			})
		
		_:
			_send_response(client, {
				"jsonrpc": "2.0",
				"id": req_id,
				"error": {
					"code": -32601,
					"message": "Method not found: %s" % method
				}
			})


func _send_response(client: Dictionary, payload: Dictionary) -> void:
	var peer: StreamPeerTCP = client.get("peer")
	if not peer or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	
	var json_str := JSON.stringify(payload) + "\n"
	peer.put_data(json_str.to_utf8_buffer())

