extends Node3D
## Собирает мир: пока это ровная пустая равнина, небо, свет, игрок и интерфейс.
## Всё остальное игроки создают сами через ИИ-строителя. Скрипты деревни,
## природы и дальнего плана (village.gd, nature.gd, scenery.gd) сейчас не
## используются и оставлены на будущее.

const Style := preload("res://scripts/style.gd")
const PlayerScript := preload("res://scripts/player.gd")
const PetScript := preload("res://scripts/pet.gd")
const HudScript := preload("res://scripts/hud.gd")
const AgentBridge := preload("res://scripts/agent_bridge.gd")
const McpHttp := preload("res://scripts/mcp_http.gd")
const AiPanel := preload("res://scripts/ai_panel.gd")

const SIZE := 240.0
## Уровень воды: на ровном мире воды нет, константа нужна питомцу.
const WATER_LEVEL := -100.0
## Слой физики, который видит только камера.
const CAMERA_LAYER := 2

var noise := FastNoiseLite.new()
var player: CharacterBody3D
var bridge: Node
var animated: Array[Callable] = []


func _ready() -> void:
	noise.seed = 7
	noise.frequency = 0.02

	_setup_environment()
	_build_ground()
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


# --- Земля ----------------------------------------------------------------

## Высота земли. Мир ровный, поэтому везде ноль.
func height_at(_x: float, _z: float) -> float:
	return 0.0


func spawn_point() -> Vector2:
	return Vector2.ZERO


func _build_ground() -> void:
	# Плоская сетка с лёгкими пятнами тона, чтобы равнина не выглядела пустым листом.
	var res := 120
	var cell := SIZE / res
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in res:
		for ix in res:
			var x0 := -SIZE * 0.5 + ix * cell
			var z0 := -SIZE * 0.5 + iz * cell
			var quad := [Vector3(x0, 0, z0), Vector3(x0 + cell, 0, z0), Vector3(x0, 0, z0 + cell), Vector3(x0 + cell, 0, z0 + cell)]
			for i in [0, 1, 2, 1, 3, 2]:
				var v: Vector3 = quad[i]
				var t := clampf(noise.get_noise_2d(v.x, v.z) * 1.2 + 0.5, 0.0, 1.0)
				st.set_color(Style.PALETTE.grass.lerp(Style.PALETTE.grass_light, t))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, Style.toon(Color.WHITE, 0.0, true))

	var body := StaticBody3D.new()
	body.name = "Ground"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	Style.add_box_collider(body, Vector3(SIZE, 1.0, SIZE), Vector3(0, -0.5, 0))
	# Невидимые стены по краю, чтобы не упасть с края мира.
	for side in 4:
		var along := side < 2
		var dir := 1.0 if side % 2 == 0 else -1.0
		var pos := Vector3(dir * SIZE * 0.5, 10, 0) if along else Vector3(0, 10, dir * SIZE * 0.5)
		var size := Vector3(1, 20, SIZE) if along else Vector3(SIZE, 20, 1)
		Style.add_box_collider(body, size, pos)
	add_child(body)


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

	# Низкое солнце напротив стартового вида: контровой свет.
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
