extends Control
## Палитра (C): цвет, в который красятся базовые детали из инвентаря.

const Ui := preload("res://scripts/ui/ui.gd")
const Style := preload("res://scripts/style.gd")

const NAMES := {
	"white": "белый", "light_gray": "светло-серый", "dark_gray": "тёмно-серый", "black": "чёрный",
	"red": "красный", "dark_red": "тёмно-красный", "orange": "оранжевый", "yellow": "жёлтый",
	"tan": "бежевый", "brown": "коричневый", "lime": "салатовый", "green": "зелёный",
	"dark_green": "тёмно-зелёный", "azure": "лазурный", "light_blue": "голубой", "dark_brown": "тёмно-коричневый", "sand": "песочный", "blue": "синий", "dark_blue": "тёмно-синий",
	"purple": "фиолетовый", "pink": "розовый", "glass": "стекло", "trans_blue": "синее стекло", "trans_orange": "оранжевое стекло", "trans_yellow": "жёлтое стекло", "trans_red": "красное стекло", "trans_green": "зелёное стекло", "gold": "золото", "silver": "серебро",
}

var ui
var _grid: GridContainer
var _current: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := Ui.panel(Ui.PAPER, 18, 18)
	center.add_child(panel)
	var col := Ui.vbox(12)
	panel.add_child(col)
	var head := Ui.hbox(10)
	var t := Ui.label("Цвет деталей", 22, Ui.INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(Ui.button("Готово (C)", func() -> void: ui.close_modal(), "plain", 14))
	col.add_child(head)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	col.add_child(_grid)
	_current = Ui.label("", 15, Ui.INK_SOFT)
	col.add_child(_current)
	visibility_changed.connect(_fill)


func _fill() -> void:
	if not visible:
		return
	for c in _grid.get_children():
		c.queue_free()
	for name: String in Style.COLORS:
		var on: bool = ui.bridge.paint == name
		var b := Button.new()
		b.custom_minimum_size = Vector2(48, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = NAMES.get(name, name.replace("_", " "))
		var c: Color = Style.COLORS[name]
		for state in ["normal", "hover", "pressed"]:
			var s := Ui.box(c, 10, 0, state == "hover", Ui.INK if on else Color(0, 0, 0, 0.18), 4 if on else 2)
			b.add_theme_stylebox_override(state, s)
		b.pressed.connect(func() -> void:
			ui.bridge.set_paint(name)
			ui.sfx.play("click")
			_fill())
		_grid.add_child(b)
	_current.text = "Сейчас: %s. Цвет меняется у базовых деталей: кирпичей, пластин, плиток." % NAMES.get(ui.bridge.paint, ui.bridge.paint)
