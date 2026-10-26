extends Control
## Интерфейс в духе референсов: задание с круглым значком, мини-карта-компас,
## полоски здоровья и сил, панель предметов. Всё рисуется линиями в _draw(),
## поэтому не нужны картинки.

var player
var world

const INK := Color(0.08, 0.07, 0.06, 0.55)
const LINE := Color(1, 0.98, 0.94, 0.92)
const DIM := Color(1, 0.98, 0.94, 0.5)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var sz := get_viewport_rect().size
	_quest(font)
	_minimap(font, Vector2(sz.x - 110, 110))
	_bars(Vector2(36, sz.y - 96))
	draw_string(font, Vector2(36, sz.y - 22), "WASD ходить · Shift бег · Пробел прыжок · клик захватить мышь · колесо зум · Esc отпустить · Enter попросить ИИ · 1–8 слот · F поставить · G подобрать · F2 подключить ИИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)


func _leaf(c: Vector2, r: float, col: Color) -> void:
	# Росток из трёх листьев, как на значке задания.
	draw_line(c + Vector2(0, r * 0.7), c + Vector2(0, -r * 0.1), col, 2.0, true)
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 13:
			var t := float(i) / 12.0
			var along := Vector2(side * r * 0.55, -r * 0.35) * t
			var bulge := Vector2(-along.y, along.x).normalized() * sin(t * PI) * r * 0.18 * side
			pts.append(c + Vector2(0, r * 0.15) + along + bulge)
		draw_polyline(pts, col, 2.0, true)
	draw_arc(c + Vector2(0, -r * 0.25), r * 0.2, 0, TAU, 16, col, 2.0, true)


func _quest(font: Font) -> void:
	var c := Vector2(64, 64)
	draw_circle(c, 30, INK)
	draw_arc(c, 30, 0, TAU, 48, LINE, 2.0, true)
	_leaf(c, 22, LINE)
	var d := Vector2(112, 58)
	var diamond := PackedVector2Array([d + Vector2(0, -6), d + Vector2(6, 0), d + Vector2(0, 6), d + Vector2(-6, 0), d + Vector2(0, -6)])
	draw_polyline(diamond, LINE, 1.5, true)
	draw_string(font, Vector2(128, 64), "Создай свой мир", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, LINE)
	draw_string(font, Vector2(128, 88), "Нажми Enter и попроси ИИ что-нибудь построить", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)


func _minimap(font: Font, c: Vector2) -> void:
	var r := 76.0
	draw_circle(c, r, INK)
	draw_arc(c, r, 0, TAU, 64, LINE, 2.0, true)
	draw_arc(c, r - 8, 0, TAU, 64, DIM, 1.0, true)
	if player == null:
		return
	# Карта вращается вместе с камерой, игрок всегда смотрит вверх.
	var yaw: float = player.yaw
	var scale := r / 70.0
	var me := Vector2(player.position.x, player.position.z)
	# Поставленные в мир объекты точками.
	if world.bridge:
		for pos: Vector2 in world.bridge.placed_positions():
			var rel: Vector2 = (pos - me).rotated(yaw) * scale
			if rel.length() < r - 10:
				draw_circle(c + rel, 3, LINE)
	var tri := PackedVector2Array([c + Vector2(0, -9), c + Vector2(7, 7), c + Vector2(0, 3), c + Vector2(-7, 7)])
	draw_colored_polygon(tri, LINE)
	for p in [["N", 0.0], ["E", PI * 0.5], ["S", PI], ["W", -PI * 0.5]]:
		var dir := Vector2(0, -1).rotated(p[1] + yaw)
		draw_string(font, c + dir * (r + 12) + Vector2(-5, 5), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LINE)


func _heart(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-4, -2), 4.5, col)
	draw_circle(c + Vector2(4, -2), 4.5, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-8.5, 0), c + Vector2(8.5, 0), c + Vector2(0, 9)]), col)


func _bolt(c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(2, -10), c + Vector2(-6, 2), c + Vector2(0, 2), c + Vector2(-2, 10), c + Vector2(6, -2), c + Vector2(0, -2)]), col)


func _bars(o: Vector2) -> void:
	_heart(o + Vector2(0, 0), LINE)
	_bar(o + Vector2(22, -4), 0.85)
	_bolt(o + Vector2(0, 30), LINE)
	_bar(o + Vector2(22, 26), 0.6)


func _bar(p: Vector2, v: float) -> void:
	draw_rect(Rect2(p, Vector2(150, 8)), INK)
	draw_rect(Rect2(p, Vector2(150 * v, 8)), LINE)
