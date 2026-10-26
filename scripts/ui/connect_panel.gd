extends Control
## Подключение ИИ-агента (F2). Делается один раз: кнопка своей программы
## копирует готовую настройку, потом агенту отправляется команда начать
## слушать просьбы. Дальше игрок просто пишет просьбы в поле внизу экрана.

const Ui := preload("res://scripts/ui/ui.gd")

## Короткая команда для агента: с неё он начинает слушать просьбы игрока.
const START_COMMAND := "Use the ai-sandbox-world MCP tools as the game's builder: call get_style_guide, then loop on wait_for_player_request and build each request from LEGO bricks with create_object (or update_object when the request has edit_target or edit_item). Keep looping until I stop you."

var ui
var _status: Label
var _note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.11, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := Ui.panel(Ui.PAPER, 18, 22)
	panel.custom_minimum_size.x = 760
	center.add_child(panel)
	var col := Ui.vbox(12)
	panel.add_child(col)

	var head := Ui.hbox(10)
	var t := Ui.label("Подключить ИИ-строителя", 24, Ui.INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(Ui.button("Закрыть (F2)", ui.close_modal, "plain", 14))
	col.add_child(head)
	_status = Ui.label("", 15, Color.WHITE, true)
	var pill := Ui.panel(Ui.GREEN, 12, 8)
	pill.add_child(_status)
	pill.set_meta("pill", true)
	col.add_child(pill)
	_status.set_meta("pill", pill)

	col.add_child(_wrap(Ui.label("Это нужно один раз. ИИ-агент (Claude Code, Cursor и другие) подключается к игре по MCP и строит всё, что ты попросишь, из кирпичиков. Строить в этом мире можешь только ты: агент работает на тебя.", 15, Ui.INK)))
	col.add_child(Ui.label("1. Нажми кнопку своей программы и вставь скопированное, куда написано:", 16, Ui.INK, true))
	var url: String = ui.mcp.url()
	var clients := [
		["Claude Code", "claude mcp add --transport http ai-sandbox-world %s\nclaude --allowedTools \"mcp__ai-sandbox-world\" \"%s\"" % [url, START_COMMAND],
			"Вставь в терминал обе строки. Агент сразу начнёт слушать игру, шаг 2 не нужен."],
		["Cursor", JSON.stringify({"mcpServers": {"ai-sandbox-world": {"url": url}}}, "  "),
			"Settings → MCP → Add new MCP server, вставь в файл и сохрани."],
		["VS Code", JSON.stringify({"servers": {"ai-sandbox-world": {"type": "http", "url": url}}}, "  "),
			"Ctrl+Shift+P → «MCP: Open User Configuration», вставь и сохрани."],
		["Claude Desktop", JSON.stringify({"mcpServers": {"ai-sandbox-world": {"command": "npx", "args": ["-y", "mcp-remote", url]}}}, "  "),
			"Настройки → Developer → Edit Config, вставь, сохрани, перезапусти. Нужен Node.js."],
		["Другой агент", url, "Адрес MCP-сервера игры (Streamable HTTP)."],
	]
	for c in clients:
		var row := Ui.hbox(12)
		var b := Ui.button(c[0], _copy.bind(c[1], "Скопировано для %s." % c[0]), "primary", 15)
		b.custom_minimum_size.x = 170
		row.add_child(b)
		var hint := _wrap(Ui.label(c[2], 14, Ui.INK_SOFT))
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hint)
		col.add_child(row)
	col.add_child(_wrap(Ui.label("2. Скопируй команду и отправь её агенту в его чат. Разреши инструменты ai-sandbox-world без подтверждения («Always allow»), иначе агент будет спрашивать разрешения на каждую постройку.", 16, Ui.INK, true)))
	col.add_child(Ui.button("Скопировать команду для агента", _copy.bind(START_COMMAND, "Команда скопирована. Отправь её агенту."), "blue", 15))
	col.add_child(_wrap(Ui.label("3. Вернись в игру, нажми Enter и напиши, что построить. Карточка слева внизу покажет, что делает ИИ.", 16, Ui.INK, true)))
	_note = Ui.label("", 14, Ui.GREEN, true)
	col.add_child(_note)


func open() -> void:
	visible = true
	_note.text = ""


func _process(_delta: float) -> void:
	if not visible:
		return
	var online: bool = ui.bridge.agent_online()
	_status.text = "Сейчас: ИИ на связи, можно просить" if online else "Сейчас: ИИ не подключён"
	var pill: PanelContainer = _status.get_meta("pill")
	pill.add_theme_stylebox_override("panel", Ui.box(Ui.GREEN if online else Color(0.4, 0.43, 0.47), 12, 8, false))


func _copy(text: String, note: String) -> void:
	DisplayServer.clipboard_set(text)
	_note.text = note
	ui.sfx.play("click")


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 540
	return l
