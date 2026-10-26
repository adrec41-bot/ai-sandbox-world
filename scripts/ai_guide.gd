extends RefCounted
## Тексты для ИИ: руководство по стилю и инструкция для агента-строителя.
## Текст руководства лежит в ai/style_guide.md, его же использует mcp-server,
## поэтому все пути генерации получают один и тот же скрытый базовый промт.

const GUIDE_PATH := "res://ai/style_guide.md"
const BUILDER_PATH := "res://ai/builder_prompt.md"

static var _guide := ""


static func guide() -> String:
	if _guide == "":
		_guide = FileAccess.get_file_as_string(GUIDE_PATH).strip_edges()
	return _guide


## Инструкция для агента-строителя: слушать просьбы игроков и строить.
static func builder_prompt() -> String:
	return FileAccess.get_file_as_string(BUILDER_PATH).strip_edges()
