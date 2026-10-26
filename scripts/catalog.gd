extends RefCounted
## Категории инвентаря и набор базовых деталей, которые есть всегда, без ИИ.
## Базовая деталь красится в цвет, выбранный в палитре (клавиша C).

const CATEGORIES := [
	["all", "Всё"],
	["new", "Новое"],
	["favorites", "Избранное"],
	["buildings", "Здания"],
	["vehicles", "Транспорт"],
	["gear", "Снаряжение"],
	["mechanisms", "Механизмы"],
	["nature", "Природа"],
	["decor", "Декор"],
	["basic", "Базовые детали"],
	["trash", "Корзина"],
]
## Категории, которые ИИ может поставить предмету.
const ITEM_CATEGORIES := ["buildings", "vehicles", "gear", "mechanisms", "nature", "decor"]
const PREFIX := "basic:"

## [id, название, кирпичи с цветом "$"]. Деталь стоит по центру начала координат.
const BASIC := [
	["brick_1x1", "Кирпич 1×1", [{"type": "brick", "at": [0, 0, 0], "size": [1, 1]}]],
	["brick_1x2", "Кирпич 1×2", [{"type": "brick", "at": [-1, 0, 0], "size": [2, 1]}]],
	["brick_1x4", "Кирпич 1×4", [{"type": "brick", "at": [-2, 0, 0], "size": [4, 1]}]],
	["brick_1x6", "Кирпич 1×6", [{"type": "brick", "at": [-3, 0, 0], "size": [6, 1]}]],
	["brick_1x8", "Кирпич 1×8", [{"type": "brick", "at": [-4, 0, 0], "size": [8, 1]}]],
	["brick_2x2", "Кирпич 2×2", [{"type": "brick", "at": [-1, 0, -1], "size": [2, 2]}]],
	["brick_2x3", "Кирпич 2×3", [{"type": "brick", "at": [-1, 0, -1], "size": [3, 2]}]],
	["brick_2x4", "Кирпич 2×4", [{"type": "brick", "at": [-2, 0, -1], "size": [4, 2]}]],
	["brick_2x6", "Кирпич 2×6", [{"type": "brick", "at": [-3, 0, -1], "size": [6, 2]}]],
	["brick_2x8", "Кирпич 2×8", [{"type": "brick", "at": [-4, 0, -1], "size": [8, 2]}]],
	["plate_1x1", "Пластина 1×1", [{"type": "plate", "at": [0, 0, 0], "size": [1, 1]}]],
	["plate_1x2", "Пластина 1×2", [{"type": "plate", "at": [-1, 0, 0], "size": [2, 1]}]],
	["plate_1x4", "Пластина 1×4", [{"type": "plate", "at": [-2, 0, 0], "size": [4, 1]}]],
	["plate_2x2", "Пластина 2×2", [{"type": "plate", "at": [-1, 0, -1], "size": [2, 2]}]],
	["plate_2x4", "Пластина 2×4", [{"type": "plate", "at": [-2, 0, -1], "size": [4, 2]}]],
	["plate_2x8", "Пластина 2×8", [{"type": "plate", "at": [-4, 0, -1], "size": [8, 2]}]],
	["plate_4x4", "Пластина 4×4", [{"type": "plate", "at": [-2, 0, -2], "size": [4, 4]}]],
	["plate_6x6", "Пластина 6×6", [{"type": "plate", "at": [-3, 0, -3], "size": [6, 6]}]],
	["plate_8x8", "Пластина 8×8", [{"type": "plate", "at": [-4, 0, -4], "size": [8, 8]}]],
	["plate_16x16", "Пластина 16×16", [{"type": "plate", "at": [-8, 0, -8], "size": [16, 16]}]],
	["tile_1x2", "Плитка 1×2", [{"type": "tile", "at": [-1, 0, 0], "size": [2, 1]}]],
	["tile_2x2", "Плитка 2×2", [{"type": "tile", "at": [-1, 0, -1], "size": [2, 2]}]],
	["tile_4x4", "Плитка 4×4", [{"type": "tile", "at": [-2, 0, -2], "size": [4, 4]}]],
	["slope_1x2", "Скос 1×2", [{"type": "slope", "at": [-1, 0, 0], "size": [2, 1]}]],
	["slope_2x2", "Скос 2×2", [{"type": "slope", "at": [-1, 0, -1], "size": [2, 2]}]],
	["slope_2x4", "Скос 2×4", [{"type": "slope", "at": [-2, 0, -1], "size": [4, 2]}]],
	["round_1x1", "Круглый 1×1", [{"type": "round", "at": [0, 0, 0], "size": [1, 1]}]],
	["round_2x2", "Круглый 2×2", [{"type": "round", "at": [-1, 0, -1], "size": [2, 2]}]],
	["cone_1x1", "Конус 1×1", [{"type": "cone", "at": [0, 0, 0], "size": [1, 1]}]],
	["cone_2x2", "Конус 2×2", [{"type": "cone", "at": [-1, 0, -1], "size": [2, 2]}]],
	["column", "Колонна", [{"type": "round", "at": [-1, 0, -1], "size": [2, 2], "h": 18}]],
	["wall_1x6", "Стенка 1×6×5", [{"type": "box", "from": [-3, 0, 0], "to": [3, 15, 1]}]],
	["window", "Окно 1×4", [
		{"type": "box", "from": [-2, 0, 0], "to": [2, 3, 1]},
		{"type": "brick", "at": [-2, 3, 0], "size": [1, 1], "h": 9},
		{"type": "brick", "at": [1, 3, 0], "size": [1, 1], "h": 9},
		{"type": "brick", "at": [-1, 3, 0], "size": [2, 1], "h": 9, "color": "glass", "studs": false},
		{"type": "plate", "at": [-2, 12, 0], "size": [4, 1]},
	]],
	["door", "Дверь", [
		{"type": "brick", "at": [-2, 0, 0], "size": [1, 1], "h": 15},
		{"type": "brick", "at": [1, 0, 0], "size": [1, 1], "h": 15},
		{"type": "brick", "at": [-1, 0, 0], "size": [2, 1], "h": 15, "color": "brown", "studs": false, "id": "door"},
		{"type": "plate", "at": [-2, 15, 0], "size": [4, 1]},
	]],
	["fence", "Забор", [
		{"type": "brick", "at": [-3, 0, 0], "size": [1, 1], "h": 6},
		{"type": "brick", "at": [2, 0, 0], "size": [1, 1], "h": 6},
		{"type": "plate", "at": [-3, 6, 0], "size": [6, 1]},
		{"type": "plate", "at": [-2, 3, 0], "size": [4, 1]},
	]],
	["stairs", "Лестница", [
		{"type": "box", "from": [-1, 0, 0], "to": [1, 3, 4]},
		{"type": "box", "from": [-1, 3, 1], "to": [1, 6, 4]},
		{"type": "box", "from": [-1, 6, 2], "to": [1, 9, 4]},
		{"type": "box", "from": [-1, 9, 3], "to": [1, 12, 4]},
	]],
	["tree", "Дерево", [
		{"type": "round", "at": [0, 0, 0], "size": [1, 1], "h": 9, "color": "brown"},
		{"type": "cone", "at": [-1, 9, -1], "size": [3, 3], "h": 6, "color": "green"},
		{"type": "cone", "at": [-1, 15, -1], "size": [3, 3], "h": 4, "color": "green"},
	]],
	["bush", "Куст", [
		{"type": "round", "at": [-1, 0, -1], "size": [2, 2], "h": 3, "color": "dark_green"},
		{"type": "round", "at": [-1, 3, -1], "size": [2, 2], "h": 2, "color": "green"},
	]],
	["flower", "Цветок", [
		{"type": "round", "at": [0, 0, 0], "size": [1, 1], "h": 3, "color": "green"},
		{"type": "plate", "at": [0, 3, 0], "size": [1, 1]},
	]],
	["lamp", "Фонарь", [
		{"type": "round", "at": [0, 0, 0], "size": [1, 1], "h": 15, "color": "dark_gray"},
		{"type": "round", "at": [0, 15, 0], "size": [1, 1], "h": 3, "color": "trans_yellow"},
		{"type": "plate", "at": [0, 18, 0], "size": [1, 1], "color": "dark_gray"},
	]],
]

## Детали, которые не красятся: у них свои цвета.
const FIXED_COLOR := ["tree", "bush", "lamp"]


static func is_basic(item_id: String) -> bool:
	return item_id.begins_with(PREFIX)


## Все базовые детали в цвете paint.
static func basic_items(paint: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in BASIC:
		out.append(basic_item(PREFIX + b[0], paint))
	return out


static func basic_item(item_id: String, paint: String) -> Dictionary:
	var key := item_id.trim_prefix(PREFIX)
	for b in BASIC:
		if b[0] != key:
			continue
		var bricks := []
		for brick: Dictionary in b[2]:
			var copy := brick.duplicate(true)
			if not copy.has("color"):
				copy["color"] = paint
			bricks.append(copy)
		var mech = null
		if key == "door":
			mech = {"type": "prop", "interact": "toggle", "animations": [{"part": "door", "motion": "angle", "axis": "y", "amount": 95, "by": "active", "pivot": [-0.4, 0, 0.2]}]}
		var spec := {"name": b[1], "category": "basic", "physics": {"mode": "static"}, "bricks": bricks}
		if mech != null:
			spec["mechanics"] = mech
		var color_word := "" if key in FIXED_COLOR else paint
		return {"item_id": item_id, "name": b[1], "spec": spec, "author": "игра", "prompt": "", "category": "basic", "basic": true, "color": color_word}
	return {}


## Категория предмета: та, что поставил ИИ, иначе по механике.
static func category_of(item: Dictionary) -> String:
	var c := str(item.get("category", ""))
	if c in ITEM_CATEGORIES or c == "basic":
		return c
	var spec: Dictionary = item.get("spec", {})
	c = str(spec.get("category", ""))
	if c in ITEM_CATEGORIES:
		return c
	var mech = spec.get("mechanics")
	if mech is Dictionary:
		match str(mech.get("type", "")):
			"vehicle":
				return "vehicles"
			"equipment":
				return "gear"
			"prop":
				return "mechanisms"
	return "buildings" if _footprint_studs(spec) >= 8 else "decor"


## Значок механики для карточки предмета.
static func badge(spec: Dictionary) -> String:
	var mech = spec.get("mechanics")
	if not mech is Dictionary:
		return ""
	match str(mech.get("type", "")):
		"vehicle":
			match str(mech.get("movement", "ground")):
				"air":
					return "летает"
				"hover":
					return "парит"
			return "едет"
		"equipment":
			return "надевается"
		"prop":
			return "оживает"
	return ""


static func _footprint_studs(spec: Dictionary) -> int:
	var Bricks = load("res://scripts/bricks.gd")
	var list: Array[Dictionary] = Bricks.expand(spec.get("bricks"))
	if list.is_empty():
		return 0
	var box: AABB = Bricks.bounds(list)
	return int(maxf(box.size.x, box.size.z) / 0.4)
