extends RefCounted
## Миньфигурка Lego: ноги без коленей, трапеция туловища, руки с кистями-
## захватами и цилиндрическая жёлтая голова с лицом. Её собирают игрок
## и экран настройки внешности.
##
## look: {"torso": цвет, "legs": цвет, "hair": цвет, "hat": "hair" | "cap" |
##        "helmet" | "bald", "face": "smile" | "grin" | "wink"}

const Style := preload("res://scripts/style.gd")

const DEFAULT_LOOK := {"torso": "red", "legs": "blue", "hair": "brown", "hat": "hair", "face": "smile"}
const HATS := ["hair", "cap", "helmet", "bald"]
const FACES := ["smile", "grin", "wink"]
## Рост фигурки в метрах (без причёски).
const HEIGHT := 1.68


## Собирает фигурку. Возвращает {"root", "legs", "arms", "head"}; вперёд это +Z.
static func build(look: Dictionary = {}) -> Dictionary:
	var l := DEFAULT_LOOK.duplicate()
	l.merge(look, true)
	var root := Node3D.new()
	root.name = "Minifig"
	var torso_m := Style.part_material(l.torso)
	var legs_m := Style.part_material(l.legs)
	var skin := Style.part_material("yellow")
	var ink := Style.part_material("black")

	var legs: Array[Node3D] = []
	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.17, 0.5, 0)
		root.add_child(leg)
		Style.add_part(leg, _rounded_box(Vector3(0.32, 0.46, 0.3)), legs_m, Vector3(0, -0.27, 0))
		# Стопа чуть длиннее вперёд.
		Style.add_part(leg, _rounded_box(Vector3(0.32, 0.1, 0.4)), legs_m, Vector3(0, -0.45, 0.04))
		legs.append(leg)
	# Бёдра.
	Style.add_part(root, _rounded_box(Vector3(0.66, 0.12, 0.3)), legs_m, Vector3(0, 0.54, 0))
	# Туловище: трапеция, шире внизу.
	Style.add_part(root, _trapezoid(0.66, 0.5, 0.34, 0.5), torso_m, Vector3(0, 0.6, 0))
	Style.add_part(root, Style.cylinder(0.11, 0.11, 0.06, 16), skin, Vector3(0, 1.13, 0))

	var arms: Array[Node3D] = []
	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.3, 1.0, 0)
		root.add_child(arm)
		var a := Style.add_part(arm, Style.cylinder(0.085, 0.1, 0.42, 14), torso_m, Vector3(side * 0.06, -0.17, 0.02), Vector3(0.12, 0, side * 0.22))
		a.name = "Sleeve"
		# Кисть-захват: короткий цилиндр поперёк.
		Style.add_part(arm, Style.cylinder(0.075, 0.075, 0.11, 14), skin, Vector3(side * 0.12, -0.42, 0.08), Vector3(PI * 0.5, 0, 0))
		arms.append(arm)

	var head := Node3D.new()
	head.position = Vector3(0, 1.16, 0)
	root.add_child(head)
	Style.add_part(head, Style.cylinder(0.2, 0.2, 0.36, 24), skin, Vector3(0, 0.2, 0))
	Style.add_part(head, Style.cylinder(0.17, 0.2, 0.03, 24), skin, Vector3(0, 0.395, 0))
	Style.add_part(head, Style.cylinder(0.2, 0.17, 0.03, 24), skin, Vector3(0, 0.005, 0))
	Style.add_part(head, Style.cylinder(0.12, 0.12, 0.08, 16), skin, Vector3(0, 0.45, 0))
	_face(head, str(l.face), ink)
	_hat(head, str(l.hat), Style.part_material(l.hair))
	return {"root": root, "legs": legs, "arms": arms, "head": head}


static func _face(head: Node3D, face: String, ink: Material) -> void:
	var eye := Style.sphere(0.026, 10, 6)
	var y := 0.25
	for side: float in [-1.0, 1.0]:
		if face == "wink" and side > 0.0:
			Style.add_part(head, Style.box(Vector3(0.06, 0.012, 0.01)), ink, _on_face(side * 0.07, y), Vector3(0, side * 0.36, 0))
		else:
			var e := Style.add_part(head, eye, ink, _on_face(side * 0.07, y))
			e.scale = Vector3(0.8, 1.2, 0.5)
	# Улыбка: дуга из маленьких отрезков по кругу головы.
	var wide := 0.11 if face == "grin" else 0.085
	var steps := 9
	for i in steps:
		var t := float(i) / (steps - 1) * 2.0 - 1.0
		var x := t * wide
		var yy := 0.155 + t * t * 0.035
		var seg := Style.add_part(head, Style.box(Vector3(wide * 2.2 / steps, 0.014, 0.01)), ink, _on_face(x, yy))
		seg.rotation = Vector3(0, -x / 0.2, -atan(t * 0.07 / wide * 2.0) * 0.6)
	if face == "grin":
		Style.add_part(head, Style.box(Vector3(0.12, 0.03, 0.006)), Style.part_material("white"), _on_face(0, 0.17))


## Точка на передней стороне головы: x вбок, y вверх от низа головы.
static func _on_face(x: float, y: float) -> Vector3:
	var a := x / 0.2
	return Vector3(sin(a) * 0.203, y, cos(a) * 0.203)


static func _hat(head: Node3D, hat: String, m: Material) -> void:
	match hat:
		"hair":
			var cap := Style.add_part(head, Style.sphere(0.235, 24, 12), m, Vector3(0, 0.36, -0.02))
			cap.scale = Vector3(1, 0.62, 1.03)
			Style.add_part(head, Style.cylinder(0.215, 0.215, 0.22, 24), m, Vector3(0, 0.28, -0.05), Vector3(-0.05, 0, 0)).scale = Vector3(1, 1, 0.9)
			# Чёлка спереди не закрывает глаза.
			Style.add_part(head, Style.box(Vector3(0.3, 0.06, 0.08)), m, Vector3(0, 0.38, 0.16), Vector3(0.3, 0, 0))
		"cap":
			var top := Style.add_part(head, Style.sphere(0.225, 24, 12), m, Vector3(0, 0.38, 0))
			top.scale = Vector3(1, 0.55, 1)
			Style.add_part(head, _rounded_box(Vector3(0.32, 0.03, 0.2)), m, Vector3(0, 0.39, 0.25), Vector3(-0.12, 0, 0))
		"helmet":
			var h := Style.add_part(head, Style.sphere(0.245, 24, 12), m, Vector3(0, 0.37, 0))
			h.scale = Vector3(1, 0.7, 1)
			Style.add_part(head, Style.cylinder(0.27, 0.27, 0.03, 24), m, Vector3(0, 0.36, 0))
		_:
			pass


## Коробка со скруглёнными рёбрами (через общий генератор кирпичей).
static func _rounded_box(size: Vector3) -> Mesh:
	var Bricks = load("res://scripts/bricks.gd")
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	a[Mesh.ARRAY_COLOR] = PackedColorArray()
	Bricks.append_bevel_box(a, AABB(-size * 0.5, size), Color.WHITE, 0.03)
	a[Mesh.ARRAY_COLOR] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh


## Трапеция туловища: низ шире верха, начало внизу по центру.
static func _trapezoid(bottom: float, top: float, depth: float, height: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := bottom * 0.5
	var t := top * 0.5
	var d := depth * 0.5
	var p := [Vector3(-b, 0, -d), Vector3(b, 0, -d), Vector3(b, 0, d), Vector3(-b, 0, d),
		Vector3(-t, height, -d), Vector3(t, height, -d), Vector3(t, height, d), Vector3(-t, height, d)]
	var center := Vector3(0, height * 0.5, 0)
	for f in [[0, 1, 2, 3], [7, 6, 5, 4], [3, 2, 6, 7], [1, 0, 4, 5], [2, 1, 5, 6], [0, 3, 7, 4]]:
		var a: Vector3 = p[f[0]]
		var bb: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var n := (bb - a).cross(c - a).normalized()
		var mid: Vector3 = (a + c) * 0.5
		if n.dot(mid - center) < 0.0:
			n = -n
		for tri in [[f[0], f[1], f[2]], [f[0], f[2], f[3]]]:
			var v0: Vector3 = p[tri[0]]
			var v1: Vector3 = p[tri[1]]
			var v2: Vector3 = p[tri[2]]
			if (v1 - v0).cross(v2 - v0).dot(n) > 0.0:
				var tmp := v1
				v1 = v2
				v2 = tmp
			for v in [v0, v1, v2]:
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()
