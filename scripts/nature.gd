extends RefCounted
## Природа: деревья трёх видов, трава, кусты, цветы, камыш и камни.
## Всё рисуется через MultiMesh, чтобы тысячи объектов не тормозили.

const Style := preload("res://scripts/style.gd")


static func build(world: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_trees(world, rng)
	_undergrowth(world, rng)
	_rocks(world, rng)


static func _clear(world: Node3D, x: float, z: float, river: float, village: float, spawn: float) -> bool:
	if world.river_dist(x, z) < river:
		return false
	if Vector2(x, z).distance_to(world.village_center()) < village:
		return false
	if Vector2(x, z).distance_to(world.spawn_point()) < spawn:
		return false
	return world.path_dist(x, z) > 2.5


static func _trees(world: Node3D, rng: RandomNumberGenerator) -> void:
	var S := Style
	var pine_trunk := S.merge([[S.cylinder(0.16, 0.3, 2.2), S.at(Vector3(0, 1.1, 0))]])
	var pine_layers := []
	var radii := [2.0, 1.7, 1.4, 1.05, 0.7]
	for i in radii.size():
		pine_layers.append([S.cylinder(0.0, radii[i], 2.0, 9), S.at(Vector3(0, 2.4 + i * 1.0, 0), Vector3(0, i * 0.7, 0))])
	var pine_crown := S.merge(pine_layers)

	var round_trunk := S.merge([
		[S.cylinder(0.2, 0.34, 3.2), S.at(Vector3(0, 1.6, 0))],
		[S.cylinder(0.06, 0.12, 1.4), S.at(Vector3(0.45, 2.8, 0), Vector3(0, 0, -0.8))],
	])
	var round_crown := S.merge([
		[S.sphere(1.8), S.at(Vector3(0, 4.2, 0))],
		[S.sphere(1.3), S.at(Vector3(1.3, 3.7, 0.4))],
		[S.sphere(1.25), S.at(Vector3(-1.1, 3.9, -0.6))],
		[S.sphere(1.1), S.at(Vector3(0.2, 5.3, -0.3))],
	])

	var giant_trunk := S.merge([
		[S.cylinder(0.45, 0.95, 16.0, 10), S.at(Vector3(0, 8.0, 0))],
		[S.cylinder(0.12, 0.25, 4.0), S.at(Vector3(1.4, 12.5, 0), Vector3(0, 0, -0.9))],
		[S.cylinder(0.1, 0.22, 3.5), S.at(Vector3(-1.2, 14.0, 0.3), Vector3(0.2, 0, 0.9))],
	])
	var giant_crown := S.merge([
		[S.sphere(3.6, 12, 7), S.at(Vector3(0, 17.5, 0))],
		[S.sphere(2.8, 12, 7), S.at(Vector3(2.8, 15.5, 0.6))],
		[S.sphere(2.6, 12, 7), S.at(Vector3(-2.6, 16.2, -0.8))],
		[S.sphere(2.4, 12, 7), S.at(Vector3(0.4, 20.0, 0.3))],
	])

	var pines: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var giants: Array[Transform3D] = []
	var trunks := StaticBody3D.new()
	trunks.name = "Trees"
	world.add_child(trunks)
	# Кроны на отдельном слое: игрок сквозь них проходит, а камера упирается,
	# чтобы не оказаться внутри дерева.
	var crowns := StaticBody3D.new()
	crowns.name = "TreeCrowns"
	crowns.collision_layer = world.CAMERA_LAYER
	crowns.collision_mask = 0
	world.add_child(crowns)

	var forest := FastNoiseLite.new()
	forest.seed = 99
	forest.frequency = 0.03
	var half: float = world.SIZE * 0.47

	var place := func(x: float, z: float, kind: int, s: float) -> void:
		var h: float = world.height_at(x, z)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, h - 0.15, z))
		var trunk_r := 0.3
		var crown_y := 3.6
		var crown_r := 1.9
		match kind:
			0:
				pines.append(t)
			1:
				rounds.append(t)
				crown_y = 4.2
			2:
				giants.append(t)
				trunk_r = 0.8
				crown_y = 17.0
				crown_r = 4.5
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = trunk_r * s
		shape.height = crown_y * s
		col.shape = shape
		col.position = Vector3(x, h + crown_y * s * 0.5, z)
		trunks.add_child(col)
		var crown := CollisionShape3D.new()
		var cs := SphereShape3D.new()
		cs.radius = crown_r * s
		crown.shape = cs
		crown.position = Vector3(x, h + crown_y * s, z)
		crowns.add_child(crown)

	# Два высоких дерева обрамляют стартовый вид, как на референсе.
	var sp: Vector2 = world.spawn_point()
	place.call(sp.x - 8.0, sp.y + 3.0, 2, 1.0)
	place.call(sp.x + 9.0, sp.y + 4.0, 2, 0.9)

	var attempts := 0
	while pines.size() + rounds.size() + giants.size() < 1100 and attempts < 40000:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h: float = world.height_at(x, z)
		if h < 1.2 or h > 30.0:
			continue
		if not _clear(world, x, z, 8.0, 21.0, 12.0):
			continue
		var f := forest.get_noise_2d(x, z)
		if f < -0.2 or (f < 0.1 and rng.randf() < 0.6):
			continue
		var r := rng.randf()
		var kind := 0
		if r < 0.05:
			kind = 2
		elif h < 10.0 and r < 0.55:
			kind = 1
		place.call(x, z, kind, rng.randf_range(0.8, 1.5) if kind != 2 else rng.randf_range(0.8, 1.1))

	S.multimesh(world, pine_trunk, S.toon(S.PALETTE.bark, 0.04), pines)
	S.multimesh(world, pine_crown, S.toon(S.PALETTE.pine, 0.06, false, 0.01), pines)
	S.multimesh(world, round_trunk, S.toon(S.PALETTE.bark, 0.04), rounds)
	S.multimesh(world, round_crown, S.toon(S.PALETTE.leaf, 0.06, false, 0.012), rounds)
	S.multimesh(world, giant_trunk, S.toon(S.PALETTE.bark, 0.06), giants)
	S.multimesh(world, giant_crown, S.toon(S.PALETTE.leaf, 0.08, false, 0.006), giants)


static func _undergrowth(world: Node3D, rng: RandomNumberGenerator) -> void:
	var S := Style
	var half: float = world.SIZE * 0.45

	# Пучок травы из нескольких наклонённых травинок.
	var blades := []
	for i in 5:
		var blade := S.cylinder(0.0, 0.05, rng.randf_range(0.4, 0.7), 3)
		blade.cap_bottom = false
		var a := i * TAU / 5.0
		blades.append([blade, S.at(Vector3(cos(a) * 0.08, 0.25, sin(a) * 0.08), Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35))])
	var tuft := S.merge(blades)
	var bush := S.merge([
		[S.sphere(0.7, 8, 5), S.at(Vector3(0, 0.45, 0))],
		[S.sphere(0.55, 8, 5), S.at(Vector3(0.55, 0.35, 0.2))],
		[S.sphere(0.5, 8, 5), S.at(Vector3(-0.45, 0.3, -0.25))],
	])
	var stem := S.cylinder(0.015, 0.015, 0.5, 4)
	var bloom := S.merge([
		[S.sphere(0.09, 6, 4), S.at(Vector3(0, 0.52, 0))],
		[S.sphere(0.06, 6, 4), S.at(Vector3(0.07, 0.48, 0.03))],
	])
	var reed := S.merge([
		[S.cylinder(0.02, 0.03, 1.4, 4), S.at(Vector3(0, 0.7, 0))],
		[S.cylinder(0.02, 0.03, 1.1, 4), S.at(Vector3(0.12, 0.55, 0.05), Vector3(0.15, 0, -0.12))],
		[S.cylinder(0.06, 0.06, 0.3, 6), S.at(Vector3(0, 1.45, 0))],
	])

	var tufts: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var flowers: Array[Transform3D] = []
	var reeds: Array[Transform3D] = []
	var meadow := FastNoiseLite.new()
	meadow.seed = 5
	meadow.frequency = 0.04

	for i in 26000:
		# Гуще у точки появления и деревни, где игрок проводит больше времени.
		var x: float
		var z: float
		if i < 9000:
			var c: Vector2 = world.spawn_point() if i % 2 == 0 else world.village_center()
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 40.0
			x = c.x + cos(a) * r
			z = c.y + sin(a) * r
		else:
			x = rng.randf_range(-half, half)
			z = rng.randf_range(-half, half)
		var h: float = world.height_at(x, z)
		if h < 1.0 or h > 26.0 or world.path_dist(x, z) < 1.4:
			continue
		if Vector2(x, z).distance_to(world.village_center()) < 15.0 and rng.randf() < 0.7:
			continue
		var s := rng.randf_range(0.45, 0.9)
		tufts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.05, z)))
		var m := meadow.get_noise_2d(x, z)
		if m > 0.25 and rng.randf() < 0.35:
			var fx := x + rng.randf_range(-0.4, 0.4)
			var fz := z + rng.randf_range(-0.4, 0.4)
			flowers.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), Vector3(fx, world.height_at(fx, fz) - 0.05, fz)))

	for i in 1400:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h: float = world.height_at(x, z)
		if h < 1.0 or h > 24.0 or not _clear(world, x, z, 7.0, 16.0, 3.0):
			continue
		var s := rng.randf_range(0.6, 1.5)
		bushes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.85, s)), Vector3(x, h - 0.1, z)))

	for i in 2600:
		var x := rng.randf_range(-half, half)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var z: float = world.river_z(x) + side * rng.randf_range(5.0, 8.5)
		var h: float = world.height_at(x, z)
		if h < -0.6 or h > 1.6:
			continue
		var s := rng.randf_range(0.7, 1.3)
		reeds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.1, z)))

	S.multimesh(world, tuft, S.toon(S.PALETTE.grass_blade, 0.0, false, 0.18), tufts, false)
	S.multimesh(world, bush, S.toon(S.PALETTE.bush, 0.04, false, 0.02), bushes)
	S.multimesh(world, stem, S.toon(S.PALETTE.bush, 0.0, false, 0.15), flowers, false)
	S.multimesh(world, bloom, S.toon(S.PALETTE.flower, 0.02, false, 0.15), flowers, false)
	S.multimesh(world, reed, S.toon(S.PALETTE.wood, 0.0, false, 0.1), reeds, false)


static func _rocks(world: Node3D, rng: RandomNumberGenerator) -> void:
	var S := Style
	var rock := S.sphere(1.0, 7, 4)
	var body := StaticBody3D.new()
	body.name = "Rocks"
	world.add_child(body)
	var half: float = world.SIZE * 0.44
	var small: Array[Transform3D] = []
	var big: Array[Transform3D] = []
	for i in 260:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if not _clear(world, x, z, 3.0, 16.0, 4.0):
			continue
		var h: float = world.height_at(x, z)
		var boulder := rng.randf() < 0.25
		var s := rng.randf_range(1.5, 3.5) if boulder else rng.randf_range(0.3, 1.0)
		var t := Transform3D(Basis.from_euler(Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4)).scaled(Vector3(s * rng.randf_range(1.0, 1.5), s * rng.randf_range(0.6, 0.9), s)), Vector3(x, h - s * 0.2, z))
		if boulder:
			big.append(t)
		else:
			small.append(t)
		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = s * 0.8
		col.shape = shape
		col.position = Vector3(x, h - s * 0.2, z)
		body.add_child(col)
	S.multimesh(world, rock, S.toon(S.PALETTE.rock, 0.05), small)
	S.multimesh(world, rock, S.toon(S.PALETTE.rock_dark, 0.08), big)
