extends Node3D
## Собирает прототип открытого мира: рельеф с рекой и уступами, природу,
## деревню, дальний план, игрока и интерфейс. Всё создаётся из кода,
## поэтому проект не требует внешних ассетов.

const Style := preload("res://scripts/style.gd")
const Nature := preload("res://scripts/nature.gd")
const Village := preload("res://scripts/village.gd")
const Scenery := preload("res://scripts/scenery.gd")
const PlayerScript := preload("res://scripts/player.gd")
const PetScript := preload("res://scripts/pet.gd")
const HudScript := preload("res://scripts/hud.gd")
const AgentBridge := preload("res://scripts/agent_bridge.gd")
const WATER_SHADER := preload("res://shaders/water.gdshader")

const SIZE := 240.0
const RES := 200
const WATER_LEVEL := 0.0
const VILLAGE_X := 30.0
const VILLAGE_LEVEL := 2.5
## Слой физики, который видит только камера.
const CAMERA_LAYER := 2

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var player: CharacterBody3D
var animated: Array[Callable] = []


func _ready() -> void:
	noise.seed = 7
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	detail.seed = 21
	detail.frequency = 0.05

	_setup_environment()
	_build_terrain()
	_build_water()
	Village.build(self)
	Nature.build(self)
	Scenery.build(self)
	_spawn_player()
	var hud: Control = HudScript.new()
	hud.player = player
	hud.world = self
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	# Через мост ИИ-агенты по MCP создают в мире новые объекты.
	var bridge: Node = AgentBridge.new()
	bridge.name = "AgentBridge"
	bridge.world = self
	add_child(bridge)


func _process(delta: float) -> void:
	for f in animated:
		f.call(delta)


# --- Рельеф ---------------------------------------------------------------

func river_z(x: float) -> float:
	return 18.0 * sin(x * 0.025) + 8.0 * sin(x * 0.061 + 1.3)


func river_dist(x: float, z: float) -> float:
	return absf(z - river_z(x))


func village_center() -> Vector2:
	return Vector2(VILLAGE_X, river_z(VILLAGE_X) - 20.0)


func spawn_point() -> Vector2:
	var x := VILLAGE_X - 4.0
	return Vector2(x, river_z(x) + 15.0)


func height_at(x: float, z: float) -> float:
	var h := 3.0 + noise.get_noise_2d(x, z) * 11.0
	h = maxf(h, 0.8)
	# Уступы с каменными обрывами, как скалы на референсах.
	var k := h / 4.0
	var f := k - floorf(k)
	var terraced := (floorf(k) + smoothstep(0.55, 0.85, f)) * 4.0
	h = lerpf(h, terraced, 0.8) + detail.get_noise_2d(x, z) * 0.5
	# Горы по краям не дают уйти за пределы мира.
	var edge := maxf(absf(x), absf(z))
	if edge > SIZE * 0.32:
		h += pow(edge - SIZE * 0.32, 1.35) * 0.35
	# Ровная площадка под деревню.
	var vd := Vector2(x, z).distance_to(village_center())
	if vd < 20.0:
		h = lerpf(VILLAGE_LEVEL, h, smoothstep(13.0, 20.0, vd))
	# Смотровой пригорок у точки появления.
	var sd := Vector2(x, z).distance_to(spawn_point())
	if sd < 10.0:
		h = lerpf(6.0, h, smoothstep(4.0, 10.0, sd))
	# Русло реки.
	var d := river_dist(x, z)
	if d < 13.0:
		h = lerpf(-2.5, h, smoothstep(4.0, 13.0, d))
	return h


## Расстояние до ближайшей тропинки деревни.
func path_dist(x: float, z: float) -> float:
	var vc := village_center()
	var p := Vector2(x, z)
	var a := _seg_dist(p, vc, Vector2(vc.x + 2.0, vc.y + 10.0))
	var b := _seg_dist(p, vc, Vector2(vc.x - 40.0, river_z(vc.x - 40.0) - 12.0))
	return minf(a, b)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _ground_color(x: float, z: float, h: float, up: float) -> Color:
	if h < 0.9:
		return Style.PALETTE.sand
	if up < 0.72 or h > 22.0:
		return Style.PALETTE.cliff.lerp(Style.PALETTE.rock_dark, clampf(detail.get_noise_2d(x * 3.0, z * 3.0) + 0.5, 0.0, 1.0))
	if path_dist(x, z) < 1.6:
		return Style.PALETTE.path
	var t := clampf(noise.get_noise_2d(x * 3.0, z * 3.0) * 1.5 + 0.5, 0.0, 1.0)
	return Style.PALETTE.grass.lerp(Style.PALETTE.grass_light, t)


func _build_terrain() -> void:
	var n := RES + 1
	var cell := SIZE / RES
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			heights[iz * n + ix] = height_at(-SIZE * 0.5 + ix * cell, -SIZE * 0.5 + iz * cell)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for iz in n:
		for ix in n:
			var x := -SIZE * 0.5 + ix * cell
			var z := -SIZE * 0.5 + iz * cell
			var h := heights[iz * n + ix]
			var hx := heights[iz * n + mini(ix + 1, RES)] - heights[iz * n + maxi(ix - 1, 0)]
			var hz := heights[mini(iz + 1, RES) * n + ix] - heights[maxi(iz - 1, 0) * n + ix]
			var nrm := Vector3(-hx, 2.0 * cell, -hz).normalized()
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
	mesh.surface_set_material(0, Style.toon(Color.WHITE, 0.0, true))

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


# --- Окружение и игрок ----------------------------------------------------

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.62, 0.62, 0.62)
	sky_mat.sky_horizon_color = Color(0.95, 0.95, 0.93)
	sky_mat.ground_horizon_color = Color(0.95, 0.95, 0.93)
	sky_mat.ground_bottom_color = Color(0.5, 0.5, 0.5)
	sky_mat.sun_angle_max = 6.0
	sky_mat.sun_curve = 0.02
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.75)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Низкое солнце за деревней, напротив стартового вида: контровой свет.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-24, 172, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _spawn_player() -> void:
	var sp := spawn_point()
	player = PlayerScript.new()
	player.name = "Player"
	player.world = self
	player.position = Vector3(sp.x, height_at(sp.x, sp.y) + 0.5, sp.y)
	add_child(player)

	var pet: Node3D = PetScript.new()
	pet.name = "Pet"
	pet.world = self
	pet.target = player
	pet.position = player.position + Vector3(1.2, 0, 0.3)
	add_child(pet)
