extends RefCounted
## Оформление интерфейса в духе коробок Lego: белые скруглённые панели с
## мягкой тенью, жёлтые кнопки, тёмный текст и яркие акценты. Все экраны
## собираются из этих функций, поэтому выглядят одинаково.

const INK := Color("1b2a34")
const INK_SOFT := Color("4b5a64")
const PAPER := Color(0.99, 0.99, 0.97, 0.97)
const PAPER_DIM := Color(0.93, 0.94, 0.93, 0.97)
const YELLOW := Color("f2cd37")
const YELLOW_HOT := Color("ffdc4a")
const RED := Color("c91a09")
const BLUE := Color("0055bf")
const GREEN := Color("237841")
const LINE := Color(0.11, 0.16, 0.2, 0.18)

static var _theme: Theme
static var _bold: FontVariation


static func bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


static func box(bg: Color, radius := 14, margin := 14, shadow := true, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.22)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.anti_aliasing = true
	return s


## Общая тема: её получает корневой Control каждого экрана.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", box(PAPER))
	t.set_stylebox("panel", "Panel", box(PAPER))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg := YELLOW
		match state:
			"hover":
				bg = YELLOW_HOT
			"pressed":
				bg = Color("d9b22a")
			"disabled":
				bg = Color(0.85, 0.85, 0.83)
		var s := box(bg, 10, 8, state != "pressed", Color(0, 0, 0, 0.12), 2)
		s.content_margin_left = 14
		s.content_margin_right = 14
		if state == "focus":
			s = box(Color(0, 0, 0, 0), 10, 8, false, BLUE, 2)
		t.set_stylebox(state, "Button", s)
	t.set_font("font", "Button", bold())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.5))
	for cls in ["LineEdit", "TextEdit"]:
		var field := box(Color.WHITE, 10, 10, false, LINE, 2)
		var focus := box(Color.WHITE, 10, 10, false, BLUE, 2)
		t.set_stylebox("normal", cls, field)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("read_only", cls, field)
		t.set_color("font_color", cls, INK)
		t.set_color("font_placeholder_color", cls, Color(0.45, 0.5, 0.55))
		t.set_color("caret_color", cls, INK)
		t.set_color("selection_color", cls, Color(0.0, 0.33, 0.75, 0.3))
	t.set_stylebox("panel", "PopupMenu", box(PAPER, 10, 6))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_stylebox("hover", "PopupMenu", box(YELLOW, 6, 4, false))
	t.set_stylebox("normal", "OptionButton", box(Color.WHITE, 10, 8, false, LINE, 2))
	t.set_stylebox("hover", "OptionButton", box(Color.WHITE, 10, 8, false, BLUE, 2))
	t.set_stylebox("pressed", "OptionButton", box(Color.WHITE, 10, 8, false, BLUE, 2))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), 10, 8, false, BLUE, 2))
	t.set_color("font_color", "OptionButton", INK)
	t.set_color("font_hover_color", "OptionButton", INK)
	t.set_color("font_pressed_color", "OptionButton", INK)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.06), 6, 0, false))
	t.set_stylebox("grabber", "VScrollBar", box(Color(0, 0, 0, 0.25), 6, 0, false))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(0, 0, 0, 0.35), 6, 0, false))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Color(0, 0, 0, 0.45), 6, 0, false))
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", INK)
	t.set_stylebox("slider", "HSlider", box(Color(0, 0, 0, 0.12), 4, 3, false))
	t.set_stylebox("grabber_area", "HSlider", box(YELLOW, 4, 3, false))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(YELLOW_HOT, 4, 3, false))
	t.set_stylebox("panel", "TooltipPanel", box(INK, 8, 8))
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	_theme = t
	return t


static func label(text: String, size := 16, color := INK, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Подпись поверх мира: светлый текст с тёмной обводкой.
static func overlay_label(text: String, size := 16) -> Label:
	var l := label(text, size, Color.WHITE, true)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.09, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, action: Callable, kind := "primary", size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	if action.is_valid():
		b.pressed.connect(action)
	match kind:
		"plain":
			for state in ["normal", "hover", "pressed"]:
				var bg := Color.WHITE if state != "hover" else Color(0.95, 0.96, 0.97)
				var s := box(bg, 10, 8, false, LINE, 2)
				s.content_margin_left = 12
				s.content_margin_right = 12
				b.add_theme_stylebox_override(state, s)
		"danger":
			for state in ["normal", "hover", "pressed"]:
				var s := box(RED if state != "hover" else RED.lightened(0.15), 10, 8, state == "normal")
				s.content_margin_left = 14
				s.content_margin_right = 14
				b.add_theme_stylebox_override(state, s)
			for c in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(c, Color.WHITE)
		"blue":
			for state in ["normal", "hover", "pressed"]:
				var s := box(BLUE if state != "hover" else BLUE.lightened(0.15), 10, 8, state == "normal")
				s.content_margin_left = 14
				s.content_margin_right = 14
				b.add_theme_stylebox_override(state, s)
			for c in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(c, Color.WHITE)
	return b


## Переключатель-чип: вид просьбы, размер, категория.
static func chip(text: String, toggled: Callable, color := BLUE) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	var off := box(Color.WHITE, 16, 6, false, LINE, 2)
	off.content_margin_left = 12
	off.content_margin_right = 12
	var hover := box(Color(0.95, 0.96, 0.97), 16, 6, false, LINE, 2)
	hover.content_margin_left = 12
	hover.content_margin_right = 12
	var on := box(color, 16, 6, false)
	on.content_margin_left = 12
	on.content_margin_right = 12
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	if toggled.is_valid():
		b.toggled.connect(toggled)
	return b


## Прикрепляет элемент к углу или краю экрана с отступом. Размер берётся
## из содержимого и растёт от края внутрь экрана.
static func pin(c: Control, preset: Control.LayoutPreset, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y
	match preset:
		Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_:
			c.grow_horizontal = Control.GROW_DIRECTION_END
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER:
			c.grow_vertical = Control.GROW_DIRECTION_BOTH
		_:
			c.grow_vertical = Control.GROW_DIRECTION_END


static func panel(bg := PAPER, radius := 14, margin := 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, radius, margin))
	return p


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Значок клавиши: «[Tab]».
static func key(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color.WHITE, 6, 3, false, LINE, 2)
	s.content_margin_left = 7
	s.content_margin_right = 7
	p.add_theme_stylebox_override("panel", s)
	var l := label(text, 13, INK, true)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
