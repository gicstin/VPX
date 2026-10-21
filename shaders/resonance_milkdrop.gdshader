shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/visualizer_loop.gdshaderinc"

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform sampler2D wave_texture : filter_linear, repeat_disable;
uniform sampler2D spectral_history_texture : filter_linear, repeat_disable;
uniform int spectral_history_head = -1;
uniform float spectral_history_fraction = 0.0;
uniform float spectral_history_valid = 0.0;
uniform int spectral_channel_count = 2;
uniform int milkdrop_style = 0;
uniform int shape = 0;
uniform int instance_count = 48;
uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float motion = 0.6;
uniform float dim = 1.0;

varying vec3 tint;
varying float light;
varying float edge;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float energy(float u, float channel, float delay) {
	float band = mix(0.5 / 48.0, 47.5 / 48.0, clamp(u, 0.0, 1.0));
	float index = float(spectral_history_head) + min(0.0, spectral_history_fraction - delay * 45.0);
	float a = mod(floor(index), 192.0);
	float b = mod(a + 1.0, 192.0);
	float row = spectral_channel_count == 1 ? 0.0 : channel * 192.0;
	float value = mix(textureLod(spectral_history_texture, vec2(band, (row + a + 0.5) / 384.0), 0.0).r,
		textureLod(spectral_history_texture, vec2(band, (row + b + 0.5) / 384.0), 0.0).r, fract(index));
	value *= 1.0 - smoothstep(spectral_history_valid * 3.8, spectral_history_valid * 3.8 + 0.08, delay);
	return 1.0 - exp(-pow(max(value, 0.0), 1.35) * sensitivity * 1.5);
}

vec3 wave_colour(float t) {
	vec3 base = vec3(0.8, 0.5, 0.3);
	float amount = 0.4;
	vec3 first = vec3(0.933, 0.9, 0.91);
	vec3 second = vec3(1.045, 0.956, 0.92);
	if (milkdrop_style == 1) {
		base = vec3(0.5);
		amount = 0.5;
	} else if (milkdrop_style == 2) {
		return vec3(0.7, 0.9, 1.0);
	} else if (milkdrop_style == 3) {
		base = vec3(0.5, 0.5, 0.8);
		amount = 0.65;
		first = vec3(1.437, 1.344, 1.251);
		second = vec3(0.97, 0.841, 1.055);
	}
	vec3 c = max(vec3(0.06), base + amount * (0.6 * sin(first * t) + 0.4 * sin(second * t)));
	return c / max(max(c.r, c.g), c.b);
}

vec3 trace(float u, float age, float channel, float signal, float wave, float t) {
	float angle = u * TAU;
	float radial = 0.5 + wave * 0.13;
	float rotation = 0.01 * (0.6 * sin(0.381 * t) + 0.4 * sin(0.579 * t));
	float zoom = 1.025 + 0.01 * (0.6 * sin(0.339 * t) + 0.4 * sin(0.276 * t));
	vec2 centre = vec2(0.0);
	if (milkdrop_style == 0) {
		rotation += 0.04 * sin(-2.7 * t + radial * 13.0) * (1.3 - radial);
		angle += rotation * age * 90.0 + sin(angle * 3.0 + t * 0.3) * age * 0.7;
		radial *= pow(zoom, age * 45.0);
	} else if (milkdrop_style == 1) {
		zoom = 1.064 + 0.013 * (0.6 * sin(0.339 * t) + 0.4 * sin(0.276 * t));
		zoom += 0.04 * sin(angle * 5.0 + t * 2.6);
		rotation *= 4.0;
		radial *= pow(zoom, age * 32.0);
		angle += rotation * age * 60.0;
	} else if (milkdrop_style == 2) {
		rotation = -0.82 + 0.73 * sin(t * 0.065);
		zoom = 1.0 + rotation * 0.2;
		angle += rotation * age * 19.0;
		radial = (0.4 + age * 2.4) * pow(zoom, age * 4.0);
		radial += wave * 0.09 + max(0.0, bass * 2.4 - 1.2) * 0.18 * sin(angle * 3.0 + t);
	} else {
		zoom = 1.053;
		centre = 0.21 * (0.6 * sin(vec2(0.374, 0.393) * t) + 0.4 * sin(vec2(0.294, 0.223) * t));
		centre += age * 0.9 * (0.6 * sin(vec2(0.234, 0.284) * t) + 0.4 * sin(vec2(0.277, 0.247) * t));
		radial *= pow(zoom, age * 36.0);
		angle += rotation * age * 90.0;
	}
	radial *= 1.0 + signal * 0.2;
	vec2 point = centre * 5.0 + vec2(cos(angle), sin(angle)) * radial * 3.4;
	float z = -6.0 - age * 5.0 + sin(angle * 2.0 + age * 3.0) * (0.35 + signal * 0.7);
	point.x += (channel * 2.0 - 1.0) * (0.16 + signal * 0.3);
	if (milkdrop_style == 2) {
		z = -7.0 - age * 4.0 + sin(angle) * radial * 1.7;
	}
	return vec3(point, z);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float t = clock * motion;
	float channel = mod(id, 2.0);
	float age = floor(id * 0.5) / max(1.0, float(instance_count) * 0.5 - 1.0);
	float u = VERTEX.x;
	float response = energy(fract(u), channel, age * 2.6);
	if (loop_weight(u) < 1.0) {
		response = loop_join(response, energy(0.0, channel, age * 2.6), energy(1.0, channel, age * 2.6), u);
	}
	float wave = loop_sample(wave_texture, u, (channel + 0.5) * 0.5, 256.0);
	tint = wave_colour(t - age * 2.6) * mix(vec3(0.35, 0.9, 1.0), vec3(1.0, 0.45, 0.7), channel);
	edge = VERTEX.y;
	light = (0.025 + response * 1.6) * exp(-age * 1.8);
	if (shape == 1) {
		float seed = hash(id + 3.0);
		float phase = fract(hash(id + 9.0) + t * (0.025 + bass * 0.02));
		float a = hash(id + 17.0) * TAU + phase * 1.5;
		float y = hash(id + 29.0) * 2.0 - 1.0;
		vec3 direction = vec3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y));
		response = energy(seed, channel, phase * 2.6);
		vec3 point = direction * (3.0 + phase * 24.0);
		point.xy += vec2(sin(t * 0.374), sin(t * 0.393)) * 0.8;
		VERTEX = point + VERTEX * (0.015 + response * 0.1);
		light = response * (0.35 + seed) * smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.75, 1.0, phase));
		edge = 0.0;
	} else {
		if (shape == 2) {
			age = floor(id * 0.5) / max(1.0, float(instance_count) * 0.5 - 1.0);
			wave = 0.0;
			light = (0.01 + response * 0.35) * exp(-age * 1.8);
		}
		vec3 point = trace(u, age, channel, response, wave, t);
		vec3 tangent = trace(u + 0.001, age, channel, response, wave, t) - trace(u - 0.001, age, channel, response, wave, t);
		vec3 across = normalize(vec3(-tangent.y, tangent.x, 0.00001));
		VERTEX = point + across * VERTEX.y * (0.012 + response * 0.025);
	}
}

void fragment() {
	float aa = max(fwidth(edge), 0.001);
	float core = 1.0 - smoothstep(max(0.0, 0.3 - aa), 0.3 + aa, abs(edge));
	float halo = pow(max(0.0, 1.0 - abs(edge)), 2.0);
	vec3 colour = tint * light * (0.7 * core + 0.3 * halo) * intensity * dim;
	ALBEDO = colour;
	EMISSION = colour * 0.5;
	ALPHA = 1.0;
}
