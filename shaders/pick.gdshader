shader_type canvas_item;

#include "res://shaders/yuv.gdshaderinc"

uniform vec2 sample_uv = vec2(0.5);

void fragment()
{
	vec4 yuva = sample_yuva(sample_uv);
	vec3 gamma = packed_rgb ? yuva.xyz : yuv_to_rgb_gamma(yuva.xyz);
	COLOR = vec4(video_to_linear(gamma), 1.0);
}
