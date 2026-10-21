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
uniform int projectm_style = 0;
uniform int shape = 0;
uniform int instance_count = 72;
uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float impulse = 0.0;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float motion = 0.6;
uniform float dim = 1.0;
uniform vec3 transients = vec3(0.0);

varying vec3 tint;
varying float light;
varying float edge;
varying vec3 surface_point;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float energy(float u, float channel, float age) {
	float band = mix(0.5 / 48.0, 47.5 / 48.0, clamp(u, 0.0, 1.0));
	float row = (spectral_channel_count == 1 ? 0.0 : channel) * 192.0;
	float index = float(spectral_history_head) + min(0.0, spectral_history_fraction - age * 45.0);
	float first = mod(floor(index), 192.0);
	float second = mod(first + 1.0, 192.0);
	float history = mix(textureLod(spectral_history_texture, vec2(band, (row + first + 0.5) / 384.0), 0.0).r,
		textureLod(spectral_history_texture, vec2(band, (row + second + 0.5) / 384.0), 0.0).r, fract(index));
	history *= 1.0 - smoothstep(spectral_history_valid * 3.8, spectral_history_valid * 3.8 + 0.05, age);
	float current = textureLod(spectrum_texture, vec2(band, (channel + 0.5) / 50.0), 0.0).r;
	float value = mix(current, history, smoothstep(0.0, 0.12, age));
	return 1.0 - exp(-pow(max(value, 0.0), 1.6) * sensitivity * 1.8);
}

vec3 colour(float u, float channel, float t) {
	vec3 a = vec3(0.08, 0.85, 0.7);
	vec3 b = vec3(1.0, 0.12, 0.45);
	if (projectm_style == 1) {
		a = vec3(1.0, 0.22, 0.025);
		b = vec3(0.65, 0.12, 1.0);
	} else if (projectm_style == 2) {
		a = vec3(0.1, 0.4, 1.0);
		b = vec3(1.0, 0.65, 0.16);
	} else if (projectm_style == 3) {
		a = vec3(0.015, 0.45, 0.85);
		b = vec3(0.05, 1.0, 0.7);
	} else if (projectm_style == 4) {
		a = vec3(1.0, 0.24, 0.015);
		b = vec3(1.0, 0.86, 0.25);
	} else if (projectm_style == 5) {
		return max(vec3(0.08), vec3(0.28, 0.35, 0.55) + 0.5 * sin(t * vec3(0.666, 0.777, 0.888) + u * 3.0 + channel));
	}
	return mix(a, b, clamp(u * 0.65 + channel * 0.35, 0.0, 1.0));
}

vec3 path(float u, float id, float signal, float wave, float t) {
	float f = id / max(1.0, float(instance_count) - 1.0);
	float around = id / max(1.0, float(instance_count));
	float a = u * TAU;
	float hit = impulse + transients.x * 0.4;
	if (projectm_style == 0) {
		float family = mod(id, 3.0);
		float drift = 0.15 * sin(0.416 * t + family * 1.7) + 0.15 * sin(0.832 * t) + 0.1 * sin(1.324 * t);
		float y = (u - 0.5) * 25.0;
		float az = around * TAU + drift + sin(y * 0.459 + t * 0.325) * (0.06 + signal * 0.15);
		float radius = 5.0 + family * 2.2 + sin(u * 14.0 + t * 0.325) * 0.6;
		radius += wave * (0.7 + signal) + hit * sin(u * 10.0) * 0.7;
		if (shape == 2) {
			az = a;
			y = (f - 0.5) * 19.0 + sin(a * 10.0 + t * 0.459) * (0.3 + signal);
			radius = 6.0 + sin(a * 14.0 + t * 0.325) * 0.4 + wave;
		}
		return vec3(cos(az) * radius, y, sin(az) * radius);
	}
	if (projectm_style == 1) {
		vec2 centre = 0.6 * (0.6 * sin(vec2(0.374, 0.393) * t) + 0.4 * sin(vec2(0.294, 0.223) * t));
		float orbit = a;
		float poloidal = around * TAU + a * 3.0 + t * 0.15;
		float minor = 1.8 + signal * 1.2 + wave * 0.65 + hit * 0.6;
		float major = 8.0 + bass * 1.3;
		float distortion = 0.2 * sin(minor * 0.05) * 18.0;
		if (shape == 2) {
			orbit = around * TAU;
			poloidal = a + t * 0.15;
		}
		float r = major + minor * cos(poloidal);
		return vec3(r * cos(orbit) + centre.x, minor * sin(poloidal) + distortion * sin(poloidal * 2.0 - 1.5), r * sin(orbit) + centre.y);
	}
	if (projectm_style == 2) {
		float cell = floor(id / 12.0);
		float axis = floor(mod(id, 12.0) / 4.0);
		float bits = mod(id, 4.0);
		vec3 p = vec3(u * 2.0 - 1.0, mod(bits, 2.0) * 2.0 - 1.0, floor(bits / 2.0) * 2.0 - 1.0);
		if (axis < 0.5) { p = p.yxz; } else if (axis < 1.5) { p = p.zyx; }
		float az = cell * 2.399963;
		vec3 centre = vec3(cos(az) * 9.5, (mod(cell, 3.0) - 1.0) * 5.0, sin(az) * 9.5);
		vec3 drift = vec3(
			0.25 * sin(t * 0.327 + az * 3.12) + 0.5 * sin(t * 0.878 + az * 8.68) + 0.25 * sin(t * 0.787 + az * 7.85),
			0.45 * sin(t * 0.877 + az * 2.37) + 0.25 * sin(t * 0.482 + az * 2.38) + 0.3 * sin(t * 0.129 + az * 3.21),
			0.35 * sin(t * 0.453 + az * 8.97) + 0.15 * sin(t * 0.365 + az * 5.13) + 0.5 * sin(t * 0.385 + az * 5.46));
		centre += drift * (0.3 + mids * 0.6);
		float scale = 1.6 + signal * 0.8 + hit * 0.5;
		p *= scale;
		p += sin(p.yzx * 2.0 + t * 0.2) * (wave * 0.15 + signal * 0.12);
		if (shape == 2) {
			float edge_id = floor(u * 4.0);
			float angle = (edge_id + 0.5) * TAU / 4.0;
			float next_angle = angle + TAU / 4.0;
			p = mix(vec3(cos(angle), sin(angle), 0.0), vec3(cos(next_angle), sin(next_angle), 0.0), fract(u * 4.0)) * (2.2 + signal);
			centre = vec3(cos(around * TAU) * 12.0, sin(around * TAU * 3.0) * 5.0, sin(around * TAU) * 12.0);
		}
		return centre + p;
	}
	if (projectm_style == 3) {
		if (shape == 3) { f = id; }
		vec2 p = vec2((u - 0.5) * 64.0, (f - 0.5) * 58.0);
		if (shape != 3 && mod(id, 2.0) > 0.5) { p = p.yx; }
		float q = t * (0.5 + bass * 0.5);
		float dx = 0.008 * sin(p.y * (4.8 + 1.2 * sin(0.412 * q))) + 0.008 * sin((p.y + sin(t * 0.163)) * (3.0 + sin(0.241 * q)));
		float dy = 0.008 * cos(p.x * (6.4 + 1.8 * sin(0.376 * q))) + 0.008 * sin((p.x + sin(q * 0.282)) * (3.0 + sin(0.349 * q)));
		float height = sin(p.x * 0.24 + t * 1.7) * cos(p.y * 0.18 - t * 0.7) * (0.4 + bass * 1.4);
		height += (dx + dy) * (10.0 + signal * 26.0) + wave * 0.45;
		height += hit * 0.65 * sin(length(p) * 1.4 - t * 1.7);
		if (shape == 2) { height -= 3.0; }
		return vec3(p.x, -3.8 + height, p.y);
	}
	if (projectm_style == 4) {
		vec3 centre = vec3(0.5 * sin(0.497 * t), 0.5 * sin(0.413 * t), -12.0);
		if (shape == 2) {
			float latitude = (f - 0.5) * PI;
			float r = (2.0 + bass * 0.7 + hit * 0.3 + signal * 0.2 + wave * 0.15);
			return centre + vec3(cos(a) * cos(latitude), sin(latitude), sin(a) * cos(latitude)) * r;
		}
		float orbit = floor(id / 6.0);
		float age = mod(id, 6.0) / 6.0;
		float radius = 4.0 + orbit * 0.9 + wave * 0.35 + signal * 0.35;
		float angle = a + t * 0.08 / (1.0 + orbit * 0.15) - age * 0.18;
		vec3 p = vec3(cos(angle) * radius, sin(angle) * radius * 0.25, sin(angle) * radius);
		float tilt = orbit * 0.47;
		p.xy = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt))) * p.xy;
		return centre + p;
	}
	float az = around * TAU;
	float y = (u - 0.5) * 29.0;
	float x = sin(az) * 0.5;
	float shear = y > 5.8 ? asin(clamp(x * (y / 29.0 - 0.2), -0.9, 0.9)) : y < -5.8 ? -asin(clamp(x * (y / 29.0 + 0.2), -0.9, 0.9)) : 0.0;
	float radius = 5.5 + mod(id, 4.0) * 1.8 + sin(y * 0.35 + t * 0.4) * (0.3 + signal);
	float knot = u * 38.0;
	float jagged = mix(hash(floor(knot) + id * 41.0), hash(floor(knot) + 1.0 + id * 41.0), fract(knot)) - 0.5;
	az += shear * 5.0 + t * 0.05 * sign(y) + wave * 0.16 + jagged * (0.1 + signal * 0.13 + hit * 0.25);
	if (shape == 2) {
		az = a + shear;
		y = (f - 0.5) * 26.0;
		radius = 7.5 + sin(a * 4.0 + t) * signal;
	}
	return vec3(cos(az) * radius, y * (1.0 + bass * 0.1), sin(az) * radius);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float t = clock * motion;
	float channel = mod(id, 2.0);
	float f = id / max(1.0, float(instance_count) - 1.0);
	bool surrounds = (projectm_style == 0 && shape == 0) || projectm_style == 1 || (projectm_style == 2 && shape == 2) || projectm_style == 5;
	float pitch = surrounds ? 0.5 - 0.5 * cos(id / max(1.0, float(instance_count)) * TAU) : f;
	float u = VERTEX.x;
	float age = shape == 2 ? pitch * 1.8 : 0.0;
	bool closed = (shape == 2 && (projectm_style == 0 || projectm_style == 2)) || ((shape == 0 || shape == 2) && (projectm_style == 1 || projectm_style == 4));
	float signal = energy(mix(pitch, closed ? fract(u) : u, 0.55), channel, age);
	if (closed && loop_weight(u) < 1.0) {
		signal = loop_join(signal, energy(mix(pitch, 0.0, 0.55), channel, age), energy(mix(pitch, 1.0, 0.55), channel, age), u);
	}
	float wave = closed ? loop_sample(wave_texture, u, (channel + 0.5) * 0.5, 256.0) : textureLod(wave_texture, vec2(mix(0.5 / 256.0, 255.5 / 256.0, u), (channel + 0.5) * 0.5), 0.0).r;
	surface_point = VERTEX;
	tint = colour(pitch, channel, t);
	edge = VERTEX.y;
	light = (0.008 + signal * 0.65 + impulse * 0.14 + dot(transients, vec3(0.05))) * (shape == 2 ? 0.65 : 1.0);
	if (shape == 3) {
		edge = 0.0;
		if (projectm_style == 4) {
			surface_point = VERTEX;
			float plasma = sin(VERTEX.x * 8.0 + t) * sin(VERTEX.y * 11.0 - t * 0.7);
			VERTEX *= 1.9 + bass * 0.65 + signal * 0.15 + plasma * (0.025 + impulse * 0.06);
			VERTEX += vec3(0.5 * sin(0.497 * t), 0.5 * sin(0.413 * t), -12.0);
			tint = vec3(1.0, 0.25, 0.012);
			light = 0.15 + signal * 0.45 + bass * 0.15;
		} else {
			VERTEX = path(u, VERTEX.y, signal, wave, t);
			surface_point = VERTEX;
			light = signal * 0.065;
		}
	} else if (shape == 1) {
		float seed = hash(id + 1.0);
		float phase = fract(hash(id + 4.0) + t * 0.035);
		signal = energy(seed, channel, 0.0);
		vec3 p = path(phase, floor(seed * 72.0), signal, 0.0, t);
		if (projectm_style == 2) {
			p += vec3(hash(id + 8.0), hash(id + 9.0), hash(id + 10.0)) * 1.6 - 0.8;
		} else if (projectm_style == 4) {
			float az = hash(id + 17.0) * TAU;
			float y = hash(id + 29.0) * 2.0 - 1.0;
			p = vec3(cos(az) * sqrt(1.0 - y * y), y, sin(az) * sqrt(1.0 - y * y)) * (22.0 + seed * 12.0);
		} else if (projectm_style == 5) {
			p.y = (0.5 - phase) * 29.0;
		}
		vec3 size = vec3(0.014 + signal * 0.045 + treble * 0.015);
		if (projectm_style == 5) { size *= vec3(0.5, 10.0 + signal * 8.0, 0.5); }
		VERTEX = p + VERTEX * size;
		tint = colour(seed, channel, t);
		light = signal * (0.2 + treble * 0.5) * sin(phase * PI);
		edge = 0.0;
	} else {
		if (projectm_style == 5) {
			light *= pow(0.5 + 0.5 * sin(u * 26.0 + id * 3.0 - t * 0.4), 5.0) * (0.4 + impulse);
		}
		vec3 p = path(u, id, signal, wave, t);
		vec3 tangent = path(u + 0.001, id, signal, wave, t) - path(u - 0.001, id, signal, wave, t);
		vec3 view = normalize(-p + vec3(0.0001));
		vec3 across = cross(tangent, view);
		across /= max(length(across), 0.00001);
		VERTEX = p + across * VERTEX.y * (0.025 + signal * 0.035 + impulse * 0.015);
	}
}

void fragment() {
	float aa = max(fwidth(edge), 0.001);
	float core = 1.0 - smoothstep(max(0.0, 0.3 - aa), 0.3 + aa, abs(edge));
	float halo = pow(max(0.0, 1.0 - abs(edge)), 2.0);
	vec3 c = tint * light * (core * 0.7 + halo * 0.3) * intensity * dim;
	if (shape == 3 && projectm_style == 4) {
		float t = clock * motion;
		float plasma = sin(surface_point.x * 16.0 + sin(surface_point.z * 12.0 + t)) * sin(surface_point.y * 19.0 - t * 0.8);
		c *= mix(vec3(0.6, 0.15, 0.04), vec3(1.0, 2.1, 1.2), plasma * 0.5 + 0.5);
	}
	ALBEDO = c;
	EMISSION = c * 0.35;
	ALPHA = 1.0;
}
