// Проверка MCP-сервера без игры: вместо Godot поднимается поддельный мир,
// который говорит по тому же протоколу, а генерация идёт через MCP sampling
// подставного клиента.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { WebSocketServer } from "ws";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { CreateMessageRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { createServer } from "../src/server.js";
import { WorldClient } from "../src/world.js";
import { extractJson } from "../src/spec.js";

process.env.GENERATOR = "sampling";
process.env.POLL_MS = "20";

const HUT = {
  name: "Хижина",
  physics: { mode: "static" },
  parts: [
    { shape: "box", size: [3, 2.4, 3], position: [0, 1.1, 0], color: "wall" },
    { shape: "prism", size: [3.4, 1.4, 3.4], position: [0, 3, 0], color: "roof" },
    { shape: "lathe", profile: [[0.4, 0], [0.5, 0.5], [0.3, 1], [0, 1.1]], position: [1, 0, 2], color: "wood" },
    { shape: "box", size: [0.6, 0.6, 0.05], position: [0, 1.4, 1.52], color: "window", material: "glow" },
  ],
  effects: [{ type: "smoke", position: [1, 4, 0] }],
};

let wss;
let world;
const objects = [];
const requests = [];
const replies = [];
const samplingRequests = [];

function fakeWorld(port) {
  wss = new WebSocketServer({ port, host: "127.0.0.1" });
  wss.on("connection", (ws) => {
    ws.on("message", (data) => {
      const { id, cmd, args } = JSON.parse(data.toString());
      const reply = (result) => ws.send(JSON.stringify({ id, ok: true, result }));
      if (cmd === "world_info") return reply({ world_size: 240, player: { position: [26, 6, 10] } });
      if (cmd === "create") {
        const obj = { id: `obj_${objects.length + 1}`, name: args.spec.name, author: args.author, prompt: args.prompt };
        objects.push(obj);
        return reply(obj);
      }
      if (cmd === "list") return reply(objects);
      if (cmd === "next_request") return reply(requests.shift() ?? null);
      if (cmd === "reply") {
        replies.push(args);
        return reply({ shown_to_player: args.text });
      }
      ws.send(JSON.stringify({ id, ok: false, error: `unknown command: ${cmd}` }));
    });
  });
}

async function connect({ sampling }) {
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-agent", version: "1.0.0" }, { capabilities: sampling ? { sampling: {} } : {} });
  if (sampling) {
    let calls = 0;
    client.setRequestHandler(CreateMessageRequestSchema, async (req) => {
      samplingRequests.push(req.params);
      calls++;
      // Первый ответ сломан, чтобы проверить повторную попытку.
      const answer = calls === 1 ? '{"name": "x", "parts": []}' : "```json\n" + JSON.stringify(HUT) + "\n```";
      return { role: "assistant", model: "fake", content: { type: "text", text: answer } };
    });
  }
  await createServer(world).connect(serverSide);
  await client.connect(clientSide);
  return client;
}

before(() => {
  fakeWorld(17777);
  world = new WorldClient("ws://127.0.0.1:17777");
});

after(() => {
  world.close();
  wss.close();
});

test("lists tools and the style guide", async () => {
  const client = await connect({ sampling: false });
  const { tools } = await client.listTools();
  assert.deepEqual(tools.map((t) => t.name).sort(), [
    "create_object",
    "generate_object",
    "get_style_guide",
    "get_world_info",
    "list_objects",
    "move_object",
    "remove_object",
    "reply_to_player",
    "wait_for_player_request",
  ]);
  const { prompts } = await client.listPrompts();
  assert.equal(prompts[0].name, "builder");
  const place = tools.find((t) => t.name === "create_object");
  assert.ok(place.inputSchema.properties.spec.properties.parts, "spec schema is exposed to agents");
  const guide = await client.readResource({ uri: "style://guide" });
  assert.match(guide.contents[0].text, /Disney/);
});

test("create_object validates and adds to the inventory", async () => {
  const client = await connect({ sampling: false });
  const bad = await client.callTool({ name: "create_object", arguments: { spec: { name: "x", parts: [{ shape: "lathe" }] } } });
  assert.equal(bad.isError, true);
  const ok = await client.callTool({ name: "create_object", arguments: { spec: HUT, prompt: "хижина", request_id: "req_9" } });
  assert.ok(!ok.isError, ok.content[0].text);
  assert.equal(JSON.parse(ok.content[0].text).created.author, "test-agent");
});

test("generate_object without a generator explains the fallback", async () => {
  const client = await connect({ sampling: false });
  const res = await client.callTool({ name: "generate_object", arguments: { prompt: "мельница" } });
  assert.equal(res.isError, true);
  assert.match(res.content[0].text, /create_object/);
});

test("generate_object uses sampling with the hidden style prompt and retries", async () => {
  const client = await connect({ sampling: true });
  const res = await client.callTool({ name: "generate_object", arguments: { prompt: "хижина лесника", physics: "static" } });
  assert.ok(!res.isError, res.content[0].text);
  const body = JSON.parse(res.content[0].text);
  assert.equal(body.generator, "sampling");
  assert.equal(body.created.prompt, "хижина лесника");
  assert.equal(samplingRequests.length, 2);
  assert.match(samplingRequests[0].systemPrompt, /hand-painted 1930s Disney/);
  const list = await client.callTool({ name: "list_objects", arguments: {} });
  assert.equal(JSON.parse(list.content[0].text).length, 2);
});

test("reports when the game is not running", async () => {
  const offline = new WorldClient("ws://127.0.0.1:17778");
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "t", version: "1" });
  await createServer(offline).connect(serverSide);
  await client.connect(clientSide);
  const res = await client.callTool({ name: "get_world_info", arguments: {} });
  assert.equal(res.isError, true);
  assert.match(res.content[0].text, /Start the game/);
});

test("extractJson handles fences and prose", () => {
  assert.deepEqual(extractJson('Here:\n```json\n{"a": 1}\n```'), { a: 1 });
  assert.deepEqual(extractJson('{"a": {"b": 2}}'), { a: { b: 2 } });
});

test("wait_for_player_request returns a request typed in the game", async () => {
  const client = await connect({ sampling: false });
  const empty = await client.callTool({ name: "wait_for_player_request", arguments: { timeout_seconds: 1 } });
  assert.match(empty.content[0].text, /No new requests/);
  setTimeout(() => requests.push({ request_id: "req_1", text: "мельница" }), 100);
  const got = await client.callTool({ name: "wait_for_player_request", arguments: { timeout_seconds: 5 } });
  assert.equal(JSON.parse(got.content[0].text).request_id, "req_1");
  const res = await client.callTool({ name: "reply_to_player", arguments: { text: "Не понял", request_id: "req_1" } });
  assert.ok(!res.isError);
  assert.equal(replies[0].text, "Не понял");
});
