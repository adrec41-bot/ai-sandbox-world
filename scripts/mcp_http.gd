extends Node
## MCP прямо внутри игры: ИИ-агент подключается к http://127.0.0.1:7778/mcp
## без отдельного сервера и без Node.js (Streamable HTTP, ответы обычным JSON).
##
## Как агент узнаёт о просьбах игрока: MCP-запросы всегда идут от агента,
## поэтому агент вызывает wait_for_player_request, а игра держит этот запрос
## открытым, пока игрок не напишет что-нибудь в поле внизу экрана. Агент сам
## придумывает форму объекта по руководству стиля и ставит её через
## place_object, а игрок видит результат без всякого копирования.

const AiGuide := preload("res://scripts/ai_guide.gd")

const PORT := 7778
## Сколько ждать полный запрос от клиента, мс.
const TIMEOUT_MS := 10000
const MAX_REQUEST := 8 * 1024 * 1024
## Сколько по умолчанию ждать просьбу игрока, секунд. Меньше типичного
## таймаута MCP-клиентов, после пустого ответа агент просто спрашивает снова.
const WAIT_DEFAULT := 50
const WAIT_MAX := 300

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
			_drop(c)
			continue
		if c.has("wait"):
			_poll_wait(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_partial_data(n)
			if got[0] == OK:
				var buf: PackedByteArray = c.buf
				buf.append_array(got[1])
				c.buf = buf
		if _try_handle(c):
			_drop(c)
		elif not c.has("wait") and (Time.get_ticks_msec() - c.since > TIMEOUT_MS or c.buf.size() > MAX_REQUEST):
			_drop(c)


func _drop(c: Dictionary) -> void:
	if c.has("wait"):
		bridge.waiting_agents -= 1
		c.erase("wait")
	(c.peer as StreamPeerTCP).disconnect_from_host()
	_conns.erase(c)


## Агент ждёт просьбу: отвечаем, как только игрок что-то написал, или по таймауту.
func _poll_wait(c: Dictionary) -> void:
	var timed_out: bool = Time.get_ticks_msec() > c.wait.deadline
	if not timed_out and not bridge.has_queued_request():
		return
	var request = bridge.run("next_request", {}).result
	var result: Dictionary
	if request == null:
		result = _text("No new requests yet. Call wait_for_player_request again right away.", false)
	else:
		result = _text(JSON.stringify(request, "  "), false)
	_send(c.peer, 200, JSON.stringify({"jsonrpc": "2.0", "id": c.wait.id, "result": result}))
	_drop(c)


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
	if msg is Dictionary and _is_wait(msg):
		# Ответ придёт позже, когда игрок напишет просьбу (см. _poll_wait).
		var args: Dictionary = msg.params.get("arguments") if msg.params.get("arguments") is Dictionary else {}
		var seconds := clampi(int(args.get("timeout_seconds", WAIT_DEFAULT)), 1, WAIT_MAX)
		c["wait"] = {"id": _json_id(msg.id), "deadline": Time.get_ticks_msec() + seconds * 1000}
		bridge.waiting_agents += 1
		return false
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


func _is_wait(msg: Dictionary) -> bool:
	return msg.has("id") and str(msg.get("method", "")) == "tools/call" and msg.get("params") is Dictionary \
		and str(msg.params.get("name", "")) == "wait_for_player_request"


func _json_id(id):
	if id is float and id == floorf(id):
		return int(id)
	return id


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
	var id = _json_id(msg.id)
	var params: Dictionary = msg.get("params") if msg.get("params") is Dictionary else {}
	var result
	match str(msg.get("method", "")):
		"initialize":
			var info = params.get("clientInfo")
			if info is Dictionary:
				_client_name = str(info.get("name", "agent"))
			result = {
				"protocolVersion": str(params.get("protocolVersion", "2025-06-18")),
				"capabilities": {"tools": {}, "prompts": {}},
				"serverInfo": {"name": "ai-sandbox-world", "version": "0.2.0"},
				"instructions": AiGuide.builder_prompt() + "\n\n" + AiGuide.guide(),
			}
		"ping":
			result = {}
		"tools/list":
			result = {"tools": _tools()}
		"prompts/list":
			result = {"prompts": [{"name": "builder", "description": "Work as the game's builder: wait for player requests typed in the game and build them."}]}
		"prompts/get":
			result = {"messages": [{"role": "user", "content": {"type": "text", "text": AiGuide.builder_prompt()}}]}
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
		"wait_for_player_request":
			# Сюда попадает только вызов из пакета запросов: отвечаем сразу.
			var request = bridge.run("next_request", {}).result
			return _text("No new requests yet. Call wait_for_player_request again." if request == null else JSON.stringify(request, "  "), false)
		"reply_to_player":
			res = bridge.run("reply", args)
		"place_object":
			var spawn := {"spec": args.get("spec"), "author": _client_name}
			for key in ["prompt", "request_id"]:
				if args.get(key) is String:
					spawn[key] = args[key]
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
			"name": "wait_for_player_request",
			"description": "Wait until a player types a request in the game's input field, then return it with its request_id. Returns 'no new requests' after timeout_seconds; then call it again. Build the request with place_object (pass request_id) or answer with reply_to_player.",
			"inputSchema": {"type": "object", "properties": {
				"timeout_seconds": {"type": "number", "description": "How long to wait, 1-300 seconds (default 50)."},
			}},
		},
		{
			"name": "reply_to_player",
			"description": "Show a short message to the player in the game, e.g. when a request is unclear or cannot be built. Write in the player's language.",
			"inputSchema": {"type": "object", "required": ["text"], "properties": {
				"text": {"type": "string"},
				"request_id": {"type": "string", "description": "The request you are answering."},
				"done": {"type": "boolean", "description": "false if you are still working on the request (default true)."},
			}},
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
			"description": "Create an object you designed in the world. Pass request_id when building a player request. spec follows the format from get_style_guide: parts (box, prism, sphere, cylinder, cone, capsule, torus, lathe, extrude) in meters, y = 0 is the ground, colors are palette names. Omit x and z to place it in front of the player.",
			"inputSchema": {"type": "object", "required": ["spec"], "properties": {
				"spec": {"type": "object", "description": "Object spec: {name, physics: {mode}, parts: [...], effects: [...]}"},
				"request_id": {"type": "string", "description": "The request from wait_for_player_request this object answers. The object is then placed where the player was looking."},
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
