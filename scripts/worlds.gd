extends RefCounted
## Миры игрока, общий инвентарь и настройки на диске.
##
## user://worlds/<id>/world.json   постройки мира и его описание
## user://worlds/<id>/physics.json физика мира от ИИ
## user://worlds/<id>/thumb.png    картинка для списка миров
## user://inventory.json           инвентарь, хотбар, шаблоны и история просьб (общие для всех миров)
## user://settings.json            внешность фигурки, мышь, звук, графика
##
## У мира ровно один создатель (owner). Приглашать других игроков без права
## строить можно будет во втором релизе: поле owner уже есть.

const ROOT := "user://worlds"
const INVENTORY_PATH := "user://inventory.json"
const SETTINGS_PATH := "user://settings.json"
## Сохранение из первой версии игры: оно становится первым миром.
const LEGACY_PATH := "user://world.json"
const LEGACY_PHYSICS := "user://world_physics.json"
const SIZES := [128, 256, 512, 1024]
const PLATE_COLORS := ["green", "tan", "light_gray", "white", "dark_green", "blue"]
const BACKUPS := 3

## Мир, который открыт сейчас (или пусто, тогда показывается список миров).
static var current := ""

const DEFAULT_SETTINGS := {
	"look": {},
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"volume": 0.8,
	"shadows": true,
	"stud_detail": true,
	"tutorial_done": false,
	"last_world": "",
	"player_name": "",
}


static func dir_of(id: String) -> String:
	return "%s/%s" % [ROOT, id]


static func world_path(id: String) -> String:
	return dir_of(id) + "/world.json"


static func physics_path(id: String) -> String:
	return dir_of(id) + "/physics.json"


static func thumb_path(id: String) -> String:
	return dir_of(id) + "/thumb.png"


## Список миров, новые сверху: [{"id", "name", "studs", "plate_color", "updated", "objects"}].
static func list() -> Array[Dictionary]:
	migrate_legacy()
	var out: Array[Dictionary] = []
	var d := DirAccess.open(ROOT)
	if d == null:
		return out
	for id in d.get_directories():
		var data := read_json(world_path(id))
		if data.is_empty():
			continue
		var meta: Dictionary = data.get("meta", {})
		out.append({
			"id": id,
			"name": str(meta.get("name", id)),
			"studs": int(meta.get("studs", 256)),
			"plate_color": str(meta.get("plate_color", "green")),
			"updated": str(meta.get("updated", "")),
			"objects": (data.get("objects", []) as Array).size(),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.updated > b.updated)
	return out


static func create(name: String, studs: int, plate_color: String) -> String:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var base := name.strip_edges().to_lower().validate_filename().replace(" ", "_").left(24)
	if base == "":
		base = "world"
	var id := base
	var n := 2
	while DirAccess.dir_exists_absolute(dir_of(id)):
		id = "%s_%d" % [base, n]
		n += 1
	DirAccess.make_dir_recursive_absolute(dir_of(id))
	var now := Time.get_datetime_string_from_system(true)
	write_json(world_path(id), {
		"meta": {"name": name.strip_edges() if name.strip_edges() != "" else "Мой мир", "studs": studs if studs in SIZES else 256,
			"plate_color": plate_color if plate_color in PLATE_COLORS else "green", "created": now, "updated": now,
			"owner": str(load_settings().get("player_name", ""))},
		"next_id": 1,
		"objects": [],
	})
	return id


static func meta(id: String) -> Dictionary:
	var data := read_json(world_path(id))
	var m: Dictionary = data.get("meta", {})
	m["id"] = id
	return m


static func rename(id: String, name: String) -> void:
	var data := read_json(world_path(id))
	if data.is_empty() or name.strip_edges() == "":
		return
	data.meta["name"] = name.strip_edges()
	write_json(world_path(id), data)


## Удаляет мир с диска вместе с резервными копиями.
static func remove(id: String) -> void:
	var dir := dir_of(id)
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)


## Перед открытием мира кладёт копию его файла в world.json.1 .. .3.
static func backup(id: String) -> void:
	var path := world_path(id)
	if not FileAccess.file_exists(path):
		return
	for i in range(BACKUPS - 1, 0, -1):
		var src := "%s.%d" % [path, i]
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(src, "%s.%d" % [path, i + 1])
	DirAccess.copy_absolute(path, path + ".1")


## Первая версия хранила один мир и инвентарь в user://world.json.
## Он становится миром «Мой первый мир», а инвентарь переезжает в общий.
static func migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	var data := read_json(LEGACY_PATH)
	var id := create("Мой первый мир", 256, "green")
	var w := read_json(world_path(id))
	w["next_id"] = int(data.get("next_id", 1))
	w["objects"] = data.get("objects", [])
	write_json(world_path(id), w)
	if FileAccess.file_exists(LEGACY_PHYSICS):
		DirAccess.copy_absolute(LEGACY_PHYSICS, physics_path(id))
		DirAccess.rename_absolute(LEGACY_PHYSICS, LEGACY_PHYSICS + ".old")
	if not FileAccess.file_exists(INVENTORY_PATH):
		write_json(INVENTORY_PATH, {"items": data.get("inventory", []), "next_item": int(data.get("next_item", 1))})
	DirAccess.rename_absolute(LEGACY_PATH, LEGACY_PATH + ".old")


static func load_settings() -> Dictionary:
	var s := DEFAULT_SETTINGS.duplicate(true)
	s.merge(read_json(SETTINGS_PATH), true)
	return s


static func save_settings(s: Dictionary) -> void:
	write_json(SETTINGS_PATH, s)


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Пишет через временный файл, чтобы сбой посреди записи не испортил сохранение.
static func write_json(path: String, data: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, path)
