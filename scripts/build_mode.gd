extends Node
## Режим строительства (B). В центре экрана прицел, перед ним полупрозрачный
## «призрак» выбранной детали: зелёный, если её можно поставить, красный,
## если мешает другая постройка или сам игрок. Деталь прилипает к сетке
## шипов и к верху или боку того, во что смотрит прицел.
##
## ЛКМ поставить, R / Shift+R повернуть, колесо поднять или опустить на
## пластину (Ctrl+колесо приближает камеру), ПКМ выделить постройку (с Shift
## несколько), M перенести выделенное, Ctrl+D копия, Delete удалить,
## средняя кнопка взять образец в слот, Alt+ЛКМ протянуть площадку для ИИ,
## Alt+ПКМ убрать её, V вид сверху.

const Builder := preload("res://scripts/object_builder.gd")
const Bridge := preload("res://scripts/agent_bridge.gd")
const Style := preload("res://scripts/style.gd")
const Catalog := preload("res://scripts/catalog.gd")

const REACH := 40.0

var ui
var world
var bridge
var player
var sfx

var active := false
## Призрак: что сейчас поставится.
var _ghost: Node3D
var _ghost_key := ""
var _ghost_box := AABB()
var _ghost_mat_ok: StandardMaterial3D
var _ghost_mat_bad: StandardMaterial3D
var _rotation := 0.0
var _lift := 0
var _target := Vector3.ZERO
var _valid := false
var _aim_ok := false
## Перенос или копия: {"spec", "item_id", "from", "name", "author", "prompt"}.
var _carry := {}
var _hover := ""
var _area_from = null
var _area_to := Vector3.ZERO
var _area_node: MeshInstance3D
var _select_node: MeshInstance3D
var _hover_node: MeshInstance3D
var _line_mat: StandardMaterial3D
var _top_view := false
var _saved_cam := []


func _ready() -> void:
	_ghost_mat_ok = _ghost_material(Color(0.35, 0.95, 0.45, 0.42))
	_ghost_mat_bad = _ghost_material(Color(1.0, 0.3, 0.25, 0.42))
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.no_depth_test = true
	_line_mat.render_priority = 10
	_area_node = _lines_node()
	_select_node = _lines_node()
	_hover_node = _lines_node()
	bridge.area_changed.connect(_draw_area)
	bridge.selection_changed.connect(_draw_selection)
	bridge.hotbar_changed.connect(_refresh_ghost)
	_draw_area()


func _ghost_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b) * 0.35
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _lines_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _line_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child.call_deferred(mi)
	return mi


func toggle() -> void:
	active = not active
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_refresh_ghost()
		sfx.play("open")
	else:
		cancel()
		bridge.set_selection([])
		_free_ghost()
		_hover = ""
		_draw_hover()
		if _top_view:
			_toggle_view()


func has_selection() -> bool:
	return not bridge.selection.is_empty()


func is_carrying() -> bool:
	return not _carry.is_empty()


## Esc: отменить перенос, потом снять выделение.
func cancel() -> void:
	if is_carrying():
		var from := str(_carry.get("from", ""))
		var node: Node3D = bridge.object_node(from)
		if node:
			node.visible = true
		_carry = {}
		_refresh_ghost()
		return
	_area_from = null
	if has_selection():
		bridge.set_selection([])


func hints() -> Array:
	if is_carrying():
		return [["ЛКМ", "поставить сюда"], ["R", "повернуть"], ["Колесо", "выше / ниже"], ["Esc", "отмена"]]
	if has_selection():
		return [["Enter", "изменить через ИИ"], ["M", "переместить"], ["Ctrl+D", "копия"], ["Del", "удалить"], ["Shift+ПКМ", "ещё"], ["Esc", "снять выделение"]]
	var item: Dictionary = bridge.current_item()
	var list := []
	if item.is_empty():
		list = [["1–9", "выбрать деталь"], ["Tab", "инвентарь"], ["ПКМ", "выделить постройку"]]
	else:
		list = [["ЛКМ", "поставить"], ["R", "повернуть"], ["Колесо", "выше / ниже"], ["ПКМ", "выделить"]]
	list.append(["Alt+ЛКМ", "площадка для ИИ" if bridge.area.is_empty() else "новая площадка"])
	if not bridge.area.is_empty():
		list.append(["Alt+ПКМ", "убрать площадку"])
	list.append(["B", "выйти"])
	list.append(["F1", "все клавиши"])
	return list


# --- Призрак --------------------------------------------------------------

## Описание того, что держим: перенос или предмет из выбранного слота.
func _held() -> Dictionary:
	if is_carrying():
		return _carry
	var item: Dictionary = bridge.current_item()
	if item.is_empty():
		return {}
	return {"spec": item.spec, "item_id": item.item_id, "from": "", "name": item.name, "author": item.get("author", ""), "prompt": item.get("prompt", "")}


func _refresh_ghost() -> void:
	if not active:
		return
	var held := _held()
	var key := "" if held.is_empty() else "%s|%s|%d" % [held.item_id, held.from, hash(JSON.stringify(held.spec))]
	if key == _ghost_key and (_ghost != null) == (key != ""):
		return
	_free_ghost()
	_ghost_key = key
	if held.is_empty():
		return
	var spec: Dictionary = (held.spec as Dictionary).duplicate(true)
	spec.erase("mechanics")
	spec.erase("effects")
	spec["physics"] = {"mode": "none"}
	_ghost = Builder.build(spec)
	_ghost.name = "BuildGhost"
	world.add_child(_ghost)
	_ghost_box = Bridge.node_aabb(_ghost)
	if _ghost_box.size == Vector3.ZERO:
		_ghost_box = AABB(Vector3(-0.2, 0, -0.2), Vector3(0.4, 0.4, 0.4))
	_set_ghost_material(_ghost_mat_ok)
	_ghost.visible = false


func _free_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_ghost_key = ""


func _set_ghost_material(m: Material) -> void:
	var stack: Array[Node] = [_ghost]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is GeometryInstance3D:
			n.material_override = m
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n is Light3D or n is GPUParticles3D or n is CPUParticles3D:
			n.visible = false


## Габариты призрака с учётом поворота, относительно его начала.
func _rotated_box() -> AABB:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(_rotation)), Vector3.ZERO) * _ghost_box


func _process(delta: float) -> void:
	var can_aim: bool = active and ui.modal == "" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not can_aim:
		if _ghost:
			_ghost.visible = false
		return
	_refresh_ghost()
	var hit := _ray()
	var over: String = "" if hit.is_empty() else bridge.object_of(hit.collider)
	if over != _hover:
		_hover = over
		_draw_hover()
	if _area_from != null and not hit.is_empty():
		_area_to = hit.position
		_draw_area()
	if _ghost == null:
		return
	_aim_ok = not hit.is_empty()
	if not _aim_ok:
		_ghost.visible = false
		return
	var rb := _rotated_box()
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var origin := Vector3.ZERO
	if n.y > 0.7:
		origin = Vector3(p.x - rb.get_center().x, p.y - rb.position.y, p.z - rb.get_center().z)
	else:
		# Сбоку: деталь прилипает к стене той гранью, что смотрит на неё.
		var side := Vector3(roundf(n.x), 0, roundf(n.z))
		if absf(n.x) >= absf(n.z):
			side = Vector3(signf(n.x), 0, 0)
		else:
			side = Vector3(0, 0, signf(n.z))
		origin = Vector3(p.x - rb.get_center().x, floorf((p.y + 0.01) / Style.PLATE) * Style.PLATE - rb.position.y, p.z - rb.get_center().z)
		if side.x > 0:
			origin.x = p.x - rb.position.x
		elif side.x < 0:
			origin.x = p.x - rb.end.x
		elif side.z > 0:
			origin.z = p.z - rb.position.z
		else:
			origin.z = p.z - rb.end.z
	origin.x = snappedf(origin.x, Style.STUD)
	origin.z = snappedf(origin.z, Style.STUD)
	if n.y <= 0.7:
		# Рядом со стеной деталь стоит на том, что под ней, а не висит в воздухе.
		var c := origin + rb.get_center()
		origin.y = _support(Vector3(c.x, p.y + 0.02, c.z)) - rb.position.y
	origin.y = maxf(snappedf(origin.y, Style.PLATE) + _lift * Style.PLATE, 0.0)
	var limit: float = world.SIZE * 0.5 - 1.0
	origin.x = clampf(origin.x, -limit, limit)
	origin.z = clampf(origin.z, -limit, limit)
	var jump := _target.distance_to(origin) > 3.0 or not _ghost.visible
	_target = origin
	_ghost.visible = true
	_ghost.rotation.y = deg_to_rad(_rotation)
	_ghost.position = origin if jump else _ghost.position.lerp(origin, minf(1.0, delta * 22.0))
	var ok := _fits(Transform3D(Basis(), origin) * rb)
	if ok != _valid:
		_valid = ok
		_set_ghost_material(_ghost_mat_ok if ok else _ghost_mat_bad)


## Можно ли поставить: не залезает в постройки и в игрока.
func _fits(box: AABB) -> bool:
	var inner := box.grow(-0.04)
	var pp: Vector3 = player.global_position
	var me := AABB(pp + Vector3(-0.3, 0.05, -0.3), Vector3(0.6, 1.4, 0.6))
	if inner.intersects(me):
		return false
	var skip := str(_carry.get("from", ""))
	for id in bridge.object_ids():
		if id == skip:
			continue
		var node: Node3D = bridge.object_node(id)
		if node == null or not node is StaticBody3D:
			# Подвижные вещи сами отъедут, на них ставить можно.
			continue
		if inner.intersects(bridge.object_aabb(id)) and _overlaps_bricks(inner, node):
			return false
	return true


## Габариты объекта бывают больше его кирпичей (дом с двором): проверяем
## физику, а не только коробку.
func _overlaps_bricks(box: AABB, node: Node3D) -> bool:
	var shape := BoxShape3D.new()
	shape.size = box.size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), box.get_center())
	q.collision_mask = 1
	for r in world.get_world_3d().direct_space_state.intersect_shape(q, 16):
		if r.collider == node:
			return true
	return false


## Высота опоры под точкой: верх постройки или земля.
func _support(from: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 80.0, 1)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
	return maxf(0.0, hit.position.y) if not hit.is_empty() else 0.0


func _ray() -> Dictionary:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var to := from + cam.project_ray_normal(center) * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var exclude: Array[RID] = [player.get_rid()]
	var from_id := str(_carry.get("from", ""))
	var carried: Node3D = bridge.object_node(from_id) if from_id != "" else null
	if carried is CollisionObject3D:
		exclude.append(carried.get_rid())
	q.exclude = exclude
	return world.get_world_3d().direct_space_state.intersect_ray(q)


# --- Действия -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or ui.blocked() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton:
		_mouse(event)
	elif event is InputEventKey and event.pressed:
		_key(event)


func _mouse(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_LEFT and e.alt_pressed:
		if e.pressed:
			var hit := _ray()
			if not hit.is_empty():
				_area_from = hit.position
				_area_to = hit.position
		elif _area_from != null:
			_finish_area()
		get_viewport().set_input_as_handled()
		return
	if not e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and _area_from != null:
			_finish_area()
		return
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if _ghost:
				_place()
			else:
				_select(e.shift_pressed)
		MOUSE_BUTTON_RIGHT:
			if e.alt_pressed:
				bridge.clear_area()
				ui.toast("Площадка убрана")
			else:
				_select(e.shift_pressed)
		MOUSE_BUTTON_MIDDLE:
			_eyedropper()
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.ctrl_pressed:
				return
			var step := 3 if e.shift_pressed else 1
			_lift = clampi(_lift + (step if e.button_index == MOUSE_BUTTON_WHEEL_UP else -step), -30, 120)
			sfx.play("tick")
		_:
			return
	get_viewport().set_input_as_handled()


func _key(e: InputEventKey) -> void:
	match e.keycode:
		KEY_R:
			_rotation = fposmod(_rotation + (-90.0 if e.shift_pressed else 90.0), 360.0)
			sfx.play("tick")
		KEY_M:
			_start_move()
		KEY_D:
			if not e.ctrl_pressed:
				return
			_start_copy()
		KEY_DELETE, KEY_X, KEY_BACKSPACE:
			_delete_selection()
		KEY_V:
			_toggle_view()
		KEY_PAGEUP:
			_lift = mini(_lift + 1, 120)
		KEY_PAGEDOWN:
			_lift = maxi(_lift - 1, -30)
		_:
			return
	get_viewport().set_input_as_handled()


func _place() -> void:
	if not _aim_ok or _ghost == null or not _ghost.visible:
		return
	if not _valid:
		sfx.play("error")
		ui.toast("Здесь занято: подвинь прицел или подними деталь колесом")
		return
	var held := _held()
	var pos := Vector2(_target.x, _target.z)
	if held.from != "":
		var node: Node3D = bridge.object_node(held.from)
		if node:
			node.visible = true
		bridge.move_object(held.from, pos, _target.y, _rotation)
		bridge.set_selection([])
		_carry = {}
		_refresh_ghost()
		return
	var id: String = bridge.place_spec(held.spec, held.item_id, pos, _target.y, _rotation, held.author, held.prompt)
	if id != "" and is_carrying():
		# Копия ставится один раз, дальше снова выбранный слот.
		_carry = {}
		_refresh_ghost()


func _select(add: bool) -> void:
	var ids: Array = bridge.selection.duplicate() if add else []
	if _hover != "":
		if _hover in ids:
			ids.erase(_hover)
		else:
			ids.append(_hover)
	bridge.set_selection(ids)
	if _hover != "":
		sfx.play("click")


func _start_move() -> void:
	if not has_selection():
		ui.toast("Сначала выдели постройку правой кнопкой")
		return
	var id: String = bridge.selection[0]
	var rec: Dictionary = bridge.object_record(id)
	if rec.is_empty():
		return
	_carry = {"spec": rec.spec, "item_id": rec.get("item_id", ""), "from": id, "name": rec.spec.get("name", ""), "author": rec.get("author", ""), "prompt": rec.get("prompt", "")}
	_rotation = float(rec.rotation_y)
	_lift = 0
	var node: Node3D = bridge.object_node(id)
	if node:
		node.visible = false
	_refresh_ghost()


func _start_copy() -> void:
	if not has_selection():
		return
	var rec: Dictionary = bridge.object_record(bridge.selection[0])
	if rec.is_empty():
		return
	_carry = {"spec": rec.spec, "item_id": rec.get("item_id", ""), "from": "", "name": rec.spec.get("name", ""), "author": rec.get("author", ""), "prompt": rec.get("prompt", ""), "copy": true}
	_rotation = float(rec.rotation_y)
	bridge.set_selection([])
	_refresh_ghost()


func _delete_selection() -> void:
	if not has_selection():
		if _hover != "":
			bridge.set_selection([_hover])
		else:
			return
	var ids: Array = bridge.selection.duplicate()
	bridge.begin_batch()
	for id in ids:
		bridge.remove_object(id)
	bridge.end_batch()
	bridge.set_selection([])
	ui.toast("Удалено: %d · Ctrl+Z вернёт" % ids.size())


## Средняя кнопка: постройка под прицелом становится деталью в текущем слоте.
func _eyedropper() -> void:
	if _hover == "":
		return
	var rec: Dictionary = bridge.object_record(_hover)
	var item_id := str(rec.get("item_id", ""))
	var item: Dictionary = bridge.get_item(item_id)
	if Catalog.is_basic(item_id):
		var bricks: Array = rec.spec.get("bricks", [])
		if not bricks.is_empty() and bricks[0] is Dictionary and bricks[0].has("color"):
			bridge.set_paint(str(bricks[0].color))
	elif item.is_empty() or item.get("deleted", false):
		item = bridge.add_item(rec.spec, str(rec.get("author", "")), str(rec.get("prompt", "")))
		item_id = str(item.get("item_id", ""))
	if item_id != "":
		bridge.assign_hotbar(bridge.selected, item_id)
		_rotation = float(rec.get("rotation_y", 0.0))
		ui.toast("В слот %d: %s" % [bridge.selected + 1, rec.spec.get("name", "объект")])
		sfx.play("click")


func _finish_area() -> void:
	var a: Vector3 = _area_from
	var b := _area_to
	_area_from = null
	var S := Style.STUD
	var x0 := int(floorf(minf(a.x, b.x) / S))
	var z0 := int(floorf(minf(a.z, b.z) / S))
	var x1 := int(ceilf(maxf(a.x, b.x) / S))
	var z1 := int(ceilf(maxf(a.z, b.z) / S))
	x1 = maxi(x1, x0 + 2)
	z1 = maxi(z1, z0 + 2)
	bridge.set_area(x0, z0, x1, z1, int(roundf(minf(a.y, b.y) / Style.PLATE)))
	ui.toast("Площадка %d×%d шипов. Напиши ИИ, что тут построить (Enter)" % [x1 - x0, z1 - z0], 5.0)
	sfx.play("snap")


func _toggle_view() -> void:
	_top_view = not _top_view
	if _top_view:
		_saved_cam = [player.pitch, player.arm.spring_length]
		player.pitch = -1.2
		player.arm.spring_length = 18.0
	elif not _saved_cam.is_empty():
		player.pitch = _saved_cam[0]
		player.arm.spring_length = _saved_cam[1]


# --- Рамки: площадка, выделение, наведение --------------------------------

func _draw_area() -> void:
	var m: ImmediateMesh = _area_node.mesh
	m.clear_surfaces()
	var S := Style.STUD
	var box := AABB()
	var col := Color(1.0, 0.82, 0.1)
	if _area_from != null:
		var a: Vector3 = _area_from
		var x0 := floorf(minf(a.x, _area_to.x) / S) * S
		var z0 := floorf(minf(a.z, _area_to.z) / S) * S
		var x1 := ceilf(maxf(a.x, _area_to.x) / S) * S
		var z1 := ceilf(maxf(a.z, _area_to.z) / S) * S
		box = AABB(Vector3(x0, minf(a.y, _area_to.y), z0), Vector3(maxf(x1 - x0, S), 0.02, maxf(z1 - z0, S)))
	elif not bridge.area.is_empty():
		var ar: Dictionary = bridge.area
		box = AABB(Vector3(ar.x0 * S, ar.y * Style.PLATE, ar.z0 * S), Vector3((ar.x1 - ar.x0) * S, 0.02, (ar.z1 - ar.z0) * S))
	else:
		return
	# Рамка по земле и столбики по углам, чтобы площадку было видно издалека.
	_box_lines(m, AABB(box.position + Vector3(0, 0.03, 0), Vector3(box.size.x, 0.0, box.size.z)), col)
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	for c in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)]:
		var p: Vector3 = box.position + box.size * c
		m.surface_set_color(col)
		m.surface_add_vertex(p)
		m.surface_set_color(Color(col, 0.0))
		m.surface_add_vertex(p + Vector3(0, 2.4, 0))
	# Сетка шипов внутри площадки, через каждые 4.
	var step := S * 4.0
	var gx := box.position.x + step
	while gx < box.end.x - 0.01:
		m.surface_set_color(Color(col, 0.45))
		m.surface_add_vertex(Vector3(gx, box.position.y + 0.03, box.position.z))
		m.surface_set_color(Color(col, 0.45))
		m.surface_add_vertex(Vector3(gx, box.position.y + 0.03, box.end.z))
		gx += step
	var gz := box.position.z + step
	while gz < box.end.z - 0.01:
		m.surface_set_color(Color(col, 0.45))
		m.surface_add_vertex(Vector3(box.position.x, box.position.y + 0.03, gz))
		m.surface_set_color(Color(col, 0.45))
		m.surface_add_vertex(Vector3(box.end.x, box.position.y + 0.03, gz))
		gz += step
	m.surface_end()


func _draw_selection() -> void:
	var m: ImmediateMesh = _select_node.mesh
	m.clear_surfaces()
	for id in bridge.selection:
		_box_lines(m, bridge.object_aabb(id).grow(0.05), Color(1.0, 0.85, 0.1))


func _draw_hover() -> void:
	var m: ImmediateMesh = _hover_node.mesh
	m.clear_surfaces()
	if _hover != "" and active and not _hover in bridge.selection:
		_box_lines(m, bridge.object_aabb(_hover).grow(0.04), Color(1, 1, 1, 0.55))


func _box_lines(m: ImmediateMesh, b: AABB, col: Color) -> void:
	if b.size == Vector3.ZERO and b.position == Vector3.ZERO:
		return
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var c: Array[Vector3] = []
	for i in 8:
		c.append(b.position + b.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		m.surface_set_color(col)
		m.surface_add_vertex(c[e[0]])
		m.surface_set_color(col)
		m.surface_add_vertex(c[e[1]])
	m.surface_end()
