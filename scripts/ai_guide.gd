extends RefCounted
## Руководство по стилю для ИИ и разбор ответов ИИ.
## Текст руководства лежит в ai/style_guide.md, его же использует mcp-server,
## поэтому все пути генерации получают один и тот же скрытый базовый промт.

const GUIDE_PATH := "res://ai/style_guide.md"

static var _guide := ""


static func guide() -> String:
	if _guide == "":
		_guide = FileAccess.get_file_as_string(GUIDE_PATH).strip_edges()
	return _guide


## Промт для обычного чата с ИИ (ChatGPT, Claude, Gemini и любой другой).
static func chat_prompt(request: String) -> String:
	return "%s\n\nDesign this object for my game: %s\n\nReply with the JSON object only (a ```json block is fine), no explanations." % [guide(), request]


## Просьба исправить ответ, если игра не приняла описание.
static func fix_prompt(error: String) -> String:
	return "The game rejected your JSON: %s. Send the corrected JSON object only." % error


## Достаёт JSON-объект из ответа ИИ, даже с текстом вокруг и ```json.
static func extract_json(text: String):
	var body := text
	var fence := text.find("```")
	if fence >= 0:
		var start := text.find("\n", fence)
		var end := text.find("```", start)
		if start >= 0 and end > start:
			body = text.substr(start, end - start)
	var a := body.find("{")
	var b := body.rfind("}")
	if a < 0 or b <= a:
		return null
	return JSON.parse_string(body.substr(a, b - a + 1))
