uniform int world_style = 0;
uniform int shape = 0;
uniform int instance_count = 1;
uniform float clock = 0.0;
uniform float motion = 0.6;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float dim = 1.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform vec3 transients = vec3(0.0);
uniform float beat_age = 4.0;
uniform float beat_phase = 0.0;
uniform float bar_phase = 0.0;
uniform float breath = 0.5;
uniform float beat_pulse = 0.0;
uniform float bar_pulse = 0.0;
uniform float percussive = 0.0;
uniform float harmonic = 0.0;
uniform float map_intensity = 0.0;
uniform float brightness = 0.0;
uniform float build = 0.0;
uniform float drop_pulse = 0.0;
uniform float drop_age = 1000.0;
uniform float section_energy = 0.5;
uniform float next_energy = 0.5;
uniform float section_change = 0.0;
uniform float anticipation = 0.0;
uniform float flash = 0.0;
uniform vec3 colour_a = vec3(0.1, 0.45, 1.0);
uniform vec3 colour_b = vec3(1.0, 0.35, 0.6);
uniform vec3 colour_c = vec3(1.0, 0.8, 0.3);
uniform float ground_level = -1.5;
uniform vec4 sources[8];
uniform vec4 source_info[8];
uniform vec4 source_bursts[8];
uniform sampler2D field_texture : filter_linear, repeat_disable;
uniform float field_head = -1.0;
uniform float field_fraction = 0.0;

uniform float source_spread = 0.9;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float energy01(float value) {
	return 1.0 - exp(-max(0.0, value) * sensitivity * 0.45);
}

vec3 palette3(float x) {
	float f = fract(x) * 3.0;
	if (f < 1.0) {
		return mix(colour_a, colour_b, smoothstep(0.0, 1.0, f));
	}
	if (f < 2.0) {
		return mix(colour_b, colour_c, smoothstep(0.0, 1.0, f - 1.0));
	}
	return mix(colour_c, colour_a, smoothstep(0.0, 1.0, f - 2.0));
}

vec4 field_at(float pan01, float delay) {
	if (field_head < 0.0) {
		return vec4(0.0);
	}
	float index = field_head + min(0.0, field_fraction - delay * 45.0);
	float a = mod(floor(index), 192.0);
	float b = mod(a + 1.0, 192.0);
	float x = mix(0.5 / 64.0, 63.5 / 64.0, clamp(pan01, 0.0, 1.0));
	return mix(textureLod(field_texture, vec2(x, (a + 0.5) / 192.0), 0.0), textureLod(field_texture, vec2(x, (b + 0.5) / 192.0), 0.0), fract(index));
}

float wrap_angle(float a) {
	return mod(a + PI, TAU) - PI;
}

float sound_at(float azimuth, float delay) {
	float a = wrap_angle(azimuth);
	float pan = clamp(a / source_spread, -1.0, 1.0);
	float level = energy01(field_at(pan * 0.5 + 0.5, delay).r);
	if (abs(a) > source_spread) {
		float across = smoothstep(source_spread, PI, abs(a)) * 0.5;
		level = mix(level, energy01(field_at(0.5 - pan * 0.5, delay).r), across);
	}
	float behind = 1.0 - smoothstep(source_spread, source_spread + 0.7, abs(a));
	return level * mix(0.3, 1.0, behind);
}

float source_distance() {
	return world_style == 1 ? 10.5 : (world_style == 2 ? 8.0 : 9.0);
}

vec3 source_position(int i) {
	vec4 s = sources[i];
	float a = clamp(s.x, -1.0, 1.0) * source_spread;
	float d = source_distance() - s.z * 1.2;
	float h = mix(-0.9, 5.5, clamp(s.y, 0.0, 1.0));
	if (world_style == 2) {
		h += sin(clock * motion * 0.31 + float(i) * 1.7) * 0.35;
	}
	return vec3(sin(a) * d, h, -cos(a) * d);
}

float source_alive(int i) {
	return source_info[i].w * smoothstep(0.03, 0.18, sources[i].z);
}

vec3 source_colour(int i) {
	return palette3(source_info[i].x);
}

float burst_glow(int i) {
	vec4 b = source_bursts[i];
	return clamp(b.w, 0.0, 1.0) * exp(-b.z * 3.0);
}

float beat_glow() {
	return exp(-beat_age * 6.0);
}

float energy_level() {
	return clamp(mix(0.35, 1.0, section_energy) + build * 0.15, 0.0, 1.2);
}
