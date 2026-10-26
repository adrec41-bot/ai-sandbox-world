extends Node3D
## Собирает мир: зелёная базовая пластина Lego, небо с кирпичными облаками,
## солнце, игрок-миньфигурка и интерфейс. Всё остальное игрок создаёт сам,
## вручную из кирпичей или через своего ИИ-агента.

const Style := preload("res://scripts/style.gd")
const Bricks := preload("res://scripts/bricks.gd")
const PlayerScript := preload("res://scripts/player.gd")
const PetScript := preload("res://scripts/pet.gd")
const AgentBridge := preload("res://scripts/agent_bridge.gd")
const McpHttp := preload("res://scripts/mcp_http.gd")
const Worlds := preload("res://scripts/worlds.gd")
const GameUi := preload("res://scripts/ui/game_ui.gd")
const WorldSelect := preload("res://scripts/ui/world_select.gd")
const Thumbnails := preload("res://scripts/ui/thumbnails.gd")
const BuildMode := preload("res://scripts/build_mode.gd")
const Effects := preload("res://scripts/effects.gd")
const Sfx := preload("res://scripts/sfx.gd")
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
var build: Node
var ui: Control
var _sun: DirectionalLight3D
var _menu_cam: Camera3D
var animated: Array[Callable] = []
var _carpet: MultiMeshInstance3D
var _clouds: Array[Node3D] = []


func _ready() -> void:
	# --world=<id> открывает мир сразу (создаёт, если его нет): для тестов и скриншотов.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world="):
			var id := arg.trim_prefix("--world=")
			if not FileAccess.file_exists(Worlds.world_path(id)):
				id = Worlds.create(id, 256, "green")
			Worlds.current = id
	if Worlds.current != "" and not FileAccess.file_exists(Worlds.world_path(Worlds.current)):
		Worlds.current = ""
	if Worlds.current == "":
		_open_world_select()
		return
	var meta := Worlds.meta(Worlds.current)
	studs = int(meta.get("studs", 256))
	plate_color = str(meta.get("plate_color", "green"))
	Worlds.backup(Worlds.current)
	var settings := Worlds.load_settings()
	settings["last_world"] = Worlds.current
	Worlds.save_settings(settings)

	SIZE = studs * Style.STUD
	_setup_environment()
	_build_ground()
	_build_clouds()
	_spawn_player()
	player.set_look(settings.get("look", {}))
	var sfx: Node = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	# Через мост ИИ-агенты по MCP создают объекты, они попадают в инвентарь.
	bridge = AgentBridge.new()
	bridge.name = "AgentBridge"
	bridge.world = self
	bridge.world_id = Worlds.current
	var fx: Node = Effects.new()
	fx.name = "Effects"
	fx.world = self
	fx.bridge = bridge
	fx.sfx = sfx
	add_child(bridge)
	add_child(fx)
	var mcp: Node = McpHttp.new()
	mcp.name = "McpHttp"
	mcp.bridge = bridge
	add_child(mcp)
	var thumbs: Node = Thumbnails.new()
	thumbs.name = "Thumbnails"
	add_child(thumbs)
	build = BuildMode.new()
	build.name = "BuildMode"
	build.world = self
	build.bridge = bridge
	build.player = player
	build.sfx = sfx

	ui = GameUi.new()
	ui.world = self
	ui.bridge = bridge
	ui.mcp = mcp
	ui.player = player
	ui.build = build
	ui.thumbs = thumbs
	ui.sfx = sfx
	ui.settings = settings
	build.ui = ui
	add_child(build)
	var layer := CanvasLayer.new()
	layer.add_child(ui)
	add_child(layer)
	ui.apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Список миров поверх пустой пластины, камера медленно облетает её.
func _open_world_select() -> void:
	SIZE = studs * Style.STUD
	_setup_environment()
	_build_ground()
	_build_clouds()
	_menu_cam = Camera3D.new()
	_menu_cam.fov = 50.0
	_menu_cam.far = 1200.0
	add_child(_menu_cam)
	_menu_cam.current = true
	var layer := CanvasLayer.new()
	layer.add_child(WorldSelect.new())
	add_child(layer)


## Тени и объёмные шипы можно выключить в настройках ради скорости.
func set_graphics(shadows: bool, stud_detail: bool) -> void:
	if _sun:
		_sun.shadow_enabled = shadows
	if _carpet:
		_carpet.visible = stud_detail


func _process(delta: float) -> void:
	for f in animated:
		f.call(delta)
	# Объёмные шипы лежат ковром вокруг игрока и переезжают вместе с ним.
	if _menu_cam:
		var t := Time.get_ticks_msec() * 0.00004
		_menu_cam.look_at_from_position(Vector3(cos(t) * 22.0, 9.0, sin(t) * 22.0), Vector3(0, 1.5, 0))
	if _carpet:
		var cam := get_viewport().get_camera_3d()
		var focus: Vector3 = cam.global_position if cam else Vector3.ZERO
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
	_sun = sun


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
