extends Node
## Миниатюры предметов для инвентаря, хотбара и карточек ИИ. Предмет
## рисуется один раз в отдельном мирке за кадром, картинка кладётся в
## user://thumbs и потом берётся оттуда, поэтому инвентарь открывается сразу.

const Builder := preload("res://scripts/object_builder.gd")
const Bridge := preload("res://scripts/agent_bridge.gd")

const SIZE := 192
const DIR := "user://thumbs"

signal thumb_ready(key: String)

var _cache := {}
var _queue: Array = []
var _viewport: SubViewport
var _camera: Camera3D
var _busy := {}
var _wait := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.86)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.75
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)


## Ключ миниатюры: меняется вместе с описанием предмета.
static func key_of(item: Dictionary) -> String:
	return "%s_%d" % [str(item.get("item_id", "x")).replace(":", "_"), hash(JSON.stringify(item.get("spec", {})))]


## Миниатюра предмета или null, если она ещё рисуется (потом придёт thumb_ready).
func get_thumb(item: Dictionary) -> Texture2D:
	if item.is_empty():
		return null
	var key := key_of(item)
	if _cache.has(key):
		return _cache[key]
	var path := "%s/%s.png" % [DIR, key]
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			_cache[key] = ImageTexture.create_from_image(img)
			return _cache[key]
	if not _busy.has(key):
		_busy[key] = true
		_queue.append([key, item.spec])
	return null


func _process(_delta: float) -> void:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_finish()
		return
	if _queue.is_empty():
		return
	var job: Array = _queue.pop_front()
	var spec: Dictionary = (job[1] as Dictionary).duplicate(true)
	# В миниатюре предмет не живой: без механик и физики.
	spec.erase("mechanics")
	spec["physics"] = {"mode": "none"}
	spec.erase("effects")
	var node := Builder.build(spec)
	node.name = "Subject"
	_viewport.add_child(node)
	var box := Bridge.node_aabb(node)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.3)
	var dist := radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.05
	var dir := Vector3(0.75, 0.6, 1.0).normalized()
	_camera.look_at_from_position(center + dir * dist, center)
	_camera.near = maxf(dist - radius * 2.0, 0.05)
	_camera.far = dist + radius * 2.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 3
	set_meta("job", job[0])


func _finish() -> void:
	var key: String = get_meta("job", "")
	var img := _viewport.get_texture().get_image()
	var node := _viewport.get_node_or_null("Subject")
	if node:
		_viewport.remove_child(node)
		node.queue_free()
	_busy.erase(key)
	if img == null or img.is_empty():
		return
	img.save_png("%s/%s.png" % [DIR, key])
	_cache[key] = ImageTexture.create_from_image(img)
	thumb_ready.emit(key)
