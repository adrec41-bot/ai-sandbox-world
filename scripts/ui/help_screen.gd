extends Control
## Все клавиши игры (F1).

const Ui := preload("res://scripts/ui/ui.gd")

const GROUPS := [
	["Ходить", [
		["W A S D", "идти"], ["Shift", "бежать"], ["Пробел", "прыгать"], ["Мышь", "смотреть"],
		["Колесо", "камера ближе / дальше"], ["E", "сесть в транспорт, надеть, включить"],
	]],
	["Предметы", [
		["1–9", "выбрать слот"], ["Shift+колесо", "листать слоты"], ["F", "поставить перед собой"],
		["G", "подобрать постройку"], ["Tab", "инвентарь"], ["C", "цвет базовых деталей"],
	]],
	["Строительство (B)", [
		["ЛКМ", "поставить деталь"], ["R / Shift+R", "повернуть"], ["Колесо", "выше / ниже на пластину"],
		["Ctrl+колесо", "камера"], ["ПКМ", "выделить (Shift: ещё)"], ["M", "переместить выделенное"],
		["Ctrl+D", "копия"], ["Delete", "удалить"], ["СКМ", "взять образец в слот"],
		["Alt+ЛКМ", "отметить площадку для ИИ"], ["Alt+ПКМ", "убрать площадку"], ["V", "вид сверху"],
	]],
	["ИИ и прочее", [
		["Enter или /", "попросить ИИ"], ["Shift+Enter", "новая строка"], ["↑ ↓", "прошлые просьбы"],
		["L", "журнал просьб"], ["Ctrl+Z / Ctrl+Y", "отменить / вернуть"], ["F2", "подключить ИИ"],
		["Esc", "меню"], ["F1", "эта справка"],
	]],
]

var ui


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.11, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := Ui.panel(Ui.PAPER, 18, 22)
	center.add_child(panel)
	var col := Ui.vbox(14)
	panel.add_child(col)
	var head := Ui.hbox(10)
	var t := Ui.label("Клавиши", 26, Ui.INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(Ui.button("Закрыть (F1)", func() -> void: ui.close_modal(), "plain", 14))
	col.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 18)
	col.add_child(grid)
	for g in GROUPS:
		var box := Ui.vbox(6)
		box.add_child(Ui.label(g[0], 18, Ui.BLUE, true))
		for k in g[1]:
			var row := Ui.hbox(10)
			var key := Ui.key(k[0])
			key.custom_minimum_size.x = 130
			row.add_child(key)
			row.add_child(Ui.label(k[1], 15))
			box.add_child(row)
		grid.add_child(box)
