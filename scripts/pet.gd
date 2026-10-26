extends Node3D
## Питомец-спутник, как на референсах: белый ушастый зверёк, который
## вприпрыжку бегает за игроком и садится рядом, когда тот стоит.

const Style := preload("res://scripts/style.gd")

var world
var target
var hop := 0.0
var body: Node3D


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var fur := Style.toon(Color(0.93, 0.92, 0.88), 0.02)
	var dark := Style.toon(Color(0.2, 0.19, 0.18), 0.0)
	Style.add_part(body, Style.sphere(0.24, 12, 8), fur, Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1, 1.05, 1.15))
	Style.add_part(body, Style.sphere(0.19, 12, 8), fur, Vector3(0, 0.5, 0.12))
	for side: float in [-1.0, 1.0]:
		var ear := CapsuleMesh.new()
		ear.radius = 0.05
		ear.height = 0.3
		Style.add_part(body, ear, fur, Vector3(side * 0.08, 0.72, 0.08), Vector3(-0.2, 0, side * 0.25))
		Style.add_part(body, Style.sphere(0.03, 6, 4), dark, Vector3(side * 0.07, 0.53, 0.29))
	Style.add_part(body, Style.sphere(0.08, 8, 5), fur, Vector3(0, 0.22, -0.27))
	# Пятнышко на боку.
	Style.add_part(body, Style.sphere(0.09, 8, 5), Style.toon(Color(0.55, 0.53, 0.5), 0.0), Vector3(0.2, 0.3, -0.05), Vector3.ZERO, Vector3(0.5, 1, 1))


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
	body.position.y = absf(sin(hop)) * 0.25
