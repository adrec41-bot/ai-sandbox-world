extends Control
## Панель просьб к ИИ. Внизу экрана поле «Попроси ИИ построить…»: Enter
## открывает его, Enter отправляет, Shift+Enter переносит строку, ↑ и ↓
## листают прошлые просьбы. Над полем чипы: что строим (здание, транспорт…),
## размер (S–XL), отмеченная площадка и выделенная постройка, которую надо
## изменить. ★ хранит шаблоны и идеи.
##
## Слева внизу карточки просьб: ИИ думает, задал вопрос (кнопки ответов),
## готово (картинка и кнопки Поставить, Переделать, Уточнить) или не вышло.
## L открывает журнал всех просьб.

const Ui := preload("res://scripts/ui/ui.gd")

const KINDS := [["building", "Здание"], ["vehicle", "Транспорт"], ["gear", "Снаряжение"], ["mechanism", "Механизм"], ["nature", "Природа"], ["rules", "Правила мира"]]
const SIZES := [["S", "8 шипов: мелочь, деталь"], ["M", "16 шипов: дом, машина"], ["L", "32 шипа: большое здание"], ["XL", "64 шипа: замок, квартал"]]
const IDEAS := [
	"Уютный домик с красной крышей, окнами и садом",
	"Гоночная машина, на которой можно ездить",
	"Реактивный ранец, чтобы летать",
	"Замок с четырьмя башнями и подъёмным мостом",
	"Батут, который подбрасывает очень высоко",
	"Маяк на скале с горящим огнём",
	"Пусть гравитация станет как на Луне",
]
const MAX_CARDS := 4
const MAX_LINES := 5

var ui
var _box: VBoxContainer
var _chips: HBoxContainer
var _context: HBoxContainer
var _field: TextEdit
var _send: Button
var _status: Label
var _kind := ""
var _size := ""
var _kind_buttons := {}
var _size_buttons := {}
var _with_area := true
var _with_target := true
var _item_target := ""
var _hist := -1
var _cards: VBoxContainer
var _dismissed := {}
var _journal: PanelContainer
var _journal_list: VBoxContainer
var _log: Array[String] = []
var _templates: MenuButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar()
	_build_cards()
	_build_journal()
	var b = ui.bridge
	b.requests_changed.connect(_refresh_cards)
	b.area_changed.connect(_refresh_context)
	b.selection_changed.connect(func() -> void:
		_with_target = true
		_refresh_context())
	b.agent_message.connect(func(_id: String, text: String, _done: bool) -> void:
		_log.append(text)
		while _log.size() > 60:
			_log.pop_front()
		if _journal.visible:
			_refresh_journal())
	ui.thumbs.thumb_ready.connect(func(_k: String) -> void: _refresh_cards())
	_refresh_context()
	_refresh_cards()


# --- Поле ввода -----------------------------------------------------------

func _build_bar() -> void:
	_box = Ui.vbox(6)
	_box.custom_minimum_size.x = 680
	Ui.pin(_box, Control.PRESET_CENTER_BOTTOM, Vector2(0, -124))
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	_chips = Ui.hbox(6)
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in KINDS:
		var c := Ui.chip(k[1], _on_kind.bind(k[0]))
		_kind_buttons[k[0]] = c
		_chips.add_child(c)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.add_child(gap)
	for s in SIZES:
		var c := Ui.chip(s[0], _on_size.bind(s[0]), Ui.GREEN)
		c.tooltip_text = s[1]
		_size_buttons[s[0]] = c
		_chips.add_child(c)
	_box.add_child(_chips)

	_context = Ui.hbox(6)
	_context.alignment = BoxContainer.ALIGNMENT_CENTER
	_context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_context)

	var frame := Ui.panel(Ui.PAPER, 14, 8)
	_box.add_child(frame)
	var row := Ui.hbox(8)
	frame.add_child(row)
	_templates = MenuButton.new()
	_templates.text = "★"
	_templates.tooltip_text = "Шаблоны и идеи"
	_templates.focus_mode = Control.FOCUS_NONE
	_templates.flat = false
	_templates.add_theme_font_size_override("font_size", 18)
	_templates.about_to_popup.connect(_fill_templates)
	_templates.get_popup().id_pressed.connect(_on_template)
	row.add_child(_templates)
	_field = TextEdit.new()
	_field.placeholder_text = "Enter — попроси ИИ построить что угодно"
	_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.add_theme_font_size_override("font_size", 17)
	_field.scroll_fit_content_height = false
	_field.gui_input.connect(_field_input)
	_field.text_changed.connect(_grow)
	_field.focus_entered.connect(_on_focus.bind(true))
	_field.focus_exited.connect(_on_focus.bind(false))
	row.add_child(_field)
	_send = Ui.button("Построить", _submit)
	row.add_child(_send)

	_status = Ui.overlay_label("", 13)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_status)
	_grow()
	_on_focus(false)


func is_typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and is_ancestor_of(f)


func focus() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_field.grab_focus()


func release() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f != null and is_ancestor_of(f):
		f.release_focus()


## Изменить предмет инвентаря через ИИ: поле открывается с этим предметом.
func edit_item(item_id: String) -> void:
	_item_target = item_id
	_refresh_context()
	focus()


func _on_focus(on: bool) -> void:
	_chips.visible = on
	_status.visible = on
	_send.visible = on or _field.text.strip_edges() != ""
	_refresh_context()
	if on:
		_status.text = ("ИИ на связи · " if ui.bridge.agent_online() else "ИИ не подключён, просьба подождёт его (F2) · ") + "Enter отправить · Shift+Enter новая строка · ↑ прошлые · Esc назад в игру"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and is_typing():
		release()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _field_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if not event.shift_pressed:
				_submit()
				_field.accept_event()
		KEY_UP:
			if _field.get_caret_line() == 0 and not ui.bridge.history.is_empty():
				_hist = ui.bridge.history.size() - 1 if _hist < 0 else maxi(_hist - 1, 0)
				_set_text(ui.bridge.history[_hist])
				_field.accept_event()
		KEY_DOWN:
			if _hist >= 0 and _field.get_caret_line() == _field.get_line_count() - 1:
				_hist += 1
				if _hist >= ui.bridge.history.size():
					_hist = -1
					_set_text("")
				else:
					_set_text(ui.bridge.history[_hist])
				_field.accept_event()


func _set_text(t: String) -> void:
	_field.text = t
	_field.set_caret_line(_field.get_line_count() - 1)
	_field.set_caret_column(_field.get_line(_field.get_line_count() - 1).length())
	_grow()


## Поле растёт вместе с текстом, до пяти строк.
func _grow() -> void:
	var lines := 0
	for i in _field.get_line_count():
		lines += _field.get_line_wrap_count(i) + 1
	lines = clampi(lines, 1, MAX_LINES)
	_field.custom_minimum_size.y = lines * _field.get_line_height() + 22
	_send.visible = _field.has_focus() or _field.text.strip_edges() != ""


func _on_kind(on: bool, kind: String) -> void:
	_kind = kind if on else ""
	for k in _kind_buttons:
		_kind_buttons[k].set_pressed_no_signal(k == _kind)


func _on_size(on: bool, s: String) -> void:
	_size = s if on else ""
	for k in _size_buttons:
		_size_buttons[k].set_pressed_no_signal(k == _size)


## Чипы того, к чему относится просьба: площадка и выделенная постройка.
func _refresh_context() -> void:
	for c in _context.get_children():
		c.queue_free()
	var b = ui.bridge
	if not b.area.is_empty():
		var a: Dictionary = b.area
		var chip := Ui.chip("Площадка %d×%d" % [a.x1 - a.x0, a.z1 - a.z0], func(on: bool) -> void: _with_area = on, Ui.YELLOW.darkened(0.25))
		chip.tooltip_text = "ИИ построит прямо на отмеченной площадке. Отжать: построить в инвентарь."
		chip.set_pressed_no_signal(_with_area)
		_context.add_child(chip)
	if not b.selection.is_empty():
		var rec: Dictionary = b.object_record(b.selection[0])
		var label := "Изменить: %s" % str(rec.get("spec", {}).get("name", "постройку"))
		if b.selection.size() > 1:
			label += " и ещё %d" % (b.selection.size() - 1)
		var chip := Ui.chip(label, func(on: bool) -> void: _with_target = on, Ui.RED)
		chip.tooltip_text = "ИИ поменяет выделенную постройку. Отжать: сделать новую."
		chip.set_pressed_no_signal(_with_target)
		_context.add_child(chip)
	elif _item_target != "":
		var item: Dictionary = b.get_item(_item_target)
		if item.is_empty():
			_item_target = ""
		else:
			var chip := Ui.chip("Изменить: %s ✕" % item.name, func(_on: bool) -> void:
				_item_target = ""
				_refresh_context(), Ui.RED)
			chip.set_pressed_no_signal(true)
			_context.add_child(chip)
	_context.visible = _context.get_child_count() > 0 and (_field.has_focus() or not b.area.is_empty() or not b.selection.is_empty())


func _submit() -> void:
	var text := _field.text.strip_edges()
	if text == "":
		release()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var b = ui.bridge
	var opts := {"kind": _kind, "size": _size, "with_area": _with_area}
	if not b.selection.is_empty() and _with_target:
		opts["target"] = b.selection[0]
	elif _item_target != "":
		opts["item"] = _item_target
	b.submit_request(text, opts)
	_field.text = ""
	_hist = -1
	_item_target = ""
	_on_kind(false, "")
	_on_size(false, "")
	_grow()
	release()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.sfx.play("click")
	if not b.agent_online():
		ui.toast("ИИ не подключён: просьба подождёт его. Подключить: F2", 6.0)


func _fill_templates() -> void:
	var p := _templates.get_popup()
	p.clear()
	var b = ui.bridge
	if not b.templates.is_empty():
		p.add_separator("Мои шаблоны")
		for i in b.templates.size():
			p.add_item(str(b.templates[i]).left(60), i)
	p.add_separator("Идеи")
	for i in IDEAS.size():
		p.add_item(IDEAS[i], 1000 + i)
	p.add_separator()
	p.add_item("★ Сохранить текст как шаблон", 2000)
	p.set_item_disabled(p.get_item_count() - 1, _field.text.strip_edges() == "")
	if not b.templates.is_empty():
		p.add_item("Удалить последний шаблон", 2001)


func _on_template(id: int) -> void:
	var b = ui.bridge
	if id == 2000:
		b.add_template(_field.text)
		ui.toast("Шаблон сохранён: ★")
	elif id == 2001:
		if not b.templates.is_empty():
			b.remove_template(b.templates[-1])
	elif id >= 1000:
		_set_text(IDEAS[id - 1000])
		focus()
	elif id < b.templates.size():
		_set_text(b.templates[id])
		focus()


# --- Карточки просьб ------------------------------------------------------

func _build_cards() -> void:
	_cards = Ui.vbox(8)
	_cards.custom_minimum_size.x = 380
	Ui.pin(_cards, Control.PRESET_BOTTOM_LEFT, Vector2(20, -20))
	_cards.alignment = BoxContainer.ALIGNMENT_END
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)


func _process(_delta: float) -> void:
	_cards.visible = ui.modal == "" or ui.modal == "colors"
	_box.visible = ui.modal == ""


func _refresh_cards() -> void:
	for c in _cards.get_children():
		c.queue_free()
	var list: Array = []
	for r in ui.bridge.requests():
		if not _dismissed.has(r.id):
			list.append(r)
	for r in list.slice(maxi(0, list.size() - MAX_CARDS)):
		_cards.add_child(_card(r))
	if _journal.visible:
		_refresh_journal()


func _card(r: Dictionary) -> PanelContainer:
	var b = ui.bridge
	var card := Ui.panel(Ui.PAPER, 12, 10)
	card.custom_minimum_size.x = 380
	var col := Ui.vbox(6)
	card.add_child(col)
	var head := Ui.hbox(8)
	col.add_child(head)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = {"queued": Color(0.6, 0.62, 0.65), "taken": Ui.BLUE, "answered": Ui.BLUE, "question": Ui.YELLOW.darkened(0.2), "done": Ui.GREEN, "failed": Ui.RED}.get(r.status, Color.GRAY)
	head.add_child(dot)
	var title := Ui.label(str(r.text).replace("\n", " "), 14, Ui.INK, true)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var close := Ui.button("✕", func() -> void:
		if r.status in ["queued", "question"]:
			b.cancel_request(r.id)
		_dismissed[r.id] = true
		_refresh_cards(), "plain", 12)
	close.tooltip_text = "Отменить просьбу" if r.status in ["queued", "taken", "question", "answered"] else "Скрыть"
	head.add_child(close)

	match r.status:
		"queued":
			col.add_child(_wrap(Ui.label("Ждёт ИИ…" if b.agent_online() else "Ждёт, когда подключится ИИ (F2)", 13, Ui.INK_SOFT)))
		"taken", "answered":
			col.add_child(_wrap(Ui.label(str(r.progress) if str(r.progress) != "" else "ИИ думает…", 13, Ui.BLUE)))
		"question":
			col.add_child(_wrap(Ui.label("ИИ спрашивает: %s" % r.question, 14, Ui.INK)))
			var opts := HFlowContainer.new()
			opts.add_theme_constant_override("h_separation", 6)
			opts.add_theme_constant_override("v_separation", 6)
			for o in r.options:
				opts.add_child(Ui.button(str(o), _answer.bind(r.id, str(o)), "blue", 13))
			col.add_child(opts)
			var own := Ui.hbox(6)
			var field := LineEdit.new()
			field.placeholder_text = "Свой ответ…"
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.add_theme_font_size_override("font_size", 14)
			field.text_submitted.connect(func(t: String) -> void: _answer(r.id, t))
			own.add_child(field)
			own.add_child(Ui.button("Ответить", func() -> void: _answer(r.id, field.text), "primary", 13))
			col.add_child(own)
		"done":
			var item: Dictionary = b.get_item(str(r.item_id))
			var row := Ui.hbox(10)
			col.add_child(row)
			if not item.is_empty():
				var tex := TextureRect.new()
				tex.custom_minimum_size = Vector2(72, 72)
				tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex.texture = ui.thumbs.get_thumb(item)
				row.add_child(tex)
			var info := Ui.vbox(6)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			info.add_child(_wrap(Ui.label(str(r.progress), 13, Ui.GREEN)))
			if not item.is_empty():
				var btns := HFlowContainer.new()
				btns.add_theme_constant_override("h_separation", 6)
				btns.add_theme_constant_override("v_separation", 6)
				var place := Ui.button("Поставить", func() -> void:
					_dismissed[r.id] = true
					ui.place_item(item.item_id)
					_refresh_cards(), "primary", 13)
				place.tooltip_text = "Взять в руки и поставить, куда смотрит прицел"
				btns.add_child(place)
				var again := Ui.button("Переделать", func() -> void:
					_dismissed[r.id] = true
					b.retry_request(r.id)
					_refresh_cards(), "plain", 13)
				again.tooltip_text = "Попросить другой вариант"
				btns.add_child(again)
				var refine := Ui.button("Уточнить", func() -> void:
					_dismissed[r.id] = true
					edit_item(item.item_id)
					_refresh_cards(), "plain", 13)
				refine.tooltip_text = "Написать, что поменять в этой постройке"
				btns.add_child(refine)
				info.add_child(btns)
		"failed":
			col.add_child(_wrap(Ui.label(str(r.progress), 13, Ui.RED)))
			col.add_child(Ui.button("Ещё раз", func() -> void:
				_dismissed[r.id] = true
				b.retry_request(r.id)
				_refresh_cards(), "primary", 13))
	return card


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 260
	return l


func _answer(id: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	ui.bridge.answer_question(id, text.strip_edges())
	release()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.sfx.play("click")


# --- Журнал (L) -----------------------------------------------------------

func _build_journal() -> void:
	_journal = Ui.panel(Ui.PAPER, 14, 14)
	_journal.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_journal.offset_left = 20
	_journal.offset_right = 460
	_journal.offset_top = 80
	_journal.offset_bottom = -20
	_journal.visible = false
	add_child(_journal)
	var col := Ui.vbox(10)
	_journal.add_child(col)
	var head := Ui.hbox(8)
	var t := Ui.label("Журнал просьб", 20, Ui.INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(Ui.button("Закрыть (L)", toggle_journal, "plain", 13))
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_journal_list = Ui.vbox(8)
	_journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_journal_list)


func toggle_journal() -> void:
	_journal.visible = not _journal.visible
	if _journal.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_journal()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_journal() -> void:
	for c in _journal_list.get_children():
		c.queue_free()
	var list: Array = ui.bridge.requests().duplicate()
	list.reverse()
	if list.is_empty():
		_journal_list.add_child(_wrap(Ui.label("Здесь будут все твои просьбы к ИИ и его ответы. Нажми Enter и напиши, что построить.", 14, Ui.INK_SOFT)))
	var names := {"queued": "ждёт", "taken": "ИИ работает", "answered": "ИИ получил ответ", "question": "вопрос", "done": "готово", "failed": "не вышло"}
	for r in list:
		var row := Ui.vbox(2)
		var l := _wrap(Ui.label(str(r.text), 14, Ui.INK, true))
		l.custom_minimum_size.x = 380
		row.add_child(l)
		var s := "%s · %s" % [names.get(r.status, r.status), r.progress] if str(r.progress) != "" else str(names.get(r.status, r.status))
		var sl := _wrap(Ui.label(s, 13, Ui.INK_SOFT))
		sl.custom_minimum_size.x = 380
		row.add_child(sl)
		var line := HBoxContainer.new()
		line.add_child(row)
		if r.status in ["done", "failed"]:
			line.add_child(Ui.button("Повторить", func() -> void: ui.bridge.retry_request(r.id), "plain", 12))
		_journal_list.add_child(line)
		_journal_list.add_child(HSeparator.new())
