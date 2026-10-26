extends Control
## Меню паузы (Esc): продолжить, настройки, внешность фигурки, подключение
## ИИ, выход к списку миров и из игры. Настройки сохраняются сразу.

const Ui := preload("res://scripts/ui/ui.gd")
const Worlds := preload("res://scripts/worlds.gd")
const Minifig := preload("res://scripts/minifig.gd")
const Style := preload("res://scripts/style.gd")

const LOOK_COLORS := ["red", "blue", "yellow", "green", "white", "black", "orange", "dark_blue", "dark_red", "lime", "pink", "purple", "tan", "brown", "dark_gray", "azure"]
const HAT_NAMES := {"hair": "Причёска", "cap": "Кепка", "helmet": "Шлем", "bald": "Без"}
const FACE_NAMES := {"smile": "Улыбка", "grin": "Смех", "wink": "Подмигивает"}

var ui
var _panel: PanelContainer
var _page: VBoxContainer
var _preview: SubViewport
var _fig: Node3D


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
	_panel = Ui.panel(Ui.PAPER, 18, 22)
	center.add_child(_panel)
	_page = Ui.vbox(10)
	_panel.add_child(_page)


func open() -> void:
	visible = true
	get_tree().paused = false
	_main()


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if _fig and is_instance_valid(_fig):
		_fig.rotation.y += delta * 0.8


func _clear(title: String) -> void:
	for c in _page.get_children():
		c.queue_free()
	_fig = null
	var t := Ui.label(title, 26, Ui.INK, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(t)


func _big(text: String, action: Callable, kind := "primary") -> Button:
	var b := Ui.button(text, action, kind, 18)
	b.custom_minimum_size = Vector2(340, 48)
	return b


func _main() -> void:
	_clear("Пауза")
	_page.add_child(Ui.label(str(ui.bridge.meta.get("name", "")), 15, Ui.INK_SOFT))
	_page.add_child(_big("Продолжить", ui.close_modal))
	_page.add_child(_big("Фигурка", _look_page, "plain"))
	_page.add_child(_big("Настройки", _settings_page, "plain"))
	_page.add_child(_big("Подключить ИИ (F2)", func() -> void: ui.open("connect"), "plain"))
	_page.add_child(_big("Все клавиши (F1)", func() -> void: ui.open("help"), "plain"))
	_page.add_child(_big("К списку миров", ui.exit_to_worlds, "blue"))
	_page.add_child(_big("Выйти из игры", ui.quit_game, "danger"))
	_page.add_child(Ui.label("Мир сохраняется сам каждую минуту и при выходе.", 13, Ui.INK_SOFT))


# --- Настройки ------------------------------------------------------------

func _settings_page() -> void:
	_clear("Настройки")
	var s: Dictionary = ui.settings
	_page.add_child(_slider("Чувствительность мыши", 0.2, 3.0, float(s.mouse_sensitivity), func(v: float) -> void: _put("mouse_sensitivity", v)))
	_page.add_child(_check("Инвертировать мышь по вертикали", bool(s.invert_y), func(v: bool) -> void: _put("invert_y", v)))
	_page.add_child(_slider("Громкость", 0.0, 1.0, float(s.volume), func(v: float) -> void: _put("volume", v)))
	_page.add_child(_check("Тени", bool(s.shadows), func(v: bool) -> void: _put("shadows", v)))
	_page.add_child(_check("Объёмные шипы на пластине", bool(s.stud_detail), func(v: bool) -> void: _put("stud_detail", v)))
	_page.add_child(_check("Показать обучение снова", not bool(s.tutorial_done), func(v: bool) -> void: _put("tutorial_done", not v)))
	_page.add_child(_big("Назад", _main, "plain"))


func _put(key: String, value) -> void:
	ui.settings[key] = value
	ui.apply_settings()


func _slider(text: String, lo: float, hi: float, value: float, changed: Callable) -> Control:
	var row := Ui.hbox(12)
	var l := Ui.label(text, 16)
	l.custom_minimum_size.x = 240
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size.x = 220
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(changed)
	row.add_child(sl)
	return row


func _check(text: String, value: bool, changed: Callable) -> Control:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 16)
	c.toggled.connect(changed)
	return c


# --- Фигурка --------------------------------------------------------------

func _look_page() -> void:
	_clear("Фигурка")
	var look: Dictionary = Minifig.DEFAULT_LOOK.duplicate()
	look.merge(ui.settings.get("look", {}), true)
	var row := Ui.hbox(18)
	_page.add_child(row)
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(220, 300)
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
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 0.8
	_preview.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	_preview.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.3, 4.6), Vector3(0, 0.95, 0))
	row.add_child(holder)
	_rebuild_fig(look)

	var opts := Ui.vbox(8)
	row.add_child(opts)
	var name_row := Ui.hbox(8)
	name_row.add_child(Ui.label("Имя", 15, Ui.INK, true))
	var name_field := LineEdit.new()
	name_field.text = str(ui.settings.get("player_name", ""))
	name_field.placeholder_text = "Как тебя зовут"
	name_field.custom_minimum_size.x = 240
	name_field.text_changed.connect(func(t: String) -> void: _put("player_name", t.strip_edges().left(24)))
	name_row.add_child(name_field)
	opts.add_child(name_row)
	for part in [["torso", "Туловище"], ["legs", "Ноги"], ["hair", "Волосы и шапка"]]:
		opts.add_child(Ui.label(part[1], 15, Ui.INK, true))
		var swatches := HFlowContainer.new()
		swatches.custom_minimum_size.x = 340
		swatches.add_theme_constant_override("h_separation", 4)
		swatches.add_theme_constant_override("v_separation", 4)
		for c in LOOK_COLORS:
			swatches.add_child(_swatch(c, look[part[0]] == c, _set_look.bind(part[0], c)))
		opts.add_child(swatches)
	var hats := Ui.hbox(6)
	for h in Minifig.HATS:
		var chip := Ui.chip(HAT_NAMES.get(h, h), func(_on: bool) -> void: _set_look("hat", h))
		chip.set_pressed_no_signal(look.hat == h)
		hats.add_child(chip)
	opts.add_child(hats)
	var faces := Ui.hbox(6)
	for f in Minifig.FACES:
		var chip := Ui.chip(FACE_NAMES.get(f, f), func(_on: bool) -> void: _set_look("face", f))
		chip.set_pressed_no_signal(look.face == f)
		faces.add_child(chip)
	opts.add_child(faces)
	_page.add_child(_big("Готово", _main, "plain"))


func _swatch(color: String, on: bool, action: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(30, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = color
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, Ui.box(Style.COLORS.get(color, Color.WHITE), 8, 0, false, Ui.BLUE if on else Color(0, 0, 0, 0.2), 3 if on else 1))
	b.pressed.connect(action)
	return b


func _set_look(key: String, value: String) -> void:
	var look: Dictionary = (ui.settings.get("look", {}) as Dictionary).duplicate()
	look[key] = value
	ui.settings["look"] = look
	ui.apply_settings()
	ui.player.set_look(look)
	ui.sfx.play("click")
	_look_page()


func _rebuild_fig(look: Dictionary) -> void:
	var fig: Dictionary = Minifig.build(look)
	_fig = fig.root
	_preview.add_child(_fig)
