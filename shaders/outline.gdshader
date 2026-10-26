// Контур методом «вывернутой оболочки».
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.13, 0.11, 0.1, 1.0);
uniform float thickness = 0.05;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
