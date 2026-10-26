extends Node
## MCP прямо внутри игры: ИИ-агент подключается к http://127.0.0.1:7778/mcp
## без отдельного сервера и без Node.js (Streamable HTTP, ответы обычным JSON).
## Здесь агент сам придумывает форму объекта по руководству стиля и ставит
## её через place_object. Генерацию по промту силами Claude API даёт
## отдельный mcp-server.

const AiGuide := preload("res://scripts/ai_guide.gd")

const PORT := 7778
## Сколько ждать полный запрос от клиента, мс.
const TIMEOUT_MS := 10000
const MAX_REQUEST := 8 * 1024 * 1024

var bridge
var _server := TCPServer.new()
var _conns: Array[Dictionary] = []
var _client_name := "agent"


func _ready() -> void:
	var port := PORT
	var env := OS.get_environment("AI_SANDBOX_MCP_PORT")
	if env.is_valid_int():
		port = env.to_int()
	if _server.listen(port, "127.0.0.1") == OK:
		print("MCP для ИИ-агентов: http://127.0.0.1:%d/mcp" % port)
	else:
		push_warning("MCP для ИИ-агентов не запустился: порт %d занят" % port)


func url() -> String:
	return "http://127.0.0.1:%d/mcp" % _server.get_local_port()


func _process(_delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		_conns.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "since": Time.get_ticks_msec()})
	for c in _conns.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_partial_data(n)
			if got[0] == OK:
				var buf: PackedByteArray = c.buf
				buf.append_array(got[1])
				c.buf = buf
		if _try_handle(c) or Time.get_ticks_msec() - c.since > TIMEOUT_MS or c.buf.size() > MAX_REQUEST:
			peer.disconnect_from_host()
			_conns.erase(c)


# --- HTTP -----------------------------------------------------------------

## Отвечает, когда запрос пришёл целиком. Возвращает true, если ответ отправлен.
func _try_handle(c: Dictionary) -> bool:
	var buf: PackedByteArray = c.buf
	var head_end := _find_head_end(buf)
	if head_end < 0:
		return false
	var lines := buf.slice(0, head_end).get_string_from_utf8().split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() < 2:
		_send(c.peer, 400, "")
		return true
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].left(colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if buf.size() < head_end + 4 + length:
		return false

	var method := request_line[0]
	var path := request_line[1]
	# Защита от чужих веб-страниц в браузере: они не должны управлять миром.
	var origin := str(headers.get("origin", ""))
	if origin.begins_with("http") and not (origin.begins_with("http://localhost") or origin.begins_with("http://127.0.0.1")):
		_send(c.peer, 403, "")
		return true
	if not path.begins_with("/mcp"):
		_send(c.peer, 404, "AI Sandbox World: MCP endpoint is /mcp", "text/plain")
		return true
	if method != "POST":
		_send(c.peer, 405, "")
		return true

	var body := buf.slice(head_end + 4, head_end + 4 + length).get_string_from_utf8()
	var msg = JSON.parse_string(body)
	var reply = null
	if msg is Dictionary:
		reply = _rpc(msg)
	elif msg is Array:
		var replies := []
		for m in msg:
			if m is Dictionary:
				var r = _rpc(m)
				if r != null:
					replies.append(r)
		reply = replies if not replies.is_empty() else null
	else:
		reply = {"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "Parse error"}}
	if reply == null:
		_send(c.peer, 202, "")
	else:
		_send(c.peer, 200, JSON.stringify(reply))
	return true


func _find_head_end(buf: PackedByteArray) -> int:
	for i in mini(buf.size(), 16384) - 3:
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


func _send(peer: StreamPeerTCP, code: int, body: String, type := "application/json") -> void:
	var reasons := {200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"}
	var data := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n" % [code, reasons.get(code, "OK"), type, data.size()]
	if code == 405:
		head += "Allow: POST\r\n"
	peer.put_data((head + "\r\n").to_utf8_buffer())
	if data.size() > 0:
		peer.put_data(data)


# --- MCP (JSON-RPC) -------------------------------------------------------

func _rpc(msg: Dictionary):
	# Уведомления (без id) ответа не требуют.
	if not msg.has("id"):
		return null
	var id = msg.id
	if id is float and id == floorf(id):
		id = int(id)
	var params: Dictionary = msg.get("params") if msg.get("params") is Dictionary else {}
	var result
	match str(msg.get("method", "")):
		"initialize":
			var info = params.get("clientInfo")
			if info is Dictionary:
				_client_name = str(info.get("name", "agent"))
			result = {
				"protocolVersion": str(params.get("protocolVersion", "2025-06-18")),
				"capabilities": {"tools": {}},
				"serverInfo": {"name": "ai-sandbox-world", "version": "0.2.0"},
				"instructions": "You are building in a shared game world. Call get_world_info to see where the player is, design objects following the style guide below, and place them with place_object.\n\n" + AiGuide.guide(),
			}
		"ping":
			result = {}
		"tools/list":
			result = {"tools": _tools()}
		"tools/call":
			result = _call_tool(str(params.get("name", "")), params.get("arguments") if params.get("arguments") is Dictionary else {})
		var other:
			return {"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found: %s" % other}}
	return {"jsonrpc": "2.0", "id": id, "result": result}


func _call_tool(name: String, args: Dictionary) -> Dictionary:
	var res: Dictionary
	match name:
		"get_style_guide":
			return _text(AiGuide.guide(), false)
		"get_world_info":
			res = bridge.run("world_info", {"points": args.get("sample_points")} if args.get("sample_points") is Array else {})
		"place_object":
			var spawn := {"spec": args.get("spec"), "prompt": str(args.get("prompt", "")), "author": _client_name}
			for key in ["x", "z", "distance", "rotation_y", "y_offset"]:
				if args.get(key) is float or args.get(key) is int:
					spawn[key] = args[key]
			res = bridge.run("spawn", spawn)
		"list_objects":
			res = bridge.run("list", {})
		"move_object":
			res = bridge.run("move", args)
		"remove_object":
			res = bridge.run("remove", args)
		_:
			return _text("Unknown tool: %s" % name, true)
	if res.ok:
		return _text(JSON.stringify(res.result, "  "), false)
	return _text(res.error, true)


func _text(text: String, is_error: bool) -> Dictionary:
	return {"content": [{"type": "text", "text": text}], "isError": is_error}


func _tools() -> Array:
	var number := {"type": "number"}
	return [
		{
			"name": "get_style_guide",
			"description": "The world's style rules and the JSON object spec accepted by place_object. Read it before designing objects.",
			"inputSchema": {"type": "object", "properties": {}},
		},
		{
			"name": "get_world_info",
			"description": "World size, player position and facing, village center, palette, object count. Pass sample_points to get terrain heights at [x, z] points.",
			"inputSchema": {"type": "object", "properties": {
				"sample_points": {"type": "array", "items": {"type": "array", "items": number}, "maxItems": 64},
			}},
		},
		{
			"name": "place_object",
			"description": "Create an object you designed in the world. spec follows the format from get_style_guide: parts (box, prism, sphere, cylinder, cone, capsule, torus, lathe, extrude) in meters, y = 0 is the ground, colors are palette names. Omit x and z to place it in front of the player.",
			"inputSchema": {"type": "object", "required": ["spec"], "properties": {
				"spec": {"type": "object", "description": "Object spec: {name, physics: {mode}, parts: [...], effects: [...]}"},
				"prompt": {"type": "string", "description": "What the player asked for."},
				"x": number,
				"z": number,
				"distance": {"type": "number", "description": "Meters in front of the player when x/z are omitted (default 8)."},
				"rotation_y": {"type": "number", "description": "Yaw in degrees."},
				"y_offset": {"type": "number", "description": "Lift above the ground in meters."},
			}},
		},
		{
			"name": "list_objects",
			"description": "All objects created by agents: id, name, author, prompt, position.",
			"inputSchema": {"type": "object", "properties": {}},
		},
		{
			"name": "move_object",
			"description": "Move or rotate an object created by an agent.",
			"inputSchema": {"type": "object", "required": ["id"], "properties": {
				"id": {"type": "string"}, "x": number, "z": number, "rotation_y": number, "y_offset": number,
			}},
		},
		{
			"name": "remove_object",
			"description": "Delete an object created by an agent.",
			"inputSchema": {"type": "object", "required": ["id"], "properties": {"id": {"type": "string"}}},
		},
	]
