extends RefCounted
## Механики объектов от ИИ-агентов: на чём можно ездить и летать, что можно
## надеть, что крутится, пружинит или открывается. Агент описывает механику
## данными в поле spec.mechanics, а код игры её исполняет. Чужой код агента
## игра не запускает: в общем мире на 5–10 игроков это было бы опасно, поэтому
## механика собирается из готовых управляемых блоков с понятными настройками.
##
## Формат (подробно в ai/mechanics_guide.md):
## "mechanics": {
##   "type": "vehicle" | "equipment" | "prop",
##   "movement": "ground" | "air" | "hover",        // vehicle
##   "max_speed": 12, "acceleration": 6, ...         // vehicle
##   "abilities": {"fly": 8, "extra_jumps": 1, ...}, // equipment
##   "on_touch": {"bounce": 14},                     // prop
##   "animations": [{"part": "wheel", "motion": "spin", "axis": "x", "amount": 720, "by": "speed"}]
## }
## У всех объектов «вперёд» это -Z, как в Godot.

const VehicleScript := preload("res://scripts/mechanics/vehicle.gd")
const AnimatorScript := preload("res://scripts/mechanics/animator.gd")
const EquipmentScript := preload("res://scripts/mechanics/equipment.gd")
const PropScript := preload("res://scripts/mechanics/prop.gd")

const TYPES := ["vehicle", "equipment", "prop"]
const MOVEMENTS := ["ground", "air", "hover"]
const MOTIONS := ["spin", "swing", "bob", "angle"]
const DRIVERS := ["always", "speed", "throttle", "steer", "climb", "active"]
const AXES := ["x", "y", "z"]
const ATTACH := ["back", "head", "hand", "feet", "body"]
const MAX_ANIMATIONS := 24

## Настройки транспорта: значение по умолчанию для каждого вида движения и пределы.
## [ground, air, hover, min, max]
const VEHICLE_PARAMS := {
	"max_speed": [10.0, 40.0, 12.0, 0.5, 120.0],
	"acceleration": [6.0, 8.0, 10.0, 0.5, 80.0],
	"brake": [12.0, 6.0, 12.0, 0.5, 120.0],
	"turn_speed": [90.0, 50.0, 100.0, 5.0, 360.0],
	"reverse_speed": [3.0, 0.0, 6.0, 0.0, 60.0],
	"lean": [0.0, 45.0, 10.0, 0.0, 60.0],
	"tilt": [0.0, 0.0, 12.0, 0.0, 45.0],
	"jump": [0.0, 0.0, 0.0, 0.0, 30.0],
	"gravity_scale": [1.0, 1.0, 0.0, 0.0, 5.0],
	"takeoff_speed": [0.0, 18.0, 0.0, 1.0, 100.0],
	"pitch_speed": [0.0, 45.0, 0.0, 5.0, 180.0],
	"climb_speed": [0.0, 0.0, 6.0, 0.0, 60.0],
}

const ABILITIES := {
	"speed": [1.0, 0.2, 5.0],
	"jump": [1.0, 0.2, 5.0],
	"extra_jumps": [0, 0, 5],
	"glide": [0.0, 0.0, 10.0],
	"fly": [0.0, 0.0, 40.0],
	"gravity": [1.0, 0.0, 3.0],
}


## Проверяет spec.mechanics. Возвращает текст ошибки или пустую строку.
static func validate(mech) -> String:
	if mech == null:
		return ""
	if not mech is Dictionary:
		return "mechanics must be an object"
	var type := str(mech.get("type", ""))
	if not type in TYPES:
		return "mechanics.type must be one of %s" % ", ".join(TYPES)
	if type == "vehicle" and mech.has("movement") and not str(mech.movement) in MOVEMENTS:
		return "mechanics.movement must be one of %s" % ", ".join(MOVEMENTS)
	if type == "equipment" and mech.has("attach") and not str(mech.attach) in ATTACH:
		return "mechanics.attach must be one of %s" % ", ".join(ATTACH)
	var anims = mech.get("animations", [])
	if not anims is Array:
		return "mechanics.animations must be an array"
	if anims.size() > MAX_ANIMATIONS:
		return "too many animations (max %d)" % MAX_ANIMATIONS
	for i in anims.size():
		var a = anims[i]
		if not a is Dictionary or str(a.get("part", "")) == "":
			return "mechanics.animations[%d] needs a part id" % i
		if not str(a.get("motion", "spin")) in MOTIONS:
			return "mechanics.animations[%d].motion must be one of %s" % [i, ", ".join(MOTIONS)]
		if not str(a.get("by", "always")) in DRIVERS:
			return "mechanics.animations[%d].by must be one of %s" % [i, ", ".join(DRIVERS)]
		if not str(a.get("axis", "x")) in AXES:
			return "mechanics.animations[%d].axis must be x, y or z" % i
	return ""


## Корень объекта для механики, которой нужен свой вид тела, или null.
static func make_root(spec: Dictionary) -> Node3D:
	var mech = spec.get("mechanics")
	if mech is Dictionary and str(mech.get("type", "")) == "vehicle":
		var v: CharacterBody3D = VehicleScript.new()
		v.mech = vehicle_params(mech)
		return v
	return null


## Подключает механику к собранному объекту: анимации, снаряжение, касания.
static func setup(root: Node3D, spec: Dictionary) -> void:
	var mech = spec.get("mechanics")
	if not mech is Dictionary:
		return
	root.set_meta("mechanics", mech)
	var anims: Array = mech.get("animations") if mech.get("animations") is Array else []
	if not anims.is_empty():
		var animator: Node = AnimatorScript.new()
		animator.name = "Animator"
		animator.animations = anims.slice(0, MAX_ANIMATIONS)
		root.add_child(animator)
	match str(mech.get("type", "")):
		"equipment":
			var eq: Node = EquipmentScript.new()
			eq.name = "Equipment"
			eq.attach = str(mech.get("attach", "back"))
			eq.offset = _vec(mech.get("offset"), Vector3.ZERO).clamp(-Vector3.ONE * 3.0, Vector3.ONE * 3.0)
			eq.abilities = abilities(mech.get("abilities"))
			eq.hint = str(mech.get("controls_hint", "")).left(200)
			root.add_child(eq)
		"prop":
			var prop: Node = PropScript.new()
			prop.name = "Prop"
			prop.toggle = str(mech.get("interact", "none")) == "toggle"
			prop.on_touch = mech.get("on_touch") if mech.get("on_touch") is Dictionary else {}
			root.add_child(prop)


## Настройки транспорта с подставленными значениями по умолчанию и пределами.
static func vehicle_params(mech: Dictionary) -> Dictionary:
	var movement := str(mech.get("movement", "ground"))
	if not movement in MOVEMENTS:
		movement = "ground"
	var col := MOVEMENTS.find(movement)
	var out := {"movement": movement}
	for key in VEHICLE_PARAMS:
		var d: Array = VEHICLE_PARAMS[key]
		out[key] = clampf(_num(mech.get(key), d[col]), d[3], d[4])
	if movement == "air":
		out.takeoff_speed = minf(out.takeoff_speed, out.max_speed * 0.8)
	out["seat"] = mech.get("seat")
	out["hint"] = str(mech.get("controls_hint", "")).left(200)
	return out


static func abilities(value) -> Dictionary:
	var src: Dictionary = value if value is Dictionary else {}
	var out := {}
	for key in ABILITIES:
		var d: Array = ABILITIES[key]
		out[key] = clampf(_num(src.get(key), d[0]), d[1], d[2])
	out.extra_jumps = int(out.extra_jumps)
	return out


static func _num(v, fallback: float) -> float:
	return float(v) if (v is float or v is int) else fallback


static func _vec(v, fallback: Vector3) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(_num(v[0], 0.0), _num(v[1], 0.0), _num(v[2], 0.0))
	return fallback
