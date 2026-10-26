extends Control
## Стартовый экран: миры игрока и создание нового. У каждого мира один
## создатель, это ты. Звать друзей поиграть (без права строить) можно будет
## во втором релизе.

const Ui := preload("res://scripts/ui/ui.gd")
const Worlds := preload("res://scripts/worlds.gd")
const Style := preload("res://scripts/style.gd")

const SIZE_NAMES := {128: "Малый", 256: "Обычный", 512: "Большой", 1024: "Огромный"}

var _list: VBoxContainer
var _name: LineEdit
var _size := 256
var _color := "green"
var _size_chips := {}
var _color_row: HBoxContainer
var _confirm := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var row := Ui.hbox(24)
	margin.add_child(row)

	var left := Ui.panel(Ui.PAPER, 18, 20)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lcol := Ui.vbox(12)
	left.add_child(lcol)
	var head := Ui.hbox(12)
	var t := Ui.label("Мои миры", 30, Ui.INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(Ui.button("Выйти из игры", func() -> void: get_tree().quit(), "plain", 14))
	lcol.add_child(head)
	lcol.add_child(Ui.label("Каждый мир твой: строишь в нём только ты и твой ИИ.", 15, Ui.INK_SOFT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lcol.add_child(scroll)
	_list = Ui.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var right := Ui.panel(Ui.PAPER, 18, 20)
	right.custom_minimum_size.x = 420
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(right)
	var rcol := Ui.vbox(12)
	right.add_child(rcol)
	rcol.add_child(Ui.label("Новый мир", 24, Ui.INK, true))
	_name = LineEdit.new()
	_name.placeholder_text = "Название, например «Город у моря»"
	_name.add_theme_font_size_override("font_size", 17)
	_name.text_submitted.connect(func(_t: String) -> void: _create())
	rcol.add_child(_name)
	rcol.add_child(Ui.label("Размер пластины", 15, Ui.INK, true))
	var sizes := Ui.hbox(6)
	for s in Worlds.SIZES:
		var chip := Ui.chip(SIZE_NAMES.get(s, str(s)), _on_size.bind(s), Ui.GREEN)
		chip.tooltip_text = "%d×%d шипов, %d м" % [s, s, int(s * Style.STUD)]
		_size_chips[s] = chip
		sizes.add_child(chip)
	_size_chips[_size].set_pressed_no_signal(true)
	rcol.add_child(sizes)
	rcol.add_child(Ui.label("Цвет пластины", 15, Ui.INK, true))
	_color_row = Ui.hbox(8)
	rcol.add_child(_color_row)
	_fill_colors()
	rcol.add_child(Ui.button("Создать и играть", _create, "primary", 20))
	rcol.add_child(_wrap(Ui.label("Скоро: приглашать друзей в свой мир поиграть. Строить в нём по-прежнему сможешь только ты.", 13, Ui.INK_SOFT)))
	_refresh()
	_name.grab_focus.call_deferred()


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	return l


func _on_size(_on: bool, s: int) -> void:
	_size = s
	for k in _size_chips:
		_size_chips[k].set_pressed_no_signal(k == s)


func _fill_colors() -> void:
	for c in _color_row.get_children():
		c.queue_free()
	for name in Worlds.PLATE_COLORS:
		var on: bool = name == _color
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, Ui.box(Style.COLORS[name], 10, 0, false, Ui.INK if on else Color(0, 0, 0, 0.2), 4 if on else 2))
		b.pressed.connect(func() -> void:
			_color = name
			_fill_colors())
		_color_row.add_child(b)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var worlds := Worlds.list()
	if worlds.is_empty():
		_list.add_child(Ui.label("Миров пока нет. Создай первый справа.", 16, Ui.INK_SOFT))
	for w in worlds:
		_list.add_child(_card(w))


func _card(w: Dictionary) -> Control:
	var card := Ui.panel(Color.WHITE, 14, 10)
	var row := Ui.hbox(14)
	card.add_child(row)
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(176, 99)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var path := Worlds.thumb_path(w.id)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			tex.texture = ImageTexture.create_from_image(img)
	if tex.texture == null:
		var swatch := ColorRect.new()
		swatch.color = Style.COLORS.get(w.plate_color, Style.COLORS.green)
		swatch.custom_minimum_size = tex.custom_minimum_size
		row.add_child(swatch)
	else:
		row.add_child(tex)
	var info := Ui.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	if _confirm == "rename:" + w.id:
		var field := LineEdit.new()
		field.text = w.name
		field.text_submitted.connect(func(t: String) -> void:
			Worlds.rename(w.id, t)
			_confirm = ""
			_refresh())
		info.add_child(field)
		field.grab_focus.call_deferred()
	else:
		info.add_child(Ui.label(w.name, 20, Ui.INK, true))
	info.add_child(Ui.label("%s · %d×%d шипов · построек: %d" % [SIZE_NAMES.get(w.studs, ""), w.studs, w.studs, w.objects], 14, Ui.INK_SOFT))
	if w.updated != "":
		info.add_child(Ui.label("Изменён %s" % str(w.updated).replace("T", " ").left(16), 13, Ui.INK_SOFT))
	var btns := Ui.vbox(6)
	row.add_child(btns)
	if _confirm == "delete:" + w.id:
		btns.add_child(Ui.label("Удалить навсегда?", 14, Ui.RED, true))
		var yes := Ui.hbox(6)
		yes.add_child(Ui.button("Да, удалить", func() -> void:
			Worlds.remove(w.id)
			_confirm = ""
			_refresh(), "danger", 13))
		yes.add_child(Ui.button("Нет", func() -> void:
			_confirm = ""
			_refresh(), "plain", 13))
		btns.add_child(yes)
	else:
		btns.add_child(Ui.button("Играть", _play.bind(w.id), "primary", 17))
		var small := Ui.hbox(6)
		small.add_child(Ui.button("Переименовать", func() -> void:
			_confirm = "rename:" + w.id
			_refresh(), "plain", 12))
		small.add_child(Ui.button("Удалить", func() -> void:
			_confirm = "delete:" + w.id
			_refresh(), "plain", 12))
		btns.add_child(small)
	return card


func _create() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		name = "Мой мир"
	_play(Worlds.create(name, _size, _color))


func _play(id: String) -> void:
	Worlds.current = id
	get_tree().reload_current_scene()
