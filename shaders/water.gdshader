// Вода непрозрачная: финальный фильтр кадра видит только непрозрачные объекты.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 deep : source_color = vec4(0.32, 0.32, 0.33, 1.0);
uniform vec4 sky : source_color = vec4(0.92, 0.91, 0.88, 1.0);
uniform vec4 ripple : source_color = vec4(1.0, 1.0, 0.97, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.3 + TIME) * 0.03 + cos(wpos.z * 0.25 + TIME * 1.3) * 0.03;
}

void fragment() {
	// Отражение неба у горизонта, глубина под ногами.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 c = mix(deep.rgb, sky.rgb, clamp(fres * 1.3 + 0.25, 0.0, 1.0));
	// Горизонтальные блики-штрихи, как в рисованной воде.
	float s = sin(wpos.z * 1.7 + sin(wpos.x * 0.21 + TIME * 0.5) * 2.0 + TIME * 0.6);
	float streak = smoothstep(0.96, 0.995, s) * smoothstep(0.3, 0.7, sin(wpos.x * 0.6 + wpos.z * 0.1 + TIME * 0.4));
	c = mix(c, ripple.rgb, streak * 0.8);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
