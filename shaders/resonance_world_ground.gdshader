shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/resonance_world.gdshaderinc"

const float RADIUS = 60.0;

varying vec3 ground_point;
varying float ridge_light;

float ridges(float a, float r) {
	float n = sin(a * 5.0 + 1.3) * 0.5 + sin(a * 11.0 + r * 0.05) * 0.3 + sin(a * 23.0 - 0.7) * 0.2;
	return n * 0.5 + 0.5;
}

void vertex() {
	float a = VERTEX.x * TAU;
	float v = VERTEX.y;
	float r = RADIUS * v * v;
	vec2 dir = vec2(sin(a), -cos(a));
	float far = smoothstep(16.0, 46.0, r);
	float sound = sound_at(a, clamp((r - 16.0) * 0.03, 0.0, 1.5));
	float h = 0.0;
	if (world_style == 0) {
		float shape_n = ridges(a, r);
		h = far * (2.5 + shape_n * 7.0 + sound * (5.0 + section_energy * 6.0) + build * 2.0);
	} else if (world_style == 1) {
		h = -smoothstep(0.0, 9.0, r) * 0.15 + far * 0.5;
	} else {
		float dune = sin(dir.x * r * 0.22 + clock * motion * 0.02) * cos(dir.y * r * 0.19) * 0.6;
		h = dune * smoothstep(5.0, 18.0, r) + far * (sound * 3.0 + ridges(a, r) * 3.5);
	}
	ridge_light = far * sound;
	VERTEX = vec3(dir.x * r, ground_level + h, dir.y * r);
	ground_point = VERTEX;
}

float line(float coordinate, float spacing, float width) {
	float d = abs(fract(coordinate / spacing + 0.5) - 0.5) * spacing;
	float aa = max(fwidth(coordinate), 0.0001);
	return 1.0 - smoothstep(width, width + aa * 1.5, d);
}

void fragment() {
	vec2 p = ground_point.xz;
	float r = length(p);
	float a = atan(p.x, -p.y);
	float fade = exp(-r / (world_style == 2 ? 22.0 : 34.0));
	vec3 base = mix(colour_a, colour_c, 0.25) * (world_style == 2 ? 0.010 : 0.006);
	float grid_strength = (world_style == 1 ? 0.07 : (world_style == 2 ? 0.018 : 0.055)) * mix(0.35, 1.0, smoothstep(2.0, 12.0, r));
	float rings = line(r, world_style == 1 ? 1.5 : 2.0, 0.025);
	float spokes = line(a * r, world_style == 1 ? 1.5 : 2.5, 0.02) * smoothstep(1.0, 3.0, r);
	float grid = max(rings, spokes) * grid_strength * (0.6 + harmonic * 0.5 + build * 0.6) * mix(0.45, 1.35, sound_at(a, r * 0.015));
	vec3 glow = palette3(a / TAU + 0.5) * grid;
	for (int i = 0; i < 8; i++) {
		float alive = source_alive(i);
		if (alive <= 0.0) {
			continue;
		}
		vec3 s = source_position(i);
		float d = distance(p, s.xz);
		vec4 b = source_bursts[i];
		float front = b.z * 7.0;
		float wave = exp(-pow((d - front) / 0.45, 2.0)) * clamp(b.w, 0.0, 1.0) * exp(-b.z * 1.4);
		float pool = exp(-d * d * 0.18) * sources[i].z * (world_style == 2 ? 0.15 : 0.3);
		glow += source_colour(i) * (wave * 0.55 + pool) * alive;
	}
	float shock_radius = 3.0 + drop_age * 16.0;
	float shock = exp(-pow((r - shock_radius) / (0.8 + drop_age * 1.2), 2.0)) * exp(-drop_age * 0.7) * smoothstep(0.0, 0.25, drop_age);
	glow += colour_c * shock * 0.6;
	float converge = exp(-pow(wrap_angle(a) / (0.9 - build * 0.6), 2.0)) * build * smoothstep(4.0, 30.0, r) * 0.18;
	glow += colour_b * converge;
	glow += colour_b * ridge_light * 0.12 * (0.5 + harmonic);
	glow += colour_a * percussive * 0.08 * smoothstep(3.0, 8.0, r) * exp(-r * 0.08);
	vec3 colour = (base + glow * fade * (0.55 + min(bass, 1.0) * 0.9)) * energy_level() * intensity * 1.3 + base * flash * 2.0;
	ALBEDO = colour * dim;
}
