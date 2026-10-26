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
const samplingRequests = [];

function fakeWorld(port) {
  wss = new WebSocketServer({ port, host: "127.0.0.1" });
  wss.on("connection", (ws) => {
    ws.on("message", (data) => {
      const { id, cmd, args } = JSON.parse(data.toString());
      const reply = (result) => ws.send(JSON.stringify({ id, ok: true, result }));
      if (cmd === "world_info") return reply({ world_size: 240, player: { position: [26, 6, 10] } });
      if (cmd === "spawn") {
        const obj = { id: `obj_${objects.length + 1}`, name: args.spec.name, author: args.author, prompt: args.prompt };
        objects.push(obj);
        return reply(obj);
      }
      if (cmd === "list") return reply(objects);
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
    "generate_object",
    "get_world_info",
    "list_objects",
    "move_object",
    "place_object",
    "remove_object",
  ]);
  const place = tools.find((t) => t.name === "place_object");
  assert.ok(place.inputSchema.properties.spec.properties.parts, "spec schema is exposed to agents");
  const guide = await client.readResource({ uri: "style://guide" });
  assert.match(guide.contents[0].text, /Disney/);
});

test("place_object validates and spawns", async () => {
  const client = await connect({ sampling: false });
  const bad = await client.callTool({ name: "place_object", arguments: { spec: { name: "x", parts: [{ shape: "lathe" }] } } });
  assert.equal(bad.isError, true);
  const ok = await client.callTool({ name: "place_object", arguments: { spec: HUT, prompt: "хижина", x: 10, z: 5 } });
  assert.ok(!ok.isError, ok.content[0].text);
  assert.equal(JSON.parse(ok.content[0].text).placed.author, "test-agent");
});

test("generate_object without a generator explains the fallback", async () => {
  const client = await connect({ sampling: false });
  const res = await client.callTool({ name: "generate_object", arguments: { prompt: "мельница" } });
  assert.equal(res.isError, true);
  assert.match(res.content[0].text, /place_object/);
});

test("generate_object uses sampling with the hidden style prompt and retries", async () => {
  const client = await connect({ sampling: true });
  const res = await client.callTool({ name: "generate_object", arguments: { prompt: "хижина лесника", physics: "static" } });
  assert.ok(!res.isError, res.content[0].text);
  const body = JSON.parse(res.content[0].text);
  assert.equal(body.generator, "sampling");
  assert.equal(body.placed.prompt, "хижина лесника");
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
