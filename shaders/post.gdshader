// Финальный «рисованный» фильтр кадра в духе старой диснеевской анимации:
// чернильные контуры по глубине, штриховка в тенях, дымка вдали, сепия,
// фактура бумаги и виньетка. Он действует на всё, что видно, поэтому любой
// объект мира, в том числе сгенерированный ИИ, получает тот же стиль.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 ink : source_color = vec3(0.09, 0.075, 0.06);
uniform vec3 mid : source_color = vec3(0.47, 0.42, 0.35);
uniform vec3 paper : source_color = vec3(0.95, 0.91, 0.83);
uniform float haze_density = 0.005;
uniform float haze_max = 0.82;
uniform float line_strength = 0.85;
uniform float hatch_spacing = 5.0;
uniform float vignette = 0.5;
uniform bool gl_depth = true;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Сырое значение глубины читается в fragment(): в OpenGL-рендерере Godot 4.3
// текстура глубины доступна только там, а не во вспомогательных функциях.
float lin_depth(vec2 uv, float d, mat4 inv_proj) {
	// В OpenGL (Compatibility) глубина хранится в 0..1, в Vulkan уже в NDC.
	vec3 ndc = gl_depth ? vec3(uv, d) * 2.0 - 1.0 : vec3(uv * 2.0 - 1.0, d);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 fc = FRAGCOORD.xy;

	// Лёгкое «дрожание» линий, как у рисунка от руки.
	vec2 wob = (vec2(vnoise(fc * 0.05), vnoise(fc * 0.05 + 17.0)) - 0.5) * 1.6;
	float w = 1.0 + vnoise(fc * 0.02 + 3.0) * 0.8;
	vec2 ul = uv + (vec2(-w, 0.0) + wob) * px;
	vec2 ur = uv + (vec2(w, 0.0) + wob) * px;
	vec2 uu = uv + (vec2(0.0, -w) + wob) * px;
	vec2 ud = uv + (vec2(0.0, w) + wob) * px;
	float d = lin_depth(uv, texture(depth_tex, uv).r, INV_PROJECTION_MATRIX);
	float dl = lin_depth(ul, texture(depth_tex, ul).r, INV_PROJECTION_MATRIX);
	float dr = lin_depth(ur, texture(depth_tex, ur).r, INV_PROJECTION_MATRIX);
	float du = lin_depth(uu, texture(depth_tex, uu).r, INV_PROJECTION_MATRIX);
	float dd = lin_depth(ud, texture(depth_tex, ud).r, INV_PROJECTION_MATRIX);

	float jump = max(max(abs(dl - d), abs(dr - d)), max(abs(du - d), abs(dd - d))) / d;
	float crease = (abs(dl + dr - 2.0 * d) + abs(du + dd - 2.0 * d)) / d;
	float edge = max(smoothstep(0.035, 0.09, jump), smoothstep(0.012, 0.04, crease) * 0.55);

	// Экранная текстура приходит в линейном цвете, переводим в sRGB.
	vec3 col = pow(max(texture(screen_tex, uv).rgb, vec3(0.0)), vec3(1.0 / 2.2));
	float l = luma(col);
	bool sky = d > 900.0;

	// Мягкое свечение ярких мест: окна, фонари, солнце.
	float bloom = 0.0;
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472;
		bloom += luma(pow(max(textureLod(screen_tex, uv + vec2(cos(a), sin(a)) * px * 14.0, 2.0).rgb, vec3(0.0)), vec3(1.0 / 2.2)));
	}
	bloom = max(bloom / 6.0 - 0.72, 0.0) * 1.6;

	// Тональная кривая и дымка по глубине.
	l = smoothstep(0.06, 0.95, l);
	l = pow(l, 1.25);
	float haze = sky ? 0.55 : min(1.0 - exp(-pow(d * haze_density, 1.25)), haze_max);
	l = mix(l, 0.93, haze);

	// Штриховка в тенях: одна диагональ, в самых тёмных местах вторая.
	vec2 hc = fc + wob * 3.0;
	float dark = (1.0 - smoothstep(0.18, 0.5, l)) * (1.0 - haze);
	float h1 = abs(fract((hc.x + hc.y) / hatch_spacing) - 0.5) * 2.0;
	float h2 = abs(fract((hc.x - hc.y) / hatch_spacing) - 0.5) * 2.0;
	float hatch = (1.0 - smoothstep(0.0, 0.35, h1 - (1.0 - dark * 0.9))) * dark;
	hatch = max(hatch, (1.0 - smoothstep(0.0, 0.35, h2 - (1.0 - max(dark - 0.5, 0.0) * 1.6))) * dark);
	l *= 1.0 - hatch * 0.32;

	// Чернильные контуры, бледнеющие с расстоянием.
	if (!sky) {
		l *= 1.0 - edge * line_strength * (1.0 - haze * 0.9);
	}
	l += bloom;

	// Бумага и зерно.
	float paper_tex = vnoise(fc * 0.7) * 0.5 + vnoise(fc * 0.13) * 0.35 + vnoise(fc * 0.03) * 0.15;
	l *= 0.93 + paper_tex * 0.1;
	l += (hash(fc + fract(TIME) * 91.0) - 0.5) * 0.03;

	// Виньетка: тёмные края кадра, как на референсах.
	vec2 v = (uv - 0.5) * vec2(1.25, 1.0);
	l *= mix(1.0, 0.35, smoothstep(0.25, 0.85, length(v) * vignette * 2.0));

	l = clamp(l, 0.0, 1.0);
	vec3 c = l < 0.5 ? mix(ink, mid, l * 2.0) : mix(mid, paper, (l - 0.5) * 2.0);
	ALBEDO = c;
}
