// Скрытый базовый промт стиля. Он добавляется к каждому запросу на генерацию,
// поэтому объекты от разных игроков и разных агентов выглядят одинаково
// уместно в мире. Игрок пишет только «мельница», остальное подставляет сервер.
//
// Текст лежит в ai/style_guide.md в корне проекта: его же читает игра,
// когда агент подключается к ней напрямую или игрок копирует промт для чата.
import { readFileSync } from "node:fs";

export const STYLE_GUIDE = readFileSync(new URL("../../ai/style_guide.md", import.meta.url), "utf8").trim();

export const GENERATION_SYSTEM_PROMPT = `${STYLE_GUIDE}

Answer with the JSON object only, no prose and no code fences.`;
