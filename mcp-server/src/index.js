#!/usr/bin/env node
// MCP-сервер AI Sandbox World. Любой ИИ-агент с поддержкой MCP (Claude Desktop,
// Claude Code, Cursor, VS Code и другие) подключается к нему и создаёт в мире
// объекты по текстовому описанию.
//
// Запуск:  node src/index.js              — stdio, для локальных агентов
//          node src/index.js --http 8787  — Streamable HTTP на /mcp
import http from "node:http";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { WorldClient } from "./world.js";
import { createServer } from "./server.js";

const WORLD_URL = process.env.WORLD_URL || "ws://127.0.0.1:7777";

async function main() {
  const world = new WorldClient(WORLD_URL);
  const httpFlag = process.argv.indexOf("--http");
  if (httpFlag < 0) {
    await createServer(world).connect(new StdioServerTransport());
    console.error(`ai-sandbox-world MCP: stdio, world ${WORLD_URL}`);
    return;
  }

  const port = Number(process.argv[httpFlag + 1]) || 8787;
  const host = process.env.HOST || "127.0.0.1";
  // Без сессий: на каждый запрос свой сервер, общий только клиент мира.
  const httpServer = http.createServer(async (req, res) => {
    if (!req.url?.startsWith("/mcp")) {
      res.writeHead(404).end();
      return;
    }
    const mcp = createServer(world);
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on("close", () => {
      transport.close();
      mcp.close();
    });
    try {
      await mcp.connect(transport);
      await transport.handleRequest(req, res);
    } catch (err) {
      console.error(err);
      if (!res.headersSent) res.writeHead(500).end();
    }
  });
  httpServer.listen(port, host, () => {
    console.error(`ai-sandbox-world MCP: http://${host}:${port}/mcp, world ${WORLD_URL}`);
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
