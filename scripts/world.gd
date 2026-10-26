extends Node3D
## Собирает мир: зелёная базовая пластина Lego, небо с кирпичными облаками,
## солнце, игрок-миньфигурка и интерфейс. Всё остальное игрок создаёт сам,
## вручную из кирпичей или через своего ИИ-агента.

const Style := preload("res://scripts/style.gd")
const Bricks := preload("res://scripts/bricks.gd")
const PlayerScript := preload("res://scripts/player.gd")
const PetScript := preload("res://scripts/pet.gd")
const HudScript := preload("res://scripts/hud.gd")
const AgentBridge := preload("res://scripts/agent_bridge.gd")
const McpHttp := preload("res://scripts/mcp_http.gd")
const AiPanel := preload("res://scripts/ai_panel.gd")
const BASEPLATE := preload("res://shaders/baseplate.gdshader")

## Сторона мира в шипах и в метрах.
var studs := 256
var SIZE := 256 * Style.STUD
## Цвет базовой пластины.
var plate_color := "green"
## Уровень воды: воды в мире нет, константа нужна питомцу.
const WATER_LEVEL := -100.0
## Слой физики, который видит только камера.
const CAMERA_LAYER := 2
## Ковёр объёмных шипов вокруг игрока, сторона в шипах.
const STUD_CARPET := 72

var player: CharacterBody3D
var bridge: Node
var animated: Array[Callable] = []
var _carpet: MultiMeshInstance3D
var _clouds: Array[Node3D] = []


func _ready() -> void:
	SIZE = studs * Style.STUD
	_setup_environment()
	_build_ground()
	_build_clouds()
	_spawn_player()
	var hud: Control = HudScript.new()
	hud.player = player
	hud.world = self
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	# Через мост ИИ-агенты по MCP создают объекты, они попадают в инвентарь.
	bridge = AgentBridge.new()
	bridge.name = "AgentBridge"
	bridge.world = self
	add_child(bridge)
	var mcp: Node = McpHttp.new()
	mcp.name = "McpHttp"
	mcp.bridge = bridge
	add_child(mcp)
	var panel: Control = AiPanel.new()
	panel.bridge = bridge
	panel.mcp = mcp
	panel.player = player
	layer.add_child(panel)


func _process(delta: float) -> void:
	for f in animated:
		f.call(delta)
	# Объёмные шипы лежат ковром вокруг игрока и переезжают вместе с ним.
	if _carpet and player:
		var cam := get_viewport().get_camera_3d()
		var focus: Vector3 = cam.global_position if cam else player.global_position
		_carpet.position = Vector3(snappedf(focus.x, Style.STUD * 4.0), 0.0, snappedf(focus.z, Style.STUD * 4.0))
	for c in _clouds:
		c.position.x += delta * 0.6
		if c.position.x > SIZE * 1.4:
			c.position.x = -SIZE * 1.4


# --- Земля ----------------------------------------------------------------

## Высота земли. Мир ровный, поэтому везде ноль.
func height_at(_x: float, _z: float) -> float:
	return 0.0


func spawn_point() -> Vector2:
	return Vector2(Style.STUD * 0.5, Style.STUD * 4.5)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var thick := Style.PLATE * 2.0
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIZE, thick, SIZE)
	mi.mesh = mesh
	mi.position.y = -thick * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = BASEPLATE
	mat.set_shader_parameter("albedo", Style.COLORS.get(plate_color, Style.COLORS.green))
	mat.set_shader_parameter("stud", Style.STUD)
	mi.material_override = mat
	body.add_child(mi)
	Style.add_box_collider(body, Vector3(SIZE, 1.0, SIZE), Vector3(0, -0.5, 0))
	add_child(body)

	# Объёмные шипы: одна пачка на все, она переезжает за камерой по сетке.
	var xfs: Array[Transform3D] = []
	var half := STUD_CARPET / 2
	for iz in range(-half, half):
		for ix in range(-half, half):
			xfs.append(Transform3D(Basis(), Vector3((ix + 0.5) * Style.STUD, 0.0, (iz + 0.5) * Style.STUD)))
	var stud_mat := ShaderMaterial.new()
	stud_mat.shader = Style.PLASTIC
	stud_mat.set_shader_parameter("use_vertex_color", false)
	stud_mat.set_shader_parameter("albedo", Style.COLORS.get(plate_color, Style.COLORS.green))
	stud_mat.set_shader_parameter("clip_half", SIZE * 0.5)
	_carpet = Style.multimesh(self, Style.stud_mesh(), stud_mat, xfs, [], false)
	_carpet.name = "GroundStuds"


## Облака из белых кирпичей далеко над краем пластины.
func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 14:
		var bricks := []
		var w := rng.randi_range(6, 12)
		for layer in 3:
			var inset := layer * rng.randi_range(1, 2)
			if w - inset * 2 < 2:
				break
			bricks.append({"type": "box", "from": [-w / 2 + inset, layer * 3, -3 + layer], "to": [w / 2 - inset, layer * 3 + 3, 3 - layer], "color": "white"})
		var cloud := Node3D.new()
		Bricks.build(cloud, Bricks.expand(bricks))
		var ang := TAU * i / 14.0 + rng.randf_range(-0.2, 0.2)
		var dist := SIZE * rng.randf_range(0.65, 1.2)
		cloud.position = Vector3(cos(ang) * dist, rng.randf_range(28.0, 48.0), sin(ang) * dist)
		cloud.scale = Vector3.ONE * rng.randf_range(2.0, 3.2)
		add_child(cloud)
		_clouds.append(cloud)


# --- Окружение и игрок ----------------------------------------------------

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.26, 0.53, 0.88)
	sky_mat.sky_horizon_color = Color(0.72, 0.85, 0.97)
	sky_mat.ground_horizon_color = Color(0.72, 0.85, 0.97)
	sky_mat.ground_bottom_color = Color(0.42, 0.6, 0.82)
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Ровный нейтральный рассеянный свет: небо не должно красить пластик в голубой.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.85)
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.85, 0.97)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0
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
