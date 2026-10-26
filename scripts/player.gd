extends CharacterBody3D
## Персонаж с камерой от третьего лица: ходьба, бег, прыжок и плавание.

const WALK := 5.0
const RUN := 9.0
const JUMP := 6.5
const GRAVITY := 18.0
const MOUSE_SENS := 0.003
const SWIM_DEPTH := -0.9

var world
var visual: Node3D
var pivot: Node3D
var arm: SpringArm3D
var yaw := 0.0
var pitch := -0.3
var walk_time := 0.0
var spawn: Vector3


func _ready() -> void:
	spawn = position
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	add_child(col)

	visual = Node3D.new()
	add_child(visual)
	_build_body()

	pivot = Node3D.new()
	pivot.position.y = 1.5
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 6.0
	arm.margin = 0.3
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	arm.shape = probe
	arm.add_excluded_object(get_rid())
	arm.collision_mask = 1 | world.CAMERA_LAYER
	pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 600.0
	arm.add_child(cam)
	cam.current = true


func _build_body() -> void:
	var coat: Material = world.toon(Color(0.36, 0.42, 0.5), 0.025)
	var dark: Material = world.toon(Color(0.25, 0.22, 0.2), 0.025)
	var skin: Material = world.toon(Color(0.95, 0.8, 0.68), 0.025)
	var hat: Material = world.toon(Color(0.5, 0.38, 0.27), 0.025)
	for side in [-0.13, 0.13]:
		world.add_part(visual, world.box(Vector3(0.18, 0.5, 0.2)), dark, Vector3(side, 0.25, 0))
	var body := CapsuleMesh.new()
	body.radius = 0.3
	body.height = 0.9
	world.add_part(visual, body, coat, Vector3(0, 0.9, 0))
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	world.add_part(visual, head, skin, Vector3(0, 1.55, 0))
	world.add_part(visual, world.cylinder(0.45, 0.45, 0.05, 16), hat, Vector3(0, 1.74, 0))
	world.add_part(visual, world.cylinder(0.24, 0.27, 0.3, 16), hat, Vector3(0, 1.9, 0))
	world.add_part(visual, world.box(Vector3(0.45, 0.55, 0.25)), hat, Vector3(0, 1.0, -0.32))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = maxf(arm.spring_length - 0.5, 2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = minf(arm.spring_length + 0.5, 14.0)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.2, 0.6)


func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_key_pressed(a) or Input.is_key_pressed(b) else 0.0


func _physics_process(delta: float) -> void:
	pivot.rotation.y = yaw
	arm.rotation.x = pitch

	var input := Vector2(_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT), _key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var swimming := position.y < SWIM_DEPTH
	var speed := RUN if Input.is_key_pressed(KEY_SHIFT) else WALK
	if swimming:
		speed *= 0.5
	velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)

	if swimming:
		# Плавучесть: держимся у поверхности, прыжком выбираемся на берег.
		velocity.y = lerpf(velocity.y, (SWIM_DEPTH - position.y) * 4.0, 5.0 * delta)
		if Input.is_key_pressed(KEY_SPACE):
			velocity.y = JUMP * 0.7
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = JUMP
	move_and_slide()

	if dir.length() > 0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
		walk_time += delta * speed * 1.8
		visual.position.y = absf(sin(walk_time)) * 0.08 if is_on_floor() else 0.0
	else:
		visual.position.y = 0.0

	if position.y < -30.0:
		position = spawn
		velocity = Vector3.ZERO
