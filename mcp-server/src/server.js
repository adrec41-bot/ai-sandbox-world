// Инструменты MCP: что ИИ-агент может делать с миром.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { checkSpec, objectSpecSchema } from "./spec.js";
import { availableGenerator, generateSpec } from "./generate.js";
import { STYLE_GUIDE } from "./style.js";

const PLAYER_NAME = process.env.PLAYER_NAME || "";

const placement = {
  x: z.number().optional().describe("World X in meters. Omit x and z to place in front of the player."),
  z: z.number().optional().describe("World Z in meters."),
  distance: z.number().min(2).max(60).optional().describe("Distance in front of the player when x/z are omitted (default 8)."),
  rotation_y: z.number().optional().describe("Yaw in degrees."),
  y_offset: z.number().min(-20).max(60).optional().describe("Lift above the ground in meters (default 0, the object stands on the terrain)."),
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
        "Build in a shared hand-drawn sepia fairy-tale world. Call get_world_info first to see where the player is. " +
        "Use generate_object with a short prompt; if it says no generator is available, design the spec yourself " +
        "following the style guide resource (style://guide) and call place_object.",
    },
  );

  const author = () => {
    const client = mcp.server.getClientVersion()?.name || "agent";
    return PLAYER_NAME ? `${PLAYER_NAME} (${client})` : client;
  };

  const spawn = async (spec, prompt, args) => {
    const placed = await world.request("spawn", { spec, prompt, author: author(), ...args });
    return placed;
  };

  mcp.registerResource(
    "style-guide",
    "style://guide",
    {
      title: "World style guide and object spec format",
      description: "The base style prompt every object follows, and the JSON spec accepted by place_object.",
      mimeType: "text/markdown",
    },
    async (uri) => ({
      contents: [{ uri: uri.href, mimeType: "text/markdown", text: `${STYLE_GUIDE}` }],
    }),
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
        "Create a new object in the world from a plain-language prompt, e.g. 'a crooked wooden windmill' or " +
        "'a pile of barrels'. The server adds the world's hidden style prompt, generates the geometry and places it. " +
        "If no generator is configured, the result explains how to design it yourself with place_object.",
      inputSchema: {
        prompt: z.string().min(1).max(2000).describe("What to build, in any language."),
        physics: z
          .enum(["static", "rigid", "none"])
          .optional()
          .describe("static: buildings/scenery; rigid: movable props that fall; none: decoration."),
        ...placement,
      },
    },
    async ({ prompt, physics, ...args }) => {
      if (!availableGenerator(mcp)) {
        return failure(
          "No built-in generator is configured on this server (no ANTHROPIC_API_KEY and your client does not support MCP sampling). " +
            "Design the object yourself: write a spec that follows the guide below, then call place_object with it and the same prompt.\n\n" +
            `${STYLE_GUIDE}`,
        );
      }
      try {
        const { spec, generator } = await generateSpec(mcp, prompt, { physics });
        const placed = await spawn(spec, prompt, args);
        return text({ placed, generator, spec });
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "place_object",
    {
      title: "Place an object from a spec",
      description:
        "Place an object you designed yourself. Read style://guide first (or the text returned by generate_object): " +
        "parts are boxes, prisms, spheres, cylinders, cones, capsules, tori, lathes and extrusions in meters, " +
        "y = 0 is the ground, colors are palette names. The game renders everything with the world's shader and palette.",
      inputSchema: {
        spec: objectSpecSchema,
        prompt: z.string().max(2000).optional().describe("The original request, stored with the object."),
        ...placement,
      },
    },
    async ({ spec, prompt, ...args }) => {
      const checked = checkSpec(spec);
      if (checked.error) return failure(checked.error);
      try {
        return text({ placed: await spawn(checked.spec, prompt || "", args) });
      } catch (err) {
        return failure(err.message);
      }
    },
  );

  mcp.registerTool(
    "list_objects",
    {
      title: "List agent-made objects",
      description: "All objects created by agents: id, name, author, prompt, position.",
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
      description: "Move or rotate an object created by an agent.",
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
      description: "Delete an object created by an agent.",
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
