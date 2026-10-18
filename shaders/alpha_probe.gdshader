shader_type canvas_item;
render_mode blend_disabled;

#include "res://shaders/yuv.gdshaderinc"

uniform vec2 jitter = vec2(0.0);

const int GRID = 40;

vec2 packed_alpha_uv(vec2 uv)
{
	float x = uv.x < 0.5 ? 0.4 * uv.x + 0.4 : fract(0.4 * uv.x + 0.7);
	return vec2(x, fract(0.4 * uv.y + 0.8));
}

vec3 classify(vec2 uv)
{
	vec3 rgb = yuv_to_rgb_gamma(sample_yuva_lod(uv, 1.0).xyz);
	float lo = min(rgb.r, min(rgb.g, rgb.b));
	float hi = max(rgb.r, max(rgb.g, rgb.b));
	bool black = hi < 0.15;
	bool red = rgb.r > 0.35 && rgb.g < 0.3 && rgb.b < 0.3;
	bool white = lo > 0.6;
	bool mask = !black && (red || white);
	return vec3(mask ? 1.0 : 0.0, black ? 1.0 : 0.0, (!mask && !black) ? 1.0 : 0.0);
}

void fragment()
{
	int column = int(UV.x * 4.0);
	vec3 left = vec3(0.0);
	vec3 right = vec3(0.0);
	float both = 0.0;
	float either = 0.0;
	float count = 0.0;
	for (int j = 0; j < GRID; j++)
	{
		for (int i = 0; i < GRID; i++)
		{
			vec2 eye = (vec2(float(i), float(j)) + 0.5 + jitter) / float(GRID);
			vec2 g = eye * 2.0 - 1.0;
			if (dot(g, g) > 1.0)
				continue;
			vec3 l = classify(packed_alpha_uv(vec2(eye.x * 0.5, eye.y)));
			vec3 r = classify(packed_alpha_uv(vec2(0.5 + eye.x * 0.5, eye.y)));
			left += l;
			right += r;
			both += l.x * r.x;
			either += max(l.x, r.x);
			count += 1.0;
		}
	}
	vec4 result;
	if (column == 0)
		result = vec4(left / count, 1.0);
	else if (column == 1)
		result = vec4(right / count, 1.0);
	else
		result = vec4(both / max(either, 1.0), either / count, both / count, 1.0);
	COLOR = clamp(result, 0.0, 1.0);
}
