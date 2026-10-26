extends RefCounted
## Общий стиль мира в духе Lego: размеры кирпичей, палитра настоящих цветов,
## материалы глянцевого пластика и простые меши. Всё, что появляется в мире,
## в том числе объекты от ИИ-агентов, строится через эти функции, поэтому
## мир выглядит цельно.

const PLASTIC := preload("res://shaders/plastic.gdshader")
const PLASTIC_TRANS := preload("res://shaders/plastic_trans.gdshader")
const PLASTIC_METAL := preload("res://shaders/plastic_metal.gdshader")

## Шаг шипов, высота пластины и кирпича в метрах. Три пластины = кирпич,
## как в настоящем Lego, а миньфигурка выходит ростом около четырёх кирпичей.
const STUD := 0.4
const PLATE := 0.16
const BRICK := 0.48
const STUD_RADIUS := 0.12
const STUD_HEIGHT := 0.075
## Зазор между соседними кирпичами: по нему видно, где кончается деталь.
const GAP := 0.006
## Скругление рёбер кирпича.
const BEVEL := 0.018

## Палитра настоящих цветов Lego (sRGB). Любой цвет от ИИ приводится к ней.
const COLORS := {
	"red": Color("c91a09"),
	"blue": Color("0055bf"),
	"yellow": Color("f2cd37"),
	"white": Color("f4f4f4"),
	"black": Color("1b2a34"),
	"green": Color("237841"),
	"light_gray": Color("a0a5a9"),
	"dark_gray": Color("6c6e68"),
	"dark_green": Color("184632"),
	"lime": Color("a5ca18"),
	"brown": Color("582a12"),
	"dark_brown": Color("352100"),
	"tan": Color("e4cd9e"),
	"sand": Color("958a73"),
	"orange": Color("fe8a18"),
	"pink": Color("e4adc8"),
	"purple": Color("923978"),
	"azure": Color("36aebf"),
	"light_blue": Color("9fc3e9"),
	"dark_blue": Color("0a3463"),
	"dark_red": Color("720e0f"),
	"glass": Color("e8f4f8"),
	"trans_blue": Color("3f8fd8"),
	"trans_orange": Color("f08f1c"),
	"trans_yellow": Color("f5cd2f"),
	"trans_red": Color("e02a1a"),
	"trans_green": Color("6fd16a"),
	"gold": Color("dbac34"),
	"silver": Color("b4b8ba"),
}
const TRANSPARENT := ["glass", "trans_blue", "trans_orange", "trans_yellow", "trans_red", "trans_green"]
const METALLIC := ["gold", "silver"]
## Светятся сами: огонь, лампы, окна ночью.
const GLOWING := ["trans_orange", "trans_yellow"]

## Названия из старой палитры и обычные слова, которые часто пишут агенты.
const ALIASES := {
	"grass": "green", "grass_light": "lime", "grass_blade": "green", "leaf": "green",
	"leaf_light": "lime", "bush": "dark_green", "pine": "dark_green", "path": "tan",
	"cliff": "dark_gray", "rock": "light_gray", "rock_dark": "dark_gray", "mountain": "dark_gray",
	"bark": "brown", "wood": "brown", "beam": "dark_brown", "wall": "white", "stone": "light_gray",
	"roof": "dark_red", "cloth": "white", "flower": "white", "cloud": "white", "smoke": "white",
	"window": "trans_yellow", "fire": "trans_orange", "water": "trans_blue",
	"gray": "light_gray", "grey": "light_gray", "light_grey": "light_gray", "dark_grey": "dark_gray",
	"transparent": "glass", "clear": "glass", "violet": "purple", "magenta": "purple",
	"cyan": "azure", "teal": "azure", "navy": "dark_blue", "beige": "tan", "dark_tan": "sand",
	"reddish_brown": "brown", "olive": "dark_green", "metal": "silver", "steel": "silver",
}

static var _cache := {}


## Имя цвета палитры для любого значения: имя, синоним или "#rrggbb".
## Произвольный цвет заменяется ближайшим непрозрачным цветом палитры.
static func color_name(value) -> String:
	if value is String:
		var key: String = value.strip_edges().to_lower().replace(" ", "_").replace("-", "_")
		if COLORS.has(key):
			return key
		if ALIASES.has(key):
			return ALIASES[key]
		if Color.html_is_valid(value):
			return nearest(Color.html(value))
	elif value is Color:
		return nearest(value)
	return "light_gray"


static func nearest(c: Color) -> String:
	var best := "light_gray"
	var best_d := INF
	for key: String in COLORS:
		if key in TRANSPARENT or key in METALLIC:
			continue
		var p: Color = COLORS[key]
		# Простая перцептивная мера: зелёный глаз различает лучше всего.
		var d := 2.0 * pow(p.r - c.r, 2) + 4.0 * pow(p.g - c.g, 2) + 3.0 * pow(p.b - c.b, 2)
		if d < best_d:
			best_d = d
			best = key
	return best


## Цвет палитры для цветов вершин. Рендерер Compatibility считает свет
## прямо в sRGB, поэтому цвет идёт как есть; другим рендерерам нужен линейный.
static func vertex_color(name: String) -> Color:
	var c: Color = COLORS.get(name, COLORS.light_gray)
	return c if _compat() else c.srgb_to_linear()


static func _compat() -> bool:
	if not _cache.has("compat"):
		_cache.compat = str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "gl_compatibility"
	return _cache.compat


## Вид пластика для цвета: solid, trans или metal.
static func kind(name: String) -> String:
	if name in TRANSPARENT:
		return "trans"
	if name in METALLIC:
		return "metal"
	return "solid"


## Материал для склеенных мешей, где цвет хранится в вершинах.
static func plastic(kind_name := "solid") -> ShaderMaterial:
	var key := "vc|" + kind_name
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = PLASTIC_TRANS if kind_name == "trans" else (PLASTIC_METAL if kind_name == "metal" else PLASTIC)
	m.set_shader_parameter("use_vertex_color", true)
	if kind_name == "trans":
		m.render_priority = 1
	_cache[key] = m
	return m


## Материал одного цвета для отдельной детали.
static func part_material(value, glow := false, sway := 0.0) -> ShaderMaterial:
	var name := color_name(value)
	var key := "%s|%s|%s" % [name, glow, sway]
	if _cache.has(key):
		return _cache[key]
	var k := kind(name)
	var m := ShaderMaterial.new()
	m.shader = PLASTIC_TRANS if k == "trans" else (PLASTIC_METAL if k == "metal" else PLASTIC)
	m.set_shader_parameter("albedo", COLORS[name])
	m.set_shader_parameter("use_vertex_color", false)
	m.set_shader_parameter("sway", sway)
	if glow or name in GLOWING:
		m.set_shader_parameter("emission", COLORS[name])
		m.set_shader_parameter("emission_strength", 1.6 if glow else 0.8)
	if k == "trans":
		m.render_priority = 1
	_cache[key] = m
	return m


## Светящийся материал: лампы, окна, огонь.
static func glow(value, _strength := 2.0) -> ShaderMaterial:
	return part_material(value, true)


# --- Меши -----------------------------------------------------------------

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cylinder(top: float, bottom: float, height: float, segments := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func sphere(radius: float, segments := 16, rings := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


static func prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


## Шип: невысокий цилиндр с крышкой, его центр внизу.
static func stud_mesh() -> Mesh:
	if _cache.has("stud"):
		return _cache.stud
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 12
	var r := STUD_RADIUS
	var h := STUD_HEIGHT
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var n0 := Vector3(cos(a0), 0, sin(a0))
		var n1 := Vector3(cos(a1), 0, sin(a1))
		# Бок: лицевая сторона по часовой стрелке, если смотреть снаружи.
		for v in [[p0, n0], [p1 + Vector3.UP * h, n1], [p1, n1], [p0, n0], [p0 + Vector3.UP * h, n0], [p1 + Vector3.UP * h, n1]]:
			st.set_normal(v[1])
			st.add_vertex(v[0])
		for v in [Vector3(0, h, 0), p0 + Vector3.UP * h, p1 + Vector3.UP * h]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	_cache.stud = st.commit()
	return _cache.stud


## Склеивает несколько примитивов в один меш: [[mesh, Transform3D], ...].
static func merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		st.append_from(p[0], 0, p[1])
	return st.commit()


static func at(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scale), pos)


static func add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func add_box_collider(body: CollisionObject3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	col.rotation = rot
	body.add_child(col)


## Пачка одинаковых мешей. colors задаёт цвет каждой копии (линейный).
static func multimesh(parent: Node3D, mesh: Mesh, mat: Material, transforms: Array[Transform3D], colors: Array[Color] = [], shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Дым из трубы или костра: круглые белые пластинки, которые всплывают и тают.
static func smoke(parent: Node3D, pos: Vector3, size := 0.55) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 18
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.mesh = cylinder(size * 0.6, size * 0.6, size * 0.3, 12)
	p.material_override = part_material("white")
	p.direction = Vector3(0.2, 1, 0)
	p.spread = 10.0
	p.gravity = Vector3(0.2, 0.4, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 0.9
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.4, 1.2))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	parent.add_child(p)
	return p
