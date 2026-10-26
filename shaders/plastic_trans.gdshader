// Прозрачный пластик: стекло, вода, огонь, свет. Общая часть в plastic.gdshaderinc.
shader_type spatial;
render_mode specular_schlick_ggx, blend_mix, depth_draw_opaque, cull_back;

#define TRANSPARENT
#include "res://shaders/plastic.gdshaderinc"
