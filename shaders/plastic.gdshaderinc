// Общая часть пластика Lego. Её подключают plastic.gdshader (обычный
// цвет), plastic_trans.gdshader (прозрачный) и plastic_metal.gdshader
// (золото, серебро). Любой объект в мире, в том числе от ИИ, рисуется
// одним из них, поэтому стиль мира остаётся единым.

uniform vec4 albedo : source_color = vec4(1.0);
// Цвет из вершин: кирпичи одного объекта склеены в один меш, и у каждого
// свой цвет. Цвета вершин уже переведены в линейное пространство.
uniform bool use_vertex_color = true;
uniform float roughness = 0.3;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
// Покачивание на ветру: листва, флаги.
uniform float sway = 0.0;
// Сборка постройки снизу вверх: всё выше этой мировой высоты не рисуется.
uniform float reveal = 100000.0;
// Шипы базовой пластины не выходят за край мира (0: без ограничения).
uniform float clip_half = 0.0;

varying vec3 world_pos;

void vertex() {
	if (sway > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float t = TIME * 1.4 + origin.x * 0.21 + origin.z * 0.17;
		VERTEX.x += sin(t) * VERTEX.y * sway;
		VERTEX.z += cos(t * 0.8) * VERTEX.y * sway * 0.6;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (world_pos.y > reveal) {
		discard;
	}
	if (clip_half > 0.0 && max(abs(world_pos.x), abs(world_pos.z)) > clip_half) {
		discard;
	}
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
#ifdef METAL
	METALLIC = 0.85;
	ROUGHNESS = 0.22;
#endif
	// Лёгкий отблеск по краю, как у глянцевого пластика.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = emission.rgb * emission_strength + c * rim * 0.12;
#ifdef TRANSPARENT
	ALPHA = 0.55;
	EMISSION += c * 0.15;
#endif
}
