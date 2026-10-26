// Инструменты MCP: что ИИ-агент может делать с миром.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { checkSpec, objectSpecSchema } from "./spec.js";
import { availableGenerator, generateSpec } from "./generate.js";
import { BUILDER_PROMPT, STYLE_GUIDE } from "./style.js";

const PLAYER_NAME = process.env.PLAYER_NAME || "";
// Как часто спрашивать игру о новых просьбах, пока агент ждёт.
const POLL_MS = Number(process.env.POLL_MS) || 1000;

const requestArgs = {
  request_id: z.string().optional().describe("The request from wait_for_player_request this object answers."),
};

const text = (value) => ({
  content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
});
const failure = (message) => ({ ...text(message), isError: true });

export function createServer(world) {
  const mcp = new McpServer(
    { name: "ai-sandbox-world", version: "0.1.0" },
    {
      instructions:
        `${BUILDER_PROMPT}\n\nWith this server you may also call generate_object with the request text and request_id ` +
        "instead of designing the spec yourself; if it says no generator is available, design it yourself and call create_object.",
    },
  );

  const author = () => {
    const client = mcp.server.getClientVersion()?.name || "agent";
    return PLAYER_NAME ? `${PLAYER_NAME} (${client})` : client;
  };

  // Созданный объект попадает в инвентарь игрока, ставит его в мир сам игрок.
  const create = (spec, prompt, args) => world.request("create", { spec, prompt, author: author(), ...args });

  mcp.registerResource(
    "style-guide",
    "style://guide",
    {
      title: "World style guide and object spec format",
      description: "The base style prompt every object follows, and the JSON spec accepted by create_object.",
      mimeType: "text/markdown",
    },
    async (uri) => ({
      contents: [{ uri: uri.href, mimeType: "text/markdown", text: `${STYLE_GUIDE}` }],
    }),
  );

  mcp.registerPrompt(
    "builder",
    {
      title: "Game builder",
      description: "Work as the game's builder: wait for player requests typed in the game and build them.",
    },
    () => ({ messages: [{ role: "user", content: { type: "text", text: BUILDER_PROMPT } }] }),
  );

  mcp.registerTool(
    "get_style_guide",
    {
      title: "Get style guide",
      description: "The world's style rules and the JSON object spec accepted by create_object. Read it before designing objects.",
      inputSchema: {},
    },
    async () => text(STYLE_GUIDE),
  );

  mcp.registerTool(
    "wait_for_player_request",
    {
      title: "Wait for a player request",
      description:
        "Wait until a player types a request in the game's input field, then return it with its request_id. " +
        "Returns 'no new requests' after timeout_seconds; then call it again. Build the request with create_object " +
        "or generate_object (pass request_id), or answer with reply_to_player.",
      inputSchema: {
        timeout_seconds: z.number().min(1).max(300).optional().describe("How long to wait (default 50)."),
      },
    },
    async ({ timeout_seconds = 50 }, extra) => {
      const deadline = Date.now() + timeout_seconds * 1000;
      try {
        while (Date.now() < deadline && !extra?.signal?.aborted) {
          const request = await world.request("next_request");
          if (request) return text(request);
          await new Promise((resolve) => setTimeout(resolve, POLL_MS));
        }
        return text("No new requests yet. Call wait_for_player_request again right away.");
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "reply_to_player",
    {
      title: "Reply to the player",
      description: "Show a short message to the player in the game, e.g. when a request is unclear or cannot be built. Write in the player's language.",
      inputSchema: {
        text: z.string().min(1).max(500),
        request_id: z.string().optional().describe("The request you are answering."),
        done: z.boolean().optional().describe("false if you are still working on the request (default true)."),
      },
    },
    async (args) => {
      try {
        return text(await world.request("reply", args));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "get_world_info",
    {
      title: "Get world info",
      description:
        "World size, player position and facing, village center, palette, object count. " +
        "Pass sample_points to get terrain heights at [x, z] points.",
      inputSchema: {
        sample_points: z.array(z.tuple([z.number(), z.number()])).max(64).optional(),
      },
    },
    async ({ sample_points }) => {
      try {
        const info = await world.request("world_info", sample_points ? { points: sample_points } : {});
        return text({ ...info, generator: availableGenerator(mcp) || "none (design specs yourself)" });
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "generate_object",
    {
      title: "Generate object from a prompt",
      description:
        "Create a new object from a plain-language prompt, e.g. 'a crooked wooden windmill' or 'a pile of barrels', " +
        "and put it into the player's inventory. The server adds the world's hidden style prompt and generates the geometry. " +
        "If no generator is configured, the result explains how to design it yourself with create_object.",
      inputSchema: {
        prompt: z.string().min(1).max(2000).describe("What to build, in any language."),
        physics: z
          .enum(["static", "rigid", "none"])
          .optional()
          .describe("static: buildings/scenery; rigid: movable props that fall; none: decoration."),
        ...requestArgs,
      },
    },
    async ({ prompt, physics, ...args }) => {
      if (!availableGenerator(mcp)) {
        return failure(
          "No built-in generator is configured on this server (no ANTHROPIC_API_KEY and your client does not support MCP sampling). " +
            "Design the object yourself: write a spec that follows the guide below, then call create_object with it and the same prompt.\n\n" +
            `${STYLE_GUIDE}`,
        );
      }
      try {
        const { spec, generator } = await generateSpec(mcp, prompt, { physics });
        const created = await create(spec, prompt, args);
        return text({ created, generator, spec });
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "create_object",
    {
      title: "Create an object from a spec",
      description:
        "Create an object you designed yourself and put it into the player's inventory; the player places it in the world. " +
        "Pass request_id when building a player request. Read get_style_guide first: " +
        "parts are boxes, prisms, spheres, cylinders, cones, capsules, tori, lathes and extrusions in meters, " +
        "y = 0 is the ground, colors are palette names. The game renders everything with the world's shader and palette.",
      inputSchema: {
        spec: objectSpecSchema,
        prompt: z.string().max(2000).optional().describe("The original request, stored with the object."),
        ...requestArgs,
      },
    },
    async ({ spec, prompt, ...args }) => {
      const checked = checkSpec(spec);
      if (checked.error) return failure(checked.error);
      try {
        return text({ created: await create(checked.spec, prompt || "", args) });
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "list_objects",
    {
      title: "List agent-made objects",
      description: "Objects the players have placed in the world: id, name, author, prompt, position.",
      inputSchema: {},
    },
    async () => {
      try {
        return text(await world.request("list"));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "move_object",
    {
      title: "Move an object",
      description: "Move or rotate an object placed in the world.",
      inputSchema: {
        id: z.string(),
        x: z.number().optional(),
        z: z.number().optional(),
        rotation_y: z.number().optional(),
        y_offset: z.number().min(-20).max(60).optional(),
      },
    },
    async (args) => {
      try {
        return text(await world.request("move", args));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "remove_object",
    {
      title: "Remove an object",
      description: "Delete an object placed in the world.",
      inputSchema: { id: z.string() },
      annotations: { destructiveHint: true },
    },
    async ({ id }) => {
      try {
        return text(await world.request("remove", { id }));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  return mcp;
}
