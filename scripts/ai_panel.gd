extends Control
## ИИ-строитель в интерфейсе игры.
## Внизу по центру поле ввода на две строки: игрок пишет «мельница», просьба
## уходит подключённому ИИ-агенту по MCP, агент создаёт объект, и он
## попадает в инвентарь (полоска слотов над полем). Клавиши: 1–8 выбрать
## слот, F поставить предмет перед собой, G подобрать объект, X удалить
## предмет из инвентаря. Над инвентарём видно, что ответил агент.
## По F2 открывается панель подключения агента: готовые настройки для
## Claude Code, Cursor, VS Code и Claude Desktop копируются одной кнопкой.

const AiGuide := preload("res://scripts/ai_guide.gd")

## Короткая команда для агента: с неё он начинает слушать просьбы игроков.
const START_COMMAND := "Use the ai-sandbox-world MCP tools as the game's builder: call get_style_guide, then loop on wait_for_player_request and build each request with create_object. Keep looping until I stop you."

var bridge
var mcp
var player

var _field: TextEdit
var _slots: HBoxContainer
var _status: Label
var _online: Label
var _status_left := 0.0
var _panel: PanelContainer
var _panel_status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_prompt_bar()
	_build_setup_panel()
	bridge.agent_message.connect(_on_agent_message)
	bridge.inventory_changed.connect(_refresh_inventory)
	_refresh_inventory()


func _process(delta: float) -> void:
	var online: bool = bridge.agent_online()
	_online.text = "● ИИ-агент на связи" if online else "○ ИИ-агент не подключён (F2)"
	_online.modulate.a = 0.9 if online else 0.6
	if _status_left > 0.0:
		_status_left -= delta
		_status.modulate.a = clampf(_status_left, 0.0, 1.0)
	# Игрок кликнул в мир и захватил мышь: значит, он больше не печатает.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _field.has_focus():
		_field.release_focus()
	player.frozen = _field.has_focus() or _panel.visible


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F2:
			_toggle_panel()
		KEY_ESCAPE:
			if _panel.visible:
				_toggle_panel()
			elif _field.has_focus():
				_field.release_focus()
			else:
				return
		KEY_ENTER, KEY_KP_ENTER:
			if _panel.visible:
				return
			if _field.has_focus():
				# Shift+Enter переносит строку, просто Enter отправляет.
				if event.shift_pressed:
					return
				_submit()
			else:
				# Enter в игре открывает поле ввода.
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_field.grab_focus()
		_:
			if _field.has_focus() or _panel.visible:
				return
			if event.keycode >= KEY_1 and event.keycode <= KEY_8:
				bridge.select(event.keycode - KEY_1)
			elif event.keycode == KEY_F:
				_show(bridge.place_selected(), 3.0)
			elif event.keycode == KEY_G:
				_show(bridge.pick_up_in_front(), 3.0)
			elif event.keycode == KEY_X:
				_show(bridge.delete_selected(), 3.0)
			else:
				return
	get_viewport().set_input_as_handled()


# --- Поле ввода внизу экрана ----------------------------------------------

func _build_prompt_bar() -> void:
	var bar := VBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -380
	bar.offset_right = 380
	bar.offset_top = -250
	bar.offset_bottom = -40
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_status = _label("", 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_status)

	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 8)
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_slots)

	_field = TextEdit.new()
	_field.placeholder_text = "Enter — попросить ИИ построить, например «мельница с лопастями» (Shift+Enter — новая строка)"
	_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_field.scroll_fit_content_height = false
	_field.custom_minimum_size = Vector2(0, 66)
	_field.add_theme_font_size_override("font_size", 17)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.09, 0.08, 0.78)
	bg.border_color = Color(1, 0.98, 0.94, 0.5)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	_field.add_theme_stylebox_override("normal", bg)
	_field.add_theme_stylebox_override("focus", bg)
	bar.add_child(_field)

	_online = _label("", 13)
	_online.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_online)


func _submit() -> void:
	var text := _field.text.strip_edges()
	_field.text = ""
	_field.release_focus()
	if text == "":
		return
	bridge.submit_request(text)
	if bridge.agent_online():
		_show("Отправлено ИИ-агенту: «%s»" % text, 0.0)
	else:
		_show("ИИ-агент не подключён. Просьба подождёт его, подключить: F2", 8.0)


## Перерисовывает слоты инвентаря.
func _refresh_inventory() -> void:
	for child in _slots.get_children():
		child.queue_free()
	for i in bridge.INVENTORY_SIZE:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(84, 62)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.07, 0.06, 0.55)
		sb.border_color = Color(1, 0.98, 0.94, 0.95 if i == bridge.selected else 0.35)
		sb.set_border_width_all(3 if i == bridge.selected else 1)
		sb.set_corner_radius_all(9)
		sb.set_content_margin_all(4)
		slot.add_theme_stylebox_override("panel", sb)
		var name_text := ""
		if i < bridge.inventory.size():
			name_text = str(bridge.inventory[i].name)
		var l := _label("%d\n%s" % [i + 1, name_text], 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		slot.add_child(l)
		_slots.add_child(slot)


func _on_agent_message(_request_id: String, text: String, done: bool) -> void:
	_show("ИИ: %s" % text, 8.0 if done else 0.0)


## Показывает строку над полем. seconds = 0: держать, пока не придёт новая.
func _show(text: String, seconds: float) -> void:
	_status.text = text
	_status.modulate.a = 1.0
	_status_left = seconds if seconds > 0.0 else 1000000.0


# --- Панель подключения агента (F2) ---------------------------------------

func _build_setup_panel() -> void:
	_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.09, 0.08, 0.94)
	bg.border_color = Color(1, 0.98, 0.94, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -360
	_panel.offset_right = 360
	_panel.offset_top = -270
	_panel.offset_bottom = 270
	_panel.visible = false
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var top := HBoxContainer.new()
	var title := _label("Подключить ИИ-агента", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_button("Закрыть (F2)", _toggle_panel))
	box.add_child(top)

	var url: String = mcp.url()
	box.add_child(_label("Это нужно сделать один раз. Потом просто пиши просьбы в поле внизу экрана, а агент будет строить.", 15))
	box.add_child(_label("1. Нажми кнопку своей программы и вставь скопированное туда, куда написано:", 16))
	var clients := [
		["Claude Code", "claude mcp add --transport http ai-sandbox-world %s\nclaude --allowedTools \"mcp__ai-sandbox-world\" \"%s\"" % [url, START_COMMAND],
			"Вставь в терминал (обе строки). Агент сразу начнёт слушать игру, шаг 2 не нужен."],
		["Cursor", JSON.stringify({"mcpServers": {"ai-sandbox-world": {"url": url}}}, "  "),
			"Settings → MCP → Add new MCP server, вставь в файл и сохрани."],
		["VS Code", JSON.stringify({"servers": {"ai-sandbox-world": {"type": "http", "url": url}}}, "  "),
			"Ctrl+Shift+P → «MCP: Open User Configuration», вставь и сохрани."],
		["Claude Desktop", JSON.stringify({"mcpServers": {"ai-sandbox-world": {"command": "npx", "args": ["-y", "mcp-remote", url]}}}, "  "),
			"Настройки → Developer → Edit Config, вставь, сохрани, перезапусти. Нужен Node.js."],
		["Другой агент", url,
			"Адрес MCP-сервера игры (Streamable HTTP)."],
	]
	for c in clients:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var b := _button(c[0], _copy.bind(c[1], "Скопировано для %s." % c[0]))
		b.custom_minimum_size = Vector2(150, 0)
		row.add_child(b)
		var hint := _label(c[2], 14)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hint)
		box.add_child(row)

	box.add_child(_label("2. Скопируй команду и отправь её агенту в его чат. Разреши ему инструменты ai-sandbox-world без подтверждения («Always allow»), иначе он будет спрашивать на каждый объект.", 16))
	box.add_child(_button("Скопировать команду для агента", _copy.bind(START_COMMAND, "Команда скопирована. Отправь её агенту.")))

	_panel_status = _label("", 15)
	box.add_child(_panel_status)


func _toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_panel_status.text = "Сейчас: ИИ-агент на связи." if bridge.agent_online() else "Сейчас: агент не подключён."


func _copy(text: String, note: String) -> void:
	DisplayServer.clipboard_set(text)
	_panel_status.text = note


# --- Мелочи ---------------------------------------------------------------

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.06))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b
