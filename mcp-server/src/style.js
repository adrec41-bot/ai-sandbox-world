// Скрытый базовый промт стиля. Он добавляется к каждому запросу на генерацию,
// поэтому объекты от разных игроков и разных агентов выглядят одинаково
// уместно в мире. Игрок пишет только «мельница», остальное подставляет сервер.

// Имена цветов совпадают с PALETTE в scripts/style.gd. Произвольный цвет
// игра всё равно заменит ближайшим по яркости тоном этой палитры.
export const PALETTE = {
  grass: "mid grey-green, lawns and moss",
  bush: "dark-mid foliage",
  leaf: "tree crowns",
  leaf_light: "lighter crowns, highlights",
  pine: "dark conifer needles",
  bark: "very dark wood, trunks",
  wood: "planks, barrels, fences",
  beam: "darkest timber, half-timbering beams, frames",
  wall: "light plaster walls",
  stone: "light masonry, steps, wells",
  rock: "boulders",
  rock_dark: "shadowed rock",
  cliff: "rock faces",
  roof: "dark roof tiles and thatch",
  path: "packed earth, paving",
  sand: "sand, pale ground",
  cloth: "near white fabric, sails, awnings",
  flower: "bright white petals",
  mountain: "distant stone",
  window: "warm lit windows (use material glow)",
  fire: "flames (use material glow)",
};

export const BASE_STYLE_PROMPT = `You design 3D objects for "AI Sandbox World", a cosy open world drawn like a
hand-painted 1930s Disney animated film, rendered in warm sepia with ink outlines.
A shared screen filter adds outlines, hatching and paper texture, so you only
describe clean, readable shapes; never try to add texture detail with geometry.

Style rules:
- Storybook proportions: slightly chunky, a bit crooked and hand-made, friendly.
  Prefer soft silhouettes, leaning roofs, bulging barrels, round tops.
- Medieval village / fairy tale forest vocabulary: half-timbered houses, stone,
  wood, thatch, lanterns, wells, mills, bridges, carts, signs, trees, rocks.
- Readable from 20 meters: few large forms first, then a handful of details.
  Typical object: 6 to 60 parts. Never exceed 256 parts.
- Value contrast matters more than hue (the frame is sepia): dark beams on light
  walls, dark roofs, light stone. Use palette names for colors.
- Real-world scale in meters: a door is 2 m tall, a house 5-9 m, a tree 4-12 m.
- Origin is the center of the object's footprint at ground level (y = 0 is the
  ground). Build upward; sink foundations ~0.2 m below 0 so nothing floats on slopes.
- Lit windows and fire use "material": "glow". Chimneys and campfires may add a
  "smoke" effect; lamps may add a "light" effect.

Palette (color names):
${Object.entries(PALETTE)
  .map(([k, v]) => `- ${k}: ${v}`)
  .join("\n")}`;

export const SPEC_FORMAT = `Object spec (JSON):
{
  "name": "short name",
  "physics": { "mode": "static" | "rigid" | "none", "mass": kg (rigid only) },
  "parts": [ part, ... ],                       // 1..256
  "effects": [ { "type": "smoke" | "light", "position": [x, y, z] } ]   // optional
}
part:
{
  "shape": "box" | "prism" | "sphere" | "cylinder" | "cone" | "capsule" | "torus" | "lathe" | "extrude",
  "position": [x, y, z],          // meters from the object origin: center of the shape (lathe, extrude: their local origin)
  "rotation": [x, y, z],          // degrees, optional
  "scale": [x, y, z],             // optional, stretch any shape
  "color": "palette name",        // or "#rrggbb", snapped to the palette
  "material": "toon" | "glow",    // optional, glow for windows / fire
  "sway": 0..0.3,                 // optional wind sway for foliage, cloth
  "collide": true | false,        // optional, default true
  // shape parameters:
  "size": [x, y, z],              // box, prism (prism = gable roof: triangle in XY, apex up, ridge along Z)
  "radius": r,                    // sphere, cylinder (bottom), cone, capsule, torus (outer)
  "top_radius": r,                // cylinder, optional (tapered posts, barrels, towers)
  "height": h,                    // cylinder, cone, capsule, extrude
  "inner_radius": r,              // torus
  "profile": [[radius, y], ...],  // lathe: [radius, y] from bottom to top, revolved around Y (vases, domes, towers)
  "segments": n,                  // lathe, 3..48
  "outline": [[x, z], ...]        // extrude: polygon in XZ raised from y = 0 to height (bottom of the part is at position.y)
}
Physics: "static" for buildings and scenery (players collide with it), "rigid"
for small movable props that fall and can be pushed (crates, barrels, balls),
"none" for decoration without collision.`;

export const GENERATION_SYSTEM_PROMPT = `${BASE_STYLE_PROMPT}

${SPEC_FORMAT}

Answer with the JSON object only, no prose and no code fences.`;
