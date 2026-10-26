extends RefCounted
## Деревня у реки: фахверковые дома с дымящими трубами, мельница, причал
## с лодкой, фонари, костёр, заборы и всякая мелочь.

const Style := preload("res://scripts/style.gd")


static func build(world: Node3D) -> void:
	var vc: Vector2 = world.village_center()
	var root := Node3D.new()
	root.name = "Village"
	root.position = Vector3(vc.x, world.VILLAGE_LEVEL, vc.y)
	world.add_child(root)

	_house(world, root, Vector3(-7, 0, 3), 0.25, 5.0, 4.5, 1)
	_house(world, root, Vector3(1, 0, -2), -0.08, 6.5, 5.0, 2)
	_house(world, root, Vector3(9, 0, 4), 0.4, 4.5, 4.0, 1)
	_house(world, root, Vector3(-4, 0, -11), 0.1, 5.0, 4.5, 2)
	_house(world, root, Vector3(-14, 0, -4), 0.6, 4.0, 4.0, 1)
	_windmill(world, root, Vector3(13, 0, -9))
	_dock(world, root)
	_campfire(world, root, Vector3(-2, 0, 6.5))
	for p: Vector3 in [Vector3(4, 0, 8), Vector3(-9, 0, 9), Vector3(5, 0, -8)]:
		_lantern(root, p)
	_props(root)
	_bridge(world)
	# Фонарь на смотровом пригорке, как слева на референсе.
	var sp: Vector2 = world.spawn_point()
	var spot := Node3D.new()
	world.add_child(spot)
	spot.position = Vector3(sp.x - 3.0, world.height_at(sp.x - 3.0, sp.y - 2.0), sp.y - 2.0)
	_lantern(spot, Vector3.ZERO)


static func _house(world: Node3D, parent: Node3D, pos: Vector3, yaw: float, w: float, d: float, floors: int) -> void:
	var S := Style
	var P := S.PALETTE
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	parent.add_child(body)
	var fh := 2.6
	var h := fh * floors
	var wall := S.toon(P.wall, 0.04)
	var beam := S.toon(P.beam, 0.0)
	var roof_mat := S.toon(P.roof, 0.06)

	# Каменный цоколь и стены.
	S.add_part(body, S.box(Vector3(w + 0.3, 0.6, d + 0.3)), S.toon(P.stone, 0.04), Vector3(0, 0.3, 0))
	S.add_part(body, S.box(Vector3(w, h, d)), wall, Vector3(0, h * 0.5 + 0.3, 0))

	# Фахверк: угловые стойки, пояса между этажами и раскосы на фасаде.
	for cx: float in [-0.5, 0.5]:
		for cz: float in [-0.5, 0.5]:
			S.add_part(body, S.box(Vector3(0.24, h, 0.24)), beam, Vector3(cx * w, h * 0.5 + 0.3, cz * d))
	for f in floors + 1:
		var y := 0.3 + f * fh
		for cz: float in [-0.5, 0.5]:
			S.add_part(body, S.box(Vector3(w + 0.1, 0.2, 0.24)), beam, Vector3(0, y, cz * d))
		for cx: float in [-0.5, 0.5]:
			S.add_part(body, S.box(Vector3(0.24, 0.2, d + 0.1)), beam, Vector3(cx * w, y, 0))
	for f in floors:
		var y := 0.3 + f * fh + fh * 0.5
		for side: float in [-1.0, 1.0]:
			S.add_part(body, S.box(Vector3(0.14, fh * 1.05, 0.08)), beam, Vector3(side * w * 0.42, y, d * 0.5 + 0.05), Vector3(0, 0, side * 0.45))

	# Окна с переплётом и ящиками для цветов.
	var win := S.glow(P.window, 1.6)
	for f in floors:
		var y := 0.3 + f * fh + fh * 0.55
		for side: float in [-1.0, 1.0]:
			if f == 0 and side > 0 and floors == 1:
				continue
			var wx := side * w * 0.22
			S.add_part(body, S.box(Vector3(0.8, 0.9, 0.08)), win, Vector3(wx, y, d * 0.5 + 0.03))
			S.add_part(body, S.box(Vector3(0.95, 0.1, 0.12)), beam, Vector3(wx, y + 0.47, d * 0.5 + 0.06))
			S.add_part(body, S.box(Vector3(0.95, 0.1, 0.12)), beam, Vector3(wx, y - 0.47, d * 0.5 + 0.06))
			S.add_part(body, S.box(Vector3(0.06, 0.9, 0.1)), beam, Vector3(wx, y, d * 0.5 + 0.06))
			S.add_part(body, S.box(Vector3(0.8, 0.06, 0.1)), beam, Vector3(wx, y, d * 0.5 + 0.06))
			S.add_part(body, S.box(Vector3(0.9, 0.2, 0.25)), S.toon(P.wood, 0.02), Vector3(wx, y - 0.6, d * 0.5 + 0.15))
			for k in 3:
				S.add_part(body, S.sphere(0.1, 6, 4), S.toon(P.flower, 0.015), Vector3(wx - 0.25 + k * 0.25, y - 0.45, d * 0.5 + 0.18))
		# Боковое окно.
		S.add_part(body, S.box(Vector3(0.08, 0.8, 0.7)), win, Vector3(w * 0.5 + 0.03, 0.3 + f * fh + fh * 0.55, 0))

	# Дверь с козырьком и ступенькой.
	var door_x := w * 0.22 if floors == 1 else 0.0
	S.add_part(body, S.box(Vector3(1.0, 1.9, 0.1)), S.toon(P.wood, 0.03), Vector3(door_x, 1.25, d * 0.5 + 0.05))
	S.add_part(body, S.box(Vector3(0.12, 0.12, 0.05)), S.toon(P.beam, 0.0), Vector3(door_x + 0.3, 1.2, d * 0.5 + 0.12))
	S.add_part(body, S.box(Vector3(1.6, 0.25, 0.8)), S.toon(P.stone, 0.03), Vector3(door_x, 0.12, d * 0.5 + 0.45))
	S.add_part(body, S.box(Vector3(1.6, 0.08, 0.8)), roof_mat, Vector3(door_x, 2.45, d * 0.5 + 0.35), Vector3(0.35, 0, 0))

	# Крутая крыша со свесами, конёк и труба с дымом.
	var rh := 2.4 + w * 0.15
	S.add_part(body, S.prism(Vector3(w + 1.3, rh, d + 1.1)), roof_mat, Vector3(0, h + 0.3 + rh * 0.5, 0))
	S.add_part(body, S.box(Vector3(0.2, 0.2, d + 1.2)), beam, Vector3(0, h + 0.3 + rh, 0))
	var chimney := Vector3(w * 0.28, h + 0.3 + rh * 0.75, -d * 0.18)
	S.add_part(body, S.box(Vector3(0.7, rh, 0.7)), S.toon(P.stone, 0.04), chimney)
	S.add_part(body, S.box(Vector3(0.85, 0.15, 0.85)), S.toon(P.stone, 0.03), chimney + Vector3(0, rh * 0.5, 0))
	S.smoke(body, chimney + Vector3(0, rh * 0.5 + 0.3, 0))
	if floors == 2:
		# Слуховое окно.
		var dormer := Vector3(0, h + 0.3 + rh * 0.35, d * 0.25)
		S.add_part(body, S.box(Vector3(1.2, 1.0, 1.2)), wall, dormer)
		S.add_part(body, S.prism(Vector3(1.5, 0.8, 1.4)), roof_mat, dormer + Vector3(0, 0.9, 0))
		S.add_part(body, S.box(Vector3(0.6, 0.6, 0.05)), win, dormer + Vector3(0, 0, 0.61))

	S.add_box_collider(body, Vector3(w + 0.3, h + 0.3, d + 0.3), Vector3(0, (h + 0.3) * 0.5, 0))


static func _windmill(world: Node3D, parent: Node3D, pos: Vector3) -> void:
	var S := Style
	var P := S.PALETTE
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	S.add_part(body, S.cylinder(1.3, 2.2, 10.0, 8), S.toon(P.stone, 0.05), Vector3(0, 5.0, 0))
	for y: float in [3.0, 6.5]:
		S.add_part(body, S.box(Vector3(0.6, 0.7, 0.08)), S.glow(P.window, 1.4), Vector3(0, y, 1.85 - y * 0.07))
	S.add_part(body, S.cylinder(0.0, 1.9, 2.6, 8), S.toon(P.roof, 0.05), Vector3(0, 11.3, 0))
	S.add_part(body, S.box(Vector3(0.8, 1.9, 0.1)), S.toon(P.wood, 0.03), Vector3(0, 1.0, 2.2))

	var blades := Node3D.new()
	blades.position = Vector3(0, 9.0, 1.9)
	body.add_child(blades)
	S.add_part(blades, S.cylinder(0.3, 0.3, 0.6, 8), S.toon(P.beam, 0.03), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	var wood := S.toon(P.wood, 0.03)
	var cloth := S.toon(P.cloth, 0.03)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = i * PI * 0.5
		blades.add_child(arm)
		S.add_part(arm, S.box(Vector3(0.2, 6.0, 0.15)), wood, Vector3(0, 3.0, 0.1))
		S.add_part(arm, S.box(Vector3(1.3, 4.6, 0.05)), cloth, Vector3(0.75, 3.6, 0.15))
		for k in 4:
			S.add_part(arm, S.box(Vector3(1.4, 0.08, 0.08)), wood, Vector3(0.75, 1.5 + k * 1.4, 0.2))
	world.animated.append(func(delta: float) -> void: blades.rotate_z(delta * 0.5))
	S.add_box_collider(body, Vector3(3.6, 10.0, 3.6), Vector3(0, 5.0, 0))


static func _dock(world: Node3D, parent: Node3D) -> void:
	var S := Style
	var P := S.PALETTE
	var body := StaticBody3D.new()
	body.position = Vector3(2, 0, 0)
	parent.add_child(body)
	var top: float = world.WATER_LEVEL - world.VILLAGE_LEVEL + 0.7
	var start := 11.0
	var length := 10.0
	var wood := S.toon(P.wood, 0.03)
	for i in 14:
		S.add_part(body, S.box(Vector3(2.6, 0.12, 0.62)), wood, Vector3(0, top, start + 0.35 + i * 0.7), Vector3(0, randf_range(-0.03, 0.03), 0))
	for i in 5:
		for side: float in [-1.25, 1.25]:
			S.add_part(body, S.cylinder(0.13, 0.15, 3.4, 6), S.toon(P.bark, 0.03), Vector3(side, top - 1.2, start + 0.5 + i * 2.3))
	for side: float in [-1.25, 1.25]:
		S.add_part(body, S.box(Vector3(0.1, 0.1, length)), wood, Vector3(side, top + 0.9, start + length * 0.5))
	S.add_box_collider(body, Vector3(2.6, 0.2, length), Vector3(0, top, start + length * 0.5))
	S.add_box_collider(body, Vector3(2.6, 0.2, 6.0), Vector3(0, top * 0.5, start - 2.0), Vector3(-atan2(top, 6.0), 0, 0))

	# Лодка: перевёрнутая призма даёт V-образный корпус.
	var boat := Node3D.new()
	boat.position = Vector3(2.8, top - 0.55, start + 6.0)
	boat.rotation.y = 0.12
	body.add_child(boat)
	S.add_part(boat, S.prism(Vector3(1.6, 0.8, 3.8)), wood, Vector3.ZERO, Vector3(0, 0, PI))
	S.add_part(boat, S.box(Vector3(1.4, 0.08, 0.3)), S.toon(P.beam, 0.02), Vector3(0, 0.36, 0.5))
	S.add_part(boat, S.box(Vector3(0.08, 0.08, 2.4)), S.toon(P.beam, 0.02), Vector3(0.5, 0.42, -0.2), Vector3(0, 0.1, 0.2))
	var base_y := boat.position.y
	world.animated.append(func(_d: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		boat.position.y = base_y + sin(t * 1.3) * 0.05
		boat.rotation.z = sin(t * 0.9) * 0.04)


static func _lantern(parent: Node3D, pos: Vector3) -> void:
	var S := Style
	var P := S.PALETTE
	var node := Node3D.new()
	node.position = pos
	parent.add_child(node)
	var beam := S.toon(P.beam, 0.03)
	S.add_part(node, S.box(Vector3(0.22, 3.2, 0.22)), beam, Vector3(0, 1.6, 0))
	S.add_part(node, S.box(Vector3(1.0, 0.16, 0.16)), beam, Vector3(0.4, 3.1, 0))
	S.add_part(node, S.box(Vector3(0.08, 0.5, 0.08)), beam, Vector3(0.1, 2.85, 0), Vector3(0, 0, -0.7))
	S.add_part(node, S.cylinder(0.05, 0.3, 0.25, 6), beam, Vector3(0.8, 2.85, 0))
	S.add_part(node, S.cylinder(0.2, 0.2, 0.45, 6), S.glow(P.window, 3.0), Vector3(0.8, 2.5, 0))
	S.add_part(node, S.box(Vector3(0.45, 0.06, 0.45)), beam, Vector3(0.8, 2.25, 0))
	var light := OmniLight3D.new()
	light.light_color = P.window
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.position = Vector3(0.8, 2.4, 0)
	node.add_child(light)


static func _campfire(world: Node3D, parent: Node3D, pos: Vector3) -> void:
	var S := Style
	var P := S.PALETTE
	var node := Node3D.new()
	node.position = pos
	parent.add_child(node)
	for i in 9:
		var a := i * TAU / 9.0
		S.add_part(node, S.sphere(0.22, 6, 4), S.toon(P.rock, 0.03), Vector3(cos(a) * 0.75, 0.1, sin(a) * 0.75))
	for i in 3:
		S.add_part(node, S.cylinder(0.08, 0.1, 1.1, 6), S.toon(P.bark, 0.02), Vector3(0, 0.25, 0), Vector3(0.9, i * TAU / 3.0, 0))
	var flames := Node3D.new()
	node.add_child(flames)
	for i in 3:
		S.add_part(flames, S.cylinder(0.0, 0.3 - i * 0.07, 0.9 - i * 0.15, 6), S.glow(P.fire, 3.5 - i), Vector3(0.1 * (i - 1), 0.6, 0.05 * i))
	var light := OmniLight3D.new()
	light.light_color = P.fire
	light.light_energy = 2.5
	light.omni_range = 10.0
	light.position = Vector3(0, 1.0, 0)
	node.add_child(light)
	S.smoke(node, Vector3(0, 1.3, 0), 0.25)
	# Брёвна-скамейки вокруг.
	for i in 3:
		var a := 0.6 + i * TAU / 3.0
		S.add_part(node, S.cylinder(0.25, 0.25, 1.8, 8), S.toon(P.wood, 0.03), Vector3(cos(a) * 2.2, 0.25, sin(a) * 2.2), Vector3(PI * 0.5, 0, 0)).rotate_y(a)
	world.animated.append(func(_d: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		var f := 1.0 + sin(t * 9.0) * 0.08 + sin(t * 23.0) * 0.05
		flames.scale = Vector3(1.0, f, 1.0)
		light.light_energy = 2.2 + sin(t * 13.0) * 0.4)


static func _props(parent: Node3D) -> void:
	var S := Style
	var P := S.PALETTE
	var wood := S.toon(P.wood, 0.03)
	var beam := S.toon(P.beam, 0.02)
	# Бочки и ящики у домов.
	for p: Vector3 in [Vector3(-3.6, 0, 5.2), Vector3(-3.0, 0, 5.9), Vector3(6.5, 0, -1.0)]:
		S.add_part(parent, S.cylinder(0.38, 0.33, 0.9, 10), wood, p + Vector3(0, 0.45, 0))
		S.add_part(parent, S.cylinder(0.4, 0.4, 0.06, 10), beam, p + Vector3(0, 0.7, 0))
	for p: Vector3 in [Vector3(4.8, 0, 2.0), Vector3(5.4, 0, 2.6), Vector3(5.0, 0.7, 2.3)]:
		S.add_part(parent, S.box(Vector3(0.7, 0.7, 0.7)), wood, p + Vector3(0, 0.35, 0), Vector3(0, p.x, 0))
	# Забор вдоль берега.
	for i in 12:
		var x := -16.0 + i * 1.6
		S.add_part(parent, S.box(Vector3(0.14, 1.1, 0.14)), beam, Vector3(x, 0.55, 10.5))
		if i < 11:
			S.add_part(parent, S.box(Vector3(1.6, 0.1, 0.08)), wood, Vector3(x + 0.8, 0.8, 10.5))
			S.add_part(parent, S.box(Vector3(1.6, 0.1, 0.08)), wood, Vector3(x + 0.8, 0.45, 10.5))
	# Знамя на шесте, как справа на референсе.
	S.add_part(parent, S.cylinder(0.07, 0.07, 5.0, 6), beam, Vector3(10.5, 2.5, 7.0))
	S.add_part(parent, S.box(Vector3(1.0, 1.8, 0.05)), S.toon(P.cloth, 0.03), Vector3(10.5, 3.7, 7.05))
	S.add_part(parent, S.sphere(0.25, 8, 5), S.toon(P.beam, 0.0), Vector3(10.5, 3.9, 7.1), Vector3.ZERO, Vector3(1, 1.4, 0.2))


## Каменный мост через реку выше по течению.
static func _bridge(world: Node3D) -> void:
	var S := Style
	var P := S.PALETTE
	var x: float = world.VILLAGE_X - 42.0
	var zc: float = world.river_z(x)
	var length := 30.0
	var deck_y := 3.2
	var body := StaticBody3D.new()
	body.name = "Bridge"
	body.position = Vector3(x, 0, zc)
	world.add_child(body)
	var stone := S.toon(P.stone, 0.05)
	S.add_part(body, S.box(Vector3(3.2, 0.6, length)), stone, Vector3(0, deck_y, 0))
	for side: float in [-1.5, 1.5]:
		S.add_part(body, S.box(Vector3(0.3, 0.7, length)), stone, Vector3(side, deck_y + 0.6, 0))
	for i in 4:
		var z := -10.5 + i * 7.0
		S.add_part(body, S.box(Vector3(3.0, deck_y + 3.0, 1.4)), stone, Vector3(0, (deck_y - 3.0) * 0.5, z))
		S.add_box_collider(body, Vector3(3.0, deck_y + 3.0, 1.4), Vector3(0, (deck_y - 3.0) * 0.5, z))
	S.add_box_collider(body, Vector3(3.2, 0.6, length), Vector3(0, deck_y, 0))
	for side: float in [-1.5, 1.5]:
		S.add_box_collider(body, Vector3(0.3, 1.4, length), Vector3(side, deck_y + 0.6, 0))
