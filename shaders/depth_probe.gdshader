shader_type canvas_item;
render_mode blend_disabled;

#include "res://shaders/yuv.gdshaderinc"

uniform int stereo_layout = 0;
uniform bool swap_eyes = false;
uniform vec4 crop = vec4(0.0);

const int COLUMNS = 16;
const int ROWS = 4;
const int SAMPLES_X = 6;
const int SAMPLES_Y = 3;
const int STEPS = 56;
const float D_MIN = -0.08;
const float D_MAX = 0.03;
const vec2 REGION_X = vec2(0.12, 0.88);
const vec2 REGION_Y = vec2(0.66, 0.98);
const float MIN_CONTRAST = 0.05;
const float MAX_RESIDUAL = 0.06;
const float UNIQUENESS = 0.65;

float luma(vec2 uv, float lod)
{
	vec4 t = textureLod(plane_y, uv, lod);
	return (packed_rgb ? t.g : t.r * sample_scale);
}

vec2 eye_uv(vec2 uv, bool right_view)
{
	bool right = right_view != swap_eyes;
	uv = crop.xy + clamp(uv, 0.0, 1.0) * (1.0 - crop.xy - crop.zw);
	if (stereo_layout == 1)
		return vec2(uv.x * 0.5 + (right ? 0.5 : 0.0), uv.y);
	if (stereo_layout == 2)
		return vec2(uv.x, uv.y * 0.5 + (right ? 0.5 : 0.0));
	return uv;
}

void fragment()
{
	int column = int(UV.x * float(COLUMNS));
	float eye_pixels = float(textureSize(plane_y, 0).x) * (stereo_layout == 1 ? 0.5 : 1.0);
	float lod = clamp(log2(max(eye_pixels * (D_MAX - D_MIN) / float(STEPS), 1.0)), 0.0, 4.0);
	vec2 cell = vec2((REGION_X.y - REGION_X.x) / float(COLUMNS), (REGION_Y.y - REGION_Y.x) / float(ROWS));
	float nearest = D_MAX;
	float valid_rows = 0.0;
	for (int row = 0; row < ROWS; row++)
	{
		vec2 origin = vec2(REGION_X.x + float(column) * cell.x, REGION_Y.x + float(row) * cell.y);
		float left[SAMPLES_X * SAMPLES_Y];
		float lo = 1.0;
		float hi = 0.0;
		for (int j = 0; j < SAMPLES_Y; j++)
		{
			for (int i = 0; i < SAMPLES_X; i++)
			{
				vec2 p = origin + (vec2(float(i), float(j)) + 0.5) / vec2(float(SAMPLES_X), float(SAMPLES_Y)) * cell;
				float v = luma(eye_uv(p, false), lod);
				left[j * SAMPLES_X + i] = v;
				lo = min(lo, v);
				hi = max(hi, v);
			}
		}
		if (hi - lo < MIN_CONTRAST)
			continue;
		float best = 1e9;
		float best_d = 0.0;
		float total = 0.0;
		for (int k = 0; k < STEPS; k++)
		{
			float d = D_MIN + (D_MAX - D_MIN) * float(k) / float(STEPS - 1);
			float sad = 0.0;
			for (int j = 0; j < SAMPLES_Y; j++)
			{
				for (int i = 0; i < SAMPLES_X; i++)
				{
					vec2 p = origin + (vec2(float(i), float(j)) + 0.5) / vec2(float(SAMPLES_X), float(SAMPLES_Y)) * cell;
					sad += abs(luma(eye_uv(p + vec2(d, 0.0), true), lod) - left[j * SAMPLES_X + i]);
				}
			}
			sad /= float(SAMPLES_X * SAMPLES_Y);
			total += sad;
			if (sad < best)
			{
				best = sad;
				best_d = d;
			}
		}
		if (best < MAX_RESIDUAL && best < UNIQUENESS * total / float(STEPS))
		{
			nearest = min(nearest, best_d);
			valid_rows += 1.0;
		}
	}
	COLOR = vec4((nearest - D_MIN) / (D_MAX - D_MIN), valid_rows / float(ROWS), 0.0, 1.0);
}
