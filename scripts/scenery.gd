extends RefCounted
## Дальний план: кольцо гор, облака и летающий остров с башней.
## Эти объекты недостижимы и нужны для глубины кадра, как на референсах.

const Style := preload("res://scripts/style.gd")


static func build(world: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	_mountains(world, rng)
	_clouds(world, rng)
	_floating_island(world, rng)


static func _mountains(world: Node3D, rng: RandomNumberGenerator) -> void:
	var S := Style
	var peaks: Array[Transform3D] = []
	for ring in 2:
		var count := 26 + ring * 10
		for i in count:
			var a := (i + rng.randf() * 0.6) * TAU / count
			var dist := rng.randf_range(210.0, 260.0) + ring * 140.0
			var r := rng.randf_range(35.0, 70.0) * (1.0 + ring * 0.5)
			var h := rng.randf_range(50.0, 120.0) * (1.0 + ring * 0.6)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, h, r * rng.randf_range(0.6, 1.0)))
			peaks.append(Transform3D(basis, Vector3(cos(a) * dist, -15.0, sin(a) * dist)))
	# Единичный конус с вершиной немного в стороне, чтобы пики не были одинаковыми.
	var cone := S.merge([
		[S.cylinder(0.02, 1.0, 1.0, 7), S.at(Vector3(0, 0.5, 0))],
		[S.cylinder(0.02, 0.6, 0.75, 6), S.at(Vector3(0.45, 0.37, 0.2))],
	])
	S.multimesh(world, cone, S.toon(S.PALETTE.mountain, 0.0), peaks, false)


static func _clouds(world: Node3D, rng: RandomNumberGenerator) -> void:
	var S := Style
	var root := Node3D.new()
	root.name = "Clouds"
	world.add_child(root)
	var mat := S.toon(S.PALETTE.cloud, 0.0)
	var puff := S.sphere(1.0, 12, 7)
	for i in 22:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(160.0, 330.0)
		var cloud := Node3D.new()
		cloud.position = Vector3(cos(a) * dist, rng.randf_range(45.0, 95.0), sin(a) * dist)
		root.add_child(cloud)
		var size := rng.randf_range(8.0, 16.0)
		for k in rng.randi_range(5, 9):
			var s := size * rng.randf_range(0.5, 1.0)
			var p := Vector3(rng.randf_range(-2.2, 2.2) * size, rng.randf_range(-0.2, 0.6) * size, rng.randf_range(-0.8, 0.8) * size)
			var mi := S.add_part(cloud, puff, mat, p, Vector3.ZERO, Vector3(s, s * 0.75, s))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.animated.append(func(delta: float) -> void: root.rotate_y(delta * 0.004))


## Летающий остров с высокой каменной башней, ориентир на горизонте.
static func _floating_island(world: Node3D, rng: RandomNumberGenerator) -> void:
	var S := Style
	var P := S.PALETTE
	var root := Node3D.new()
	root.name = "FloatingIsland"
	root.position = Vector3(world.VILLAGE_X - 20.0, 62.0, -190.0)
	world.add_child(root)
	var rock := S.toon(P.rock_dark, 0.0)
	var stone := S.toon(P.stone, 0.0)
	S.add_part(root, S.cylinder(20.0, 2.0, 32.0, 9), rock, Vector3(0, -16.0, 0))
	S.add_part(root, S.cylinder(13.0, 1.5, 22.0, 8), rock, Vector3(8.0, -20.0, 5.0))
	S.add_part(root, S.cylinder(20.5, 20.0, 2.0, 12), S.toon(P.grass, 0.0), Vector3(0, 0.5, 0))

	# Башня из смещённых блоков, как на референсе.
	var y := 1.5
	var blocks := [Vector3(16, 18, 13), Vector3(12, 14, 10), Vector3(14, 10, 9), Vector3(9, 12, 8), Vector3(6, 8, 6)]
	for b: Vector3 in blocks:
		var off := Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-1.5, 1.5))
		S.add_part(root, S.box(b), stone, Vector3(0, y + b.y * 0.5, 0) + off)
		# Тёмные окна-провалы на фасаде.
		for k in 4:
			S.add_part(root, S.box(Vector3(1.2, 2.0, 0.3)), rock, off + Vector3(rng.randf_range(-0.4, 0.4) * b.x, y + rng.randf_range(0.2, 0.8) * b.y, b.z * 0.5 + 0.1))
		# Пристройки и балконы.
		S.add_part(root, S.box(Vector3(3.0, 3.5, 3.0)), stone, off + Vector3(b.x * 0.5 + 1.0, y + b.y * 0.6, rng.randf_range(-2.0, 2.0)))
		y += b.y
	S.add_part(root, S.cylinder(0.0, 3.5, 7.0, 8), S.toon(P.roof, 0.0), Vector3(0, y + 3.5, 0))
	# Деревья на краю острова.
	for i in 7:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 16.0, 1.5, sin(a) * 16.0)
		S.add_part(root, S.cylinder(0.0, 2.2, 6.0, 8), S.toon(P.pine, 0.0), p + Vector3(0, 3.5, 0))
	# Лианы, свисающие с краёв.
	for i in 14:
		var a := rng.randf() * TAU
		var vine := rng.randf_range(6.0, 16.0)
		S.add_part(root, S.cylinder(0.15, 0.08, vine, 4), S.toon(P.leaf, 0.0), Vector3(cos(a) * 17.0, -vine * 0.5, sin(a) * 17.0))
	# Водопад, срывающийся с острова.
	var fall := S.add_part(root, S.box(Vector3(3.0, 70.0, 0.6)), S.glow(P.cloud, 0.6), Vector3(-6.0, -35.0, 19.0))
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Маленькие парящие камни вокруг.
	var shards: Array[Node3D] = []
	for i in 6:
		var a := i * TAU / 6.0 + 0.4
		var s := rng.randf_range(2.0, 4.0)
		var shard := S.add_part(root, S.cylinder(s, 0.3, s * 2.2, 7), rock, Vector3(cos(a) * 34.0, rng.randf_range(-12.0, 10.0), sin(a) * 34.0))
		shards.append(shard)
	var base := root.position.y
	world.animated.append(func(_d: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		root.position.y = base + sin(t * 0.25) * 1.5
		for i in shards.size():
			shards[i].position.y += sin(t * 0.6 + i) * 0.004)
