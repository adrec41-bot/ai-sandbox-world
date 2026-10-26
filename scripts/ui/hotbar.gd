extends Control
## Хотбар внизу экрана: 9 слотов с картинками предметов. 1–9 или Shift+колесо
## выбирают слот, F ставит предмет перед собой, в режиме строительства его
## ставит ЛКМ. Предмет из инвентаря перетаскивается в слот мышью или
## назначается клавишей 1–9, пока курсор над карточкой.

const Ui := preload("res://scripts/ui/ui.gd")
const Style := preload("res://scripts/style.gd")

var ui
var _row: HBoxContainer
var _name: Label
var _paint: ColorRect
var _slots: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Ui.vbox(6)
	Ui.pin(col, Control.PRESET_CENTER_BOTTOM, Vector2(0, -16))
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var top := Ui.hbox(8)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint = ColorRect.new()
	_paint.custom_minimum_size = Vector2(16, 16)
	_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_paint)
	_name = Ui.overlay_label("", 15)
	top.add_child(_name)
	col.add_child(top)
	var frame := Ui.panel(Color(0.08, 0.11, 0.14, 0.55), 14, 6)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(frame)
	_row = Ui.hbox(6)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_row)
	for i in ui.bridge.HOTBAR_SIZE:
		var s := Slot.new()
		s.ui = ui
		s.index = i
		s.size_px = 62
		_row.add_child(s)
		_slots.append(s)
	ui.bridge.hotbar_changed.connect(_refresh)
	ui.bridge.inventory_changed.connect(_refresh)
	ui.thumbs.thumb_ready.connect(func(_k: String) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	# Пока открыт инвентарь, у него свой хотбар.
	visible = ui.modal != "inventory"


func _refresh() -> void:
	for s in _slots:
		s.queue_redraw()
	var item: Dictionary = ui.bridge.current_item()
	_name.text = "" if item.is_empty() else str(item.name)
	_paint.visible = not item.is_empty() and str(item.get("color", "")) != ""
	if _paint.visible:
		_paint.color = Style.COLORS.get(ui.bridge.paint, Color.WHITE)


## Слот с картинкой предмета. Его же использует экран инвентаря.
class Slot extends Control:
	const Ui := preload("res://scripts/ui/ui.gd")
	var ui
	var index := 0
	var size_px := 62
	## В инвентаре ПКМ очищает слот.
	var clearable := false

	func _ready() -> void:
		custom_minimum_size = Vector2(size_px, size_px)
		mouse_filter = Control.MOUSE_FILTER_STOP
		ui.bridge.hotbar_changed.connect(queue_redraw)

	func _item() -> Dictionary:
		return ui.bridge.get_item(ui.bridge.hotbar[index])

	func _draw() -> void:
		var sel: bool = ui.bridge.selected == index
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(Ui.box(Color(1, 1, 1, 0.95) if sel else Color(1, 1, 1, 0.78), 10, 0, false, Ui.YELLOW if sel else Color(0, 0, 0, 0.15), 4 if sel else 2), r)
		var item := _item()
		if not item.is_empty():
			var tex: Texture2D = ui.thumbs.get_thumb(item)
			if tex:
				draw_texture_rect(tex, r.grow(-5), false)
			else:
				draw_string(get_theme_default_font(), Vector2(8, size.y * 0.6), str(item.name).left(8), HORIZONTAL_ALIGNMENT_LEFT, size.x - 10, 11, Ui.INK_SOFT)
		var f := Ui.bold()
		draw_string(f, Vector2(6, 15), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK if sel else Ui.INK_SOFT)

	func _get_tooltip(_pos: Vector2) -> String:
		var item := _item()
		return "" if item.is_empty() else "%s\n%d — выбрать" % [item.name, index + 1]

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				ui.bridge.select(index)
				ui.sfx.play("tick")
				accept_event()
			elif event.button_index == MOUSE_BUTTON_RIGHT and clearable:
				ui.bridge.assign_hotbar(index, "")
				accept_event()

	func _get_drag_data(_pos: Vector2):
		var item := _item()
		if item.is_empty():
			return null
		var preview := TextureRect.new()
		preview.texture = ui.thumbs.get_thumb(item)
		preview.custom_minimum_size = Vector2(56, 56)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(preview)
		return {"item_id": item.item_id, "from_slot": index}

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("item_id")

	func _drop_data(_pos: Vector2, data) -> void:
		ui.bridge.assign_hotbar(index, str(data.item_id))
		ui.sfx.play("snap")
