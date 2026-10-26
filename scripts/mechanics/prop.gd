extends Node
## Интерактивный предмет без водителя: батут, ускоритель, катапульта,
## дверь, рычаг, карусель.
##   on_touch {"bounce": м/с вверх, "push": [x, y, z] м/с в координатах предмета}
##            срабатывает, когда игрок наступает или упирается в предмет;
##   interact "toggle": E включает и выключает анимации с "by": "active".

var toggle := false
var on_touch := {}
var active := false


func _ready() -> void:
	var root := get_parent()
	if not on_touch.is_empty():
		root.set_meta("on_touch", on_touch)
	if toggle:
		add_to_group("interactable")


func interact(_player: Node3D) -> void:
	active = not active
	var animator := get_parent().get_node_or_null("Animator")
	if animator:
		animator.inputs["active"] = 1.0 if active else 0.0


func prompt() -> String:
	return "E — %s «%s»" % ["выключить" if active else "включить", get_parent().name]


## Скорость, которую предмет передаёт игроку при касании, в координатах мира.
static func touch_velocity(body: Node3D, touch: Dictionary) -> Vector3:
	var v := Vector3.ZERO
	var b = touch.get("bounce")
	if b is float or b is int:
		v.y = clampf(float(b), 0.0, 60.0)
	var p = touch.get("push")
	if p is Array and p.size() >= 3:
		var local := Vector3(float(p[0]), float(p[1]), float(p[2])).limit_length(60.0)
		v += body.global_transform.basis.orthonormalized() * local
	return v
