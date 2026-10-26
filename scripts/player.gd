extends CharacterBody3D
## Миньфигурка Lego с камерой от третьего лица: ходьба, бег, прыжок и
## плавание. Ноги машут целиком, как у настоящей фигурки.
##
## Механики от ИИ: E садится в транспорт и выходит из него, надевает и снимает
## снаряжение, включает предметы. Физика мира (гравитация, скорость, прыжок)
## и способности снаряжения меняют движение персонажа.

const Style := preload("res://scripts/style.gd")
const Minifig := preload("res://scripts/minifig.gd")
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
var head: Node3D
## Внешность фигурки, см. minifig.gd.
var look := {}
var walk_time := 0.0
var spawn: Vector3
## Пока открыто окно или игрок печатает, клавиши не двигают персонажа.
var frozen := false
## Настройки мыши из меню.
var mouse_scale := 1.0
var invert_y := false
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
	pivot.position.y = 1.5
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
	_add_hint()


func _build_body() -> void:
	for c in visual.get_children():
		c.queue_free()
	var fig := Minifig.build(look)
	visual.add_child(fig.root)
	legs = fig.legs
	arms = fig.arms
	head = fig.head


## Меняет внешность на ходу (экран настройки фигурки).
func set_look(new_look: Dictionary) -> void:
	look = new_look
	_build_body()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# В режиме строительства колесо поднимает деталь, камеру двигает Ctrl+колесо.
		var building: bool = world.build != null and world.build.active
		if (building and not event.ctrl_pressed) or event.shift_pressed:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = maxf(arm.spring_length - 0.5, 2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = minf(arm.spring_length + 0.5, 20.0)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and not frozen:
		interact()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * mouse_scale
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens * (-1.0 if invert_y else 1.0), -1.2, 0.6)


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
	visual.position.y = absf(sin(walk_time)) * 0.06 if moving and is_on_floor() else 0.0
	if head:
		head.rotation.y = sin(walk_time * 0.5) * 0.08 if moving else lerpf(head.rotation.y, 0.0, 4.0 * delta)

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
