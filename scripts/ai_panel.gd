extends Control
## Панель «ИИ-строитель» (F2 или кнопка вверху экрана). Два способа строить:
## 1. Любой чат с ИИ: игра копирует промт, игрок вставляет его в ChatGPT,
##    Claude, Gemini и т. п., а ответ ИИ вставляет обратно в игру.
## 2. ИИ-агент по MCP: игра копирует готовую настройку подключения для
##    Claude Code, Cursor, VS Code или Claude Desktop.

const AiGuide := preload("res://scripts/ai_guide.gd")

var bridge
var mcp
var player

var _panel: PanelContainer
var _request: LineEdit
var _answer: TextEdit
var _status: Label
var _fix: Button
var _agent_status: Label
var _last_error := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var open := Button.new()
	open.text = "ИИ-строитель (F2)"
	open.set_anchors_preset(Control.PRESET_CENTER_TOP)
	open.offset_left = -90
	open.offset_right = 90
	open.offset_top = 16
	open.offset_bottom = 52
	open.focus_mode = Control.FOCUS_NONE
	open.pressed.connect(toggle)
	add_child(open)

	_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.09, 0.08, 0.94)
	bg.border_color = Color(1, 0.98, 0.94, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -350
	_panel.offset_right = 350
	_panel.offset_top = -290
	_panel.offset_bottom = 290
	_panel.visible = false
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := _label("ИИ-строитель", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_button("Закрыть (F2)", toggle))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_chat_tab())
	tabs.add_child(_agent_tab())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2 or (event.keycode == KEY_ESCAPE and _panel.visible):
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	_panel.visible = not _panel.visible
	# Пока панель открыта, персонаж стоит, а мышь свободна для кнопок.
	player.frozen = _panel.visible
	if _panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_request.grab_focus()


# --- Вкладка «Любой чат с ИИ» ---------------------------------------------

func _chat_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Любой чат с ИИ"
	box.add_theme_constant_override("separation", 8)

	box.add_child(_label("1. Напиши, что построить", 16))
	_request = LineEdit.new()
	_request.placeholder_text = "например: кривая деревянная мельница с лопастями"
	box.add_child(_request)

	box.add_child(_label("2. Скопируй промт и вставь его в любой чат с ИИ: ChatGPT, Claude, Gemini, DeepSeek...", 16))
	box.add_child(_button("Скопировать промт", _copy_prompt))

	box.add_child(_label("3. Скопируй ответ ИИ целиком и вставь сюда", 16))
	_answer = TextEdit.new()
	_answer.placeholder_text = "сюда вставляется ответ ИИ (Ctrl+V)"
	_answer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_answer.custom_minimum_size = Vector2(0, 120)
	box.add_child(_answer)

	var row := HBoxContainer.new()
	row.add_child(_button("Вставить из буфера", func(): _answer.text = DisplayServer.clipboard_get()))
	row.add_child(_button("Построить", _build))
	_fix = _button("Скопировать ошибку для ИИ", _copy_fix)
	_fix.visible = false
	row.add_child(_fix)
	box.add_child(row)

	_status = _label("", 15)
	box.add_child(_status)
	return box


func _copy_prompt() -> void:
	var request := _request.text.strip_edges()
	if request == "":
		_status.text = "Сначала напиши, что построить."
		return
	DisplayServer.clipboard_set(AiGuide.chat_prompt(request))
	_status.text = "Промт скопирован. Вставь его в чат с ИИ (Ctrl+V) и отправь."


func _copy_fix() -> void:
	DisplayServer.clipboard_set(AiGuide.fix_prompt(_last_error))
	_status.text = "Скопировано. Вставь в тот же чат, а исправленный ответ снова сюда."


func _build() -> void:
	_fix.visible = false
	var spec = AiGuide.extract_json(_answer.text)
	if not spec is Dictionary:
		_status.text = "Не нашёл описание объекта в ответе. Скопируй ответ ИИ целиком."
		return
	var res: Dictionary = bridge.run("spawn", {"spec": spec, "prompt": _request.text.strip_edges(), "author": "чат с ИИ"})
	if res.ok:
		_status.text = "Готово: «%s» стоит перед тобой. Закрой панель (F2), чтобы посмотреть." % res.result.name
		_answer.text = ""
	else:
		_last_error = res.error
		_status.text = "Игра не приняла ответ: %s" % res.error
		_fix.visible = true


# --- Вкладка «ИИ-агент (MCP)» ---------------------------------------------

func _agent_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "ИИ-агент (MCP)"
	box.add_theme_constant_override("separation", 8)

	box.add_child(_label("Игра сама работает как MCP-сервер, пока она запущена:\n%s\nВыбери свою программу, нажми кнопку и сделай, что написано рядом. Потом просто попроси агента: «построй передо мной мельницу»." % mcp.url(), 15))

	var url: String = mcp.url()
	var clients := [
		["Claude Code", "claude mcp add --transport http ai-sandbox-world %s" % url,
			"Вставь в терминал и нажми Enter, потом запусти claude."],
		["Cursor", JSON.stringify({"mcpServers": {"ai-sandbox-world": {"url": url}}}, "  "),
			"Cursor → Settings → MCP → Add new MCP server, вставь в открывшийся файл."],
		["VS Code", JSON.stringify({"servers": {"ai-sandbox-world": {"type": "http", "url": url}}}, "  "),
			"Ctrl+Shift+P → «MCP: Open User Configuration», вставь и сохрани."],
		["Claude Desktop", JSON.stringify({"mcpServers": {"ai-sandbox-world": {"command": "npx", "args": ["-y", "mcp-remote", url]}}}, "  "),
			"Настройки → Developer → Edit Config, вставь, сохрани и перезапусти. Нужен Node.js с nodejs.org."],
		["Другой агент", url,
			"Адрес MCP-сервера (Streamable HTTP). Вставь его в настройки MCP своего агента."],
	]
	for c in clients:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var b := _button(c[0], _copy_snippet.bind(c[0], c[1]))
		b.custom_minimum_size = Vector2(150, 0)
		row.add_child(b)
		var hint := _label(c[2], 14)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hint)
		box.add_child(row)

	_agent_status = _label("", 15)
	box.add_child(_agent_status)
	return box


func _copy_snippet(client: String, snippet: String) -> void:
	DisplayServer.clipboard_set(snippet)
	_agent_status.text = "Скопировано для %s." % client


# --- Мелочи ---------------------------------------------------------------

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b
