shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

#include "res://shaders/yuv.gdshaderinc"

uniform vec3 screen_center = vec3(0.0, 1.5, -3.0);
uniform vec3 screen_right = vec3(1.0, 0.0, 0.0);
uniform vec3 screen_up = vec3(0.0, 1.0, 0.0);
uniform vec2 screen_half = vec2(1.7, 1.0);
uniform int stereo_layout = 0;
uniform bool video_glow = true;
uniform vec3 fallback_glow : source_color = vec3(0.35, 0.35, 0.4);
uniform float glow_lod = 8.0;
uniform float glow_gain = 2.2;
uniform float brightness = 1.0;
uniform float room_floor = 0.0;
uniform float room_height = 7.0;

varying vec3 world_position;
varying vec3 world_normal;

const int COLUMNS = 3;
const int ROWS = 2;

vec3 video_color(vec2 uv)
{
	if (stereo_layout == 1)
		uv.x *= 0.5;
	else if (stereo_layout == 2)
		uv.y *= 0.5;
	return video_to_linear(yuv_to_rgb_gamma(sample_yuva_lod(uv, glow_lod).xyz));
}

float hash(vec2 p)
{
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 surface_color(vec3 p, vec3 n)
{
	float height = p.y - room_floor;
	if (n.y > 0.5)
	{
		float fibre = hash(floor(p.xz * 40.0)) * 0.06;
		float aisle = step(0.5, fract(p.x * 0.25)) * 0.02;
		return vec3(0.16, 0.035, 0.045) + fibre + aisle;
	}
	if (n.y < -0.5)
		return vec3(0.02);
	float panel = smoothstep(0.02, 0.0, abs(fract(dot(p.xz, vec2(n.z, -n.x)) * 0.5) - 0.5) - 0.47);
	float skirting = step(height, 0.25);
	vec3 fabric = vec3(0.07, 0.065, 0.075) * (1.0 - panel * 0.5);
	return mix(fabric, vec3(0.02), skirting);
}

void vertex()
{
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = -normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment()
{
	vec3 p = world_position;
	vec3 n = normalize(world_normal);
	vec3 screen_normal = normalize(cross(screen_right, screen_up));
	vec3 light = vec3(0.0);
	float cell_area = (screen_half.x * 2.0 / float(COLUMNS)) * (screen_half.y * 2.0 / float(ROWS));
	for (int column = 0; column < COLUMNS; column++)
	{
		for (int row = 0; row < ROWS; row++)
		{
			vec2 uv = vec2((float(column) + 0.5) / float(COLUMNS), (float(row) + 0.5) / float(ROWS));
			vec3 source = screen_center + screen_right * (uv.x * 2.0 - 1.0) * screen_half.x + screen_up * (1.0 - uv.y * 2.0) * screen_half.y;
			vec3 to_source = source - p;
			float distance_sq = dot(to_source, to_source);
			vec3 direction = to_source * inversesqrt(max(distance_sq, 0.0001));
			float facing = max(dot(n, direction), 0.0) * abs(dot(screen_normal, direction));
			vec3 emitted = video_glow ? video_color(uv) : fallback_glow;
			light += emitted * facing * cell_area / (distance_sq + 1.0);
		}
	}
	vec3 albedo = surface_color(p, n);
	ALBEDO = albedo * (vec3(0.03) + light * glow_gain * brightness);
}
