// Скрытый базовый промт стиля. Он добавляется к каждому запросу на генерацию,
// поэтому объекты от разных игроков и разных агентов выглядят одинаково
// уместно в мире. Игрок пишет только «мельница», остальное подставляет сервер.
//
// Текст лежит в ai/style_guide.md в корне проекта: его же читает игра,
// когда агент подключается к ней напрямую или игрок копирует промт для чата.
import { readFileSync } from "node:fs";

const read = (name) => readFileSync(new URL(`../../ai/${name}`, import.meta.url), "utf8").trim();

// Руководство по стилю и раздел о механиках (транспорт, снаряжение, предметы).
export const STYLE_GUIDE = `${read("style_guide.md")}\n\n${read("mechanics_guide.md")}`;

// Инструкция для агента-строителя: слушать просьбы из поля ввода в игре и строить.
export const BUILDER_PROMPT = read("builder_prompt.md");

export const GENERATION_SYSTEM_PROMPT = `${STYLE_GUIDE}

Answer with the JSON object only, no prose and no code fences.`;
