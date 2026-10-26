extends Control
## Весь интерфейс поверх мира и то, кто сейчас получает клавиши.
##
## Слева вверху карточка мира и режим, справа вверху связь с ИИ и журнал,
## внизу хотбар и панель просьб к ИИ, справа внизу подсказки клавиш, которые
## работают прямо сейчас. Поверх открываются окна: инвентарь (Tab), меню (Esc),
## справка (F1), подключение ИИ (F2), палитра (C). Пока окно открыто, мышь
## свободна, а персонаж стоит.

const Ui := preload("res://scripts/ui/ui.gd")
const HotbarScript := preload("res://scripts/ui/hotbar.gd")
const PromptScript := preload("res://scripts/ui/prompt_panel.gd")
const InventoryScript := preload("res://scripts/ui/inventory_screen.gd")
const ConnectScript := preload("res://scripts/ui/connect_panel.gd")
const MenuScript := preload("res://scripts/ui/pause_menu.gd")
const HelpScript := preload("res://scripts/ui/help_screen.gd")
const ColorsScript := preload("res://scripts/ui/color_picker.gd")
const TutorialScript := preload("res://scripts/ui/tutorial.gd")
const Style := preload("res://scripts/style.gd")
const Worlds := preload("res://scripts/worlds.gd")

var world
var bridge
var mcp
var player
var build
var thumbs
var sfx
## Настройки игрока (worlds.gd DEFAULT_SETTINGS), меняются в меню.
var settings := {}

var hotbar: Control
var prompt: Control
var inventory: Control
var connect_panel: Control
var menu: Control
var help: Control
var colors: Control
var tutorial: Control
## Открытое окно: "", "inventory", "menu", "help", "connect", "colors".
var modal := ""

var _world_name: Label
var _mode: Label
var _mode_box: PanelContainer
var _agent: Label
var _agent_box: PanelContainer
var _hints: VBoxContainer
var _hint_key := ""
var _toast: PanelContainer
var _toast_label: Label
var _toast_left := 0.0
var _crosshair: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	if settings.is_empty():
		settings = Worlds.load_settings()
	_build_top()
	_build_hints()
	_build_toast()
	_crosshair = _Crosshair.new()
	Ui.pin(_crosshair, Control.PRESET_CENTER, Vector2.ZERO)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	prompt = PromptScript.new()
	prompt.ui = self
	add_child(prompt)
	hotbar = HotbarScript.new()
	hotbar.ui = self
	add_child(hotbar)
	inventory = InventoryScript.new()
	inventory.ui = self
	add_child(inventory)
	colors = ColorsScript.new()
	colors.ui = self
	add_child(colors)
	connect_panel = ConnectScript.new()
	connect_panel.ui = self
	add_child(connect_panel)
	help = HelpScript.new()
	help.ui = self
	add_child(help)
	menu = MenuScript.new()
	menu.ui = self
	add_child(menu)
	tutorial = TutorialScript.new()
	tutorial.ui = self
	add_child(tutorial)

	bridge.notice.connect(toast)
	bridge.agent_message.connect(func(_id: String, text: String, done: bool) -> void:
		if done:
			sfx.play("done"))


func _process(delta: float) -> void:
	var online: bool = bridge.agent_online()
	_agent.text = "ИИ на связи" if online else "ИИ не подключён · F2"
	_agent_box.add_theme_stylebox_override("panel", Ui.box(Ui.GREEN if online else Color(0.35, 0.38, 0.42, 0.92), 18, 8))
	_world_name.text = str(bridge.meta.get("name", "Мой мир"))
	var building: bool = build.active
	_mode.text = "Строительство" if building else "Игра"
	_mode_box.add_theme_stylebox_override("panel", Ui.box(Ui.BLUE if building else Ui.GREEN, 10, 5, false))
	_crosshair.visible = building and modal == "" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_crosshair.queue_redraw()
	_update_hints()
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left * 2.0, 0.0, 1.0)
		_toast.visible = _toast_left > 0.0
	player.frozen = blocked()


## Взять предмет в руки: он встаёт в слот хотбара, включается строительство.
func place_item(item_id: String) -> void:
	var item: Dictionary = bridge.get_item(item_id)
	if item.is_empty():
		return
	var slot: int = bridge.hotbar.find(item_id)
	if slot < 0:
		slot = bridge.hotbar.find("")
	if slot < 0:
		slot = bridge.selected
	bridge.assign_hotbar(slot, item_id)
	close_modal()
	if not build.active:
		build.toggle()
	toast("«%s» в руках: наведи прицел и нажми ЛКМ" % item.name, 4.0)


## Применяет и сохраняет настройки.
func apply_settings() -> void:
	Worlds.save_settings(settings)
	player.mouse_scale = float(settings.get("mouse_sensitivity", 1.0))
	player.invert_y = bool(settings.get("invert_y", false))
	sfx.volume = float(settings.get("volume", 0.8))
	world.set_graphics(bool(settings.get("shadows", true)), bool(settings.get("stud_detail", true)))
	if not bool(settings.get("tutorial_done", false)) and tutorial and not tutorial.visible:
		tutorial.restart()


## Сохраняет мир с картинкой для списка миров и возвращает к нему.
func exit_to_worlds() -> void:
	await _save_world()
	Worlds.current = ""
	get_tree().reload_current_scene()


func quit_game() -> void:
	await _save_world()
	get_tree().quit()


func _save_world() -> void:
	close_modal()
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		var w := 384
		img.resize(w, int(w * float(img.get_height()) / img.get_width()), Image.INTERPOLATE_BILINEAR)
		img.save_png(Worlds.thumb_path(bridge.world_id))
	bridge.save_now(true)


## Персонаж не ходит, пока открыто окно или игрок печатает.
func blocked() -> bool:
	return modal != "" or prompt.is_typing()


func open(name: String) -> void:
	if modal == name:
		close_modal()
		return
	close_modal()
	modal = name
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match name:
		"inventory":
			inventory.open()
		"menu":
			menu.open()
		"help":
			help.visible = true
		"connect":
			connect_panel.open()
		"colors":
			colors.visible = true
	sfx.play("open")


func close_modal() -> void:
	match modal:
		"inventory":
			inventory.visible = false
		"menu":
			menu.close()
		"help":
			help.visible = false
		"connect":
			connect_panel.visible = false
		"colors":
			colors.visible = false
	if modal != "":
		modal = ""
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	# Клик в мир, пока мышь свободна, возвращает управление камерой.
	if event is InputEventMouseButton and event.pressed and modal == "" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered == null or hovered == self:
			prompt.release()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: Key = event.keycode
	if modal != "":
		if k == KEY_ESCAPE or (k == KEY_TAB and modal == "inventory") or (k == KEY_F1 and modal == "help") \
				or (k == KEY_F2 and modal == "connect") or (k == KEY_C and modal == "colors" and not _typing_in_gui()):
			close_modal()
			get_viewport().set_input_as_handled()
		return
	if prompt.is_typing():
		return
	var handled := true
	match k:
		KEY_ESCAPE:
			if build.has_selection() or build.is_carrying():
				build.cancel()
			else:
				open("menu")
		KEY_TAB:
			open("inventory")
		KEY_F1:
			open("help")
		KEY_F2:
			open("connect")
		KEY_ENTER, KEY_KP_ENTER, KEY_SLASH:
			prompt.focus()
		KEY_B:
			build.toggle()
		KEY_C:
			if not event.ctrl_pressed:
				open("colors")
			else:
				handled = false
		KEY_L:
			prompt.toggle_journal()
		KEY_Z:
			if event.ctrl_pressed:
				toast(bridge.redo() if event.shift_pressed else bridge.undo())
				sfx.play("click")
			else:
				handled = false
		KEY_Y:
			if event.ctrl_pressed:
				toast(bridge.redo())
				sfx.play("click")
			else:
				handled = false
		KEY_F:
			if not build.active:
				var msg: String = bridge.place_selected()
				if msg != "":
					toast(msg)
			else:
				handled = false
		KEY_G:
			if not build.active:
				toast(bridge.pick_up_in_front())
			else:
				handled = false
		_:
			if k >= KEY_1 and k <= KEY_9:
				bridge.select(k - KEY_1)
				sfx.play("tick")
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Колесо с Shift листает слоты хотбара.
	if event is InputEventMouseButton and event.pressed and event.shift_pressed and modal == "" and not build.active:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			bridge.select(posmod(bridge.selected - 1, bridge.HOTBAR_SIZE))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			bridge.select(posmod(bridge.selected + 1, bridge.HOTBAR_SIZE))


func _typing_in_gui() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Короткое сообщение вверху экрана.
func toast(text: String, seconds := 3.0) -> void:
	if text == "":
		return
	_toast_label.text = text
	_toast_left = seconds
	_toast.visible = true
	_toast.modulate.a = 1.0


# --- Верх экрана ------------------------------------------------------------

func _build_top() -> void:
	var card := Ui.panel(Ui.PAPER, 14, 10)
	card.position = Vector2(20, 18)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var row := Ui.hbox(10)
	card.add_child(row)
	var brick := _BrickIcon.new()
	brick.custom_minimum_size = Vector2(34, 26)
	row.add_child(brick)
	_world_name = Ui.label("", 18, Ui.INK, true)
	row.add_child(_world_name)
	_mode_box = PanelContainer.new()
	_mode = Ui.label("", 13, Color.WHITE, true)
	_mode_box.add_child(_mode)
	row.add_child(_mode_box)

	_agent_box = PanelContainer.new()
	Ui.pin(_agent_box, Control.PRESET_TOP_RIGHT, Vector2(-20, 20))
	_agent_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_agent = Ui.label("", 15, Color.WHITE, true)
	_agent_box.add_child(_agent)
	add_child(_agent_box)


func _build_hints() -> void:
	_hints = Ui.vbox(6)
	Ui.pin(_hints, Control.PRESET_BOTTOM_RIGHT, Vector2(-20, -20))
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hints)


## Подсказки только про то, что работает сейчас.
func _update_hints() -> void:
	var list: Array = []
	if modal != "" or prompt.is_typing():
		list = []
	elif build.active:
		list = build.hints()
	else:
		list = [["B", "строить"], ["Tab", "инвентарь"], ["Enter", "попросить ИИ"], ["F", "поставить"], ["F1", "все клавиши"]]
	var key := str(list)
	if key == _hint_key:
		return
	_hint_key = key
	for c in _hints.get_children():
		c.queue_free()
	for h in list:
		var row := Ui.hbox(6)
		row.alignment = BoxContainer.ALIGNMENT_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(Ui.overlay_label(h[1], 14))
		row.add_child(Ui.key(h[0]))
		_hints.add_child(row)


func _build_toast() -> void:
	_toast = Ui.panel(Ui.INK, 12, 10)
	Ui.pin(_toast, Control.PRESET_CENTER_TOP, Vector2(0, 76))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = Ui.label("", 16, Color.WHITE, true)
	_toast.add_child(_toast_label)
	_toast.visible = false
	add_child(_toast)


## Значок кирпичика рядом с именем мира.
class _BrickIcon extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2(0, 8), Vector2(size.x, size.y - 8))
		draw_rect(r, Color("c91a09"))
		for i in 2:
			var c := Vector2(size.x * (0.27 + i * 0.46), 8)
			draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 6)), Color("e03a26"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color(1, 1, 1, 0.18))


## Прицел в режиме строительства.
class _Crosshair extends Control:
	func _draw() -> void:
		var c := Color(1, 1, 1, 0.9)
		var o := Color(0, 0, 0, 0.5)
		for col: Color in [o, c]:
			var w := 4.0 if col == o else 2.0
			draw_line(Vector2(-10, 0), Vector2(-4, 0), col, w)
			draw_line(Vector2(4, 0), Vector2(10, 0), col, w)
			draw_line(Vector2(0, -10), Vector2(0, -4), col, w)
			draw_line(Vector2(0, 4), Vector2(0, 10), col, w)
