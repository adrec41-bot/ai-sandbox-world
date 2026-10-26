extends Node3D
## Строит прототип открытого мира: рельеф с рекой, лес, деревню, игрока и HUD.
## Всё создаётся процедурно из кода, поэтому проект не требует внешних ассетов.

const SIZE := 240.0
const RES := 160
const WATER_LEVEL := 0.0
const VILLAGE_X := 30.0
const VILLAGE_LEVEL := 2.5
## Слой физики, который видит только камера.
const CAMERA_LAYER := 2

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const PlayerScript := preload("res://scripts/player.gd")

# Палитра мира. Позже к ней будут приводиться цвета сгенерированных объектов.
const PALETTE := {
	"grass": Color(0.47, 0.63, 0.38),
	"grass_light": Color(0.63, 0.71, 0.42),
	"sand": Color(0.8, 0.74, 0.57),
	"rock": Color(0.58, 0.56, 0.54),
	"rock_dark": Color(0.45, 0.44, 0.45),
	"bark": Color(0.42, 0.3, 0.22),
	"pine": Color(0.28, 0.46, 0.36),
	"leaf": Color(0.45, 0.6, 0.32),
	"wall": Color(0.82, 0.75, 0.62),
	"roof": Color(0.55, 0.3, 0.25),
	"wood": Color(0.55, 0.4, 0.28),
	"window": Color(1.0, 0.82, 0.45),
}

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var forest := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var windmill_blades: Node3D


func _ready() -> void:
	rng.seed = 1337
	noise.seed = 7
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	detail.seed = 21
	detail.frequency = 0.05
	forest.seed = 99
	forest.frequency = 0.03

	_setup_environment()
	_build_terrain()
	_build_water()
	_build_village()
	_build_trees()
	_build_rocks()
	_spawn_player()
	_build_hud()


func _process(delta: float) -> void:
	if windmill_blades:
		windmill_blades.rotate_z(delta * 0.6)


# --- Рельеф ---------------------------------------------------------------

func river_z(x: float) -> float:
	return 18.0 * sin(x * 0.025) + 8.0 * sin(x * 0.061 + 1.3)


func village_center() -> Vector2:
	return Vector2(VILLAGE_X, river_z(VILLAGE_X) - 20.0)


func height_at(x: float, z: float) -> float:
	var h := 3.0 + noise.get_noise_2d(x, z) * 9.0 + detail.get_noise_2d(x, z) * 0.6
	h = maxf(h, 0.8)
	# Горы по краям не дают уйти за пределы мира.
	var edge := maxf(absf(x), absf(z))
	if edge > SIZE * 0.32:
		h += pow(edge - SIZE * 0.32, 1.35) * 0.35
	# Ровная площадка под деревню.
	var vd := Vector2(x, z).distance_to(village_center())
	if vd < 18.0:
		h = lerpf(VILLAGE_LEVEL, h, smoothstep(11.0, 18.0, vd))
	# Русло реки.
	var d := absf(z - river_z(x))
	if d < 14.0:
		h = lerpf(-2.5, h, smoothstep(4.0, 14.0, d))
	return h


func _ground_color(x: float, z: float, h: float, up: float) -> Color:
	if h < 0.9:
		return PALETTE.sand
	if up < 0.78 or h > 16.0:
		return PALETTE.rock.lerp(PALETTE.rock_dark, clampf(detail.get_noise_2d(x * 2.0, z * 2.0) + 0.5, 0.0, 1.0))
	var t := clampf(noise.get_noise_2d(x * 3.0, z * 3.0) * 1.5 + 0.5, 0.0, 1.0)
	return PALETTE.grass.lerp(PALETTE.grass_light, t)


func _build_terrain() -> void:
	var n := RES + 1
	var cell := SIZE / RES
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for iz in n:
		for ix in n:
			var x := -SIZE * 0.5 + ix * cell
			var z := -SIZE * 0.5 + iz * cell
			var h := height_at(x, z)
			var hx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
			var hz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
			var nrm := Vector3(-hx, 1.0, -hz).normalized()
			verts.append(Vector3(x, h, z))
			normals.append(nrm)
			colors.append(_ground_color(x, z, h, nrm.y))
	for iz in RES:
		for ix in RES:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, toon(Color.WHITE, 0.0, true))

	var body := StaticBody3D.new()
	body.name = "Terrain"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child(body)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Материалы и меши -----------------------------------------------------

## Материал мира: тун-освещение плюс контур, если толщина больше нуля.
func toon(color: Color, outline := 0.05, vertex_color := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE_SHADER
		o.set_shader_parameter("thickness", outline)
		m.next_pass = o
	return m


func glow(color: Color, strength := 2.0) -> ShaderMaterial:
	var m := toon(color, 0.0)
	m.set_shader_parameter("emission", color)
	m.set_shader_parameter("emission_strength", strength)
	return m


## Склеивает несколько примитивов в один меш, чтобы рисовать их одним вызовом.
func merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		st.append_from(p[0], 0, p[1])
	return st.commit()


func add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func cylinder(top: float, bottom: float, height: float, segments := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


func add_box_collider(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)


# --- Деревня --------------------------------------------------------------

func _build_village() -> void:
	var vc := village_center()
	var village := Node3D.new()
	village.name = "Village"
	village.position = Vector3(vc.x, VILLAGE_LEVEL, vc.y)
	add_child(village)

	_make_house(village, Vector3(-6, 0, 2), 0.2, Vector3(5, 2.8, 4))
	_make_house(village, Vector3(2, 0, -3), -0.1, Vector3(6, 3.4, 5))
	_make_house(village, Vector3(8, 0, 3), 0.35, Vector3(4, 2.6, 4))
	_make_house(village, Vector3(-3, 0, -9), 0.0, Vector3(4.5, 2.6, 4))
	_make_windmill(village, Vector3(12, 0, -7))
	_make_dock(village)
	_make_lantern(village, Vector3(-1, 0, 6))
	_make_lantern(village, Vector3(6, 0, 7))


func _make_house(parent: Node3D, pos: Vector3, yaw: float, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	parent.add_child(body)
	var w := size.x
	var h := size.y
	var d := size.z
	add_part(body, box(Vector3(w, h, d)), toon(PALETTE.wall), Vector3(0, h * 0.5, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(w + 0.8, 1.8, d + 0.8)
	add_part(body, roof, toon(PALETTE.roof), Vector3(0, h + 0.9, 0))
	add_part(body, box(Vector3(0.6, 1.4, 0.6)), toon(PALETTE.rock), Vector3(w * 0.25, h + 1.3, -d * 0.15))
	add_part(body, box(Vector3(1.0, 1.8, 0.1)), toon(PALETTE.wood, 0.03), Vector3(0, 0.9, d * 0.5 + 0.05))
	for side in [-1.0, 1.0]:
		add_part(body, box(Vector3(0.8, 0.8, 0.1)), glow(PALETTE.window), Vector3(side * w * 0.3, h * 0.6, d * 0.5 + 0.05))
	add_box_collider(body, size, Vector3(0, h * 0.5, 0))


func _make_windmill(parent: Node3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	add_part(body, cylinder(1.0, 1.8, 9.0, 8), toon(PALETTE.wall), Vector3(0, 4.5, 0))
	add_part(body, cylinder(0.0, 1.5, 2.0, 8), toon(PALETTE.roof), Vector3(0, 10.0, 0))
	windmill_blades = Node3D.new()
	windmill_blades.position = Vector3(0, 8.0, 1.6)
	body.add_child(windmill_blades)
	for i in 4:
		var blade := Node3D.new()
		blade.rotation.z = i * PI * 0.5
		windmill_blades.add_child(blade)
		add_part(blade, box(Vector3(0.9, 4.5, 0.08)), toon(PALETTE.wood, 0.03), Vector3(0, 2.6, 0))
	add_box_collider(body, Vector3(2.8, 9.0, 2.8), Vector3(0, 4.5, 0))


func _make_dock(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(2, 0, 0)
	parent.add_child(body)
	var top := WATER_LEVEL - VILLAGE_LEVEL + 0.6
	var start := 10.0
	var length := 9.0
	add_part(body, box(Vector3(2.4, 0.2, length)), toon(PALETTE.wood, 0.03), Vector3(0, top, start + length * 0.5))
	for i in 4:
		for side in [-1.1, 1.1]:
			add_part(body, cylinder(0.12, 0.12, 3.0, 6), toon(PALETTE.bark, 0.03), Vector3(side, top - 1.4, start + 1.0 + i * 2.4))
	add_box_collider(body, Vector3(2.4, 0.2, length), Vector3(0, top, start + length * 0.5))
	# Лодка у причала.
	add_part(body, box(Vector3(1.4, 0.5, 3.4)), toon(PALETTE.wood, 0.03), Vector3(2.6, top - 0.5, start + 6.0), Vector3(0, 0.15, 0))


func _make_lantern(parent: Node3D, pos: Vector3) -> void:
	var node := Node3D.new()
	node.position = pos
	parent.add_child(node)
	add_part(node, box(Vector3(0.15, 2.6, 0.15)), toon(PALETTE.bark, 0.03), Vector3(0, 1.3, 0))
	add_part(node, box(Vector3(0.35, 0.45, 0.35)), glow(PALETTE.window, 3.0), Vector3(0, 2.7, 0))
	var light := OmniLight3D.new()
	light.light_color = PALETTE.window
	light.light_energy = 1.5
	light.omni_range = 7.0
	light.position = Vector3(0, 2.7, 0)
	node.add_child(light)


# --- Природа --------------------------------------------------------------

func _build_trees() -> void:
	var pine_trunk := merge([[cylinder(0.15, 0.25, 1.6), Transform3D(Basis(), Vector3(0, 0.8, 0))]])
	var pine_crown := merge([
		[cylinder(0.0, 1.6, 2.2), Transform3D(Basis(), Vector3(0, 2.4, 0))],
		[cylinder(0.0, 1.25, 1.9), Transform3D(Basis(), Vector3(0, 3.5, 0))],
		[cylinder(0.0, 0.85, 1.6), Transform3D(Basis(), Vector3(0, 4.5, 0))],
	])
	var round_trunk := merge([[cylinder(0.2, 0.3, 2.4), Transform3D(Basis(), Vector3(0, 1.2, 0))]])
	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var small := SphereMesh.new()
	small.radius = 1.0
	small.height = 1.9
	small.radial_segments = 8
	small.rings = 5
	var round_crown := merge([
		[sphere, Transform3D(Basis(), Vector3(0, 3.4, 0))],
		[small, Transform3D(Basis(), Vector3(0.9, 2.9, 0.5))],
	])

	var pines: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var colliders := StaticBody3D.new()
	colliders.name = "Trees"
	add_child(colliders)
	var crowns := StaticBody3D.new()
	crowns.name = "TreeCrowns"
	crowns.collision_layer = CAMERA_LAYER
	crowns.collision_mask = 0
	add_child(crowns)
	var vc := village_center()
	var attempts := 0
	while pines.size() + rounds.size() < 520 and attempts < 20000:
		attempts += 1
		var x := rng.randf_range(-SIZE * 0.45, SIZE * 0.45)
		var z := rng.randf_range(-SIZE * 0.45, SIZE * 0.45)
		var h := height_at(x, z)
		if h < 1.2 or h > 20.0:
			continue
		if absf(z - river_z(x)) < 9.0 or Vector2(x, z).distance_to(vc) < 19.0:
			continue
		if Vector2(x, z).distance_to(_spawn_point()) < 10.0:
			continue
		if forest.get_noise_2d(x, z) < -0.15:
			continue
		var s := rng.randf_range(0.8, 1.5)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.1, z))
		if h > 8.0 or rng.randf() < 0.5:
			pines.append(t)
		else:
			rounds.append(t)
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.3 * s
		shape.height = 3.0 * s
		col.shape = shape
		col.position = Vector3(x, h + 1.5 * s, z)
		colliders.add_child(col)
		# Крона на отдельном слое: игрок сквозь неё проходит, а камера
		# упирается, чтобы не оказаться внутри дерева.
		var crown := CollisionShape3D.new()
		var cs := SphereShape3D.new()
		cs.radius = 1.8 * s
		crown.shape = cs
		crown.position = Vector3(x, h + 3.3 * s, z)
		crowns.add_child(crown)

	_multimesh(pine_trunk, toon(PALETTE.bark, 0.04), pines)
	_multimesh(pine_crown, toon(PALETTE.pine, 0.06), pines)
	_multimesh(round_trunk, toon(PALETTE.bark, 0.04), rounds)
	_multimesh(round_crown, toon(PALETTE.leaf, 0.06), rounds)


func _multimesh(mesh: Mesh, mat: Material, transforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _build_rocks() -> void:
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.6
	rock.radial_segments = 6
	rock.rings = 3
	var body := StaticBody3D.new()
	body.name = "Rocks"
	add_child(body)
	var mat := toon(PALETTE.rock, 0.05)
	for i in 70:
		var x := rng.randf_range(-SIZE * 0.42, SIZE * 0.42)
		var z := rng.randf_range(-SIZE * 0.42, SIZE * 0.42)
		if Vector2(x, z).distance_to(village_center()) < 16.0:
			continue
		var h := height_at(x, z)
		var s := rng.randf_range(0.5, 2.0)
		var mi := add_part(body, rock, mat, Vector3(x, h, z), Vector3(rng.randf(), rng.randf() * TAU, rng.randf() * 0.3))
		mi.scale = Vector3(s * rng.randf_range(0.8, 1.4), s, s)
		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = s * 0.75
		col.shape = shape
		col.position = Vector3(x, h, z)
		body.add_child(col)


# --- Окружение, игрок, интерфейс ------------------------------------------

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.52, 0.66, 0.8)
	sky_mat.sky_horizon_color = Color(0.93, 0.89, 0.8)
	sky_mat.ground_horizon_color = Color(0.93, 0.89, 0.8)
	sky_mat.ground_bottom_color = Color(0.45, 0.5, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.62, 0.75)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.88, 0.87, 0.82)
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.2
	env.glow_enabled = true
	env.glow_bloom = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _spawn_point() -> Vector2:
	var x := VILLAGE_X - 4.0
	return Vector2(x, river_z(x) + 17.0)


func _spawn_player() -> void:
	var sp := _spawn_point()
	var player: CharacterBody3D = PlayerScript.new()
	player.name = "Player"
	player.world = self
	player.position = Vector3(sp.x, height_at(sp.x, sp.y) + 1.0, sp.y)
	add_child(player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var quest := Label.new()
	quest.text = "◆ Исследуй мир\n    Найди новое место для строительства"
	quest.position = Vector2(24, 20)
	quest.label_settings = _label_style(22)
	layer.add_child(quest)
	var help := Label.new()
	help.text = "WASD ходить · Shift бег · Пробел прыжок · клик захватить мышь · колесо зум · Esc отпустить"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -44
	help.offset_left = 24
	help.label_settings = _label_style(16)
	layer.add_child(help)


func _label_style(size: int) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = Color(1, 1, 0.97)
	ls.outline_size = 6
	ls.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	return ls
