// Инструменты MCP: что ИИ-агент может делать с миром.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { CATEGORIES, checkSpec, objectSpecSchema } from "./spec.js";
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
        "Wait until the player types a request in the game, then return it with its request_id, kind, size, " +
        "marked area and edit_target or edit_item. Also returns the player's answers to ask_player (type 'answer'). " +
        "Returns 'no new requests' after timeout_seconds; then call it again. Build with create_object, update_object " +
        "or generate_object (pass request_id), ask with ask_player, or answer with reply_to_player.",
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
        "World size in studs and meters, player position and facing, the area the player marked, LEGO colors, " +
        "object count and physics. Pass sample_points to get ground heights at [x, z] points.",
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
        "Create an object you designed from LEGO bricks and put it into the player's inventory. " +
        "Pass request_id when building a player request. If the request has an area (a footprint the player marked), " +
        "the object is placed right there; pass place: true to place it in front of the player otherwise. " +
        "Read get_style_guide first: bricks (brick, plate, tile, slope, round, cone with at/size in studs and plates) " +
        "and the box, wall, roof and tower commands; parts only for shapes bricks cannot make. " +
        "Add spec.mechanics to make it rideable (vehicle), wearable (equipment) or interactive (prop), as described in the guide.",
      inputSchema: {
        spec: objectSpecSchema,
        prompt: z.string().max(2000).optional().describe("The original request, stored with the object."),
        category: z.enum(CATEGORIES).optional().describe("Inventory category."),
        place: z.boolean().optional().describe("Also place it in the world (on the marked area, or in front of the player)."),
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
    "update_object",
    {
      title: "Change an object",
      description:
        "Change an existing object: a placed object (object_id, from edit_target or list_objects) or an inventory item " +
        "(item_id, from edit_item). Read it first with get_object_spec, then send the whole changed spec. " +
        "The player can undo the change with Ctrl+Z.",
      inputSchema: {
        spec: objectSpecSchema,
        object_id: z.string().optional(),
        item_id: z.string().optional(),
        ...requestArgs,
      },
    },
    async ({ spec, ...args }) => {
      const checked = checkSpec(spec);
      if (checked.error) return failure(checked.error);
      if (!args.object_id && !args.item_id) return failure("Pass object_id or item_id.");
      try {
        return text(await world.request("update", { spec: checked.spec, ...args }));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "get_object_spec",
    {
      title: "Get an object's spec",
      description: "The full spec of a placed object (object_id) or an inventory item (item_id), to change it with update_object.",
      inputSchema: { object_id: z.string().optional(), item_id: z.string().optional() },
    },
    async (args) => {
      try {
        return text(await world.request("get_spec", args));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "ask_player",
    {
      title: "Ask the player",
      description:
        "Ask the player a short question about a request when it is really unclear (style, size, which variant). " +
        "Give 2-4 options as buttons; the player can also type an answer. The answer comes from wait_for_player_request " +
        "as type 'answer' with the same request_id. Write in the player's language.",
      inputSchema: {
        request_id: z.string(),
        question: z.string().min(1).max(300),
        options: z.array(z.string().max(60)).max(4).optional(),
      },
    },
    async (args) => {
      try {
        return text(await world.request("ask", args));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "report_progress",
    {
      title: "Report progress",
      description:
        "Show what you are doing on the request card in the game, e.g. 'Building the walls'. " +
        "Use it for big builds that take a while. Write in the player's language.",
      inputSchema: { request_id: z.string(), text: z.string().min(1).max(120) },
    },
    async (args) => {
      try {
        return text(await world.request("progress", args));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "get_area",
    {
      title: "What stands on an area",
      description:
        "Objects standing on a rectangle, with their top heights, so you do not build on top of them. " +
        "Without arguments it checks the area the player marked; or pass from and to as [x, z] in meters.",
      inputSchema: {
        from: z.tuple([z.number(), z.number()]).optional(),
        to: z.tuple([z.number(), z.number()]).optional(),
      },
    },
    async (args) => {
      try {
        return text(await world.request("area", args));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "set_world_physics",
    {
      title: "Set world physics",
      description:
        "Change the physics of the player's world: gravity (1 normal, 0.16 moon, 0 weightless), " +
        "player speed, jump height and time scale (below 1 is slow motion). Omitted values stay as they are; " +
        "reset: true restores the defaults. Returns the current values.",
      inputSchema: {
        gravity: z.number().min(0).max(5).optional().describe("Gravity multiplier, 1 is normal."),
        player_speed: z.number().min(0.2).max(5).optional().describe("Walking and running speed multiplier."),
        jump: z.number().min(0.2).max(5).optional().describe("Jump height multiplier."),
        time_scale: z.number().min(0.1).max(3).optional().describe("Game speed, 1 is normal."),
        reset: z.boolean().optional().describe("Restore all defaults first."),
      },
    },
    async (args) => {
      try {
        return text(await world.request("set_physics", { ...args, author: author() }));
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "list_objects",
    {
      title: "List agent-made objects",
      description: "Objects placed in the world: id, name, author, prompt, position, brick count.",
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
