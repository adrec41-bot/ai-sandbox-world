// Общий тун-шейдер мира. Любой объект, в том числе сгенерированный ИИ,
// рисуется через него, поэтому стиль мира остаётся единым.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
// Покачивание на ветру: трава, кроны, флаги.
uniform float sway = 0.0;
// Живописная неровность тона, чтобы поверхности не выглядели плоскими.
uniform float mottle = 0.12;

varying vec3 wpos;

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

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (sway > 0.0) {
		float t = TIME * 1.4 + origin.x * 0.21 + origin.z * 0.17;
		VERTEX.x += sin(t) * VERTEX.y * sway;
		VERTEX.z += cos(t * 0.8) * VERTEX.y * sway * 0.6;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	float n = vnoise(wpos.xz * 0.35 + wpos.y * 0.2) * 0.6 + vnoise(wpos.xz * 2.1 + wpos.y) * 0.4;
	c *= 1.0 - mottle + n * mottle * 2.0;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = emission.rgb * emission_strength;
}

void light() {
	float l = dot(NORMAL, LIGHT) * ATTENUATION;
	// Три ступени тона, как в заливке рисованной анимации.
	float band = smoothstep(0.0, 0.05, l) * 0.6 + smoothstep(0.35, 0.42, l) * 0.4;
	// Контровой свет: края объектов светятся, когда солнце позади них.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * clamp(dot(LIGHT, -VIEW), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (band + rim * 0.5 * ATTENUATION);
}
