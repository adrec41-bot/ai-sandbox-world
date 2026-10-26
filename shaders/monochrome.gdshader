// Финальный фильтр экрана: переводит кадр в монохром в духе референса.
// Действует на всё, что видно, поэтому любой объект, в том числе
// сгенерированный ИИ, автоматически попадает в стиль мира.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform vec3 paper : source_color = vec3(0.96, 0.94, 0.9);
uniform vec3 ink : source_color = vec3(0.07, 0.07, 0.08);
uniform float contrast = 1.15;
uniform float gamma = 1.7;
uniform float grain = 0.035;
uniform float vignette = 0.45;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	l = pow(l, gamma);
	l = clamp((l - 0.5) * contrast + 0.5, 0.0, 1.0);
	l += (hash(SCREEN_UV * 731.0 + fract(TIME)) - 0.5) * grain;
	vec2 d = SCREEN_UV - 0.5;
	l *= 1.0 - dot(d, d) * vignette;
	COLOR = vec4(mix(ink, paper, clamp(l, 0.0, 1.0)), 1.0);
}
