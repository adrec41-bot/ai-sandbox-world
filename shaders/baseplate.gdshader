// Базовая пластина мира: шипы нарисованы прямо в шейдере, поэтому даже
// огромная пластина стоит почти ничего. Рядом с игроком поверх лежат
// настоящие объёмные шипы (world.gd), а здесь они видны издалека.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.14, 0.47, 0.25, 1.0);
uniform float stud = 0.4;
// Пластина собрана из плит 32 на 32 шипа, стыки видны тонкими линиями.
uniform float tile_studs = 32.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo.rgb;
	vec2 cell = world_pos.xz / stud;
	vec2 f = fract(cell) - 0.5;
	float d = length(f);
	// Чем мельче шипы на экране, тем слабее рисунок: так нет ряби вдали.
	float px = length(fwidth(cell));
	float fade = clamp(1.6 - px * 3.0, 0.0, 1.0);
	float aa = max(px, 0.02);
	float top = 1.0 - smoothstep(0.3 - aa, 0.3 + aa, d);
	// Мягкая тень сбоку от шипа и чуть светлее его верх.
	float ring = smoothstep(0.26, 0.31, d) * (1.0 - smoothstep(0.31, 0.38, d));
	c *= 1.0 + (top * 0.05 - ring * 0.1) * fade;
	// Стыки плит.
	vec2 t = abs(fract(cell / tile_studs + 0.5) - 0.5) * tile_studs;
	float seam = 1.0 - smoothstep(0.0, max(px, 0.02), min(t.x, t.y));
	c *= 1.0 - seam * 0.18;
	ALBEDO = c;
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
}
