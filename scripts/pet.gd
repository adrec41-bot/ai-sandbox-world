extends Node3D
## Питомец-спутник: кирпичная собака, которая вприпрыжку бегает за игроком
## и садится рядом, когда тот стоит.

const Style := preload("res://scripts/style.gd")
const Bricks := preload("res://scripts/bricks.gd")

var world
var target
var hop := 0.0
var body: Node3D
var _tail: Node3D


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	# Собака из кирпичей: туловище, голова, уши и лапы, вперёд это +Z.
	var dog := Node3D.new()
	dog.scale = Vector3.ONE * 0.62
	dog.position = Vector3(-0.25, 0, -0.5)
	body.add_child(dog)
	Bricks.build(dog, Bricks.expand([
		{"type": "brick", "at": [0, 0, 0], "size": [1, 1], "color": "white", "h": 2},
		{"type": "brick", "at": [1, 0, 0], "size": [1, 1], "color": "white", "h": 2},
		{"type": "brick", "at": [0, 0, 2], "size": [1, 1], "color": "white", "h": 2},
		{"type": "brick", "at": [1, 0, 2], "size": [1, 1], "color": "white", "h": 2},
		{"type": "brick", "at": [0, 2, 0], "size": [2, 3], "color": "white", "studs": false},
		{"type": "brick", "at": [0, 4, 2], "size": [2, 2], "color": "white", "studs": false},
		{"type": "slope", "at": [0, 4, 4], "size": [2, 1], "color": "white", "h": 2, "dir": "+z"},
		{"type": "plate", "at": [0, 7, 2], "size": [1, 1], "color": "dark_brown"},
		{"type": "plate", "at": [1, 7, 2], "size": [1, 1], "color": "dark_brown"},
	]))
	# Пятно на спине и хвост.
	Style.add_part(dog, Style.box(Vector3(0.4, 0.03, 0.4)), Style.part_material("dark_brown"), Vector3(0.4, 0.8, 0.45))
	_tail = Node3D.new()
	_tail.position = Vector3(0.4, 0.7, 0.0)
	dog.add_child(_tail)
	Style.add_part(_tail, Style.cylinder(0.05, 0.06, 0.35, 10), Style.part_material("white"), Vector3(0, 0.12, -0.08), Vector3(-0.7, 0, 0))
	for side: float in [0.15, 0.65]:
		Style.add_part(dog, Style.box(Vector3(0.1, 0.1, 0.03)), Style.part_material("black"), Vector3(side, 0.98, 1.61))
	var nose := Style.add_part(dog, Style.box(Vector3(0.1, 0.08, 0.04)), Style.part_material("black"), Vector3(0.4, 0.78, 2.03))
	nose.name = "Nose"


func _physics_process(delta: float) -> void:
	if not target:
		return
	var goal: Vector3 = target.global_position + target.visual.global_basis * Vector3(1.0, 0, -0.6)
	var to := Vector3(goal.x - position.x, 0, goal.z - position.z)
	var dist := to.length()
	if dist > 0.4:
		var speed := clampf(dist * 2.0, 0.0, 9.0)
		position += to.normalized() * minf(speed * delta, dist)
		body.rotation.y = lerp_angle(body.rotation.y, atan2(to.x, to.z), 8.0 * delta)
		hop += delta * 12.0
	else:
		hop = lerpf(hop, roundf(hop / PI) * PI, 6.0 * delta)
	if dist > 25.0:
		position = goal
	position.y = world.height_at(position.x, position.z)
	if position.y < world.WATER_LEVEL:
		position.y = world.WATER_LEVEL - 0.2
	body.position.y = absf(sin(hop)) * 0.18
	if _tail:
		_tail.rotation.z = sin(Time.get_ticks_msec() * 0.012) * 0.5
