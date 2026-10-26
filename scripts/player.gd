extends CharacterBody3D
## Персонаж в пропорциях референса (большая голова, шляпа, рюкзак) с камерой
## от третьего лица: ходьба, бег, прыжок и плавание. На камере висит финальный
## рисованный фильтр кадра.

const Style := preload("res://scripts/style.gd")
const POST_SHADER := preload("res://shaders/post.gdshader")

const WALK := 4.5
const RUN := 8.0
const JUMP := 6.5
const GRAVITY := 18.0
const MOUSE_SENS := 0.003
const SWIM_DEPTH := -0.9

var world
var visual: Node3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var yaw := 0.0
var pitch := -0.12
var walk_time := 0.0
var spawn: Vector3


func _ready() -> void:
	spawn = position
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	col.shape = cap
	col.position.y = 0.7
	add_child(col)

	visual = Node3D.new()
	visual.rotation.y = PI
	add_child(visual)
	_build_body()

	pivot = Node3D.new()
	pivot.position.y = 1.4
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 5.0
	arm.margin = 0.3
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	arm.shape = probe
	arm.add_excluded_object(get_rid())
	arm.collision_mask = 1 | world.CAMERA_LAYER
	arm.position.x = 0.6
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 1200.0
	arm.add_child(camera)
	camera.current = true
	_add_post_filter()
	_add_motes()


## Полноэкранный квад с рисованным фильтром. Он рисуется последним и
## переводит весь кадр в стиль референса.
func _add_post_filter() -> void:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = POST_SHADER
	mat.render_priority = 127
	var compat := str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "gl_compatibility"
	mat.set_shader_parameter("gl_depth", compat)
	quad.material_override = mat
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position.z = -1.0
	camera.add_child(quad)


## Пылинки и светлячки, медленно парящие вокруг игрока.
func _add_motes() -> void:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.local_coords = false
	p.mesh = Style.sphere(0.035, 6, 4)
	p.material_override = Style.glow(Color(1, 0.97, 0.88), 2.5)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14, 3, 14)
	p.position.y = 2.0
	p.gravity = Vector3(0, 0.02, 0)
	p.direction = Vector3(1, 0.3, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	add_child(p)


func _build_body() -> void:
	var P := Style.PALETTE
	var coat := Style.toon(Color(0.42, 0.4, 0.37), 0.025)
	var dark := Style.toon(Color(0.2, 0.19, 0.18), 0.025)
	var skin := Style.toon(Color(0.9, 0.86, 0.8), 0.025)
	var hat := Style.toon(Color(0.5, 0.47, 0.42), 0.025)
	var pack := Style.toon(Color(0.33, 0.3, 0.27), 0.025)

	for side: float in [-0.12, 0.12]:
		var leg := Node3D.new()
		leg.position = Vector3(side, 0.45, 0)
		visual.add_child(leg)
		Style.add_part(leg, Style.box(Vector3(0.16, 0.3, 0.18)), coat, Vector3(0, -0.15, 0))
		Style.add_part(leg, Style.box(Vector3(0.2, 0.18, 0.28)), dark, Vector3(0, -0.36, 0.04))
		legs.append(leg)
	# Короткое тело в куртке и шарф.
	var body := CapsuleMesh.new()
	body.radius = 0.27
	body.height = 0.72
	Style.add_part(visual, body, coat, Vector3(0, 0.78, 0))
	Style.add_part(visual, Style.cylinder(0.24, 0.29, 0.12, 12), Style.toon(P.cloth, 0.02), Vector3(0, 1.08, 0))
	for side: float in [-1.0, 1.0]:
		var a := Node3D.new()
		a.position = Vector3(side * 0.3, 1.0, 0)
		visual.add_child(a)
		var sleeve := CapsuleMesh.new()
		sleeve.radius = 0.08
		sleeve.height = 0.48
		Style.add_part(a, sleeve, coat, Vector3(side * 0.04, -0.2, 0), Vector3(0, 0, side * 0.2))
		Style.add_part(a, Style.sphere(0.07, 8, 5), skin, Vector3(side * 0.08, -0.45, 0))
		arms.append(a)
	# Большая голова и глаза-бусинки.
	Style.add_part(visual, Style.sphere(0.34, 16, 10), skin, Vector3(0, 1.42, 0))
	for side: float in [-0.11, 0.11]:
		Style.add_part(visual, Style.sphere(0.045, 8, 5), dark, Vector3(side, 1.42, 0.31), Vector3.ZERO, Vector3(1, 1.4, 0.6))
	# Шляпа-панама с широкими полями.
	Style.add_part(visual, Style.cylinder(0.56, 0.6, 0.06, 18), hat, Vector3(0, 1.66, 0), Vector3(0.12, 0, 0))
	Style.add_part(visual, Style.cylinder(0.3, 0.36, 0.3, 16), hat, Vector3(0, 1.82, -0.02))
	Style.add_part(visual, Style.cylinder(0.365, 0.365, 0.07, 16), dark, Vector3(0, 1.71, -0.02))
	# Рюкзак со свёрнутым одеялом.
	Style.add_part(visual, Style.box(Vector3(0.46, 0.5, 0.26)), pack, Vector3(0, 0.88, -0.32))
	Style.add_part(visual, Style.box(Vector3(0.36, 0.2, 0.06)), dark, Vector3(0, 0.75, -0.46))
	Style.add_part(visual, Style.cylinder(0.1, 0.1, 0.56, 10), Style.toon(P.cloth, 0.02), Vector3(0, 1.18, -0.32), Vector3(0, 0, PI * 0.5))


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

	# Походка: качаем руки и ноги, слегка подпрыгиваем.
	var moving := dir.length() > 0.1
	if moving:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
		walk_time += delta * speed * 2.0
	else:
		walk_time = lerpf(walk_time, roundf(walk_time / PI) * PI, 8.0 * delta)
	var swing := sin(walk_time) * (0.7 if moving else 0.0)
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		legs[i].rotation.x = swing * s
		arms[i].rotation.x = -swing * s * 0.8
	visual.position.y = absf(sin(walk_time)) * 0.07 if moving and is_on_floor() else 0.0

	if position.y < -30.0:
		position = spawn
		velocity = Vector3.ZERO
