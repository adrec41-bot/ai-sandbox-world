// Схема описания объекта. Та же проверка повторяется в игре
// (scripts/object_builder.gd), здесь она нужна, чтобы агент сразу получил
// понятную ошибку, а не отказ от игры.
import { z } from "zod";

const MAX = 40;
const num = (min, max) => z.number().min(min).max(max);
const vec3 = z.tuple([num(-MAX, MAX), num(-MAX, MAX), num(-MAX, MAX)]);
const size3 = z.tuple([num(0.01, MAX), num(0.01, MAX), num(0.01, MAX)]);
const point2 = z.tuple([num(-MAX, MAX), num(-MAX, MAX)]);

export const SHAPES = ["box", "prism", "sphere", "cylinder", "cone", "capsule", "torus", "lathe", "extrude"];

export const partSchema = z
  .object({
    shape: z.enum(SHAPES),
    id: z.string().max(32).optional().describe("Name for animating this part with mechanics.animations"),
    position: vec3.optional(),
    rotation: z.tuple([z.number(), z.number(), z.number()]).optional(),
    scale: size3.optional(),
    color: z.string().max(32).optional(),
    material: z.enum(["toon", "glow"]).optional(),
    sway: num(0, 0.3).optional(),
    collide: z.boolean().optional(),
    size: size3.optional(),
    radius: num(0.01, MAX).optional(),
    top_radius: num(0, MAX).optional(),
    height: num(0.01, MAX).optional(),
    inner_radius: num(0.01, MAX).optional(),
    profile: z.array(z.tuple([num(0, MAX), num(-MAX, MAX)])).min(2).max(64).optional(),
    segments: z.number().int().min(3).max(48).optional(),
    outline: z.array(point2).min(3).max(64).optional(),
  })
  .superRefine((p, ctx) => {
    if (p.shape === "lathe" && !p.profile) ctx.addIssue({ code: "custom", message: "lathe needs profile" });
    if (p.shape === "extrude" && !p.outline) ctx.addIssue({ code: "custom", message: "extrude needs outline" });
  });

// Кирпичи Lego на сетке шипов: x и z в шипах, y в пластинах. Та же проверка
// и разворачивание команд (box, wall, roof, tower) есть в игре, scripts/bricks.gd.
export const BRICK_TYPES = ["brick", "plate", "tile", "slope", "round", "cone"];
export const BRICK_COMMANDS = ["box", "wall", "roof", "tower"];
const int = (min, max) => z.number().int().min(min).max(max);
const cell3 = z.tuple([int(-512, 512), int(-60, 600), int(-512, 512)]);
const cell2 = z.tuple([int(-512, 512), int(-512, 512)]);

export const brickSchema = z
  .object({
    type: z.enum([...BRICK_TYPES, ...BRICK_COMMANDS]).optional(),
    color: z.string().max(32).optional(),
    id: z.string().max(32).optional().describe("Bricks with the same id move together (mechanics.animations)"),
    studs: z.boolean().optional(),
    // кирпич
    at: cell3.optional(),
    size: z.tuple([int(1, 64), int(1, 64)]).optional(),
    h: int(1, 60).optional(),
    dir: z.enum(["+x", "-x", "+z", "-z"]).optional(),
    // команды
    from: z.union([cell3, cell2]).optional(),
    to: z.union([cell3, cell2]).optional(),
    hollow: z.boolean().optional(),
    y: int(-60, 600).optional(),
    height: int(1, 120).optional(),
    thickness: int(1, 4).optional(),
    openings: z
      .array(
        z.object({
          at: int(0, 512),
          width: int(1, 64).optional(),
          y: int(0, 120).optional(),
          height: int(1, 120).optional(),
          fill: z.string().max(32).optional(),
        }),
      )
      .max(32)
      .optional(),
    ridge: z.enum(["x", "z"]).optional(),
    flat: z.boolean().optional(),
    center: cell2.optional(),
    radius: int(1, 32).optional(),
  })
  .superRefine((b, ctx) => {
    const type = b.type ?? "brick";
    const need = (cond, message) => cond || ctx.addIssue({ code: "custom", message });
    if (BRICK_TYPES.includes(type)) need(b.at, `${type} needs at: [x, y, z]`);
    if (type === "box") need(b.from?.length === 3 && b.to?.length === 3, "box needs from and to as [x, y, z]");
    if (type === "wall" || type === "roof") need(b.from?.length === 2 && b.to?.length === 2, `${type} needs from and to as [x, z]`);
    if (type === "wall" && b.from && b.to) {
      need(b.from[0] === b.to[0] || b.from[1] === b.to[1], "wall must run along x or along z");
    }
    if (type === "tower") need(b.center, "tower needs center: [x, z]");
  });

// Механики: транспорт, снаряжение, интерактивные предметы. Пределы те же,
// что в scripts/mechanics/mechanics.gd, игра проверяет их ещё раз.
const animationSchema = z.object({
  part: z.string().min(1).max(32),
  motion: z.enum(["spin", "swing", "bob", "angle"]).optional(),
  axis: z.enum(["x", "y", "z"]).optional(),
  amount: num(-3600, 3600).optional(),
  rate: num(0, 20).optional(),
  by: z.enum(["always", "speed", "throttle", "steer", "climb", "active"]).optional(),
  pivot: vec3.optional(),
});

export const mechanicsSchema = z.object({
  type: z.enum(["vehicle", "equipment", "prop"]),
  // vehicle
  movement: z.enum(["ground", "air", "hover"]).optional(),
  seat: vec3.optional(),
  max_speed: num(0.5, 120).optional(),
  acceleration: num(0.5, 80).optional(),
  brake: num(0.5, 120).optional(),
  turn_speed: num(5, 360).optional(),
  reverse_speed: num(0, 60).optional(),
  lean: num(0, 60).optional(),
  tilt: num(0, 45).optional(),
  jump: num(0, 30).optional(),
  gravity_scale: num(0, 5).optional(),
  takeoff_speed: num(1, 100).optional(),
  pitch_speed: num(5, 180).optional(),
  climb_speed: num(0, 60).optional(),
  // equipment
  attach: z.enum(["back", "head", "hand", "feet", "body"]).optional(),
  offset: z.tuple([num(-3, 3), num(-3, 3), num(-3, 3)]).optional(),
  abilities: z
    .object({
      speed: num(0.2, 5).optional(),
      jump: num(0.2, 5).optional(),
      extra_jumps: z.number().int().min(0).max(5).optional(),
      glide: num(0, 10).optional(),
      fly: num(0, 40).optional(),
      gravity: num(0, 3).optional(),
    })
    .optional(),
  // prop
  on_touch: z
    .object({
      bounce: num(0, 60).optional(),
      push: z.tuple([num(-60, 60), num(-60, 60), num(-60, 60)]).optional(),
    })
    .optional(),
  interact: z.enum(["none", "toggle"]).optional(),
  controls_hint: z.string().max(200).optional(),
  animations: z.array(animationSchema).max(24).optional(),
});

export const CATEGORIES = ["buildings", "vehicles", "gear", "mechanisms", "nature", "decor"];

export const objectSpecSchema = z.object({
  name: z.string().min(1).max(64),
  category: z.enum(CATEGORIES).optional(),
  physics: z
    .object({
      mode: z.enum(["static", "rigid", "none"]),
      mass: num(0.1, 5000).optional(),
    })
    .optional(),
  bricks: z.array(brickSchema).max(6000).optional(),
  parts: z.array(partSchema).max(256).optional(),
  effects: z
    .array(
      z.object({
        type: z.enum(["smoke", "light"]),
        position: vec3.optional(),
        size: num(0.1, 2).optional(),
        energy: num(0.1, 4).optional(),
        range: num(1, 20).optional(),
      }),
    )
    .max(16)
    .optional(),
  mechanics: mechanicsSchema.optional(),
}).superRefine((spec, ctx) => {
  if (!spec.bricks?.length && !spec.parts?.length) {
    ctx.addIssue({ code: "custom", path: ["bricks"], message: "spec needs bricks (or parts for shapes that bricks cannot make)" });
  }
  // Анимация, которая ссылается на несуществующую деталь, ничего не сделает: лучше сказать агенту сразу.
  const ids = new Set([...(spec.parts ?? []), ...(spec.bricks ?? [])].map((p) => p.id).filter(Boolean));
  for (const [i, a] of (spec.mechanics?.animations ?? []).entries()) {
    if (!ids.has(a.part)) {
      ctx.addIssue({ code: "custom", path: ["mechanics", "animations", i, "part"], message: `no part has id "${a.part}"` });
    }
  }
});

/** Проверяет описание. Возвращает { spec } или { error } с текстом для агента. */
export function checkSpec(value) {
  const res = objectSpecSchema.safeParse(value);
  if (res.success) return { spec: res.data };
  const issues = res.error.issues
    .slice(0, 8)
    .map((i) => `${i.path.join(".") || "spec"}: ${i.message}`)
    .join("; ");
  return { error: `Invalid object spec: ${issues}` };
}

/** Достаёт JSON из ответа модели, даже если он обёрнут в ```json. */
export function extractJson(text) {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const body = fenced ? fenced[1] : text;
  const start = body.indexOf("{");
  const end = body.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no JSON object in the model answer");
  return JSON.parse(body.slice(start, end + 1));
}
