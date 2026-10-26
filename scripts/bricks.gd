extends RefCounted
## Кирпичи Lego в описании объекта (spec.bricks): ИИ-агент раскладывает
## кирпичи по сетке шипов, а игра склеивает их в один меш с цветом в вершинах,
## сама ставит шипы на открытые сверху грани и делает коллизию.
##
## Координаты: x и z в шипах (0,4 м), y в пластинах (0,16 м), начало объекта
## на углу клетки сетки, y = 0 это земля. Кирпич задаётся минимальным углом:
##   {"type": "brick", "at": [x, y, z], "size": [w, d], "color": "red"}
## type: brick (3 пластины), plate (1), tile (1, гладкая), slope (скос),
##       round (круглый), cone (конус). "h" меняет высоту в пластинах,
##       "dir" задаёт, куда спускается скос (+x, -x, +z, -z), "studs": false
##       убирает шипы, "id" делает группу кирпичей подвижной деталью.
## Крупные команды сами разбиваются на кирпичи с перевязкой:
##   {"type": "box", "from": [x, y, z], "to": [x, y, z], "hollow": true}
##   {"type": "wall", "from": [x, z], "to": [x, z], "y": 0, "height": 9,
##    "openings": [{"at": 2, "width": 2, "y": 3, "height": 6, "fill": "glass"}]}
##   {"type": "roof", "from": [x, z], "to": [x, z], "y": 9, "ridge": "x"}
##   {"type": "tower", "center": [x, z], "radius": 4, "y": 0, "height": 18}

const Style := preload("res://scripts/style.gd")

const MAX_BRICKS := 6000
const MAX_VOXELS := 60000
const MAX_COORD := 512
const TYPES := ["brick", "plate", "tile", "slope", "round", "cone"]
const MACROS := ["box", "wall", "roof", "tower"]
const DEFAULT_H := {"brick": 3, "plate": 1, "tile": 1, "slope": 3, "round": 3, "cone": 3}
const DIRS := ["+x", "-x", "+z", "-z"]
## Сколько отдельных форм коллизии получает подвижный объект из кирпичей.
const MAX_BOX_COLLIDERS := 48


## Проверяет spec.bricks. Возвращает текст ошибки или пустую строку.
static func validate(list) -> String:
	if list == null:
		return ""
	if not list is Array:
		return "spec.bricks must be an array"
	if list.size() > MAX_BRICKS:
		return "too many bricks (max %d)" % MAX_BRICKS
	var voxels := 0
	for i in list.size():
		var b = list[i]
		if not b is Dictionary:
			return "bricks[%d] must be an object" % i
		var type := str(b.get("type", "brick"))
		if type in MACROS:
			var problem := _validate_macro(b, type)
			if problem != "":
				return "bricks[%d]: %s" % [i, problem]
			voxels += _macro_volume(b, type)
			continue
		if not type in TYPES:
			return "bricks[%d].type must be one of %s" % [i, ", ".join(TYPES + MACROS)]
		if not _ints(b.get("at"), 3):
			return "bricks[%d].at must be [x, y, z] in studs and plates" % i
		if b.has("size") and not _ints(b.get("size"), 2):
			return "bricks[%d].size must be [w, d] in studs" % i
		if b.has("dir") and not str(b.dir) in DIRS:
			return "bricks[%d].dir must be one of %s" % [i, ", ".join(DIRS)]
	if voxels > MAX_VOXELS:
		return "box, wall and tower commands cover too much volume (%d of %d stud-plates); use hollow boxes or fewer layers" % [voxels, MAX_VOXELS]
	return ""


static func _validate_macro(b: Dictionary, type: String) -> String:
	match type:
		"box":
			if not _ints(b.get("from"), 3) or not _ints(b.get("to"), 3):
				return "box needs from and to as [x, y, z]"
		"wall", "roof":
			if not _ints(b.get("from"), 2) or not _ints(b.get("to"), 2):
				return "%s needs from and to as [x, z]" % type
			if type == "wall":
				var f: Array = b.from
				var t: Array = b.to
				if int(f[0]) != int(t[0]) and int(f[1]) != int(t[1]):
					return "wall must run along x or along z (from and to share x or z)"
		"tower":
			if not _ints(b.get("center"), 2):
				return "tower needs center as [x, z]"
	return ""


static func _macro_volume(b: Dictionary, type: String) -> int:
	match type:
		"box":
			var f: Array = b.from
			var t: Array = b.to
			var dx := absi(int(t[0]) - int(f[0]))
			var dy := absi(int(t[1]) - int(f[1]))
			var dz := absi(int(t[2]) - int(f[2]))
			if b.get("hollow") == true:
				return (dx + dz) * 2 * dy
			return dx * dy * dz
		"wall":
			var f: Array = b.from
			var t: Array = b.to
			var length := absi(int(t[0]) - int(f[0])) + absi(int(t[1]) - int(f[1]))
			return length * clampi(_int(b.get("thickness"), 1), 1, 4) * clampi(_int(b.get("height"), 9), 1, 120)
		"tower":
			var r := clampi(_int(b.get("radius"), 3), 1, 32)
			return int(TAU * r) * clampi(_int(b.get("height"), 9), 1, 120)
	return 0


# --- Разворачивание команд в кирпичи --------------------------------------

## Превращает spec.bricks в список простых кирпичей:
## {"type", "x", "y", "z", "w", "d", "h", "color", "dir", "studs", "id"}.
static func expand(list) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not list is Array:
		return out
	for b in list:
		if out.size() >= MAX_BRICKS:
			break
		if not b is Dictionary:
			continue
		var type := str(b.get("type", "brick"))
		var color := Style.color_name(b.get("color", "light_gray"))
		var id := str(b.get("id", ""))
		match type:
			"box":
				_paint_box(out, b, color, id)
			"wall":
				_paint_wall(out, b, color, id)
			"roof":
				_roof(out, b, color, id)
			"tower":
				_paint_tower(out, b, color, id)
			_:
				if not type in TYPES or not _ints(b.get("at"), 3):
					continue
				var at: Array = b.at
				var size = b.get("size", [2, 2] if type in ["round", "cone"] else [2, 4])
				if not _ints(size, 2):
					size = [2, 2]
				var w := clampi(int(size[0]), 1, 64)
				var d := clampi(int(size[1]), 1, 64)
				if type in ["round", "cone"]:
					d = w
				out.append({
					"type": type,
					"x": clampi(_int(at[0], 0), -MAX_COORD, MAX_COORD),
					"y": clampi(_int(at[1], 0), -60, 600),
					"z": clampi(_int(at[2], 0), -MAX_COORD, MAX_COORD),
					"w": w, "d": d,
					"h": clampi(_int(b.get("h"), DEFAULT_H[type]), 1, 60),
					"color": color,
					"dir": str(b.get("dir", "+z")) if str(b.get("dir", "+z")) in DIRS else "+z",
					"studs": b.get("studs", true) != false and type != "tile",
					"id": id,
				})
	if out.size() > MAX_BRICKS:
		out.resize(MAX_BRICKS)
	return out


static func _paint_box(out: Array[Dictionary], b: Dictionary, color: String, id: String) -> void:
	var f: Array = b.from
	var t: Array = b.to
	var x0 := mini(int(f[0]), int(t[0]))
	var x1 := maxi(int(f[0]), int(t[0]))
	var y0 := mini(int(f[1]), int(t[1]))
	var y1 := maxi(int(f[1]), int(t[1]))
	var z0 := mini(int(f[2]), int(t[2]))
	var z1 := maxi(int(f[2]), int(t[2]))
	var hollow: bool = b.get("hollow") == true
	var vox := {}
	for y in range(y0, y1):
		for z in range(z0, z1):
			for x in range(x0, x1):
				if hollow and x != x0 and x != x1 - 1 and z != z0 and z != z1 - 1:
					continue
				vox[Vector3i(x, y, z)] = color
	_to_bricks(out, vox, y0, id, b.get("studs", true) != false)


static func _paint_wall(out: Array[Dictionary], b: Dictionary, color: String, id: String) -> void:
	var f: Array = b.from
	var t: Array = b.to
	var along_x := int(f[1]) == int(t[1])
	var a0 := mini(int(f[0]), int(t[0])) if along_x else mini(int(f[1]), int(t[1]))
	var a1 := maxi(int(f[0]), int(t[0])) if along_x else maxi(int(f[1]), int(t[1]))
	var across := int(f[1]) if along_x else int(f[0])
	var thick := clampi(_int(b.get("thickness"), 1), 1, 4)
	var y0 := _int(b.get("y"), 0)
	var height := clampi(_int(b.get("height"), 9), 1, 120)
	var openings: Array = b.get("openings") if b.get("openings") is Array else []
	var vox := {}
	for y in range(y0, y0 + height):
		for a in range(a0, maxi(a1, a0 + 1)):
			var fill = color
			for o in openings:
				if not o is Dictionary:
					continue
				var oa := a0 + _int(o.get("at"), 0)
				var oy := y0 + _int(o.get("y"), 0)
				if a >= oa and a < oa + clampi(_int(o.get("width"), 2), 1, 64) and y >= oy and y < oy + clampi(_int(o.get("height"), 6), 1, 120):
					fill = Style.color_name(o.fill) if o.get("fill") is String and str(o.fill) != "none" else null
			if fill == null:
				continue
			for k in thick:
				var key := Vector3i(a, y, across + k) if along_x else Vector3i(across + k, y, a)
				vox[key] = fill
	_to_bricks(out, vox, y0, id, b.get("studs", true) != false)


static func _paint_tower(out: Array[Dictionary], b: Dictionary, color: String, id: String) -> void:
	var c: Array = b.center
	var cx := float(int(c[0]))
	var cz := float(int(c[1]))
	var r := clampi(_int(b.get("radius"), 3), 1, 32)
	var thick := clampi(_int(b.get("thickness"), 1), 1, r)
	var y0 := _int(b.get("y"), 0)
	var height := clampi(_int(b.get("height"), 9), 1, 120)
	var filled: bool = b.get("hollow") == false
	var cells: Array[Vector2i] = []
	for z in range(int(cz) - r, int(cz) + r):
		for x in range(int(cx) - r, int(cx) + r):
			var d := Vector2(x + 0.5 - cx, z + 0.5 - cz).length()
			if d < r and (filled or d >= r - thick):
				cells.append(Vector2i(x, z))
	var vox := {}
	for y in range(y0, y0 + height):
		for cell in cells:
			vox[Vector3i(cell.x, y, cell.y)] = color
	_to_bricks(out, vox, y0, id, b.get("studs", true) != false)


## Двускатная крыша из скосов: каждый ряд на шип уже и на кирпич выше,
## под скосами подложка, сверху конёк. "flat": true даёт плоскую крышу.
static func _roof(out: Array[Dictionary], b: Dictionary, color: String, id: String) -> void:
	var f: Array = b.from
	var t: Array = b.to
	var x0 := mini(int(f[0]), int(t[0]))
	var x1 := maxi(int(f[0]), int(t[0]))
	var z0 := mini(int(f[1]), int(t[1]))
	var z1 := maxi(int(f[1]), int(t[1]))
	var y := _int(b.get("y"), 0)
	if x1 <= x0 or z1 <= z0:
		return
	var vox := {}
	if b.get("flat") == true or str(b.get("style", "")) == "flat":
		for z in range(z0, z1):
			for x in range(x0, x1):
				vox[Vector3i(x, y, z)] = color
		_to_bricks(out, vox, y, id, true)
		return
	# Конёк вдоль длинной стороны, если не сказано иначе.
	var ridge_x := str(b.get("ridge", "x" if (x1 - x0) >= (z1 - z0) else "z")) == "x"
	var length := (x1 - x0) if ridge_x else (z1 - z0)
	var span := (z1 - z0) if ridge_x else (x1 - x0)
	var a0 := x0 if ridge_x else z0
	var s0 := z0 if ridge_x else x0
	var steps := span / 2
	for k in steps:
		var level := y + k * 3
		for side in 2:
			var s := s0 + k if side == 0 else s0 + span - 1 - k
			# Скос спускается наружу: у ближнего края к меньшей координате.
			var dir := ("-z" if side == 0 else "+z") if ridge_x else ("-x" if side == 0 else "+x")
			for seg in _segments(length, 4):
				var w: int = seg[1] if ridge_x else 1
				var d: int = 1 if ridge_x else seg[1]
				var bx: int = (a0 + seg[0]) if ridge_x else s
				var bz: int = s if ridge_x else (a0 + seg[0])
				out.append(_brick("slope", bx, level, bz, w, d, 3, color, dir, false, id))
				if k > 0:
					out.append(_brick("brick", bx, level - 3, bz, w, d, 3, color, "+z", false, id))
	# Конёк: если пролёт нечётный, остаётся ряд шириной в шип.
	if span % 2 == 1:
		var s := s0 + steps
		for seg in _segments(length, 4):
			var bx: int = (a0 + seg[0]) if ridge_x else s
			var bz: int = s if ridge_x else (a0 + seg[0])
			var w: int = seg[1] if ridge_x else 1
			var d: int = 1 if ridge_x else seg[1]
			out.append(_brick("brick", bx, y + steps * 3, bz, w, d, 3, color, "+z", true, id))
			if steps > 0:
				out.append(_brick("brick", bx, y + (steps - 1) * 3, bz, w, d, 3, color, "+z", false, id))


## Отрезки длины n кусками не длиннее step: [[начало, длина], ...].
static func _segments(n: int, step: int) -> Array:
	var out := []
	var a := 0
	while a < n:
		var l := mini(step, n - a)
		out.append([a, l])
		a += l
	return out


## Раскладывает воксели (клетка шипа × пластина) на кирпичи: полные столбики
## в три пластины становятся кирпичами, остальное пластинами. Слои считаются
## от base, соседние слои укладываются по-разному, получается перевязка.
static func _to_bricks(out: Array[Dictionary], vox: Dictionary, base: int, id: String, studs: bool) -> void:
	if vox.is_empty():
		return
	var y_min := 1000000
	var y_max := -1000000
	for key: Vector3i in vox:
		y_min = mini(y_min, key.y)
		y_max = maxi(y_max, key.y)
	var layer := base + floori(float(y_min - base) / 3.0) * 3
	var parity := 0
	while layer <= y_max:
		# Клетки, где все три пластины одного цвета, идут в кирпичи.
		var full := {}
		var rest := {}
		for key: Vector3i in vox:
			if key.y < layer or key.y >= layer + 3:
				continue
			var cell := Vector2i(key.x, key.z)
			if full.has(cell) or rest.has(cell):
				continue
			var c0 = vox.get(Vector3i(key.x, layer, key.z))
			var c1 = vox.get(Vector3i(key.x, layer + 1, key.z))
			var c2 = vox.get(Vector3i(key.x, layer + 2, key.z))
			if c0 != null and c0 == c1 and c1 == c2:
				full[cell] = c0
			else:
				rest[cell] = true
		for rect in _tile(full, parity):
			out.append(_brick("brick", rect[0], layer, rect[1], rect[2], rect[3], 3, rect[4], "+z", studs, id))
		for py in range(layer, layer + 3):
			var plates := {}
			for cell: Vector2i in rest:
				var c = vox.get(Vector3i(cell.x, py, cell.y))
				if c != null:
					plates[cell] = c
			for rect in _tile(plates, parity + py):
				out.append(_brick("plate", rect[0], py, rect[1], rect[2], rect[3], 1, rect[4], "+z", studs, id))
		layer += 3
		parity += 1
		if out.size() >= MAX_BRICKS:
			return


## Жадно покрывает клетки одного цвета прямоугольниками стандартных размеров.
## Возвращает [[x, z, w, d, цвет], ...]. Чётность меняет порядок обхода и
## ориентацию, чтобы швы соседних слоёв не совпадали.
static func _tile(cells: Dictionary, parity: int) -> Array:
	var out := []
	var keys: Array = cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	if parity % 2 == 1:
		keys.reverse()
	var sizes := [Vector2i(4, 2), Vector2i(2, 4), Vector2i(2, 2), Vector2i(4, 1), Vector2i(1, 4), Vector2i(3, 1), Vector2i(1, 3), Vector2i(2, 1), Vector2i(1, 2), Vector2i(1, 1)]
	if parity % 2 == 1:
		sizes = [Vector2i(2, 4), Vector2i(4, 2), Vector2i(2, 2), Vector2i(1, 4), Vector2i(4, 1), Vector2i(1, 3), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(1, 1)]
	var used := {}
	var step := -1 if parity % 2 == 1 else 1
	for cell: Vector2i in keys:
		if used.has(cell):
			continue
		var color = cells[cell]
		for s: Vector2i in sizes:
			var ok := true
			for dz in s.y:
				for dx in s.x:
					var c := Vector2i(cell.x + dx * step, cell.y + dz * step)
					if used.has(c) or cells.get(c) != color:
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue
			for dz in s.y:
				for dx in s.x:
					used[Vector2i(cell.x + dx * step, cell.y + dz * step)] = true
			var x := cell.x if step > 0 else cell.x - s.x + 1
			var z := cell.y if step > 0 else cell.y - s.y + 1
			out.append([x, z, s.x, s.y, color])
			break
	return out


static func _brick(type: String, x: int, y: int, z: int, w: int, d: int, h: int, color: String, dir: String, studs: bool, id: String) -> Dictionary:
	return {"type": type, "x": x, "y": y, "z": z, "w": w, "d": d, "h": h, "color": color, "dir": dir, "studs": studs, "id": id}


# --- Меш, шипы, коллизия --------------------------------------------------

## Добавляет кирпичи к корню объекта: меш по каждой группе (id), шипы и коллизию.
static func build(root: Node3D, bricks: Array[Dictionary]) -> void:
	if bricks.is_empty():
		return
	# Где кирпич накрыт сверху: ключ (x, нижний уровень, z) занятой клетки.
	var covered := {}
	for b in bricks:
		for dz in b.d:
			for dx in b.w:
				covered[Vector3i(b.x + dx, b.y, b.z + dz)] = true
	var groups := {}
	for b in bricks:
		if not groups.has(b.id):
			groups[b.id] = []
		groups[b.id].append(b)
	var physical := root is CollisionObject3D
	var boxes := 0
	for id: String in groups:
		var arrays := {"solid": _new_arrays(), "trans": _new_arrays(), "metal": _new_arrays()}
		var studs := {"solid": [], "trans": [], "metal": []}
		var faces := PackedVector3Array()
		for b: Dictionary in groups[id]:
			var k := Style.kind(b.color)
			var col := Style.vertex_color(b.color)
			_append_brick(arrays[k], b, col)
			if b.studs:
				for p in _stud_positions(b, covered):
					studs[k].append([p, col])
			if physical:
				_box_faces(faces, _brick_aabb(b))
		var mi := MeshInstance3D.new()
		var mesh := ArrayMesh.new()
		for k: String in arrays:
			var a: Array = arrays[k]
			# Студы маленьких подвижных групп вклеиваются в меш, чтобы двигаться вместе.
			if id != "":
				for s in studs[k]:
					_append_stud(a, s[0], s[1])
			if (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mesh.surface_set_material(mesh.get_surface_count() - 1, Style.plastic(k))
		if mesh.get_surface_count() == 0:
			continue
		mi.mesh = mesh
		mi.name = ("Bricks_" + id) if id != "" else "Bricks"
		if id != "":
			mi.set_meta("part_id", id)
		root.add_child(mi)
		if id == "":
			for k: String in studs:
				if studs[k].is_empty():
					continue
				var xfs: Array[Transform3D] = []
				var cols: Array[Color] = []
				for s in studs[k]:
					xfs.append(Transform3D(Basis(), s[0]))
					cols.append(s[1])
				var mmi := Style.multimesh(root, Style.stud_mesh(), Style.plastic(k), xfs, cols)
				mmi.name = "Studs_" + k
				# Дальние шипы не видны, их не рисуем.
				mmi.visibility_range_end = 70.0
				mmi.visibility_range_end_margin = 10.0
		if physical:
			if root is StaticBody3D:
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(faces)
				# Прицел и камера должны видеть стены с любой стороны.
				shape.backface_collision = true
				var cs := CollisionShape3D.new()
				cs.shape = shape
				if id != "":
					cs.set_meta("part_id", id)
				root.add_child(cs)
			else:
				var list: Array = groups[id]
				if list.size() + boxes <= MAX_BOX_COLLIDERS:
					for b: Dictionary in list:
						var box := _brick_aabb(b)
						var cs := CollisionShape3D.new()
						var shape := BoxShape3D.new()
						shape.size = box.size
						cs.shape = shape
						cs.position = box.get_center()
						if id != "":
							cs.set_meta("part_id", id)
						root.add_child(cs)
						boxes += 1
				else:
					var shape := ConvexPolygonShape3D.new()
					shape.points = faces
					var cs := CollisionShape3D.new()
					cs.shape = shape
					if id != "":
						cs.set_meta("part_id", id)
					root.add_child(cs)


## Габариты кирпичей в метрах относительно начала объекта.
static func bounds(bricks: Array[Dictionary]) -> AABB:
	var box := AABB()
	for i in bricks.size():
		var b := _brick_aabb(bricks[i])
		box = b if i == 0 else box.merge(b)
	return box


static func _brick_aabb(b: Dictionary) -> AABB:
	var S := Style.STUD
	var P := Style.PLATE
	return AABB(Vector3(b.x * S, b.y * P, b.z * S), Vector3(b.w * S, b.h * P, b.d * S))


static func _new_arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	a[Mesh.ARRAY_COLOR] = PackedColorArray()
	return a


static func _stud_positions(b: Dictionary, covered: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var S := Style.STUD
	var top: float = (b.y + b.h) * Style.PLATE
	match b.type:
		"cone":
			if not covered.has(Vector3i(b.x + b.w / 2, b.y + b.h, b.z + b.d / 2)):
				out.append(Vector3((b.x + b.w * 0.5) * S, top, (b.z + b.d * 0.5) * S))
			return out
		"slope":
			# Шипы только на верхней полосе скоса, у его высокой стороны.
			if (b.dir in ["+z", "-z"] and b.d < 2) or (b.dir in ["+x", "-x"] and b.w < 2):
				return out
	for dz in b.d:
		for dx in b.w:
			if b.type == "slope":
				var row: int = {"+z": dz, "-z": b.d - 1 - dz, "+x": dx, "-x": b.w - 1 - dx}[b.dir]
				if row != 0:
					continue
			if b.type == "round":
				var off := Vector2(dx + 0.5 - b.w * 0.5, dz + 0.5 - b.d * 0.5)
				if off.length() > b.w * 0.5 - 0.3:
					continue
			if covered.has(Vector3i(b.x + dx, b.y + b.h, b.z + dz)):
				continue
			out.append(Vector3((b.x + dx + 0.5) * S, top, (b.z + dz + 0.5) * S))
	return out


static func _append_brick(a: Array, b: Dictionary, col: Color) -> void:
	var box := _brick_aabb(b)
	var g := Style.GAP * 0.5
	box = box.grow(-g)
	match b.type:
		"slope":
			_append_slope(a, box, b.dir, col, b.h)
		"round":
			_append_cylinder(a, box, 1.0, col)
		"cone":
			_append_cylinder(a, box, 0.3, col)
		_:
			append_bevel_box(a, box, col)


## Кирпич со скруглёнными рёбрами: на скосах рёбер играет блик, как у пластика.
static func append_bevel_box(a: Array, box: AABB, col: Color, bevel := Style.BEVEL) -> void:
	var h := box.size * 0.5
	var c := box.get_center()
	var bv := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.5)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var cl: PackedColorArray = a[Mesh.ARRAY_COLOR]
	# Отпускаем ссылки в массиве, иначе каждое добавление копирует весь буфер.
	a[Mesh.ARRAY_VERTEX] = null
	a[Mesh.ARRAY_NORMAL] = null
	a[Mesh.ARRAY_COLOR] = null
	var hi := [h.x, h.y, h.z]
	# Грани.
	for axis in 3:
		for s: float in [-1.0, 1.0]:
			var u := (axis + 1) % 3
			var w := (axis + 2) % 3
			var q := []
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = s * hi[axis]
				p[u] = corner.x * (hi[u] - bv)
				p[w] = corner.y * (hi[w] - bv)
				q.append(c + p)
			var nn := Vector3.ZERO
			nn[axis] = s
			_quad(v, n, cl, q[0], q[1], q[2], q[3], nn, col)
	# Скошенные рёбра.
	for i in 3:
		var j := (i + 1) % 3
		var k := (i + 2) % 3
		for si: float in [-1.0, 1.0]:
			for sj: float in [-1.0, 1.0]:
				var q := []
				for sk: float in [-1.0, 1.0]:
					var p1 := Vector3.ZERO
					p1[i] = si * hi[i]
					p1[j] = sj * (hi[j] - bv)
					p1[k] = sk * (hi[k] - bv)
					var p2 := Vector3.ZERO
					p2[i] = si * (hi[i] - bv)
					p2[j] = sj * hi[j]
					p2[k] = sk * (hi[k] - bv)
					q.append(c + p1)
					q.append(c + p2)
				var nn := Vector3.ZERO
				nn[i] = si
				nn[j] = sj
				_quad(v, n, cl, q[0], q[1], q[3], q[2], nn.normalized(), col)
	# Уголки.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				var px := c + Vector3(sx * h.x, sy * (h.y - bv), sz * (h.z - bv))
				var py := c + Vector3(sx * (h.x - bv), sy * h.y, sz * (h.z - bv))
				var pz := c + Vector3(sx * (h.x - bv), sy * (h.y - bv), sz * h.z)
				_tri(v, n, cl, px, py, pz, s.normalized(), col)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_COLOR] = cl


## Скос: профиль сбоку выдавлен поперёк направления спуска dir.
static func _append_slope(a: Array, box: AABB, dir: String, col: Color, h_plates: int) -> void:
	var along_z := dir in ["+z", "-z"]
	var L := box.size.z if along_z else box.size.x
	var W := box.size.x if along_z else box.size.z
	var H := box.size.y
	var top := Style.STUD if L > Style.STUD * 1.5 else 0.0
	var low := minf(Style.PLATE, H * 0.5) if h_plates > 1 else 0.0
	# Точка профиля (t вдоль спуска от высокой стороны, y) и s поперёк в мир.
	var to_world := func(t: float, y: float, s: float) -> Vector3:
		var p := box.position
		match dir:
			"+z":
				return Vector3(p.x + s, p.y + y, p.z + t)
			"-z":
				return Vector3(p.x + s, p.y + y, p.z + L - t)
			"+x":
				return Vector3(p.x + t, p.y + y, p.z + s)
			_:
				return Vector3(p.x + L - t, p.y + y, p.z + s)
	var prof := [Vector2(0, 0), Vector2(L, 0), Vector2(L, low), Vector2(top, H), Vector2(0, H)]
	var center: Vector3 = box.get_center()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var cl: PackedColorArray = a[Mesh.ARRAY_COLOR]
	# Отпускаем ссылки в массиве, иначе каждое добавление копирует весь буфер.
	a[Mesh.ARRAY_VERTEX] = null
	a[Mesh.ARRAY_NORMAL] = null
	a[Mesh.ARRAY_COLOR] = null
	# Боковины: веер треугольников из первой точки.
	for s: float in [0.0, W]:
		for i in range(1, prof.size() - 1):
			var p0: Vector3 = to_world.call(prof[0].x, prof[0].y, s)
			var p1: Vector3 = to_world.call(prof[i].x, prof[i].y, s)
			var p2: Vector3 = to_world.call(prof[i + 1].x, prof[i + 1].y, s)
			var out_n: Vector3 = to_world.call(0, 0, s) - to_world.call(0, 0, W - s)
			if (p1 - p0).cross(p2 - p0).length() < 0.000001:
				continue
			_tri(v, n, cl, p0, p1, p2, out_n.normalized(), col)
	# Полосы между соседними точками профиля.
	for i in prof.size():
		var q0: Vector2 = prof[i]
		var q1: Vector2 = prof[(i + 1) % prof.size()]
		if q0.distance_to(q1) < 0.0001:
			continue
		var p00: Vector3 = to_world.call(q0.x, q0.y, 0.0)
		var p10: Vector3 = to_world.call(q1.x, q1.y, 0.0)
		var p11: Vector3 = to_world.call(q1.x, q1.y, W)
		var p01: Vector3 = to_world.call(q0.x, q0.y, W)
		var mid := (p00 + p11) * 0.5
		var out_n := (p10 - p00).cross(p01 - p00).normalized()
		if out_n.dot(mid - center) < 0.0:
			out_n = -out_n
		_quad(v, n, cl, p00, p10, p11, p01, out_n, col)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_COLOR] = cl


## Круглый кирпич (top = 1) или конус (top < 1) в габаритах box.
static func _append_cylinder(a: Array, box: AABB, top: float, col: Color) -> void:
	var c := box.get_center()
	var r := minf(box.size.x, box.size.z) * 0.5
	var y0 := box.position.y
	var y1 := box.end.y
	var seg := 20 if r > 0.5 else 14
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var cl: PackedColorArray = a[Mesh.ARRAY_COLOR]
	# Отпускаем ссылки в массиве, иначе каждое добавление копирует весь буфер.
	a[Mesh.ARRAY_VERTEX] = null
	a[Mesh.ARRAY_NORMAL] = null
	a[Mesh.ARRAY_COLOR] = null
	var rt := r * top
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := Vector3(c.x, y0, c.z) + d0 * r
		var b1 := Vector3(c.x, y0, c.z) + d1 * r
		var t0 := Vector3(c.x, y1, c.z) + d0 * rt
		var t1 := Vector3(c.x, y1, c.z) + d1 * rt
		var side := ((d0 + d1) * 0.5).normalized()
		side.y = (r - rt) / maxf(y1 - y0, 0.01)
		_quad(v, n, cl, b0, b1, t1, t0, side.normalized(), col)
		_tri(v, n, cl, Vector3(c.x, y1, c.z), t0, t1, Vector3.UP, col)
		_tri(v, n, cl, Vector3(c.x, y0, c.z), b0, b1, Vector3.DOWN, col)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_COLOR] = cl


## Вклеивает шип в меш группы (для подвижных деталей).
static func _append_stud(a: Array, pos: Vector3, col: Color) -> void:
	var src := Style.stud_mesh().surface_get_arrays(0)
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var idx = src[Mesh.ARRAY_INDEX]
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var cl: PackedColorArray = a[Mesh.ARRAY_COLOR]
	# Отпускаем ссылки в массиве, иначе каждое добавление копирует весь буфер.
	a[Mesh.ARRAY_VERTEX] = null
	a[Mesh.ARRAY_NORMAL] = null
	a[Mesh.ARRAY_COLOR] = null
	if idx is PackedInt32Array and not idx.is_empty():
		for i in idx:
			v.append(sv[i] + pos)
			n.append(sn[i])
			cl.append(col)
	else:
		for i in sv.size():
			v.append(sv[i] + pos)
			n.append(sn[i])
			cl.append(col)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_COLOR] = cl


## Треугольник, лицевой стороной к out. В Godot лицевая сторона обходится
## по часовой стрелке, у неё (b - a) x (c - a) смотрит внутрь.
static func _tri(v: PackedVector3Array, n: PackedVector3Array, cl: PackedColorArray, p0: Vector3, p1: Vector3, p2: Vector3, out: Vector3, col: Color) -> void:
	if (p1 - p0).cross(p2 - p0).dot(out) > 0.0:
		var t := p1
		p1 = p2
		p2 = t
	v.append(p0)
	v.append(p1)
	v.append(p2)
	for i in 3:
		n.append(out)
		cl.append(col)


static func _quad(v: PackedVector3Array, n: PackedVector3Array, cl: PackedColorArray, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, out: Vector3, col: Color) -> void:
	_tri(v, n, cl, p0, p1, p2, out, col)
	_tri(v, n, cl, p0, p2, p3, out, col)


## Треугольники коробки для коллизии.
static func _box_faces(faces: PackedVector3Array, box: AABB) -> void:
	var p := box.position
	var e := box.end
	var c := [
		Vector3(p.x, p.y, p.z), Vector3(e.x, p.y, p.z), Vector3(e.x, p.y, e.z), Vector3(p.x, p.y, e.z),
		Vector3(p.x, e.y, p.z), Vector3(e.x, e.y, p.z), Vector3(e.x, e.y, e.z), Vector3(p.x, e.y, e.z),
	]
	for f in [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]:
		faces.append(c[f[0]])
		faces.append(c[f[1]])
		faces.append(c[f[2]])
		faces.append(c[f[0]])
		faces.append(c[f[2]])
		faces.append(c[f[3]])


static func _ints(v, count: int) -> bool:
	if not v is Array or v.size() < count:
		return false
	for i in count:
		if not (v[i] is int or v[i] is float):
			return false
	return true


static func _int(v, fallback: int) -> int:
	return int(round(float(v))) if (v is float or v is int) else fallback
