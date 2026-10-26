extends Node
## Снаряжение, которое игрок надевает: реактивный ранец, крылья, сапоги-скороходы,
## пружинные ботинки. Игрок подходит к предмету и нажимает E, предмет
## садится на нужное место персонажа и меняет его способности (spec.mechanics.abilities):
##   speed        во сколько раз быстрее бегать
##   jump         во сколько раз выше прыгать
##   extra_jumps  сколько дополнительных прыжков в воздухе
##   glide        планирование: скорость падения в м/с, пока зажат Пробел
##   fly          полёт: скорость в м/с, Пробел вверх, Shift вниз
##   gravity      множитель гравитации для персонажа
## Повторное E без предметов рядом снимает снаряжение и кладёт его на землю.

## Где на персонаже: back, head, hand, feet, body.
var attach := "back"
## Сдвиг от точки крепления, в координатах предмета (-Z вперёд).
var offset := Vector3.ZERO
var abilities := {}
var hint := ""

## Точки крепления в координатах фигурки персонажа (у неё +Z смотрит вперёд).
const POINTS := {
	"back": Vector3(0, 0.95, -0.5),
	"head": Vector3(0, 1.75, 0),
	"hand": Vector3(0.4, 0.55, 0.15),
	"feet": Vector3(0, 0, 0),
	"body": Vector3(0, 0.8, 0),
}


func _ready() -> void:
	add_to_group("interactable")


func interact(player: Node3D) -> void:
	player.equip(get_parent())


func prompt() -> String:
	return "E — надеть «%s»" % get_parent().name


## Положение предмета на персонаже. Предмет повёрнут так, что его -Z смотрит
## туда же, куда персонаж.
func attach_transform() -> Transform3D:
	var flip := Basis(Vector3.UP, PI)
	return Transform3D(flip, POINTS.get(attach, POINTS.back)) * Transform3D(Basis(), offset)
