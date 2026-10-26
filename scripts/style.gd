extends RefCounted
## Общий стиль мира: тональная палитра, материалы и простые меши.
## Всё, что появляется в мире, в том числе объекты от ИИ-агентов, должно
## строиться через эти функции, чтобы мир выглядел цельно.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

# Итоговый кадр переводится в сепию, поэтому важна яркость цветов, а не оттенок:
# тёмная хвоя и кора, средняя трава, светлые стены и облака.
const PALETTE := {
	"grass": Color(0.4, 0.4, 0.37),
	"grass_light": Color(0.47, 0.47, 0.43),
	"grass_blade": Color(0.48, 0.48, 0.44),
	"path": Color(0.6, 0.58, 0.53),
	"sand": Color(0.7, 0.68, 0.63),
	"cliff": Color(0.52, 0.5, 0.48),
	"rock": Color(0.56, 0.55, 0.53),
	"rock_dark": Color(0.4, 0.39, 0.38),
	"mountain": Color(0.45, 0.44, 0.43),
	"bark": Color(0.24, 0.22, 0.2),
	"pine": Color(0.27, 0.27, 0.26),
	"leaf": Color(0.38, 0.38, 0.35),
	"leaf_light": Color(0.48, 0.48, 0.44),
	"bush": Color(0.36, 0.36, 0.33),
	"flower": Color(1.0, 0.99, 0.95),
	"wall": Color(0.8, 0.77, 0.7),
	"beam": Color(0.22, 0.2, 0.18),
	"roof": Color(0.3, 0.28, 0.27),
	"stone": Color(0.62, 0.6, 0.57),
	"wood": Color(0.42, 0.38, 0.33),
	"cloth": Color(0.85, 0.83, 0.78),
	"cloud": Color(0.97, 0.96, 0.93),
	"smoke": Color(0.88, 0.87, 0.84),
	"window": Color(1.0, 0.9, 0.7),
	"fire": Color(1.0, 0.8, 0.5),
}

static var _cache := {}


## Приводит любой цвет к палитре мира. Имя из PALETTE берётся как есть,
## а произвольный цвет заменяется ближайшим по яркости тоном палитры:
## кадр всё равно сепийный, поэтому важна только яркость.
static func to_palette(value) -> Color:
	if value is String and PALETTE.has(value):
		return PALETTE[value]
	var c := Color.GRAY
	if value is Color:
		c = value
	elif value is String and Color.html_is_valid(value):
		c = Color.html(value)
	var best: Color = PALETTE.stone
	var best_d := INF
	for key: String in PALETTE:
		if key in ["window", "fire", "smoke", "cloud"]:
			continue
		var d := absf(PALETTE[key].get_luminance() - c.get_luminance())
		if d < best_d:
			best_d = d
			best = PALETTE[key]
	return best


## Материал мира: тун-освещение плюс контур, если толщина больше нуля.
static func toon(color: Color, outline := 0.05, vertex_color := false, sway := 0.0) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [color.to_html(), outline, vertex_color, sway]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	m.set_shader_parameter("sway", sway)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("thickness", outline)
		o.set_shader_parameter("sway", sway)
		m.next_pass = o
	_cache[key] = m
	return m


## Светящийся материал: окна, фонари, огонь.
static func glow(color: Color, strength := 2.0) -> ShaderMaterial:
	var key := "glow|%s|%s" % [color.to_html(), strength]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission", color)
	m.set_shader_parameter("emission_strength", strength)
	m.set_shader_parameter("mottle", 0.0)
	_cache[key] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cylinder(top: float, bottom: float, height: float, segments := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func sphere(radius: float, segments := 10, rings := 6) -> SphereMesh:
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


static func multimesh(parent: Node3D, mesh: Mesh, mat: Material, transforms: Array[Transform3D], shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Дым из трубы или костра. Частицы непрозрачные, чтобы их видел фильтр кадра.
static func smoke(parent: Node3D, pos: Vector3, size := 0.55) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 26
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.mesh = sphere(size, 8, 5)
	p.material_override = toon(PALETTE.smoke, 0.0)
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0.25, 0.35, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 0.7
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.6))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	parent.add_child(p)
	return p
