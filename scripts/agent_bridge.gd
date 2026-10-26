extends Node
## Мост между миром и ИИ-агентами, а заодно хранилище мира: постройки,
## инвентарь, хотбар, просьбы игрока к ИИ и история отмены.
##
## Игрок пишет просьбу в панели внизу экрана, подключённый агент забирает её
## командой next_request и создаёт объект командой create: объект попадает
## в инвентарь (или сразу на отмеченную площадку). Из инвентаря игрок ставит
## предмет в мир сколько угодно раз, предмет остаётся как чертёж.
##
## Игра слушает WebSocket на 127.0.0.1:7777, к нему подключается MCP-сервер
## из папки mcp-server. Каждое сообщение это JSON {"id", "cmd", "args"},
## ответ {"id", "ok", "result" | "error"}. Те же команды выполняет MCP внутри
## игры (mcp_http.gd).
##
## У мира один создатель. Гостей без права строить можно будет пустить во
## втором релизе: у мира и каждого объекта уже записан автор.

const Builder := preload("res://scripts/object_builder.gd")
const Bricks := preload("res://scripts/bricks.gd")
const Style := preload("res://scripts/style.gd")
const Catalog := preload("res://scripts/catalog.gd")
const Worlds := preload("res://scripts/worlds.gd")
const WorldPhysics := preload("res://scripts/mechanics/world_physics.gd")

const PORT := 7777
const MAX_OBJECTS := 2000
const MAX_ITEMS := 1000
const HOTBAR_SIZE := 9
const UNDO_STEPS := 50
const AUTOSAVE_SECONDS := 60.0
## На каком расстоянии перед игроком ставится предмет по F.
const PLACE_DISTANCE := 5.0
## Размеры просьб в шипах по ширине.
const SIZES := {"S": 8, "M": 16, "L": 32, "XL": 64}
const KINDS := {
	"building": "a building or structure",
	"vehicle": "a vehicle the player can ride or fly (add mechanics.type vehicle)",
	"gear": "equipment the player can wear (add mechanics.type equipment)",
	"mechanism": "an interactive or moving object (add mechanics.type prop)",
	"nature": "nature: trees, rocks, hills, water, gardens",
	"rules": "a change to the world rules (call set_world_physics)",
}

var world
## Гравитация, скорость игроков и замедление времени, которые задают агенты.
var physics: Node
var world_id := ""
var meta := {}
var _server := TCPServer.new()
var _peers: Array[WebSocketPeer] = []
## id -> {"record": Dictionary, "node": Node3D}
var _objects := {}
var _next_id := 1
## Инвентарь: {"item_id", "name", "spec", "author", "prompt", "created",
## "category", "favorite", "deleted", "uses", "seen"}.
var inventory: Array[Dictionary] = []
var _next_item := 1
## Хотбар: id предметов в 9 слотах (пусто, если слот свободен).
var hotbar: Array[String] = []
var selected := 0
## Цвет базовых деталей.
var paint := "red"
var templates: Array[String] = []
var history: Array[String] = []
## Площадка «здесь» для ИИ в шипах: {"x0", "z0", "x1", "z1", "y"} или пусто.
var area := {}
## Выделенные в режиме строительства объекты: просьба к ИИ меняет их.
var selection: Array[String] = []
## Просьбы игрока: {"id", "text", "kind", "size", "area", "target", "status",
## "progress", "question", "options", "answer", "item_id", "time", "error"}.
## status: queued, taken, question, answered, done, failed.
var _requests: Array[Dictionary] = []
var _next_request := 1
var _agent_seen_ms := -1000000
## Сколько агентов прямо сейчас ждут просьбу (долгий запрос MCP).
var waiting_agents := 0
var _undo: Array = []
var _redo: Array = []
var _dirty_world := false
var _dirty_inventory := false
var _save_in := 0.0
var _autosave := AUTOSAVE_SECONDS

## Новости для интерфейса: что ответил агент, построен ли объект.
signal agent_message(request_id: String, text: String, done: bool)
signal inventory_changed
signal hotbar_changed
signal requests_changed
signal area_changed
signal selection_changed
## Объект появился в мире (animate: игрок или ИИ только что его поставил).
signal object_added(node: Node3D, animate: bool)
## Объект сейчас исчезнет: можно рассыпать его на кирпичи.
signal object_removing(node: Node3D)
signal notice(text: String)

const AGENT_ONLINE_MS := 90000
## Если агент взял просьбу и молчит дольше, игрок увидит предупреждение.
const REQUEST_STALE_MS := 300000


func _ready() -> void:
	var port := PORT
	var env := OS.get_environment("AI_SANDBOX_PORT")
	if env.is_valid_int():
		port = env.to_int()
	if _server.listen(port, "127.0.0.1") == OK:
		print("Мост для ИИ-агентов слушает ws://127.0.0.1:%d" % port)
	else:
		push_warning("Мост для ИИ-агентов не запустился: порт %d занят" % port)
	hotbar.resize(HOTBAR_SIZE)
	hotbar.fill("")
	physics = WorldPhysics.new()
	physics.name = "WorldPhysics"
	physics.world = world
	if world_id != "":
		physics.save_path = Worlds.physics_path(world_id)
	add_child(physics)
	_load()


func _process(delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		var ws := WebSocketPeer.new()
		# Описание объекта может быть большим.
		ws.inbound_buffer_size = 8 * 1024 * 1024
		ws.outbound_buffer_size = 8 * 1024 * 1024
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
			_finish(r, "failed", "ИИ долго не отвечает. Проверь, что агент запущен (F2).")

	if _dirty_world or _dirty_inventory:
		_save_in -= delta
		if _save_in <= 0.0:
			save_now()
	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = AUTOSAVE_SECONDS
		save_now(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if world_id != "":
			save_now()


func _handle(ws: WebSocketPeer, text: String) -> void:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	var args: Dictionary = msg.get("args") if msg.get("args") is Dictionary else {}
	var reply := run(str(msg.get("cmd", "")), args)
	reply["id"] = msg.get("id")
	ws.send_text(JSON.stringify(reply))


## Выполняет команду мира. Её зовут и WebSocket-мост, и MCP внутри игры.
## Ответ {"ok": true, "result"} или {"ok": false, "error"}.
func run(cmd: String, args: Dictionary) -> Dictionary:
	_agent_seen_ms = Time.get_ticks_msec()
	match cmd:
		"world_info":
			return _ok(_world_info(args))
		"create":
			return _create(args)
		"update":
			return _update(args)
		"get_spec":
			return _get_spec(args)
		"inventory":
			return _ok(_inventory_summary())
		"list":
			return _ok(_list())
		"area":
			return _area_info(args)
		"move":
			return _move_cmd(args)
		"remove":
			return _remove_cmd(args)
		"next_request":
			return _ok(_take_request())
		"reply":
			return _reply(args)
		"ask":
			return _ask(args)
		"progress":
			return _progress(args)
		"set_physics":
			var values: Dictionary = physics.set_values(args)
			notice.emit("%s меняет физику мира" % str(args.get("author", "ИИ")))
			return _ok(values)
	return _err("unknown command: %s" % cmd)


# --- Просьбы игрока -------------------------------------------------------

## Игрок отправил просьбу. opts: kind, size (S/M/L/XL), with_area, target, variant_of.
func submit_request(text: String, opts: Dictionary = {}) -> String:
	var r := {
		"id": "req_%d" % _next_request,
		"text": text,
		"kind": str(opts.get("kind", "")),
		"size": str(opts.get("size", "")),
		"area": area.duplicate() if opts.get("with_area", true) and not area.is_empty() else {},
		"target": str(opts.get("target", "")),
		"item": str(opts.get("item", "")),
		"variant_of": str(opts.get("variant_of", "")),
		"status": "queued",
		"progress": "",
		"question": "",
		"options": [],
		"answer": "",
		"item_id": "",
		"time": Time.get_ticks_msec(),
		"player": _player_pos(),
		"facing": _facing(),
	}
	_next_request += 1
	_requests.append(r)
	while _requests.size() > 40:
		_requests.pop_front()
	if text != "" and (history.is_empty() or history[-1] != text):
		history.append(text)
		while history.size() > 100:
			history.pop_front()
		_mark_inventory()
	requests_changed.emit()
	return r.id


func requests() -> Array[Dictionary]:
	return _requests


func find_request(id: String) -> Dictionary:
	for r in _requests:
		if r.id == id:
			return r
	return {}


## Игрок выбрал ответ на вопрос ИИ: ответ уходит агенту новой просьбой.
func answer_question(id: String, answer: String) -> void:
	var r := find_request(id)
	if r.is_empty() or r.status != "question":
		return
	r.answer = answer
	r.status = "answered"
	r.time = Time.get_ticks_msec()
	requests_changed.emit()


func cancel_request(id: String) -> void:
	var r := find_request(id)
	if r.is_empty():
		return
	_requests.erase(r)
	requests_changed.emit()


## Переделать: та же просьба ещё раз, агент знает, что нужен другой вариант.
func retry_request(id: String) -> String:
	var r := find_request(id)
	if r.is_empty():
		return ""
	return submit_request(r.text, {"kind": r.kind, "size": r.size, "with_area": false, "variant_of": r.item_id, "target": r.target, "item": r.get("item", "")})


## Шаблоны просьб: частые фразы игрока, вставляются одной кнопкой.
func add_template(text: String) -> void:
	text = text.strip_edges()
	if text == "" or text in templates:
		return
	templates.append(text.left(300))
	while templates.size() > 30:
		templates.pop_front()
	_mark_inventory()


func remove_template(text: String) -> void:
	templates.erase(text)
	_mark_inventory()


func has_queued_request() -> bool:
	for r in _requests:
		if r.status in ["queued", "answered"]:
			return true
	return false


## Есть ли подключённый агент, который слушает просьбы.
func agent_online() -> bool:
	return waiting_agents > 0 or Time.get_ticks_msec() - _agent_seen_ms < AGENT_ONLINE_MS


## Отдаёт агенту следующую просьбу (или ответ на его вопрос), null если нет.
func _take_request():
	for r in _requests:
		if r.status == "answered":
			r.status = "taken"
			r.time = Time.get_ticks_msec()
			r.progress = "ИИ получил ответ"
			requests_changed.emit()
			return {
				"type": "answer",
				"request_id": r.id,
				"original_request": r.text,
				"question": r.question,
				"answer": r.answer,
				"how_to_answer": "Continue the original request with this answer: build it with create_object (same request_id) or ask again with ask_player.",
			}
	for r in _requests:
		if r.status != "queued":
			continue
		r.status = "taken"
		r.time = Time.get_ticks_msec()
		r.progress = "ИИ думает…"
		requests_changed.emit()
		var out := {
			"type": "request",
			"request_id": r.id,
			"text": r.text,
			"player_position": r.player,
			"player_facing": r.facing,
			"how_to_answer": "Design the object from LEGO bricks and call create_object with this request_id: it goes to the player's inventory. If it is unclear, call ask_player. If you cannot build it, call reply_to_player with a short answer in the player's language.",
		}
		if r.kind != "":
			out["kind"] = KINDS.get(r.kind, r.kind)
		if r.size != "":
			out["size"] = "%s: fit the footprint into %d studs (%.1f m)" % [r.size, SIZES.get(r.size, 16), SIZES.get(r.size, 16) * Style.STUD]
		if not r.area.is_empty():
			var a: Dictionary = r.area
			out["area"] = {
				"size_studs": [a.x1 - a.x0, a.z1 - a.z0],
				"base_plates": a.y,
				"note": "The player marked this footprint. Build centered on the origin with exactly this footprint (x from %d to %d, z from %d to %d) and pass place: true to create_object: the object appears right there." % [-(a.x1 - a.x0) / 2, (a.x1 - a.x0) - (a.x1 - a.x0) / 2, -(a.z1 - a.z0) / 2, (a.z1 - a.z0) - (a.z1 - a.z0) / 2],
			}
		if r.target != "" and _objects.has(r.target):
			var rec: Dictionary = _objects[r.target].record
			out["edit_target"] = {"object_id": r.target, "name": rec.spec.get("name", "object"), "note": "The player wants to change this object. Read it with get_object_spec, then call update_object with object_id and the changed spec."}
		var it := get_item(str(r.get("item", "")))
		if not it.is_empty() and not it.get("basic", false):
			out["edit_item"] = {"item_id": it.item_id, "name": it.name, "note": "The player wants to change this inventory item. Read it with get_object_spec (item_id), then call update_object with item_id and the changed spec."}
		if r.variant_of != "":
			out["note"] = "The player asked for another variant: make it clearly different from the previous one (item %s)." % r.variant_of
		return out
	return null


func _reply(args: Dictionary) -> Dictionary:
	var text := str(args.get("text", "")).strip_edges()
	if text == "":
		return _err("text is empty")
	var id := str(args.get("request_id", ""))
	var done: bool = not (args.get("done") is bool and args.get("done") == false)
	var r := find_request(id)
	if not r.is_empty():
		if done:
			_finish(r, "done" if r.item_id != "" or r.status != "failed" else "failed", text)
		else:
			r.progress = text
			requests_changed.emit()
	agent_message.emit(id, text, done)
	return _ok({"shown_to_player": text})


func _ask(args: Dictionary) -> Dictionary:
	var r := find_request(str(args.get("request_id", "")))
	if r.is_empty():
		return _err("unknown request_id")
	var q := str(args.get("question", "")).strip_edges()
	if q == "":
		return _err("question is empty")
	var options: Array[String] = []
	if args.get("options") is Array:
		for o in (args.options as Array).slice(0, 4):
			options.append(str(o).left(60))
	r.status = "question"
	r.question = q.left(300)
	r.options = options
	r.progress = ""
	requests_changed.emit()
	agent_message.emit(r.id, q, false)
	return _ok({"asked": q, "options": options, "note": "The answer will come from wait_for_player_request as type 'answer'. Keep waiting for requests."})


func _progress(args: Dictionary) -> Dictionary:
	var r := find_request(str(args.get("request_id", "")))
	if r.is_empty():
		return _err("unknown request_id")
	r.progress = str(args.get("text", "")).left(120)
	r.time = Time.get_ticks_msec()
	requests_changed.emit()
	return _ok({"shown": r.progress})


func _finish(r: Dictionary, status: String, text: String) -> void:
	r.status = status
	r.progress = text
	requests_changed.emit()
	agent_message.emit(r.id, text, true)


# --- Команды агента -------------------------------------------------------

func _world_info(args: Dictionary) -> Dictionary:
	var info := {
		"units": "meters; 1 stud = 0.4 m, 1 plate = 0.16 m, 1 brick = 3 plates; +Y is up; the ground is a flat baseplate at y = 0",
		"world_name": meta.get("name", ""),
		"world_size_studs": world.studs,
		"world_size_meters": world.SIZE,
		"buildable_half_extent": _limit(),
		"player": {"position": _player_pos(), "facing": _facing()},
		"objects_in_world": _objects.size(),
		"inventory_items": _visible_items().size(),
		"max_objects": MAX_OBJECTS,
		"colors": Style.COLORS.keys(),
		"physics": WorldPhysics.values(),
		"physics_params": WorldPhysics.describe(),
	}
	if not area.is_empty():
		info["marked_area_studs"] = area
	if args.get("points") is Array:
		var heights := []
		for q in (args.points as Array).slice(0, 64):
			if q is Array and q.size() >= 2:
				heights.append(world.height_at(float(q[0]), float(q[1])))
		info["heights"] = heights
	return info


## Агент создал объект: он попадает в инвентарь, а с place: true ещё и в мир.
func _create(args: Dictionary) -> Dictionary:
	var spec = args.get("spec")
	var problem := Builder.validate(spec)
	if problem != "":
		return _err(problem)
	var request := find_request(str(args.get("request_id", "")))
	var prompt := str(args.get("prompt", ""))
	if prompt == "":
		prompt = str(request.get("text", ""))
	var category := str(args.get("category", spec.get("category", "")))
	if category == "" and not request.is_empty():
		category = {"building": "buildings", "vehicle": "vehicles", "gear": "gear", "mechanism": "mechanisms", "nature": "nature"}.get(request.kind, "")
	var item := add_item(spec, str(args.get("author", "ИИ")), prompt, category)
	if item.is_empty():
		return _err("the inventory is full (%d items)" % MAX_ITEMS)
	var placed := ""
	var place: bool = args.get("place") == true or (not request.is_empty() and not request.area.is_empty() and args.get("place") != false)
	if place:
		var a: Dictionary = request.get("area", {}) if not request.is_empty() and not request.area.is_empty() else area
		if not a.is_empty():
			placed = place_spec(item.spec, item.item_id, _area_center(a), a.y * Style.PLATE, 0.0, item.author, item.prompt)
		else:
			var spot := _default_position(PLACE_DISTANCE + _footprint(item.spec))
			placed = place_spec(item.spec, item.item_id, spot, 0.0, _snap_angle(rad_to_deg(world.player.yaw)), item.author, item.prompt)
	var note := "«%s» в инвентаре." % item.name if placed == "" else "«%s» построено на площадке." % item.name
	if request.is_empty():
		notice.emit("%s: %s" % [item.author, note])
	else:
		request.item_id = item.item_id
		_finish(request, "done", note)
	var out := {"item_id": item.item_id, "name": item.name, "where": "player's inventory"}
	if placed != "":
		out["object_id"] = placed
		out["where"] = "placed in the world and kept in the inventory"
	return _ok(out)


## Агент поменял существующий объект или предмет инвентаря.
func _update(args: Dictionary) -> Dictionary:
	var spec = args.get("spec")
	var problem := Builder.validate(spec)
	if problem != "":
		return _err(problem)
	var request := find_request(str(args.get("request_id", "")))
	var oid := str(args.get("object_id", args.get("id", "")))
	var iid := str(args.get("item_id", ""))
	var name := str(spec.get("name", "объект"))
	if oid != "":
		if not _objects.has(oid):
			return _err("no object with id %s" % oid)
		var record: Dictionary = _objects[oid].record
		_push_undo({"type": "spec", "id": oid, "before": record.spec, "after": spec})
		_set_spec(oid, spec)
		iid = str(record.get("item_id", ""))
	var item := get_item(iid)
	if not item.is_empty() and not item.get("basic", false):
		item.spec = spec
		item.name = name
		_mark_inventory()
		inventory_changed.emit()
	elif oid == "":
		return _err("pass object_id (from list_objects or edit_target) or item_id")
	if not request.is_empty():
		request.item_id = iid
		_finish(request, "done", "«%s» изменено." % name)
	return _ok({"updated": oid if oid != "" else iid, "name": name})


func _get_spec(args: Dictionary) -> Dictionary:
	var oid := str(args.get("object_id", args.get("id", "")))
	if oid != "" and _objects.has(oid):
		var rec: Dictionary = _objects[oid].record
		return _ok({"object_id": oid, "item_id": rec.get("item_id", ""), "spec": rec.spec})
	var item := get_item(str(args.get("item_id", "")))
	if not item.is_empty():
		return _ok({"item_id": item.item_id, "spec": item.spec})
	return _err("no such object or item")


## Что стоит на прямоугольнике [x, z] в метрах: чтобы агент не строил поверх.
func _area_info(args: Dictionary) -> Dictionary:
	var a := area
	var rect := Rect2()
	if args.get("from") is Array and args.get("to") is Array and (args.from as Array).size() >= 2 and (args.to as Array).size() >= 2:
		var f: Array = args.from
		var t: Array = args.to
		rect = Rect2(Vector2(minf(f[0], t[0]), minf(f[1], t[1])), Vector2(absf(t[0] - f[0]), absf(t[1] - f[1])))
	elif not a.is_empty():
		rect = Rect2(Vector2(a.x0, a.z0) * Style.STUD, Vector2(a.x1 - a.x0, a.z1 - a.z0) * Style.STUD)
	else:
		return _err("pass from and to as [x, z] in meters, or ask the player to mark an area")
	var found := []
	for id in _objects:
		var box := object_aabb(id)
		var r2 := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		if r2.intersects(rect):
			var s := _summary(_objects[id].record)
			s["top_height"] = box.end.y
			found.append(s)
	return _ok({"rect_meters": [rect.position.x, rect.position.y, rect.end.x, rect.end.y], "objects": found})


func _inventory_summary() -> Array:
	var out := []
	for item in _visible_items():
		out.append({"item_id": item.item_id, "name": item.name, "author": item.author, "category": Catalog.category_of(item)})
	return out


func _move_cmd(args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not _objects.has(id):
		return _err("no object with id %s" % id)
	var r: Dictionary = _objects[id].record
	var x := float(args.get("x", r.x)) if (args.get("x") is float or args.get("x") is int) else float(r.x)
	var z := float(args.get("z", r.z)) if (args.get("z") is float or args.get("z") is int) else float(r.z)
	var y := float(args.get("y_offset")) if (args.get("y_offset") is float or args.get("y_offset") is int) else float(r.y_offset)
	var rot := float(args.get("rotation_y")) if (args.get("rotation_y") is float or args.get("rotation_y") is int) else float(r.rotation_y)
	move_object(id, Vector2(x, z), y, rot)
	return _ok(_summary(_objects[id].record))


func _remove_cmd(args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not _objects.has(id):
		return _err("no object with id %s" % id)
	remove_object(id)
	return _ok({"removed": id})


func _list() -> Array:
	var out := []
	for id in _objects:
		out.append(_summary(_objects[id].record))
	return out


# --- Инвентарь ------------------------------------------------------------

## Новый предмет в инвентаре. Пустой словарь, если места нет.
func add_item(spec: Dictionary, author: String, prompt: String, category := "") -> Dictionary:
	if _active_items() >= MAX_ITEMS:
		# Сначала освобождаем место за счёт корзины.
		for item in inventory:
			if item.get("deleted", false):
				inventory.erase(item)
				break
		if _active_items() >= MAX_ITEMS:
			return {}
	var item := {
		"item_id": "item_%d" % _next_item,
		"name": str(spec.get("name", "объект")).left(64),
		"spec": spec,
		"author": author,
		"prompt": prompt,
		"created": Time.get_datetime_string_from_system(true),
		"category": category if category in Catalog.ITEM_CATEGORIES else "",
		"favorite": false,
		"deleted": false,
		"uses": 0,
		"seen": false,
	}
	item.category = Catalog.category_of(item)
	_next_item += 1
	inventory.append(item)
	# Новый предмет сам встаёт в первый свободный слот хотбара.
	var free := hotbar.find("")
	if free >= 0:
		hotbar[free] = item.item_id
		hotbar_changed.emit()
	_mark_inventory()
	inventory_changed.emit()
	return item


## Предмет по id, в том числе базовая деталь в текущем цвете.
func get_item(item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	if Catalog.is_basic(item_id):
		return Catalog.basic_item(item_id, paint)
	for item in inventory:
		if item.item_id == item_id:
			return item
	return {}


## Предметы для экрана инвентаря. sort: new, name, uses.
func items(category: String, query := "", sort := "new") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if category == "basic":
		out = Catalog.basic_items(paint)
	else:
		for item in inventory:
			var deleted: bool = item.get("deleted", false)
			if (category == "trash") != deleted:
				continue
			match category:
				"all", "trash":
					pass
				"new":
					if item.get("seen", false):
						continue
				"favorites":
					if not item.get("favorite", false):
						continue
				_:
					if Catalog.category_of(item) != category:
						continue
			out.append(item)
	var q := query.strip_edges().to_lower()
	if q != "":
		out = out.filter(func(i: Dictionary) -> bool: return str(i.name).to_lower().contains(q) or str(i.get("prompt", "")).to_lower().contains(q))
	match sort:
		"name":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
		"uses":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("uses", 0)) > int(b.get("uses", 0)))
		_:
			if category != "basic":
				out.reverse()
	return out


func _visible_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in inventory:
		if not item.get("deleted", false):
			out.append(item)
	return out


func _active_items() -> int:
	return _visible_items().size()


func current_item() -> Dictionary:
	return get_item(hotbar[selected]) if selected < hotbar.size() else {}


func select(slot: int) -> void:
	if slot >= 0 and slot < HOTBAR_SIZE:
		selected = slot
		hotbar_changed.emit()


func assign_hotbar(slot: int, item_id: String) -> void:
	if slot < 0 or slot >= HOTBAR_SIZE:
		return
	# Один предмет в одном слоте: если он уже где-то стоит, меняем местами.
	var old := hotbar.find(item_id)
	if old >= 0 and item_id != "":
		hotbar[old] = hotbar[slot]
	hotbar[slot] = item_id
	selected = slot
	_mark_inventory()
	hotbar_changed.emit()


func set_paint(color: String) -> void:
	paint = Style.color_name(color)
	_mark_inventory()
	hotbar_changed.emit()
	inventory_changed.emit()


func mark_seen(item_id: String) -> void:
	var item := get_item(item_id)
	if not item.is_empty() and not item.get("basic", false) and not item.get("seen", false):
		item.seen = true
		_mark_inventory()


func toggle_favorite(item_id: String) -> void:
	var item := get_item(item_id)
	if item.is_empty() or item.get("basic", false):
		return
	item.favorite = not item.get("favorite", false)
	_mark_inventory()
	inventory_changed.emit()


func rename_item(item_id: String, name: String) -> void:
	var item := get_item(item_id)
	if item.is_empty() or item.get("basic", false) or name.strip_edges() == "":
		return
	item.name = name.strip_edges().left(64)
	_mark_inventory()
	inventory_changed.emit()


func set_item_category(item_id: String, category: String) -> void:
	var item := get_item(item_id)
	if item.is_empty() or item.get("basic", false) or not category in Catalog.ITEM_CATEGORIES:
		return
	item.category = category
	_mark_inventory()
	inventory_changed.emit()


## Копия предмета: её можно поменять через ИИ, не трогая оригинал.
func duplicate_item(item_id: String) -> Dictionary:
	var item := get_item(item_id)
	if item.is_empty():
		return {}
	var copy := add_item(item.spec.duplicate(true), item.author, item.prompt, Catalog.category_of(item) if not item.get("basic", false) else "")
	if not copy.is_empty():
		rename_item(copy.item_id, "%s (копия)" % item.name)
	return copy


## Удалить в корзину. Поставленные в мир копии остаются.
func delete_item(item_id: String) -> void:
	var item := get_item(item_id)
	if item.is_empty() or item.get("basic", false):
		return
	item.deleted = true
	var slot := hotbar.find(item_id)
	if slot >= 0:
		hotbar[slot] = ""
		hotbar_changed.emit()
	_mark_inventory()
	inventory_changed.emit()


func restore_item(item_id: String) -> void:
	var item := get_item(item_id)
	if item.is_empty():
		return
	item.deleted = false
	_mark_inventory()
	inventory_changed.emit()


func purge_item(item_id: String) -> void:
	var item := get_item(item_id)
	if item.is_empty() or item.get("basic", false):
		return
	inventory.erase(item)
	_mark_inventory()
	inventory_changed.emit()


func empty_trash() -> void:
	inventory = inventory.filter(func(i: Dictionary) -> bool: return not i.get("deleted", false))
	_mark_inventory()
	inventory_changed.emit()


## Сохраняет описание предмета в файл: им можно поделиться.
func export_item(item_id: String) -> String:
	var item := get_item(item_id)
	if item.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute("user://exports")
	var base := str(item.name).validate_filename().replace(" ", "_")
	var path := "user://exports/%s.json" % (base if base != "" else item_id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({"name": item.name, "prompt": item.get("prompt", ""), "spec": item.spec}, "  "))
	return ProjectSettings.globalize_path(path)


# --- Постройки в мире (с отменой) -----------------------------------------

## Ставит объект в мир. pos в метрах (x, z), y и угол поворота вокруг Y.
## Возвращает id объекта или пустую строку.
func place_spec(spec: Dictionary, item_id: String, pos: Vector2, y_offset: float, rotation_y: float, author := "", prompt := "") -> String:
	if _objects.size() >= MAX_OBJECTS:
		notice.emit("В мире уже %d объектов, убери что-нибудь." % MAX_OBJECTS)
		return ""
	var record := {
		"id": "obj_%d" % _next_id,
		"item_id": item_id,
		"spec": spec,
		"x": clampf(pos.x, -_limit(), _limit()),
		"z": clampf(pos.y, -_limit(), _limit()),
		"y_offset": y_offset,
		"rotation_y": rotation_y,
		"author": author,
		"prompt": prompt,
		"created": Time.get_datetime_string_from_system(true),
	}
	_next_id += 1
	_place(record, true)
	_push_undo({"type": "add", "record": record})
	var item := get_item(item_id)
	if not item.is_empty() and not item.get("basic", false):
		item.uses = int(item.get("uses", 0)) + 1
		_mark_inventory()
	_mark_world()
	return record.id


func move_object(id: String, pos: Vector2, y_offset: float, rotation_y: float, undoable := true) -> void:
	if not _objects.has(id):
		return
	var r: Dictionary = _objects[id].record
	var before := {"x": r.x, "z": r.z, "y_offset": r.y_offset, "rotation_y": r.rotation_y}
	var after := {"x": clampf(pos.x, -_limit(), _limit()), "z": clampf(pos.y, -_limit(), _limit()), "y_offset": y_offset, "rotation_y": rotation_y}
	if undoable:
		_push_undo({"type": "move", "id": id, "before": before, "after": after})
	_apply_move(id, after)


func remove_object(id: String, undoable := true) -> void:
	if not _objects.has(id):
		return
	var record: Dictionary = _objects[id].record
	if undoable:
		_push_undo({"type": "remove", "record": record})
	_unplace(id, true)
	_mark_world()


## Подобрать объект: чертёж возвращается в инвентарь, если его там нет.
func pick_up(id: String) -> String:
	if not _objects.has(id):
		return ""
	var record: Dictionary = _objects[id].record
	var item_name := str(record.spec.get("name", "объект"))
	var item := get_item(str(record.get("item_id", "")))
	if item.is_empty() or item.get("deleted", false):
		if not item.is_empty():
			item.deleted = false
		else:
			add_item(record.spec, str(record.get("author", "")), str(record.get("prompt", "")))
		inventory_changed.emit()
	remove_object(id)
	return "Подобрано: %s" % item_name


func object_record(id: String) -> Dictionary:
	return _objects[id].record if _objects.has(id) else {}


func object_node(id: String) -> Node3D:
	return _objects[id].node if _objects.has(id) else null


func object_ids() -> Array:
	return _objects.keys()


## Объект, которому принадлежит узел (после raycast), или пустая строка.
func object_of(node: Node) -> String:
	var n := node
	while n != null and n != world:
		if n.has_meta("agent_object_id"):
			var id := str(n.get_meta("agent_object_id"))
			return id if _objects.has(id) else ""
		n = n.get_parent()
	return ""


## Габариты объекта в мире.
func object_aabb(id: String) -> AABB:
	var node := object_node(id)
	if node == null:
		return AABB()
	return node_aabb(node)


static func node_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D and not n is Light3D and not n is GPUParticles3D and not n is CPUParticles3D:
			var b: AABB = (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		stack.append_array(n.get_children())
	return box


func undo() -> String:
	if _undo.is_empty():
		return "Нечего отменять."
	var op: Dictionary = _undo.pop_back()
	_apply(op, true)
	_redo.append(op)
	return "Отменено: %s" % _describe(op)


func redo() -> String:
	if _redo.is_empty():
		return "Нечего возвращать."
	var op: Dictionary = _redo.pop_back()
	_apply(op, false)
	_undo.append(op)
	return "Возвращено: %s" % _describe(op)


## Несколько действий подряд (например, удалить пять объектов) отменяются разом.
func begin_batch() -> void:
	_undo.append({"type": "batch", "ops": [], "open": true})


func end_batch() -> void:
	if not _undo.is_empty() and _undo[-1].get("open", false):
		_undo[-1].erase("open")
		if _undo[-1].ops.is_empty():
			_undo.pop_back()


func _push_undo(op: Dictionary) -> void:
	_redo.clear()
	if not _undo.is_empty() and _undo[-1].get("open", false):
		_undo[-1].ops.append(op)
		return
	_undo.append(op)
	while _undo.size() > UNDO_STEPS:
		_undo.pop_front()


func _apply(op: Dictionary, reverse: bool) -> void:
	match op.type:
		"batch":
			var ops: Array = op.ops.duplicate()
			if reverse:
				ops.reverse()
			for o in ops:
				_apply(o, reverse)
		"add", "remove":
			var adding: bool = (op.type == "add") != reverse
			if adding:
				_place(op.record, true)
			else:
				_unplace(op.record.id, true)
		"move":
			_apply_move(op.id, op.before if reverse else op.after)
		"spec":
			_set_spec(op.id, op.before if reverse else op.after)
	_mark_world()


func _describe(op: Dictionary) -> String:
	match op.type:
		"batch":
			return "%d действий" % op.ops.size()
		"add":
			return "постановка «%s»" % op.record.spec.get("name", "объект")
		"remove":
			return "удаление «%s»" % op.record.spec.get("name", "объект")
		"move":
			return "перенос"
		"spec":
			return "изменение"
	return "действие"


func _apply_move(id: String, values: Dictionary) -> void:
	if not _objects.has(id):
		return
	var r: Dictionary = _objects[id].record
	for k in values:
		r[k] = values[k]
	var node: Node3D = _objects[id].node
	_objects.erase(id)
	node.queue_free()
	_place(r, false)
	_mark_world()


func _set_spec(id: String, spec: Dictionary) -> void:
	if not _objects.has(id):
		return
	var r: Dictionary = _objects[id].record
	r.spec = spec
	var node: Node3D = _objects[id].node
	_objects.erase(id)
	node.queue_free()
	_place(r, true)
	_mark_world()


func _place(record: Dictionary, animate: bool) -> void:
	var spec: Dictionary = record.spec
	var node := Builder.build(spec)
	var ground: float = world.height_at(record.x, record.z)
	# Подвижные предметы появляются чуть выше и падают сами.
	var lift := 0.3 if node is RigidBody3D else (0.1 if node is CharacterBody3D else 0.0)
	node.position = Vector3(record.x, ground + float(record.y_offset) + lift, record.z)
	node.rotation.y = deg_to_rad(float(record.rotation_y))
	node.set_meta("agent_object_id", record.id)
	world.add_child(node)
	_objects[record.id] = {"record": record, "node": node}
	object_added.emit(node, animate)


func _unplace(id: String, animate: bool) -> void:
	if not _objects.has(id):
		return
	var node: Node3D = _objects[id].node
	_objects.erase(id)
	selection.erase(id)
	if animate:
		object_removing.emit(node)
	node.queue_free()


# --- Площадка, позиции ----------------------------------------------------

## Площадка для ИИ в шипах (углы включительно-исключительно) и высота в пластинах.
func set_area(x0: int, z0: int, x1: int, z1: int, y: int) -> void:
	if x1 - x0 < 1 or z1 - z0 < 1:
		clear_area()
		return
	area = {"x0": x0, "z0": z0, "x1": x1, "z1": z1, "y": y}
	area_changed.emit()


func clear_area() -> void:
	area = {}
	area_changed.emit()


func set_selection(ids: Array) -> void:
	selection.clear()
	for id in ids:
		if _objects.has(id):
			selection.append(id)
	selection_changed.emit()


## Центр площадки в метрах: начало объекта ровно на узле сетки.
func _area_center(a: Dictionary) -> Vector2:
	var cx: int = a.x0 + (a.x1 - a.x0) / 2
	var cz: int = a.z0 + (a.z1 - a.z0) / 2
	return Vector2(cx, cz) * Style.STUD


func _player_pos() -> Array:
	var p: Node3D = world.player
	return [snappedf(p.position.x, 0.01), snappedf(p.position.y, 0.01), snappedf(p.position.z, 0.01)]


func _facing() -> Array:
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, world.player.yaw)
	return [snappedf(fwd.x, 0.01), snappedf(fwd.z, 0.01)]


## Точка перед игроком на заданном расстоянии, по сетке шипов.
func _default_position(distance: float) -> Vector2:
	var p: Node3D = world.player
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, world.player.yaw)
	var d := clampf(distance, 2.0, 60.0)
	return Vector2(snappedf(p.position.x + fwd.x * d, Style.STUD), snappedf(p.position.z + fwd.z * d, Style.STUD))


static func _snap_angle(deg: float) -> float:
	return fposmod(snappedf(deg, 90.0), 360.0)


## F: поставить текущий предмет перед собой.
func place_selected() -> String:
	var item := current_item()
	if item.is_empty():
		return "Слот пустой. Открой инвентарь (Tab) или попроси ИИ (Enter)."
	var spot := _default_position(PLACE_DISTANCE + _footprint(item.spec))
	var id := place_spec(item.spec, item.item_id, spot, 0.0, _snap_angle(rad_to_deg(world.player.yaw)), item.author, item.get("prompt", ""))
	return "Поставлено: %s" % item.name if id != "" else ""


## G: подобрать ближайший объект перед собой.
func pick_up_in_front() -> String:
	var p: Node3D = world.player
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, world.player.yaw)
	var probe := Vector2(p.position.x + fwd.x * 3.0, p.position.z + fwd.z * 3.0)
	var best := ""
	var best_d := 8.0
	for id in _objects:
		var node: Node3D = _objects[id].node
		var d := probe.distance_to(Vector2(node.global_position.x, node.global_position.z))
		if d < best_d:
			best_d = d
			best = id
	if best == "":
		return "Рядом нет объектов, которые можно подобрать."
	return pick_up(best)


## Примерный радиус объекта на земле, в метрах.
func _footprint(spec: Dictionary) -> float:
	var r := 0.0
	var list := Bricks.expand(spec.get("bricks"))
	if not list.is_empty():
		var box := Bricks.bounds(list)
		r = maxf(Vector2(box.position.x, box.position.z).length(), Vector2(box.end.x, box.end.z).length())
	for p in spec.get("parts", []):
		if not p is Dictionary:
			continue
		var pos = p.get("position", [0, 0, 0])
		var center := Vector2(float(pos[0]), float(pos[2])).length() if pos is Array and pos.size() >= 3 else 0.0
		var half := 0.5
		if p.get("size") is Array and (p["size"] as Array).size() >= 3:
			half = maxf(float(p["size"][0]), float(p["size"][2])) * 0.5
		elif p.get("radius") is float or p.get("radius") is int:
			half = float(p["radius"])
		r = maxf(r, center + half)
	return minf(r, 30.0)


func placed_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for id in _objects:
		var node: Node3D = _objects[id].node
		out.append(Vector2(node.global_position.x, node.global_position.z))
	return out


func _limit() -> float:
	return world.SIZE * 0.5 - 1.0


func _summary(record: Dictionary) -> Dictionary:
	var spec: Dictionary = record.spec
	var phys: Dictionary = spec.get("physics") if spec.get("physics") is Dictionary else {}
	return {
		"id": record.id,
		"name": spec.get("name", "object"),
		"author": record.get("author", ""),
		"prompt": record.get("prompt", ""),
		"position": [record.x, world.height_at(record.x, record.z) + float(record.y_offset), record.z],
		"rotation_y": record.rotation_y,
		"bricks": (spec.get("bricks", []) as Array).size(),
		"parts": (spec.get("parts", []) as Array).size(),
		"physics": phys.get("mode", "static"),
	}


# --- Сохранение -----------------------------------------------------------

func _mark_world() -> void:
	_dirty_world = true
	_save_in = 0.5


func _mark_inventory() -> void:
	_dirty_inventory = true
	_save_in = 0.5


## Сохраняет изменения. force: записать, даже если ничего не менялось.
func save_now(force := false) -> void:
	if (_dirty_world or force) and world_id != "":
		var records := []
		for id in _objects:
			records.append(_objects[id].record)
		meta["updated"] = Time.get_datetime_string_from_system(true)
		Worlds.write_json(Worlds.world_path(world_id), {"meta": meta, "next_id": _next_id, "objects": records})
	if _dirty_inventory or force:
		Worlds.write_json(Worlds.INVENTORY_PATH, {
			"items": inventory, "next_item": _next_item, "hotbar": hotbar, "selected": selected,
			"paint": paint, "templates": templates, "history": history,
		})
	_dirty_world = false
	_dirty_inventory = false


func _load() -> void:
	var inv := Worlds.read_json(Worlds.INVENTORY_PATH)
	_next_item = int(inv.get("next_item", 1))
	for item in inv.get("items", []):
		if item is Dictionary and Builder.validate(item.get("spec")) == "" and inventory.size() < MAX_ITEMS + 100:
			var it: Dictionary = item
			if not it.has("category") or str(it.category) == "":
				it["category"] = Catalog.category_of(it)
			inventory.append(it)
	var hb = inv.get("hotbar")
	if hb is Array:
		for i in mini(hb.size(), HOTBAR_SIZE):
			hotbar[i] = str(hb[i])
	else:
		# Старый инвентарь без хотбара: первые предметы встают в слоты,
		# а в пустой игре там базовые детали.
		for i in mini(inventory.size(), HOTBAR_SIZE):
			hotbar[i] = inventory[i].item_id
		if hotbar.count("") == HOTBAR_SIZE:
			hotbar[0] = "basic:brick_2x4"
			hotbar[1] = "basic:plate_2x4"
			hotbar[2] = "basic:brick_2x2"
			hotbar[3] = "basic:slope_2x2"
			hotbar[4] = "basic:tree"
	selected = clampi(int(inv.get("selected", 0)), 0, HOTBAR_SIZE - 1)
	paint = Style.color_name(inv.get("paint", "red"))
	for t in inv.get("templates", []):
		templates.append(str(t))
	for h in inv.get("history", []):
		history.append(str(h))

	if world_id != "":
		var data := Worlds.read_json(Worlds.world_path(world_id))
		meta = data.get("meta", {})
		_next_id = int(data.get("next_id", 1))
		for record in data.get("objects", []):
			if record is Dictionary and Builder.validate(record.get("spec")) == "":
				_place(record, false)
				_next_id = maxi(_next_id, int(str(record.get("id", "obj_0")).trim_prefix("obj_")) + 1)
	inventory_changed.emit()
	hotbar_changed.emit()


func _ok(result) -> Dictionary:
	return {"ok": true, "result": result}


func _err(message: String) -> Dictionary:
	return {"ok": false, "error": message}
