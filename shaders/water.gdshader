shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 deep : source_color = vec4(0.27, 0.45, 0.55, 1.0);
uniform vec4 shallow : source_color = vec4(0.5, 0.72, 0.74, 1.0);
uniform vec4 foam : source_color = vec4(0.95, 0.95, 0.9, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.3 + TIME) * 0.04 + cos(wpos.z * 0.25 + TIME * 1.3) * 0.04;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 c = mix(deep.rgb, shallow.rgb, fres);
	float s = sin(wpos.x * 0.35 + sin(wpos.z * 0.3 + TIME * 0.6) * 2.5 + TIME * 0.8);
	float lines = smoothstep(0.93, 0.98, s) * smoothstep(0.2, 0.6, sin(wpos.z * 0.9 + TIME));
	ALBEDO = mix(c, foam.rgb, lines * 0.7);
	ROUGHNESS = 0.6;
	ALPHA = 0.85;
}
