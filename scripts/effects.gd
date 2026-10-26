extends Node
## Как объекты появляются и исчезают. Новая постройка собирается снизу
## вверх слой за слоем, удалённая рассыпается на кирпичики, которые
## прыгают по пластине и пропадают. Если постройка встала прямо на игрока,
## он оказывается на её крыше, а не внутри стен.

const Bricks := preload("res://scripts/bricks.gd")
const Bridge := preload("res://scripts/agent_bridge.gd")
const Style := preload("res://scripts/style.gd")

const MAX_DEBRIS := 120
## Скорость сборки: метров высоты в секунду.
const REVEAL_SPEED := 6.0

var world
var bridge
var sfx
var _debris: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	bridge.object_added.connect(_on_added)
	bridge.object_removing.connect(_on_removing)


func _on_added(node: Node3D, animate: bool) -> void:
	if not animate:
		return
	var box := Bridge.node_aabb(node)
	if box.size == Vector3.ZERO:
		return
	_unstick_player(box)
	if sfx:
		sfx.play("place" if box.size.y < 1.5 else "snap", 1.0 if box.size.y < 1.5 else 0.8)
	_reveal(node, box)


## Постройка вырастает снизу вверх: всё выше границы не рисуется.
func _reveal(node: Node3D, box: AABB) -> void:
	var mats: Array[ShaderMaterial] = []
	var restore: Array = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MultiMeshInstance3D:
			var m = n.material_override
			if m is ShaderMaterial:
				var dup: ShaderMaterial = m.duplicate()
				n.material_override = dup
				mats.append(dup)
				restore.append([n, -1, m])
		elif n is MeshInstance3D and n.mesh != null:
			for i in n.mesh.get_surface_count():
				var m = n.get_active_material(i)
				if m is ShaderMaterial:
					var dup: ShaderMaterial = m.duplicate()
					var had = n.get_surface_override_material(i)
					n.set_surface_override_material(i, dup)
					mats.append(dup)
					restore.append([n, i, had])
	if mats.is_empty():
		return
	var from := box.position.y - 0.05
	var to := box.end.y + 0.1
	var seconds := clampf((to - from) / REVEAL_SPEED, 0.35, 2.2)
	var set_level := func(y: float) -> void:
		for m in mats:
			m.set_shader_parameter("reveal", y)
	set_level.call(from)
	# Твин живёт вместе с объектом: убрали объект, сборка остановилась.
	var tw := node.create_tween()
	tw.tween_method(set_level, from, to, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		# Общие материалы возвращаются на место: так меньше вызовов отрисовки.
		for r in restore:
			if not is_instance_valid(r[0]):
				continue
			if r[1] < 0:
				r[0].material_override = r[2]
			else:
				r[0].set_surface_override_material(r[1], r[2]))


func _unstick_player(box: AABB) -> void:
	var p: Node3D = world.player
	if p == null or p.riding != null:
		return
	var pos := p.global_position
	var grown := box.grow(0.3)
	if pos.x > grown.position.x and pos.x < grown.end.x and pos.z > grown.position.z and pos.z < grown.end.z \
			and pos.y + 1.4 > box.position.y and pos.y < box.end.y - 0.05:
		p.global_position.y = box.end.y + 0.05
		p.velocity = Vector3.ZERO


# --- Рассыпание на кирпичи ------------------------------------------------

func _on_removing(node: Node3D) -> void:
	var box := Bridge.node_aabb(node)
	if box.size == Vector3.ZERO:
		return
	if sfx:
		sfx.play("break")
	var colors := _colors_of(node)
	var count := clampi(int(box.size.x * box.size.z * 1.2 + box.size.y * 4.0), 6, 28)
	for i in count:
		if _debris.size() >= MAX_DEBRIS:
			var old: Dictionary = _debris.pop_front()
			if is_instance_valid(old.node):
				old.node.queue_free()
		var piece := Node3D.new()
		var w := 2 if _rng.randf() < 0.5 else 1
		Bricks.build(piece, Bricks.expand([{"type": "plate" if _rng.randf() < 0.5 else "brick", "at": [0, 0, 0], "size": [w, 1], "color": colors[_rng.randi() % colors.size()]}]))
		world.add_child(piece)
		piece.global_position = Vector3(
			_rng.randf_range(box.position.x, box.end.x),
			_rng.randf_range(box.position.y, box.end.y),
			_rng.randf_range(box.position.z, box.end.z))
		piece.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		var out := (piece.global_position - box.get_center())
		out.y = 0.0
		var vel := out.normalized() * _rng.randf_range(1.0, 3.5) + Vector3(0, _rng.randf_range(2.0, 5.5), 0)
		_debris.append({"node": piece, "vel": vel, "spin": Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8)), "life": _rng.randf_range(1.2, 1.8)})


func _process(delta: float) -> void:
	for d in _debris.duplicate():
		var n: Node3D = d.node
		if not is_instance_valid(n):
			_debris.erase(d)
			continue
		d.life -= delta
		if d.life <= 0.0:
			n.queue_free()
			_debris.erase(d)
			continue
		d.vel.y -= 18.0 * delta
		n.global_position += d.vel * delta
		n.rotation += d.spin * delta
		if n.global_position.y < 0.05:
			n.global_position.y = 0.05
			d.vel.y = absf(d.vel.y) * 0.35
			d.vel.x *= 0.6
			d.vel.z *= 0.6
			d.spin *= 0.5
		if d.life < 0.35:
			n.scale = Vector3.ONE * maxf(d.life / 0.35, 0.01)


## Цвета объекта: берём из цветов вершин его кирпичей.
func _colors_of(node: Node3D) -> Array[String]:
	var found := {}
	var stack: Array[Node] = [node]
	while not stack.is_empty() and found.size() < 6:
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh is ArrayMesh and n.mesh.get_surface_count() > 0:
			var arrays: Array = n.mesh.surface_get_arrays(0)
			var cols = arrays[Mesh.ARRAY_COLOR]
			if cols is PackedColorArray and not cols.is_empty():
				var step := maxi(1, cols.size() / 12)
				for i in range(0, cols.size(), step):
					var c: Color = cols[i]
					found[Style.nearest(c if Style._compat() else c.linear_to_srgb())] = true
	var out: Array[String] = []
	for k in found:
		out.append(str(k))
	if out.is_empty():
		out = ["red", "yellow", "blue", "white"]
	return out
