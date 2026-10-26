extends Node
## Мост между миром и ИИ-агентами. Здесь же очередь просьб игрока: игрок пишет
## в поле внизу экрана, подключённый агент забирает просьбу командой
## next_request, строит объект и отвечает через spawn или reply.
##
## Игра слушает WebSocket на 127.0.0.1:7777,
## к нему подключается MCP-сервер из папки mcp-server. Каждое сообщение это
## JSON {"id", "cmd", "args"}, ответ {"id", "ok", "result" | "error"}.
##
## Сейчас мир хранит сама игра. Когда появится выделенный сервер для 5–10
## игроков, он будет говорить по этому же протоколу, а MCP-серверу нужно
## будет только поменять адрес мира (WORLD_URL).

const Builder := preload("res://scripts/object_builder.gd")
const Style := preload("res://scripts/style.gd")

const PORT := 7777
const SAVE_PATH := "user://agent_objects.json"
const MAX_OBJECTS := 500

var world
var _server := TCPServer.new()
var _peers: Array[WebSocketPeer] = []
## id -> {"record": Dictionary, "node": Node3D}
var _objects := {}
var _next_id := 1
var _toast: Label
var _toast_left := 0.0
## Просьбы игрока: {"id", "text", "status": queued|taken|done, "x", "z", "time"}.
var _requests: Array[Dictionary] = []
var _next_request := 1
var _agent_seen_ms := -1000000
## Сколько агентов прямо сейчас ждут просьбу (долгий запрос MCP).
var waiting_agents := 0

## Новости для поля ввода: что ответил агент, построен ли объект.
signal agent_message(request_id: String, text: String, done: bool)

const AGENT_ONLINE_MS := 90000
## Если агент взял просьбу и молчит дольше, игрок увидит предупреждение.
const REQUEST_STALE_MS := 240000


func _ready() -> void:
	var port := PORT
	var env := OS.get_environment("AI_SANDBOX_PORT")
	if env.is_valid_int():
		port = env.to_int()
	if _server.listen(port, "127.0.0.1") == OK:
		print("Мост для ИИ-агентов слушает ws://127.0.0.1:%d" % port)
	else:
		push_warning("Мост для ИИ-агентов не запустился: порт %d занят" % port)

	var layer := CanvasLayer.new()
	_toast = Label.new()
	_toast.position = Vector2(36, 120)
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	_toast.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.06))
	_toast.add_theme_constant_override("outline_size", 6)
	layer.add_child(_toast)
	add_child(layer)

	_load()


func _process(delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		var ws := WebSocketPeer.new()
		# Описание объекта может быть большим.
		ws.inbound_buffer_size = 4 * 1024 * 1024
		ws.outbound_buffer_size = 4 * 1024 * 1024
		if ws.accept_stream(_server.take_connection()) == OK:
			_peers.append(ws)
	for ws in _peers.duplicate():
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					_handle(ws, ws.get_packet().get_string_from_utf8())
			WebSocketPeer.STATE_CLOSED:
				_peers.erase(ws)

	for r in _requests:
		if r.status == "taken" and Time.get_ticks_msec() - r.time > REQUEST_STALE_MS:
			r.status = "done"
			agent_message.emit(r.id, "Агент долго не отвечает. Проверь, что он запущен (F2).", true)

	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left, 0.0, 1.0)


func _handle(ws: WebSocketPeer, text: String) -> void:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	var args: Dictionary = msg.get("args") if msg.get("args") is Dictionary else {}
	var reply := run(str(msg.get("cmd", "")), args)
	reply["id"] = msg.get("id")
	ws.send_text(JSON.stringify(reply))


## Выполняет команду мира. Её зовут и WebSocket-мост, и MCP внутри игры,
## и панель ИИ. Ответ {"ok": true, "result"} или {"ok": false, "error"}.
func run(cmd: String, args: Dictionary) -> Dictionary:
	match cmd:
		"world_info":
			return _ok(_world_info(args))
		"spawn":
			return _spawn(args)
		"list":
			return _ok(_list())
		"move":
			return _move(args)
		"remove":
			return _remove(args)
		"next_request":
			return _ok(_take_request())
		"reply":
			return _reply(args)
	return _err("unknown command: %s" % cmd)


# --- Просьбы игрока -------------------------------------------------------

## Игрок написал просьбу в поле ввода. Возвращает её id.
func submit_request(text: String) -> String:
	var p: Node3D = world.player
	var spot := _default_position(8.0)
	var r := {
		"id": "req_%d" % _next_request,
		"text": text,
		"status": "queued",
		"x": spot.x,
		"z": spot.y,
		"time": Time.get_ticks_msec(),
		"player": [p.position.x, p.position.y, p.position.z],
	}
	_next_request += 1
	_requests.append(r)
	if _requests.size() > 50:
		_requests.pop_front()
	return r.id


func has_queued_request() -> bool:
	for r in _requests:
		if r.status == "queued":
			return true
	return false


## Есть ли подключённый агент, который слушает просьбы.
func agent_online() -> bool:
	return waiting_agents > 0 or Time.get_ticks_msec() - _agent_seen_ms < AGENT_ONLINE_MS


## Отдаёт агенту следующую просьбу или null, если просьб нет.
func _take_request():
	_agent_seen_ms = Time.get_ticks_msec()
	for r in _requests:
		if r.status == "queued":
			r.status = "taken"
			r.time = Time.get_ticks_msec()
			agent_message.emit(r.id, "Агент строит…", false)
			return {
				"request_id": r.id,
				"text": r.text,
				"place_at": [r.x, r.z],
				"player_position": r.player,
				"how_to_answer": "Design the object and call place_object with this request_id (it is placed in front of the player automatically). If you cannot build it, call reply_to_player with a short answer in the player's language.",
			}
	return null


func _reply(args: Dictionary) -> Dictionary:
	var text := str(args.get("text", "")).strip_edges()
	if text == "":
		return _err("text is empty")
	var id := str(args.get("request_id", ""))
	var done := not (args.get("done") is bool and args.get("done") == false)
	var r := _find_request(id)
	if not r.is_empty() and done:
		r.status = "done"
	agent_message.emit(id, text, done)
	_agent_seen_ms = Time.get_ticks_msec()
	return _ok({"shown_to_player": text})


func _find_request(id: String) -> Dictionary:
	for r in _requests:
		if r.id == id:
			return r
	return {}


# --- Команды --------------------------------------------------------------

func _world_info(args: Dictionary) -> Dictionary:
	var p: Node3D = world.player
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, world.player.yaw)
	var vc: Vector2 = world.village_center()
	var info := {
		"units": "meters; +Y is up; ground height depends on terrain",
		"world_size": world.SIZE,
		"buildable_half_extent": _limit(),
		"water_level": world.WATER_LEVEL,
		"village_center": [vc.x, vc.y],
		"river_z_at_x0": world.river_z(0.0),
		"player": {
			"position": [p.position.x, p.position.y, p.position.z],
			"facing": [fwd.x, fwd.z],
		},
		"objects": _objects.size(),
		"max_objects": MAX_OBJECTS,
		"palette": Style.PALETTE.keys(),
	}
	# Высота земли в запрошенных точках [[x, z], ...].
	if args.get("points") is Array:
		var heights := []
		for q in (args.points as Array).slice(0, 64):
			if q is Array and q.size() >= 2:
				heights.append(world.height_at(float(q[0]), float(q[1])))
		info["heights"] = heights
	return info


func _spawn(args: Dictionary) -> Dictionary:
	if _objects.size() >= MAX_OBJECTS:
		return _err("world is full (%d objects), remove something first" % MAX_OBJECTS)
	var spec = args.get("spec")
	var problem := Builder.validate(spec)
	if problem != "":
		return _err(problem)

	var request := _find_request(str(args.get("request_id", "")))
	var pos := _default_position(float(args.get("distance", 8.0)))
	# Объект по просьбе ставится туда, куда игрок смотрел, когда просил.
	if not request.is_empty():
		pos = Vector2(request.x, request.z)
	if args.get("x") is float or args.get("x") is int:
		pos.x = float(args.x)
	if args.get("z") is float or args.get("z") is int:
		pos.y = float(args.z)
	var record := {
		"id": "obj_%d" % _next_id,
		"spec": spec,
		"x": clampf(pos.x, -_limit(), _limit()),
		"z": clampf(pos.y, -_limit(), _limit()),
		"y_offset": clampf(float(args.get("y_offset", 0.0)), -20.0, 60.0),
		"rotation_y": float(args.get("rotation_y", 0.0)),
		"author": str(args.get("author", "agent")),
		"prompt": str(args.get("prompt", "")) if str(args.get("prompt", "")) != "" else str(request.get("text", "")),
		"created": Time.get_datetime_string_from_system(true),
	}
	_next_id += 1
	_place(record)
	_save()
	if request.is_empty():
		_notify("%s создаёт: %s" % [record.author, spec.get("name", "объект")])
	else:
		request.status = "done"
		agent_message.emit(request.id, "Готово: %s" % spec.get("name", "объект"), true)
	_agent_seen_ms = Time.get_ticks_msec()
	return _ok(_summary(record))


func _move(args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not _objects.has(id):
		return _err("no object with id %s" % id)
	var record: Dictionary = _objects[id].record
	for key in ["x", "z", "y_offset", "rotation_y"]:
		if args.get(key) is float or args.get(key) is int:
			record[key] = float(args[key])
	record.x = clampf(record.x, -_limit(), _limit())
	record.z = clampf(record.z, -_limit(), _limit())
	_objects[id].node.queue_free()
	_place(record)
	_save()
	return _ok(_summary(record))


func _remove(args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not _objects.has(id):
		return _err("no object with id %s" % id)
	_objects[id].node.queue_free()
	_objects.erase(id)
	_save()
	return _ok({"removed": id})


func _list() -> Array:
	var out := []
	for id in _objects:
		out.append(_summary(_objects[id].record))
	return out


# --- Размещение и сохранение ----------------------------------------------

func _place(record: Dictionary) -> void:
	var spec: Dictionary = record.spec
	var node := Builder.build(spec)
	var ground: float = world.height_at(record.x, record.z)
	# Подвижные предметы появляются чуть выше и падают на землю сами.
	var lift := 0.4 if node is RigidBody3D else 0.0
	node.position = Vector3(record.x, ground + record.y_offset + lift, record.z)
	node.rotation.y = deg_to_rad(record.rotation_y)
	node.set_meta("agent_object_id", record.id)
	world.add_child(node)
	_objects[record.id] = {"record": record, "node": node}


func _default_position(distance: float) -> Vector2:
	var p: Node3D = world.player
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, world.player.yaw)
	var d := clampf(distance, 2.0, 60.0)
	return Vector2(p.position.x + fwd.x * d, p.position.z + fwd.z * d)


func _limit() -> float:
	return world.SIZE * 0.4


func _summary(record: Dictionary) -> Dictionary:
	var spec: Dictionary = record.spec
	var physics: Dictionary = spec.get("physics") if spec.get("physics") is Dictionary else {}
	return {
		"id": record.id,
		"name": spec.get("name", "object"),
		"author": record.author,
		"prompt": record.prompt,
		"position": [record.x, world.height_at(record.x, record.z) + record.y_offset, record.z],
		"rotation_y": record.rotation_y,
		"parts": (spec.parts as Array).size(),
		"physics": physics.get("mode", "static"),
	}


func _save() -> void:
	var records := []
	for id in _objects:
		records.append(_objects[id].record)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"next_id": _next_id, "objects": records}))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return
	_next_id = int(data.get("next_id", 1))
	for record in data.get("objects", []):
		if record is Dictionary and Builder.validate(record.get("spec")) == "":
			_place(record)


func _notify(text: String) -> void:
	_toast.text = text
	_toast_left = 4.0


func _ok(result) -> Dictionary:
	return {"ok": true, "result": result}


func _err(message: String) -> Dictionary:
	return {"ok": false, "error": message}
