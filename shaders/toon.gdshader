// Общий тун-шейдер мира. Любой объект, в том числе сгенерированный ИИ,
// рисуется через него, поэтому стиль мира остаётся единым.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = emission.rgb * emission_strength;
}

void light() {
	float l = dot(NORMAL, LIGHT) * ATTENUATION;
	// Жёсткая граница света и тени плюс мягкая вторая ступень.
	float band = smoothstep(0.0, 0.06, l) * 0.85 + smoothstep(0.45, 0.5, l) * 0.15;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * band;
}
