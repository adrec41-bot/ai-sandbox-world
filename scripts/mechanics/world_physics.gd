extends Node
## Физика всего мира, которую игроки задают через своих ИИ-агентов:
## гравитация, скорость и прыжок персонажей, замедление времени.
## Значения статические, поэтому их читают игрок, транспорт и снаряжение
## без ссылок друг на друга. Сохраняются между запусками.

const SAVE_PATH := "user://world_physics.json"
## Обычная гравитация для тел физики, м/с².
const EARTH := 9.8

## {ключ: [по умолчанию, минимум, максимум, описание для агента]}
const PARAMS := {
	"gravity": [1.0, 0.0, 5.0, "gravity multiplier: 1 normal, 0.16 moon, 0 weightless"],
	"player_speed": [1.0, 0.2, 5.0, "walking and running speed multiplier"],
	"jump": [1.0, 0.2, 5.0, "jump height multiplier"],
	"time_scale": [1.0, 0.1, 3.0, "game speed: 0.3 slow motion, 2 fast"],
}

static var gravity := 1.0
static var player_speed := 1.0
static var jump := 1.0
static var time_scale := 1.0

var world: Node3D


func _ready() -> void:
	_load()
	_apply()


## Меняет переданные параметры. Возвращает все текущие значения.
func set_values(args: Dictionary) -> Dictionary:
	if args.get("reset") == true:
		for key in PARAMS:
			_assign(key, PARAMS[key][0])
	for key in PARAMS:
		var v = args.get(key)
		if v is float or v is int:
			_assign(key, clampf(float(v), PARAMS[key][1], PARAMS[key][2]))
	_apply()
	_save()
	return values()


static func values() -> Dictionary:
	return {"gravity": gravity, "player_speed": player_speed, "jump": jump, "time_scale": time_scale}


static func describe() -> Dictionary:
	var out := {}
	for key in PARAMS:
		out[key] = "%s (%s..%s)" % [PARAMS[key][3], PARAMS[key][1], PARAMS[key][2]]
	return out


func _assign(key: String, value: float) -> void:
	match key:
		"gravity":
			gravity = value
		"player_speed":
			player_speed = value
		"jump":
			jump = value
		"time_scale":
			time_scale = value


func _apply() -> void:
	# Ящики, бочки и прочие подвижные предметы падают с новой гравитацией.
	PhysicsServer3D.area_set_param(world.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, EARTH * gravity)
	Engine.time_scale = time_scale


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(values()))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		for key in PARAMS:
			var v = data.get(key)
			if v is float or v is int:
				_assign(key, clampf(float(v), PARAMS[key][1], PARAMS[key][2]))
