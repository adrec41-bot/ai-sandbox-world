// Контур методом «вывернутой оболочки». Покачивание совпадает с toon.gdshader.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.1, 0.085, 0.07, 1.0);
uniform float thickness = 0.05;
uniform float sway = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (sway > 0.0) {
		float t = TIME * 1.4 + origin.x * 0.21 + origin.z * 0.17;
		VERTEX.x += sin(t) * VERTEX.y * sway;
		VERTEX.z += cos(t * 0.8) * VERTEX.y * sway * 0.6;
	}
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
