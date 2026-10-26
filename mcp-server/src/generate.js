// Генерация описания объекта по промту игрока. К промту всегда добавляется
// скрытый базовый промт стиля (GENERATION_SYSTEM_PROMPT).
//
// Генераторы по порядку:
//   1. anthropic: Claude через API, если задан ANTHROPIC_API_KEY.
//   2. sampling: модель самого подключённого агента через MCP sampling,
//      если клиент его поддерживает. Тогда ключ API не нужен.
// Если нет ни того ни другого, агент сам пишет описание и зовёт place_object.
import Anthropic from "@anthropic-ai/sdk";
import { GENERATION_SYSTEM_PROMPT } from "./style.js";
import { checkSpec, extractJson } from "./spec.js";

const MODEL = process.env.ANTHROPIC_MODEL || "claude-opus-5-5";
const ATTEMPTS = 2;

let anthropic = null;
function anthropicClient() {
  if (!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_AUTH_TOKEN) return null;
  anthropic ??= new Anthropic();
  return anthropic;
}

async function askAnthropic(client, messages) {
  const response = await client.beta.messages
    .stream({
      model: MODEL,
      max_tokens: 64000,
      thinking: { type: "adaptive" },
      output_config: { effort: "medium" },
      // При отказе модели запрос сам повторится на запасной модели.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: GENERATION_SYSTEM_PROMPT,
      messages,
    })
    .finalMessage();
  if (response.stop_reason === "refusal") throw new Error("the model declined to design this object");
  if (response.stop_reason === "max_tokens") throw new Error("the object description was too long");
  return response.content
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
}

async function askSampling(mcp, messages) {
  const result = await mcp.server.createMessage({
    systemPrompt: GENERATION_SYSTEM_PROMPT,
    messages: messages.map((m) => ({ role: m.role, content: { type: "text", text: m.content } })),
    maxTokens: 16000,
    includeContext: "none",
  });
  const content = Array.isArray(result.content) ? result.content : [result.content];
  return content
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("");
}

/** Какой генератор доступен для этого подключения: "anthropic", "sampling" или null. */
export function availableGenerator(mcp) {
  const wanted = process.env.GENERATOR || "auto";
  if (wanted === "none") return null;
  if ((wanted === "auto" || wanted === "anthropic") && anthropicClient()) return "anthropic";
  if ((wanted === "auto" || wanted === "sampling") && mcp.server.getClientCapabilities()?.sampling) return "sampling";
  return null;
}

/**
 * Превращает промт игрока в проверенное описание объекта.
 * physics, если задан, подсказывает модели нужный режим физики.
 */
export async function generateSpec(mcp, prompt, { physics } = {}) {
  const generator = availableGenerator(mcp);
  if (!generator) throw new Error("no generator available");
  const ask = generator === "anthropic" ? (m) => askAnthropic(anthropicClient(), m) : (m) => askSampling(mcp, m);

  let request = `Design this object: ${prompt}`;
  if (physics) request += `\nUse physics mode "${physics}".`;
  const messages = [{ role: "user", content: request }];
  let lastError = "";
  for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
    const text = await ask(messages);
    let parsed;
    try {
      parsed = extractJson(text);
    } catch (err) {
      lastError = err.message;
    }
    if (parsed !== undefined) {
      const { spec, error } = checkSpec(parsed);
      if (spec) {
        if (physics) spec.physics = { ...spec.physics, mode: physics };
        return { spec, generator };
      }
      lastError = error;
    }
    // Вторая попытка: показываем модели её ответ и что в нём не так.
    messages.push({ role: "assistant", content: text });
    messages.push({ role: "user", content: `${lastError}. Answer again with the corrected JSON only.` });
  }
  throw new Error(`Generation failed: ${lastError}`);
}
