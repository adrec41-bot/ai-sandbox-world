extends Node
## Двигает детали объекта по spec.mechanics.animations: крутит колёса и
## пропеллеры, качает маятник, поворачивает руль и открывает двери.
## Детали находятся по полю "id" у части (part.id), все части с одним id
## двигаются вместе вокруг общей точки (pivot).
##
## animation: {"part": "wheel", "motion": "spin" | "swing" | "bob" | "angle",
##             "axis": "x" | "y" | "z", "amount": градусы (bob: метры),
##             "rate": колебаний в секунду, "by": от чего зависит, "pivot": [x, y, z]}
## by: always всегда, speed скорость транспорта (-1..1), throttle газ (0..1),
## steer руль (-1..1), climb вверх-вниз (-1..1), active включён (сел водитель
## или игрок нажал E у предмета).

var animations: Array = []
## Текущие значения входов, их обновляет хозяин объекта.
var inputs := {"active": 0.0}
var _groups: Array[Dictionary] = []
var _ready_done := false
var _time := 0.0


func _process(delta: float) -> void:
	if not _ready_done:
		_build()
	_time += delta
	for g in _groups:
		var a: Dictionary = g.anim
		var by := str(a.get("by", "always"))
		var k := 1.0 if by == "always" else float(inputs.get(by, 0.0))
		var amount := clampf(_num(a.get("amount"), 90.0), -3600.0, 3600.0)
		var rate := clampf(_num(a.get("rate"), 1.0), 0.0, 20.0)
		var pivot: Node3D = g.node
		match str(a.get("motion", "spin")):
			"spin":
				g.value += deg_to_rad(amount) * k * delta
			"swing":
				g.value = deg_to_rad(amount) * sin(_time * TAU * rate) * k
			"bob":
				g.value = clampf(amount, -10.0, 10.0) * sin(_time * TAU * rate) * k
			"angle":
				g.value = lerpf(g.value, deg_to_rad(amount) * k, minf(6.0 * delta, 1.0))
		if str(a.get("motion", "spin")) == "bob":
			pivot.transform = Transform3D(g.base.basis, g.base.origin + g.axis * g.value)
		else:
			pivot.transform = Transform3D(g.base.basis * Basis(g.axis, g.value), g.base.origin)
		# Повёрнутая дверь не должна мешать пройти, закрытая мешает.
		var resting := absf(g.value) < 0.05 and str(a.get("motion", "spin")) == "angle"
		for col in g.colliders:
			col.disabled = not resting


func _build() -> void:
	_ready_done = true
	var owner_node := get_parent()
	var container: Node3D = owner_node.get_node_or_null("Visual")
	if container == null:
		container = owner_node
	for a in animations:
		if not a is Dictionary:
			continue
		var id := str(a.get("part", ""))
		var meshes: Array[Node3D] = []
		for c in container.get_children():
			if c is Node3D and c.get_meta("part_id", "") == id:
				meshes.append(c)
		if meshes.is_empty():
			continue
		var pivot := Node3D.new()
		pivot.name = ("Anim_" + id).validate_node_name()
		var p = a.get("pivot")
		if p is Array and p.size() >= 3:
			pivot.position = Vector3(_num(p[0], 0.0), _num(p[1], 0.0), _num(p[2], 0.0))
		else:
			pivot.position = meshes[0].position
		# Вторая анимация той же детали оборачивает первую: колесо крутится
		# и одновременно поворачивается рулём.
		pivot.set_meta("part_id", id)
		container.add_child(pivot)
		for m in meshes:
			var xf := pivot.transform.affine_inverse() * m.transform
			container.remove_child(m)
			pivot.add_child(m)
			m.transform = xf
		var colliders: Array[CollisionShape3D] = []
		for c in owner_node.get_children():
			if c is CollisionShape3D and not c.is_queued_for_deletion() and c.get_meta("part_id", "") == id:
				colliders.append(c)
		var axis := Vector3.RIGHT
		match str(a.get("axis", "x")):
			"y":
				axis = Vector3.UP
			"z":
				axis = Vector3.BACK
		_groups.append({"anim": a, "node": pivot, "base": pivot.transform, "axis": axis, "value": 0.0, "colliders": colliders})


static func _num(v, fallback: float) -> float:
	return float(v) if (v is float or v is int) else fallback
