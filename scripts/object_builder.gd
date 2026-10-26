extends RefCounted
## Строит объект мира из описания, которое прислал ИИ-агент через MCP.
## Основа описания это кирпичи Lego на сетке шипов (spec.bricks, см.
## scripts/bricks.gd). Для того, что из кирпичей не собрать (колёса, купола,
## пропеллеры), есть свободные детали spec.parts: примитивы, тела вращения,
## выдавленные контуры. Материал у всего один, глянцевый пластик, а цвета
## приводятся к палитре Lego, поэтому любой объект выглядит частью мира.
##
## Формат описания (подробно в ai/style_guide.md):
## {
##   "name": "Мельница",
##   "category": "buildings",
##   "physics": {"mode": "static" | "rigid" | "none", "mass": 50},
##   "bricks": [{"type": "brick", "at": [0, 0, 0], "size": [2, 4], "color": "red"}, ...],
##   "parts": [{"shape": "cylinder", "radius": 0.5, "height": 0.4, "position": [0, 1, 0],
##              "rotation": [0, 0, 90], "color": "black"}, ...],
##   "effects": [{"type": "smoke" | "light", "position": [0, 4, 0]}],
##   "mechanics": {"type": "vehicle" | "equipment" | "prop", ...}
## }
## Ноль по Y это уровень земли под объектом, у деталей единицы в метрах, углы в градусах.
## Механики (транспорт, снаряжение, анимации) описаны в scripts/mechanics/mechanics.gd.

const Style := preload("res://scripts/style.gd")
const Mechanics := preload("res://scripts/mechanics/mechanics.gd")
const Bricks := preload("res://scripts/bricks.gd")

const MAX_PARTS := 256
const MAX_EFFECTS := 16
## Предел размеров и смещений деталей в метрах.
const MAX_SIZE := 40.0
const SHAPES := ["box", "sphere", "cylinder", "cone", "capsule", "torus", "prism", "lathe", "extrude"]


static func build(spec: Dictionary) -> Node3D:
	var physics: Dictionary = spec.get("physics") if spec.get("physics") is Dictionary else {}
	# Транспорту нужен свой вид тела, остальное решает physics.mode.
	var root: Node3D = Mechanics.make_root(spec)
	if root == null:
		match str(physics.get("mode", "static")):
			"rigid":
				var rb := RigidBody3D.new()
				rb.mass = clampf(_num(physics.get("mass"), 10.0), 0.1, 5000.0)
				root = rb
			"none":
				root = Node3D.new()
			_:
				root = StaticBody3D.new()
	root.name = str(spec.get("name", "object")).validate_node_name()

	var parts: Array = spec.get("parts") if spec.get("parts") is Array else []
	for i in mini(parts.size(), MAX_PARTS):
		if parts[i] is Dictionary:
			_add_part(root, parts[i])

	var effects: Array = spec.get("effects") if spec.get("effects") is Array else []
	for i in mini(effects.size(), MAX_EFFECTS):
		if effects[i] is Dictionary:
			_add_effect(root, effects[i])
	Bricks.build(root, Bricks.expand(spec.get("bricks")))
	Mechanics.setup(root, spec)
	return root


## Проверяет описание до постройки. Возвращает текст ошибки или пустую строку.
static func validate(spec) -> String:
	if not spec is Dictionary:
		return "spec must be an object"
	var parts = spec.get("parts", [])
	var bricks = spec.get("bricks", [])
	if not parts is Array:
		return "spec.parts must be an array"
	if (not bricks is Array or bricks.is_empty()) and parts.is_empty():
		return "spec needs bricks (or parts for shapes that bricks cannot make)"
	var brick_problem := Bricks.validate(bricks)
	if brick_problem != "":
		return brick_problem
	if parts.size() > MAX_PARTS:
		return "too many parts (max %d)" % MAX_PARTS
	for i in parts.size():
		var p = parts[i]
		if not p is Dictionary:
			return "parts[%d] must be an object" % i
		if not str(p.get("shape", "")) in SHAPES:
			return "parts[%d].shape must be one of %s" % [i, ", ".join(SHAPES)]
	return Mechanics.validate(spec.get("mechanics"))


static func _add_part(root: Node3D, p: Dictionary) -> void:
	var mesh := _part_mesh(p)
	if mesh == null:
		return
	var rot := _vec(p.get("rotation"), Vector3.ZERO) * (PI / 180.0)
	var scl := _vec(p.get("scale"), Vector3.ONE).clamp(Vector3.ONE * 0.01, Vector3.ONE * MAX_SIZE)
	var pos := _vec(p.get("position"), Vector3.ZERO).clamp(-Vector3.ONE * MAX_SIZE, Vector3.ONE * MAX_SIZE)
	var xf := Transform3D(Basis.from_euler(rot).scaled(scl), pos)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = _material(p)
	# По id детали её находят анимации механик (колёса, пропеллер, дверь).
	var part_id := str(p.get("id", ""))
	if part_id != "":
		mi.set_meta("part_id", part_id)
	root.add_child(mi)

	var collide = p.get("collide", true)
	if root is CollisionObject3D and not (collide is bool and not collide):
		var col := CollisionShape3D.new()
		# Масштаб и поворот запекаются в форму: неравномерный масштаб
		# у CollisionShape3D физика не поддерживает.
		col.shape = Style.merge([[mesh, xf]]).create_convex_shape()
		if part_id != "":
			col.set_meta("part_id", part_id)
		root.add_child(col)
	_add_box_studs(mi, p, xf)


## Коробке без наклона сама добавляет шипы сверху, как у кирпича.
static func _add_box_studs(mi: MeshInstance3D, p: Dictionary, xf: Transform3D) -> void:
	if str(p.get("shape", "")) != "box" or p.get("studs") == false or str(p.get("material", "")) == "glow":
		return
	var rot := _vec(p.get("rotation"), Vector3.ZERO)
	if absf(rot.x) > 0.5 or absf(rot.z) > 0.5:
		return
	var size := _size(p) * _vec(p.get("scale"), Vector3.ONE).abs()
	var nx := int(floor(size.x / Style.STUD + 0.2))
	var nz := int(floor(size.z / Style.STUD + 0.2))
	if nx < 1 or nz < 1 or nx * nz > 400:
		return
	var parts := []
	for iz in nz:
		for ix in nx:
			var local := Vector3((ix + 0.5) * Style.STUD - nx * Style.STUD * 0.5, size.y * 0.5, (iz + 0.5) * Style.STUD - nz * Style.STUD * 0.5)
			parts.append([Style.stud_mesh(), Transform3D(Basis(), local)])
	var studs := MeshInstance3D.new()
	studs.mesh = Style.merge(parts)
	studs.material_override = mi.material_override
	# Шипы в своей системе координат: без масштаба детали, только поворот вокруг Y.
	studs.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(rot.y)), xf.origin)
	if mi.has_meta("part_id"):
		studs.set_meta("part_id", mi.get_meta("part_id"))
	mi.get_parent().add_child(studs)


static func _material(p: Dictionary) -> Material:
	var sway := clampf(_num(p.get("sway"), 0.0), 0.0, 0.3)
	return Style.part_material(p.get("color", "light_gray"), str(p.get("material", "")) == "glow", sway)


static func _part_mesh(p: Dictionary) -> Mesh:
	var r := _len(p.get("radius"), 0.5)
	var h := _len(p.get("height"), 1.0)
	match str(p.get("shape", "")):
		"box":
			return Style.box(_size(p))
		"prism":
			return Style.prism(_size(p))
		"sphere":
			return Style.sphere(r, 14, 8)
		"cylinder":
			return Style.cylinder(_len(p.get("top_radius"), r), r, h, 14)
		"cone":
			return Style.cylinder(0.0, r, h, 14)
		"capsule":
			var c := CapsuleMesh.new()
			c.radius = r
			c.height = maxf(h, r * 2.0)
			c.radial_segments = 14
			c.rings = 4
			return c
		"torus":
			var t := TorusMesh.new()
			t.outer_radius = r
			t.inner_radius = minf(_len(p.get("inner_radius"), r * 0.6), r * 0.95)
			t.rings = 16
			t.ring_segments = 8
			return t
		"lathe":
			return _lathe(p.get("profile"), clampi(int(_num(p.get("segments"), 16)), 3, 48))
		"extrude":
			return _extrude(p.get("outline"), h)
	return null


## Тело вращения: профиль [[радиус, высота], ...] снизу вверх вращается вокруг оси Y.
## Подходит для ваз, башен, колонн, бочек, куполов.
static func _lathe(profile, segments: int) -> Mesh:
	var pts: Array[Vector2] = []
	if profile is Array:
		for q in profile:
			if q is Array and q.size() >= 2:
				pts.append(Vector2(clampf(_num(q[0], 0.0), 0.0, MAX_SIZE), clampf(_num(q[1], 0.0), -MAX_SIZE, MAX_SIZE)))
	if pts.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		for i in pts.size() - 1:
			var v00 := Vector3(cos(a0) * pts[i].x, pts[i].y, sin(a0) * pts[i].x)
			var v10 := Vector3(cos(a1) * pts[i].x, pts[i].y, sin(a1) * pts[i].x)
			var v01 := Vector3(cos(a0) * pts[i + 1].x, pts[i + 1].y, sin(a0) * pts[i + 1].x)
			var v11 := Vector3(cos(a1) * pts[i + 1].x, pts[i + 1].y, sin(a1) * pts[i + 1].x)
			# Порядок вершин даёт лицевую сторону снаружи при профиле снизу вверх.
			_vert3(st, v00, v10, v01)
			_vert3(st, v10, v11, v01)
	st.index()
	st.generate_normals()
	return st.commit()


## Выдавленный контур: многоугольник [[x, z], ...] поднимается от земли на height.
## Подходит для стен сложной формы, платформ, оград, крыльев, вывесок.
static func _extrude(outline, height: float) -> Mesh:
	var poly := PackedVector2Array()
	if outline is Array:
		for q in outline:
			if q is Array and q.size() >= 2:
				poly.append(Vector2(clampf(_num(q[0], 0.0), -MAX_SIZE, MAX_SIZE), clampf(_num(q[1], 0.0), -MAX_SIZE, MAX_SIZE)))
	if poly.size() < 3:
		return null
	# Приводим контур к обходу против часовой стрелки в плоскости XZ.
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		poly.reverse()
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		_face(st, Vector3(a.x, height, a.y), Vector3(b.x, height, b.y), Vector3(c.x, height, c.y), Vector3.UP)
		_face(st, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(c.x, 0, c.y), Vector3.DOWN)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var out := Vector3(b.y - a.y, 0, -(b.x - a.x))
		var a0 := Vector3(a.x, 0, a.y)
		var b0 := Vector3(b.x, 0, b.y)
		var a1 := Vector3(a.x, height, a.y)
		var b1 := Vector3(b.x, height, b.y)
		_face(st, a0, b0, a1, out)
		_face(st, b0, b1, a1, out)
	st.generate_normals()
	return st.commit()


## Добавляет треугольник так, чтобы лицевая сторона смотрела в сторону out.
## В Godot лицевая сторона обходится по часовой стрелке, поэтому векторное
## произведение (b - a) x (c - a) у неё направлено внутрь.
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		_vert3(st, a, c, b)
	else:
		_vert3(st, a, b, c)


static func _vert3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_uv(Vector2(v.x, v.y))
		st.add_vertex(v)


static func _add_effect(root: Node3D, e: Dictionary) -> void:
	var pos := _vec(e.get("position"), Vector3.ZERO).clamp(-Vector3.ONE * MAX_SIZE, Vector3.ONE * MAX_SIZE)
	match str(e.get("type", "")):
		"smoke":
			Style.smoke(root, pos, clampf(_num(e.get("size"), 0.5), 0.1, 2.0))
		"light":
			var l := OmniLight3D.new()
			l.position = pos
			l.light_color = Color(1.0, 0.9, 0.7)
			l.light_energy = clampf(_num(e.get("energy"), 1.2), 0.1, 4.0)
			l.omni_range = clampf(_num(e.get("range"), 6.0), 1.0, 20.0)
			root.add_child(l)


static func _size(p: Dictionary) -> Vector3:
	return _vec(p.get("size"), Vector3.ONE).clamp(Vector3.ONE * 0.01, Vector3.ONE * MAX_SIZE)


static func _len(v, fallback: float) -> float:
	return clampf(_num(v, fallback), 0.01, MAX_SIZE)


static func _num(v, fallback: float) -> float:
	return float(v) if (v is float or v is int) else fallback


static func _vec(v, fallback: Vector3) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(_num(v[0], 0.0), _num(v[1], 0.0), _num(v[2], 0.0))
	return fallback
