extends Control
## Три шага для нового игрока: поставить деталь, открыть инвентарь и
## попросить ИИ. Каждый шаг засчитывается сам, когда игрок его сделал.
## Обучение можно пропустить, и оно больше не покажется (вернуть: Настройки).

const Ui := preload("res://scripts/ui/ui.gd")

const STEPS := [
	["B", "Нажми B, чтобы строить, и поставь деталь левой кнопкой мыши"],
	["Tab", "Открой инвентарь: там все детали и всё, что построит ИИ"],
	["Enter", "Нажми Enter и напиши ИИ, что построить: «домик с садом»"],
]

var ui
var _step := 0
var _card: PanelContainer
var _key: PanelContainer
var _text: Label
var _count: Label
var _done_left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = Ui.panel(Ui.PAPER, 14, 12)
	Ui.pin(_card, Control.PRESET_CENTER_TOP, Vector2(0, 120))
	add_child(_card)
	var row := Ui.hbox(12)
	_card.add_child(row)
	_count = Ui.label("", 13, Ui.INK_SOFT, true)
	row.add_child(_count)
	_key = Ui.key("")
	row.add_child(_key)
	_text = Ui.label("", 16, Ui.INK, true)
	row.add_child(_text)
	row.add_child(Ui.button("Пропустить", finish, "plain", 13))
	ui.bridge.object_added.connect(func(_n: Node3D, animate: bool) -> void:
		if animate and _step == 0:
			_next())
	ui.bridge.requests_changed.connect(func() -> void:
		if _step == 2 and not ui.bridge.requests().is_empty():
			_next())
	visible = not bool(ui.settings.get("tutorial_done", false))
	_show()


func _process(delta: float) -> void:
	if _done_left > 0.0:
		_done_left -= delta
		if _done_left <= 0.0:
			visible = false
		return
	if not visible:
		return
	if _step == 1 and ui.modal == "inventory":
		_next()
	_card.visible = ui.modal == "" or (_step == 1 and ui.modal == "inventory")


func restart() -> void:
	_step = 0
	_done_left = 0.0
	visible = true
	_show()


func _next() -> void:
	_step += 1
	ui.sfx.play("done")
	if _step >= STEPS.size():
		_count.text = ""
		_key.visible = false
		_text.text = "Готово! Этот мир твой: строй что угодно. Все клавиши: F1"
		_done_left = 4.0
		_save()
		return
	_show()


func _show() -> void:
	if _step >= STEPS.size():
		return
	_count.text = "%d/%d" % [_step + 1, STEPS.size()]
	_key.visible = true
	(_key.get_child(0) as Label).text = STEPS[_step][0]
	var t: String = STEPS[_step][1]
	if _step == 2 and not ui.bridge.agent_online():
		t += " (ИИ подключается по F2)"
	_text.text = t


func finish() -> void:
	visible = false
	_save()


func _save() -> void:
	ui.settings["tutorial_done"] = true
	ui.apply_settings()
