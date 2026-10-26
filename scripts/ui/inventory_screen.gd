extends Control
## Большой инвентарь (Tab). Слева категории, сверху поиск и сортировка,
## в центре карточки предметов с картинками, справа выбранный предмет:
## крутящийся предпросмотр, имя, кто и по какой просьбе его сделал, кнопки.
## Внизу хотбар: карточку можно перетащить в слот мышью или навести на неё
## курсор и нажать 1–9. Двойной клик берёт предмет в руки, чтобы поставить.

const Ui := preload("res://scripts/ui/ui.gd")
const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/object_builder.gd")
const Bridge := preload("res://scripts/agent_bridge.gd")
const Style := preload("res://scripts/style.gd")
const HotbarScript := preload("res://scripts/ui/hotbar.gd")

const CATEGORY_NAMES := {"buildings": "Здания", "vehicles": "Транспорт", "gear": "Снаряжение", "mechanisms": "Механизмы", "nature": "Природа", "decor": "Декор"}

var ui
var _category := "all"
var _query := ""
var _sort := "new"
var _cat_buttons := {}
var _grid: GridContainer
var _search: LineEdit
var _sort_box: OptionButton
var _paint_row: HBoxContainer
var _empty: Label
var _selected := ""
var _hovered := ""
var _detail: VBoxContainer
var _preview: SubViewport
var _preview_pivot: Node3D
var _preview_cam: Camera3D
var _preview_key := ""
var _dirty := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.11, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := Ui.panel(Ui.PAPER, 18, 16)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48
	panel.offset_right = -48
	panel.offset_top = 36
	panel.offset_bottom = -36
	add_child(panel)
	var col := Ui.vbox(12)
	panel.add_child(col)
	col.add_child(_build_head())
	var body := Ui.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_categories())
	body.add_child(_build_grid())
	body.add_child(_build_detail())
	col.add_child(_build_hotbar())
	ui.bridge.inventory_changed.connect(func() -> void: _dirty = true)
	ui.bridge.hotbar_changed.connect(func() -> void: _dirty = true)
	ui.thumbs.thumb_ready.connect(func(_k: String) -> void:
		for c in _grid.get_children():
			c.queue_redraw())


func open() -> void:
	visible = true
	_dirty = true
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	if _dirty:
		_refresh()
	if _preview_pivot:
		_preview_pivot.rotation.y += delta * 0.6


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed) or _search.has_focus():
		return
	var k: Key = event.keycode
	if k >= KEY_1 and k <= KEY_9:
		var target := _hovered if _hovered != "" else _selected
		if target != "":
			ui.bridge.assign_hotbar(k - KEY_1, target)
			ui.sfx.play("snap")
			get_viewport().set_input_as_handled()
	elif k == KEY_DELETE and _selected != "":
		ui.bridge.delete_item(_selected)
		get_viewport().set_input_as_handled()


# --- Разметка -------------------------------------------------------------

func _build_head() -> Control:
	var row := Ui.hbox(12)
	var t := Ui.label("Инвентарь", 26, Ui.INK, true)
	row.add_child(t)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по названию и просьбе…"
	_search.custom_minimum_size.x = 320
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(t2: String) -> void:
		_query = t2
		_dirty = true)
	row.add_child(_search)
	_sort_box = OptionButton.new()
	_sort_box.focus_mode = Control.FOCUS_NONE
	for s in [["new", "Сначала новые"], ["name", "По имени"], ["uses", "Часто ставлю"]]:
		_sort_box.add_item(s[1])
		_sort_box.set_item_metadata(_sort_box.item_count - 1, s[0])
	_sort_box.item_selected.connect(func(i: int) -> void:
		_sort = str(_sort_box.get_item_metadata(i))
		_dirty = true)
	row.add_child(_sort_box)
	_paint_row = Ui.hbox(6)
	row.add_child(_paint_row)
	row.add_child(Ui.spacer())
	row.add_child(Ui.label("1–9 над карточкой: в слот · двойной клик: поставить", 13, Ui.INK_SOFT))
	row.add_child(Ui.button("Закрыть (Tab)", ui.close_modal, "plain", 14))
	return row


func _build_categories() -> Control:
	var col := Ui.vbox(4)
	col.custom_minimum_size.x = 190
	for c in Catalog.CATEGORIES:
		var b := Ui.chip(c[1], _on_category.bind(c[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		_cat_buttons[c[0]] = b
		col.add_child(b)
	_cat_buttons[_category].set_pressed_no_signal(true)
	col.add_child(Ui.spacer())
	return col


func _build_grid() -> Control:
	var wrap := Ui.vbox(6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	scroll.resized.connect(func() -> void: _grid.columns = maxi(2, int((scroll.size.x - 12) / 142.0)))
	_empty = Ui.label("", 16, Ui.INK_SOFT)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(_empty)
	return wrap


func _build_detail() -> Control:
	var panel := Ui.panel(Ui.PAPER_DIM, 14, 12)
	panel.custom_minimum_size.x = 300
	_detail = Ui.vbox(8)
	panel.add_child(_detail)
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(276, 220)
	holder.stretch = true
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.msaa_3d = Viewport.MSAA_4X
	holder.add_child(_preview)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.86)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	_preview.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.75
	_preview.add_child(sun)
	_preview_cam = Camera3D.new()
	_preview_cam.fov = 30.0
	_preview.add_child(_preview_cam)
	panel.set_meta("preview", holder)
	return panel


func _build_hotbar() -> Control:
	var row := Ui.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(Ui.label("Хотбар (перетащи сюда, ПКМ очистить):", 14, Ui.INK_SOFT))
	for i in ui.bridge.HOTBAR_SIZE:
		var s = HotbarScript.Slot.new()
		s.ui = ui
		s.index = i
		s.size_px = 58
		s.clearable = true
		row.add_child(s)
	return row


func _on_category(on: bool, id: String) -> void:
	if not on and id == _category:
		_cat_buttons[id].set_pressed_no_signal(true)
		return
	_category = id
	for k in _cat_buttons:
		_cat_buttons[k].set_pressed_no_signal(k == id)
	_dirty = true


# --- Содержимое -----------------------------------------------------------

func _refresh() -> void:
	_dirty = false
	var b = ui.bridge
	for k in _cat_buttons:
		var count := 0
		if k != "basic":
			count = b.items(k).size()
		else:
			count = Catalog.BASIC.size()
		var base: String = ""
		for c in Catalog.CATEGORIES:
			if c[0] == k:
				base = c[1]
		_cat_buttons[k].text = "%s  %d" % [base, count] if count > 0 or k in ["all", "basic"] else base
	_paint_row.visible = _category == "basic"
	for c in _paint_row.get_children():
		c.queue_free()
	if _category == "basic":
		_paint_row.add_child(Ui.label("Цвет:", 14, Ui.INK_SOFT))
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(22, 22)
		sw.color = Style.COLORS.get(b.paint, Color.WHITE)
		_paint_row.add_child(sw)
		_paint_row.add_child(Ui.button("Сменить (C)", func() -> void: ui.open("colors"), "plain", 13))
	for c in _grid.get_children():
		c.queue_free()
	var list: Array[Dictionary] = b.items(_category, _query, _sort)
	for item in list:
		var card := Card.new()
		card.ui = ui
		card.screen = self
		card.item = item
		_grid.add_child(card)
	_empty.visible = list.is_empty()
	match _category:
		"trash":
			_empty.text = "Корзина пуста."
		"favorites":
			_empty.text = "Нет избранного. Отметь предмет звёздочкой справа."
		"new":
			_empty.text = "Новых предметов нет. Попроси ИИ что-нибудь построить (Enter)."
		_:
			_empty.text = "Ничего не нашлось." if _query != "" else "Здесь пока пусто. Нажми Enter в игре и попроси ИИ построить что угодно, а базовые детали есть всегда."
	if _selected != "" and b.get_item(_selected).is_empty():
		_selected = ""
	if _selected == "" and not list.is_empty():
		_selected = list[0].item_id
	_show_detail()


func select(item_id: String) -> void:
	_selected = item_id
	ui.bridge.mark_seen(item_id)
	for c in _grid.get_children():
		c.queue_redraw()
	_show_detail()


func hover(item_id: String, on: bool) -> void:
	if on:
		_hovered = item_id
	elif _hovered == item_id:
		_hovered = ""


func selected() -> String:
	return _selected


func take(item_id: String) -> void:
	ui.place_item(item_id)


func _show_detail() -> void:
	var holder: Control = _detail.get_parent().get_meta("preview")
	if holder.get_parent():
		holder.get_parent().remove_child(holder)
	for c in _detail.get_children():
		c.queue_free()
	var b = ui.bridge
	var item: Dictionary = b.get_item(_selected)
	if item.is_empty():
		_set_preview({})
		_detail.add_child(Ui.label("Выбери предмет", 16, Ui.INK_SOFT))
		return
	_detail.add_child(holder)
	_set_preview(item)
	var basic: bool = item.get("basic", false)
	var deleted: bool = item.get("deleted", false)
	if basic:
		_detail.add_child(Ui.label(str(item.name), 20, Ui.INK, true))
		_detail.add_child(_wrap(Ui.label("Базовая деталь. Цвет меняется клавишей C.", 13, Ui.INK_SOFT)))
	else:
		var name_field := LineEdit.new()
		name_field.text = str(item.name)
		name_field.add_theme_font_size_override("font_size", 18)
		name_field.text_submitted.connect(func(t: String) -> void:
			b.rename_item(item.item_id, t)
			name_field.release_focus())
		name_field.focus_exited.connect(func() -> void:
			if name_field.text != str(item.name):
				b.rename_item(item.item_id, name_field.text))
		_detail.add_child(name_field)
		var who := "Сделал: %s" % str(item.get("author", "")) if str(item.get("author", "")) != "" else ""
		var badge := Catalog.badge(item.spec)
		if badge != "":
			who += (" · " if who != "" else "") + badge
		if who != "":
			_detail.add_child(Ui.label(who, 13, Ui.INK_SOFT))
		if str(item.get("prompt", "")) != "":
			_detail.add_child(_wrap(Ui.label("«%s»" % str(item.prompt).left(220), 13, Ui.INK)))
		var cat := OptionButton.new()
		cat.focus_mode = Control.FOCUS_NONE
		var current := Catalog.category_of(item)
		for c in Catalog.ITEM_CATEGORIES:
			cat.add_item(CATEGORY_NAMES[c])
			cat.set_item_metadata(cat.item_count - 1, c)
			if c == current:
				cat.select(cat.item_count - 1)
		cat.item_selected.connect(func(i: int) -> void: b.set_item_category(item.item_id, str(cat.get_item_metadata(i))))
		_detail.add_child(cat)
	if deleted:
		_detail.add_child(Ui.button("Вернуть из корзины", func() -> void: b.restore_item(item.item_id), "primary"))
		_detail.add_child(Ui.button("Удалить навсегда", func() -> void: b.purge_item(item.item_id), "danger"))
		_detail.add_child(Ui.spacer())
		_detail.add_child(Ui.button("Очистить корзину", func() -> void: b.empty_trash(), "plain", 13))
		return
	_detail.add_child(Ui.button("Взять и поставить", take.bind(item.item_id), "primary", 17))
	var row := Ui.hbox(6)
	if not basic:
		var fav := Ui.button("★ В избранном" if item.get("favorite", false) else "☆ В избранное", func() -> void: b.toggle_favorite(item.item_id), "plain", 13)
		row.add_child(fav)
	row.add_child(Ui.button("Копия", func() -> void:
		var copy: Dictionary = b.duplicate_item(item.item_id)
		if not copy.is_empty():
			_selected = copy.item_id
			ui.toast("Копия в инвентаре: её можно менять, не трогая оригинал"), "plain", 13))
	_detail.add_child(row)
	if not basic:
		_detail.add_child(Ui.button("Изменить через ИИ…", func() -> void:
			ui.close_modal()
			ui.prompt.edit_item(item.item_id), "blue", 14))
		var row2 := Ui.hbox(6)
		row2.add_child(Ui.button("Сохранить в файл", func() -> void:
			var path: String = b.export_item(item.item_id)
			ui.toast("Сохранено: %s" % path if path != "" else "Не получилось сохранить", 6.0), "plain", 13))
		row2.add_child(Ui.button("В корзину", func() -> void: b.delete_item(item.item_id), "danger", 13))
		_detail.add_child(row2)
	var slot: int = b.hotbar.find(item.item_id)
	_detail.add_child(Ui.label("В слоте %d" % (slot + 1) if slot >= 0 else "Наведи и нажми 1–9, чтобы положить в слот", 12, Ui.INK_SOFT))


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 270
	return l


## Крутящаяся модель выбранного предмета.
func _set_preview(item: Dictionary) -> void:
	var key := "" if item.is_empty() else "%s|%d" % [item.item_id, hash(JSON.stringify(item.spec))]
	if key == _preview_key:
		return
	_preview_key = key
	if _preview_pivot:
		_preview_pivot.queue_free()
		_preview_pivot = null
	if item.is_empty():
		return
	var spec: Dictionary = (item.spec as Dictionary).duplicate(true)
	spec.erase("mechanics")
	spec.erase("effects")
	spec["physics"] = {"mode": "none"}
	var node := Builder.build(spec)
	_preview_pivot = Node3D.new()
	_preview.add_child(_preview_pivot)
	_preview_pivot.add_child(node)
	var box := Bridge.node_aabb(node)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	node.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var radius := maxf(box.size.length() * 0.5, 0.3)
	var dist := radius / sin(deg_to_rad(_preview_cam.fov * 0.5)) * 1.05
	var center := Vector3(0, box.size.y * 0.5, 0)
	_preview_cam.look_at_from_position(center + Vector3(0, 0.55, 1).normalized() * dist, center)
	_preview_cam.far = dist + radius * 3.0


## Карточка предмета в сетке.
class Card extends Control:
	const Ui := preload("res://scripts/ui/ui.gd")
	const Catalog := preload("res://scripts/catalog.gd")
	var ui
	var screen
	var item: Dictionary
	var _hover := false

	func _ready() -> void:
		custom_minimum_size = Vector2(132, 160)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = str(item.name)
		mouse_entered.connect(func() -> void:
			_hover = true
			screen.hover(item.item_id, true)
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			screen.hover(item.item_id, false)
			queue_redraw())

	func _draw() -> void:
		var sel: bool = screen.selected() == item.item_id
		var border := Ui.BLUE if sel else (Ui.YELLOW if _hover else Color(0, 0, 0, 0.1))
		draw_style_box(Ui.box(Color.WHITE, 12, 0, _hover or sel, border, 3 if sel or _hover else 2), Rect2(Vector2.ZERO, size))
		var tex: Texture2D = ui.thumbs.get_thumb(item)
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(10, 6), Vector2(112, 112)), false)
		var f := Ui.bold()
		draw_string(f, Vector2(8, 136), str(item.name), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 13, Ui.INK)
		var sub := Catalog.badge(item.spec)
		if sub != "":
			draw_string(get_theme_default_font(), Vector2(8, 153), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 11, Ui.INK_SOFT)
		if not item.get("seen", true) and not item.get("basic", false):
			draw_style_box(Ui.box(Ui.RED, 8, 0, false), Rect2(Vector2(size.x - 52, 6), Vector2(46, 18)))
			draw_string(f, Vector2(size.x - 50, 20), "новое", HORIZONTAL_ALIGNMENT_CENTER, 42, 11, Color.WHITE)
		if item.get("favorite", false):
			draw_string(f, Vector2(8, 22), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Ui.YELLOW.darkened(0.2))
		var slot: int = ui.bridge.hotbar.find(item.item_id)
		if slot >= 0:
			draw_style_box(Ui.box(Ui.INK, 6, 0, false), Rect2(Vector2(8, size.y - 52), Vector2(20, 18)))
			draw_string(f, Vector2(8, size.y - 38), str(slot + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				screen.take(item.item_id)
			else:
				screen.select(item.item_id)
			accept_event()

	func _get_drag_data(_pos: Vector2):
		var preview := TextureRect.new()
		preview.texture = ui.thumbs.get_thumb(item)
		preview.custom_minimum_size = Vector2(64, 64)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(preview)
		return {"item_id": item.item_id}
