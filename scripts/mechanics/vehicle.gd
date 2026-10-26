extends CharacterBody3D
## Транспорт, придуманный ИИ-агентом: велосипед, машина, лошадь, самолёт,
## воздушный шар, ковёр-самолёт. Внешний вид собирает object_builder из
## spec.parts, а движение задаёт один из трёх видов (spec.mechanics.movement):
##   ground  едет по земле: газ, тормоз, руль, наклон в повороте, прыжок;
##   air     летит как самолёт: разбег, подъёмная сила от скорости, крен, сваливание;
##   hover   парит: вперёд-назад, поворот, вверх-вниз (вертолёт, метла, дрон).
## Физика аркадная: она предсказуемая и одинаково ведёт себя у всех игроков.
##
## Управление водителя: W/S газ и тормоз, A/D поворот, Пробел и Shift вверх и
## вниз (у самолёта нос вверх и вниз, у наземного транспорта Пробел прыжок),
## E выйти.

const WorldPhysics := preload("res://scripts/mechanics/world_physics.gd")

## Настройки после Mechanics.vehicle_params().
var mech: Dictionary
var driver: Node3D = null
## Вся видимая часть: её наклоняем в поворотах, не трогая коллизию.
var visual: Node3D
var seat := Vector3.ZERO
## Половина ширины, чтобы водитель выходил сбоку, а не внутри.
var half_width := 0.5
## Скорость вдоль носа, м/с.
var speed := 0.0
var throttle := 0.0
var steer := 0.0
var climb := 0.0
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
## Вертикальная скорость от гравитации и прыжков.
var fall := 0.0
var _hover_velocity := Vector3.ZERO
var _home := Vector3.ZERO
var _time := 0.0


func _ready() -> void:
	add_to_group("interactable")
	yaw = rotation.y
	_home = position
	visual = Node3D.new()
	visual.name = "Visual"
	var box := AABB()
	var first := true
	for c in get_children():
		if not c is Node3D:
			continue
		if c is CollisionShape3D:
			# Детали на ходу не цепляются за землю: вместо них одна простая форма.
			c.queue_free()
			continue
		remove_child(c)
		visual.add_child(c)
		if c is MeshInstance3D:
			var b: AABB = c.transform * c.get_aabb()
			box = b if first else box.merge(b)
			first = false
	add_child(visual)

	var size := box.size.max(Vector3(0.4, 0.4, 0.4))
	half_width = size.x * 0.5
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Чуть уже и ниже: так транспорт не застревает в узких местах.
	# Низ формы совпадает с низом колёс.
	shape.size = Vector3(size.x * 0.9, size.y * 0.8, size.z * 0.9)
	col.shape = shape
	col.position = Vector3(box.get_center().x, box.position.y + size.y * 0.4, box.get_center().z)
	add_child(col)

	var s = mech.get("seat")
	if s is Array and s.size() >= 3:
		seat = Vector3(float(s[0]), float(s[1]), float(s[2])).clamp(-Vector3.ONE * 20.0, Vector3.ONE * 20.0)
	else:
		seat = Vector3(box.get_center().x, box.end.y - 0.2, box.get_center().z)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)


## Игрок нажал E рядом с транспортом.
func interact(player: Node3D) -> void:
	if driver == null:
		driver = player
		player.board(self)


func leave() -> void:
	driver = null


func prompt() -> String:
	return "E — сесть: «%s»" % name


func hint() -> String:
	var custom: String = mech.get("hint", "")
	if custom != "":
		return custom
	match mech.movement:
		"air":
			return "W/S газ, A/D крен, Пробел нос вверх, Shift нос вниз, E выйти"
		"hover":
			return "W/S вперёд-назад, A/D поворот, Пробел вверх, Shift вниз, E выйти"
	return "W/S газ и тормоз, A/D руль, Пробел прыжок, E выйти"


## Где сидит водитель, в координатах мира.
func seat_transform() -> Transform3D:
	return visual.global_transform * Transform3D(Basis(), seat)


func _key(a: Key, b: Key) -> float:
	if driver == null or driver.frozen:
		return 0.0
	return 1.0 if Input.is_key_pressed(a) or Input.is_key_pressed(b) else 0.0


func _gravity() -> float:
	return 18.0 * WorldPhysics.gravity * float(mech.gravity_scale)


func _physics_process(delta: float) -> void:
	_time += delta
	match mech.movement:
		"air":
			_fly(delta)
		"hover":
			_hover(delta)
		_:
			_drive(delta)
	if position.y < -50.0:
		position = _home
		speed = 0.0
		fall = 0.0
		_hover_velocity = Vector3.ZERO

	var animator := get_node_or_null("Animator")
	if animator:
		animator.inputs = {
			"speed": speed / maxf(float(mech.max_speed), 0.1),
			"throttle": throttle,
			"steer": steer,
			"climb": climb,
			"active": 1.0 if driver != null else 0.0,
		}


# --- По земле -------------------------------------------------------------

func _drive(delta: float) -> void:
	var gas := _key(KEY_W, KEY_UP) - _key(KEY_S, KEY_DOWN)
	var max_v := float(mech.max_speed)
	if gas > 0.0:
		var a := float(mech.acceleration) if speed >= 0.0 else float(mech.brake)
		speed = move_toward(speed, max_v, a * delta)
	elif gas < 0.0:
		var a := float(mech.brake) if speed > 0.0 else float(mech.acceleration)
		speed = move_toward(speed, -float(mech.reverse_speed), a * delta)
	else:
		speed = move_toward(speed, 0.0, float(mech.acceleration) * 0.4 * delta)
	throttle = absf(gas)

	steer = move_toward(steer, _key(KEY_A, KEY_LEFT) - _key(KEY_D, KEY_RIGHT), 4.0 * delta)
	# На месте не развернуться: руль работает только в движении.
	var grip := clampf(absf(speed) / maxf(max_v * 0.2, 0.5), 0.0, 1.0)
	yaw += deg_to_rad(float(mech.turn_speed)) * steer * grip * signf(speed) * delta
	rotation = Vector3(0, yaw, 0)

	if is_on_floor():
		fall = 0.0
		if float(mech.jump) > 0.0 and _key(KEY_SPACE, KEY_SPACE) > 0.0:
			fall = float(mech.jump)
	else:
		fall -= _gravity() * delta
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	velocity = fwd * speed + Vector3(0, fall, 0)
	move_and_slide()
	if is_on_wall():
		speed *= 0.5
	if is_on_ceiling() and fall > 0.0:
		fall = 0.0

	# Велосипед и мотоцикл наклоняются в поворот.
	var lean := deg_to_rad(float(mech.lean)) * steer * grip
	visual.rotation.z = lerpf(visual.rotation.z, lean, 6.0 * delta)
	visual.rotation.x = lerpf(visual.rotation.x, 0.0, 6.0 * delta)


# --- Самолёт --------------------------------------------------------------

func _fly(delta: float) -> void:
	var max_v := float(mech.max_speed)
	var takeoff := float(mech.takeoff_speed)
	throttle = clampf(throttle + (_key(KEY_W, KEY_UP) - _key(KEY_S, KEY_DOWN)) * 0.6 * delta, 0.0, 1.0)
	if driver == null:
		throttle = move_toward(throttle, 0.0, delta)
	var target := max_v * throttle
	var a := float(mech.acceleration) if target > speed else float(mech.brake) * 0.5
	speed = move_toward(speed, target, a * delta)

	steer = move_toward(steer, _key(KEY_A, KEY_LEFT) - _key(KEY_D, KEY_RIGHT), 2.5 * delta)
	climb = _key(KEY_SPACE, KEY_SPACE) - _key(KEY_SHIFT, KEY_SHIFT)
	var on_ground := is_on_floor()
	var max_roll := deg_to_rad(float(mech.lean))
	var pitch_rate := deg_to_rad(float(mech.pitch_speed))

	if on_ground:
		# Руление по земле и разбег: нос поднимается только на скорости отрыва.
		roll = move_toward(roll, 0.0, 2.0 * delta)
		yaw += deg_to_rad(float(mech.turn_speed)) * 0.6 * steer * clampf(speed / 3.0, 0.0, 1.0) * delta
		var up := deg_to_rad(12.0) if climb > 0.0 and speed >= takeoff * 0.9 else 0.0
		pitch = move_toward(maxf(pitch, 0.0), up, pitch_rate * delta)
		speed = move_toward(speed, 0.0, 1.5 * delta) if throttle < 0.05 else speed
	else:
		roll = move_toward(roll, steer * max_roll, 1.5 * delta)
		yaw += deg_to_rad(float(mech.turn_speed)) * (roll / maxf(max_roll, 0.1)) * delta
		pitch = clampf(pitch + pitch_rate * climb * delta, deg_to_rad(-70.0), deg_to_rad(70.0))
		# Пикирование разгоняет, набор высоты тормозит.
		speed = clampf(speed - _gravity() * 0.5 * sin(pitch) * delta, 0.0, max_v * 1.5)

	var lift := clampf(pow(speed / maxf(takeoff, 0.1), 2.0), 0.0, 1.0)
	if lift >= 1.0:
		fall = move_toward(fall, 0.0, _gravity() * 2.0 * delta)
	else:
		fall -= _gravity() * (1.0 - lift) * delta
		if not on_ground and lift < 0.6:
			# Сваливание: без скорости нос опускается.
			pitch = move_toward(pitch, deg_to_rad(-35.0), 0.8 * delta)
	if on_ground and fall < 0.0:
		fall = 0.0

	rotation = Vector3(pitch, yaw, 0)
	visual.rotation.z = roll
	var fwd := -global_transform.basis.z
	velocity = fwd * speed + Vector3(0, fall, 0)
	move_and_slide()
	if is_on_wall():
		speed *= 0.3


# --- Парение --------------------------------------------------------------

func _hover(delta: float) -> void:
	var go := _key(KEY_W, KEY_UP) - _key(KEY_S, KEY_DOWN)
	steer = move_toward(steer, _key(KEY_A, KEY_LEFT) - _key(KEY_D, KEY_RIGHT), 4.0 * delta)
	climb = _key(KEY_SPACE, KEY_SPACE) - _key(KEY_SHIFT, KEY_SHIFT)
	yaw += deg_to_rad(float(mech.turn_speed)) * steer * delta
	rotation = Vector3(0, yaw, 0)

	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	var limit := float(mech.max_speed) if go >= 0.0 else float(mech.reverse_speed)
	var h := Vector3(_hover_velocity.x, 0, _hover_velocity.z).move_toward(fwd * go * limit, float(mech.acceleration) * delta)
	var vy := _hover_velocity.y
	if driver != null:
		vy = move_toward(vy, climb * float(mech.climb_speed), float(mech.acceleration) * delta)
		# Без газа вверх немного тянет вниз, если задана гравитация.
		if climb == 0.0:
			vy -= _gravity() * 0.15 * delta
	elif not is_on_floor():
		# Пустой транспорт мягко опускается на землю.
		vy = move_toward(vy, -3.0, _gravity() * 0.3 * delta + 2.0 * delta)
	if is_on_floor() and vy < 0.0:
		vy = 0.0
	_hover_velocity = Vector3(h.x, vy, h.z)
	velocity = _hover_velocity
	move_and_slide()
	speed = h.dot(fwd)
	throttle = clampf(absf(go) + absf(climb), 0.0, 1.0)

	var tilt := deg_to_rad(float(mech.tilt))
	visual.rotation.x = lerpf(visual.rotation.x, -tilt * go, 4.0 * delta)
	visual.rotation.z = lerpf(visual.rotation.z, deg_to_rad(float(mech.lean)) * steer, 4.0 * delta)
	# Лёгкое покачивание в воздухе.
	visual.position.y = sin(_time * 2.0) * 0.08 if not is_on_floor() else 0.0
