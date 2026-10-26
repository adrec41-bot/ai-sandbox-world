extends CharacterBody3D
## Персонаж в пропорциях референса (большая голова, шляпа, рюкзак) с камерой
## от третьего лица: ходьба, бег, прыжок и плавание. На камере висит финальный
## рисованный фильтр кадра.
##
## Механики от ИИ: E садится в транспорт и выходит из него, надевает и снимает
## снаряжение, включает предметы. Физика мира (гравитация, скорость, прыжок)
## и способности снаряжения меняют движение персонажа.

const Style := preload("res://scripts/style.gd")
const POST_SHADER := preload("res://shaders/post.gdshader")
const WorldPhysics := preload("res://scripts/mechanics/world_physics.gd")
const PropScript := preload("res://scripts/mechanics/prop.gd")

const WALK := 4.5
const RUN := 8.0
const JUMP := 6.5
const GRAVITY := 18.0
const MOUSE_SENS := 0.003
const SWIM_DEPTH := -0.9
## С какого расстояния E достаёт до транспорта и предметов.
const INTERACT_RANGE := 4.5

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
## Пока открыта панель ИИ, клавиши не двигают персонажа.
var frozen := false
## Транспорт, на котором едет игрок, и надетое снаряжение.
var riding: Node3D = null
var worn: Node3D = null
var abilities := {}
var _col: CollisionShape3D
var _air_jumps := 0
var _jump_held := false
var _flying := false
## Толчок от батута или ускорителя, затухает постепенно.
var _push := Vector3.ZERO
var _touch_cooldown := 0.0
var _hint: Label


func _ready() -> void:
	spawn = position
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	col.shape = cap
	col.position.y = 0.7
	add_child(col)
	_col = col

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
	_add_hint()


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
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and not frozen:
		interact()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.2, 0.6)


func _key(a: Key, b: Key) -> float:
	if frozen:
		return 0.0
	return 1.0 if Input.is_key_pressed(a) or Input.is_key_pressed(b) else 0.0


func _physics_process(delta: float) -> void:
	pivot.rotation.y = yaw
	arm.rotation.x = pitch
	_touch_cooldown -= delta
	# Транспорт или снаряжение могли убрать из мира (G или агент).
	if riding != null and not is_instance_valid(riding):
		riding = null
		_set_seated(false)
	if worn != null and not is_instance_valid(worn):
		worn = null
		abilities = {}
	_update_hint()
	if riding != null:
		_ride(delta)
		return

	var input := Vector2(_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT), _key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var swimming := position.y < SWIM_DEPTH
	var shift := _key(KEY_SHIFT, KEY_SHIFT) > 0.0
	var space := _key(KEY_SPACE, KEY_SPACE) > 0.0
	var jump_pressed := space and not _jump_held
	_jump_held = space
	var gravity := GRAVITY * WorldPhysics.gravity * float(abilities.get("gravity", 1.0))
	# Множитель задаёт высоту прыжка, а высота растёт как квадрат скорости.
	var jump := JUMP * sqrt(WorldPhysics.jump * float(abilities.get("jump", 1.0)))
	var fly := float(abilities.get("fly", 0.0))
	var speed := (RUN if shift else WALK) * WorldPhysics.player_speed * float(abilities.get("speed", 1.0))
	if fly > 0.0 and space:
		_flying = true
	if _flying and (fly <= 0.0 or (is_on_floor() and not space)):
		_flying = false
	if _flying:
		speed = maxf(speed, fly)
	if swimming:
		speed *= 0.5
	velocity.x = move_toward(velocity.x, dir.x * speed + _push.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed + _push.z, 40.0 * delta)
	_push = _push.move_toward(Vector3.ZERO, 12.0 * delta)
	if is_on_floor():
		_air_jumps = int(abilities.get("extra_jumps", 0))

	if swimming:
		# Плавучесть: держимся у поверхности, прыжком выбираемся на берег.
		velocity.y = lerpf(velocity.y, (SWIM_DEPTH - position.y) * 4.0, 5.0 * delta)
		if space:
			velocity.y = jump * 0.7
	elif _flying:
		# Полёт со снаряжением: Пробел вверх, Shift вниз, иначе висим.
		var up := (1.0 if space else 0.0) - (1.0 if shift else 0.0)
		velocity.y = move_toward(velocity.y, up * fly, 30.0 * delta)
	elif not is_on_floor():
		velocity.y -= gravity * delta
		if jump_pressed and _air_jumps > 0:
			velocity.y = jump
			_air_jumps -= 1
		elif space and float(abilities.get("glide", 0.0)) > 0.0:
			# Планирование: падаем не быстрее заданной скорости.
			velocity.y = maxf(velocity.y, -float(abilities.glide))
	elif space:
		velocity.y = jump
	move_and_slide()
	_touch()

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


# --- Механики: транспорт, снаряжение, предметы ----------------------------

## E: выйти из транспорта, сесть, надеть, включить или снять снаряжение.
func interact() -> void:
	if riding != null:
		leave_vehicle()
		return
	var target := _nearest_interactable()
	if target != null:
		target.interact(self)
	elif worn != null:
		unequip()


func _nearest_interactable() -> Node:
	var best: Node = null
	var best_d := INTERACT_RANGE
	for n in get_tree().get_nodes_in_group("interactable"):
		var body: Node3D = n if n is Node3D else n.get_parent()
		if body == worn or body == riding or (n.get("driver") != null):
			continue
		var d := Vector2(body.global_position.x - global_position.x, body.global_position.z - global_position.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


## Транспорт сажает игрока (зовёт vehicle.interact).
func board(vehicle: Node3D) -> void:
	riding = vehicle
	velocity = Vector3.ZERO
	_flying = false
	_set_seated(true)
	arm.add_excluded_object(vehicle.get_rid())


func leave_vehicle() -> void:
	var v := riding
	riding = null
	_set_seated(false)
	if not is_instance_valid(v):
		return
	v.leave()
	arm.remove_excluded_object(v.get_rid())
	# Выходим сбоку от транспорта.
	var side := v.global_transform.basis.x.normalized()
	side.y = 0.0
	global_position = Vector3(v.global_position.x, maxf(v.global_position.y, 0.0) + 0.3, v.global_position.z) - side * (v.half_width + 0.8)


func _set_seated(seated: bool) -> void:
	_col.disabled = seated
	for i in 2:
		legs[i].rotation.x = -1.4 if seated else 0.0
		arms[i].rotation.x = -0.9 if seated else 0.0
	visual.position.y = 0.0


func _ride(delta: float) -> void:
	var seat: Transform3D = riding.seat_transform()
	# Начало координат персонажа у ног, а сидит он бёдрами.
	global_position = seat.origin - seat.basis.y.normalized() * 0.45
	visual.rotation.y = riding.yaw + PI
	# Камера сама разворачивается за транспортом, пока он едет.
	if absf(riding.speed) > 1.0:
		yaw = lerp_angle(yaw, riding.yaw, 1.5 * delta)
	velocity = Vector3.ZERO


## Снаряжение надевается через equipment.interact.
func equip(obj: Node3D) -> void:
	if worn != null:
		unequip()
	var eq := obj.get_node_or_null("Equipment")
	if eq == null:
		return
	worn = obj
	_set_object_physics(obj, false)
	obj.reparent(visual, false)
	obj.transform = eq.attach_transform()
	abilities = eq.abilities
	_air_jumps = int(abilities.get("extra_jumps", 0))
	_set_active(obj, true)


## Снимает снаряжение и кладёт его на землю перед собой.
func unequip() -> void:
	var obj := worn
	worn = null
	abilities = {}
	_flying = false
	if not is_instance_valid(obj):
		return
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	obj.reparent(world, false)
	obj.global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + fwd * 1.5)
	_set_object_physics(obj, true)
	_set_active(obj, false)


## Анимации снаряжения с "by": "active" работают, пока оно надето.
func _set_active(obj: Node3D, on: bool) -> void:
	var animator = obj.get_node_or_null("Animator")
	if animator:
		animator.inputs["active"] = 1.0 if on else 0.0


func _set_object_physics(obj: Node3D, on: bool) -> void:
	if obj is RigidBody3D:
		obj.freeze = not on
	for c in obj.get_children():
		if c is CollisionShape3D:
			c.disabled = not on


## Батуты, ускорители и катапульты толкают игрока при касании.
func _touch() -> void:
	if _touch_cooldown > 0.0:
		return
	for i in get_slide_collision_count():
		var body = get_slide_collision(i).get_collider()
		if body is Node3D and body.has_meta("on_touch"):
			var v := PropScript.touch_velocity(body, body.get_meta("on_touch"))
			if v == Vector3.ZERO:
				continue
			if v.y > 0.0:
				velocity.y = v.y
			_push = Vector3(v.x, 0, v.z)
			velocity.x += v.x
			velocity.z += v.z
			_touch_cooldown = 0.3
			return


func _add_hint() -> void:
	var layer := CanvasLayer.new()
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_left = -360
	_hint.offset_right = 360
	_hint.offset_top = 70
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	_hint.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.06))
	_hint.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hint)
	add_child(layer)


## Подсказка вверху экрана: что сделает E и как управлять.
func _update_hint() -> void:
	var text := ""
	if riding != null:
		text = riding.hint()
	else:
		var target := _nearest_interactable()
		if target != null and target.has_method("prompt"):
			text = target.prompt()
		elif worn != null:
			var eq := worn.get_node_or_null("Equipment")
			var how: String = eq.hint if eq != null and eq.hint != "" else _ability_hint()
			text = "%s · E — снять" % how
	_hint.text = text


func _ability_hint() -> String:
	var parts: Array[String] = []
	if float(abilities.get("fly", 0.0)) > 0.0:
		parts.append("Пробел взлететь, Shift вниз")
	if float(abilities.get("glide", 0.0)) > 0.0:
		parts.append("держи Пробел в воздухе, чтобы планировать")
	if int(abilities.get("extra_jumps", 0)) > 0:
		parts.append("Пробел в воздухе ещё раз прыгнуть")
	return ", ".join(parts) if not parts.is_empty() else "Снаряжение надето"
