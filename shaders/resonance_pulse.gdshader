shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_enable;
uniform sampler2D spectral_history_texture : filter_linear, repeat_disable;
uniform sampler2D wave_texture : filter_linear, repeat_disable;
uniform int spectral_history_head = -1;
uniform float spectral_history_fraction = 0.0;
uniform float spectral_history_valid = 0.0;
uniform int spectral_channel_count = 2;
uniform float history_head = 0.0;
uniform float history_fraction = 0.0;
uniform int pulse_style = 0;
uniform int shape = 0;
uniform int instance_count = 64;
uniform float clock = 0.0;
uniform float travel = 0.0;
uniform float spin = 0.0;
uniform float surge = 0.0;
uniform float beat_age = 4.0;
uniform float beat_count = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform vec3 transients = vec3(0.0);
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float motion = 0.6;
uniform float palette = 0.0;
uniform float dim = 1.0;

varying vec3 colour;
varying float glow;
varying float edge;

const float FLOOR = -1.6;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float shaped(float value) {
	return 1.0 - exp(-pow(max(0.0, value), 1.35) * sensitivity * 1.5);
}

float level(float band, float channel) {
	return textureLod(spectrum_texture, vec2(mix(0.5 / 48.0, 47.5 / 48.0, clamp(band, 0.0, 1.0)), (channel + 0.5) / 50.0), 0.0).r;
}

float band_level(float band) {
	return max(level(band, 0.0), level(band, 1.0));
}

float spectral_at(float frequency, float delay, float channel) {
	channel = spectral_channel_count == 1 ? 0.0 : channel;
	float index = float(spectral_history_head) + min(0.0, spectral_history_fraction - delay * 45.0);
	float a = mod(floor(index), 192.0);
	float b = mod(a + 1.0, 192.0);
	float band = mix(0.5 / 48.0, 47.5 / 48.0, clamp(frequency, 0.0, 1.0));
	float row_a = (channel * 192.0 + a + 0.5) / 384.0;
	float row_b = (channel * 192.0 + b + 0.5) / 384.0;
	float value = mix(textureLod(spectral_history_texture, vec2(band, row_a), 0.0).r, textureLod(spectral_history_texture, vec2(band, row_b), 0.0).r, fract(index));
	return value * (1.0 - smoothstep(spectral_history_valid * 3.8, spectral_history_valid * 3.8 + 0.08, delay));
}

vec4 energy_history(float channel, float delay) {
	float position = history_head + (min(0.0, history_fraction - delay * 90.0) + 0.5) / 192.0;
	return textureLod(history_texture, vec2(position, (channel + 0.5) * 0.5), 0.0) * (1.0 - smoothstep(2.0, 2.1, delay));
}

float bass_wave(float delay, float side) {
	vec4 left = energy_history(0.0, delay);
	vec4 right = energy_history(1.0, delay);
	float value = mix(left.r, right.r, side) + mix(left.g, right.g, side) * 0.35;
	return 1.0 - exp(-min(value, 2.0) * sensitivity * 0.9);
}

float kick() {
	return exp(-beat_age * 5.0);
}

vec3 ramp(float x, vec3 a, vec3 b, vec3 c) {
	x = clamp(x, 0.0, 1.0);
	return x < 0.5 ? mix(a, b, x * 2.0) : mix(b, c, x * 2.0 - 1.0);
}

vec3 rainbow(float x) {
	return 0.5 + 0.5 * cos(TAU * (x + vec3(0.0, 0.33, 0.67)));
}

vec3 laser_colour(float pick) {
	int i = int(floor(pick * 6.0));
	if (i == 0) return vec3(0.1, 1.0, 0.25);
	if (i == 1) return vec3(0.05, 0.75, 1.0);
	if (i == 2) return vec3(1.0, 0.08, 0.15);
	if (i == 3) return vec3(0.85, 0.1, 1.0);
	if (i == 4) return vec3(0.2, 0.25, 1.0);
	return vec3(1.0, 0.75, 0.1);
}

float sweep(float x) {
	return abs(fract(x) * 2.0 - 1.0);
}

vec3 billboard(vec3 point, vec3 direction, float width) {
	vec3 side = cross(direction, point);
	float size = length(side);
	return size > 0.0001 ? side / size * width : vec3(0.0);
}

vec3 tunnel_point(float around, float progress, float lift) {
	float side = smoothstep(-0.3, 0.3, sin(around * TAU));
	float frequency = 1.0 - abs(around * 2.0 - 1.0);
	float delay = progress * 3.6;
	float value = mix(spectral_at(frequency, delay, 0.0), spectral_at(frequency, delay, 1.0), side);
	float response = shaped(value);
	float z = mix(-44.0, 4.0, progress);
	float radius = 3.0 + response * 1.7 * intensity + kick() * 0.55 * intensity * smoothstep(0.3, 0.8, progress) + lift;
	float angle = around * TAU + sin(clock * 0.07) * progress * 0.5;
	float bend = smoothstep(-2.0, -26.0, z);
	vec2 centre = vec2(sin(z * 0.07 + clock * 0.11), cos(z * 0.05 + clock * 0.09) * 0.7) * 2.4 * bend;
	return vec3(centre.x + sin(angle) * radius, centre.y - cos(angle) * radius, z);
}

float tunnel_response(float around, float progress) {
	float side = smoothstep(-0.3, 0.3, sin(around * TAU));
	float frequency = 1.0 - abs(around * 2.0 - 1.0);
	return shaped(mix(spectral_at(frequency, progress * 3.6, 0.0), spectral_at(frequency, progress * 3.6, 1.0), side));
}

struct Pulse {
	vec3 point;
	vec3 colour;
	float glow;
	float edge;
};

Pulse hidden() {
	Pulse p;
	p.point = vec3(0.0);
	p.colour = vec3(0.0);
	p.glow = 0.0;
	p.edge = 0.0;
	return p;
}

Pulse warp(vec3 vertex, float id, float count, vec4 custom) {
	Pulse p;
	float u = (id + 0.5) / count;
	if (shape == 0) {
		float progress = fract(u + travel * 0.05);
		float around = vertex.x;
		vec3 point = tunnel_point(around, progress, 0.0);
		vec3 outward = normalize(point - tunnel_point(around, progress, -0.5));
		float response = tunnel_response(around, progress);
		point += outward * vertex.y * (0.02 + response * 0.05 * intensity);
		float fade = smoothstep(0.0, 0.14, progress) * (1.0 - smoothstep(0.84, 0.95, progress));
		float frequency = 1.0 - abs(around * 2.0 - 1.0);
		p.colour = ramp(sweep(frequency * 0.55 + palette * 2.0), vec3(0.08, 0.32, 1.0), vec3(0.85, 0.12, 1.0), vec3(1.0, 0.45, 0.12));
		p.colour = mix(p.colour, vec3(1.0, 0.92, 1.0), smoothstep(0.75, 1.0, response) * 0.5);
		p.glow = (0.1 + response * 1.6 + kick() * 0.4) * intensity * fade;
		p.edge = vertex.y;
		p.point = point;
	} else if (shape == 2) {
		float around = u;
		float progress = mix(0.02, 0.9, vertex.x);
		vec3 point = tunnel_point(around, progress, 0.0);
		vec3 tangent = normalize(tunnel_point(around + 0.002, progress, 0.0) - point);
		float response = tunnel_response(around, progress);
		point += tangent * vertex.y * (0.016 + response * 0.03);
		float dash = pow(max(0.0, sin((point.z - travel * 2.4) * 1.1)), 10.0);
		float fade = smoothstep(0.02, 0.15, progress) * (1.0 - smoothstep(0.8, 0.9, progress));
		p.colour = mix(vec3(0.1, 0.5, 1.0), vec3(0.9, 0.3, 1.0), sweep(around + palette));
		p.glow = (0.03 + response * 0.45 + dash * (0.25 + treble * 0.8)) * intensity * fade;
		p.edge = vertex.y;
		p.point = point;
	} else if (shape == 1) {
		float angle = custom.w * TAU;
		float radius = 1.6 + pow(custom.x, 0.6) * 11.0;
		float progress = fract(custom.z + travel * 0.12);
		float z = mix(-60.0, 6.0, progress);
		float response = shaped(band_level(mix(0.5, 1.0, custom.y)));
		vec3 local = vertex * (0.012 + response * 0.022 * intensity);
		local.z *= 2.0 + surge * 9.0;
		p.point = vec3(cos(angle) * radius, sin(angle) * radius, z) + local;
		p.colour = mix(vec3(0.55, 0.8, 1.0), vec3(1.0, 0.6, 1.0), custom.y);
		p.glow = (0.08 + response * 0.7 + transients.z * response * 1.2) * intensity * smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.86, 0.94, progress));
		p.edge = 0.0;
	} else {
		float echo = id;
		if (echo > 2.0) {
			return hidden();
		}
		float age = max(0.0, beat_age - echo * 0.07);
		float z = -42.0 + age * 46.0;
		float angle = vertex.x * TAU;
		float radius = 3.6 + echo * 0.35 + vertex.y * (0.06 + bass * 0.08);
		p.point = vec3(sin(angle) * radius, -cos(angle) * radius, z);
		p.colour = vec3(0.75, 0.9, 1.0);
		p.glow = (0.9 - echo * 0.25) * (0.35 + bass) * intensity * smoothstep(-42.0, -36.0, z) * (1.0 - smoothstep(-6.0, -2.0, z));
		p.edge = vertex.y;
	}
	return p;
}

vec3 laser_origin(float group) {
	return vec3((group / 7.0 - 0.5) * 22.0, 3.2 + mod(group, 2.0) * 1.6, -24.0);
}

Pulse laser(vec3 vertex, float id, float count, vec4 custom) {
	Pulse p;
	float bar = floor(beat_count * 0.25);
	float t = spin;
	if (shape == 0) {
		float groups = 8.0;
		float per = max(1.0, floor(count / groups));
		float group = mod(id, groups);
		float k = floor(id / groups);
		float kn = per > 1.0 ? k / (per - 1.0) : 0.5;
		vec3 origin = laser_origin(group);
		float mode = floor(hash(bar * 3.1 + group * 0.71) * 3.0);
		vec3 target;
		if (mode < 1.0) {
			target = vec3((kn - 0.5) * 30.0 + sin(t * 0.8 + group) * 9.0, -0.6 + sin(t * 1.3 + group * 1.9) * 2.6, 10.0);
		} else if (mode < 2.0) {
			float a = kn * TAU + t * 1.4 * (mod(group, 2.0) * 2.0 - 1.0);
			target = vec3(cos(a) * 6.0 + sin(t * 0.5 + group) * 6.0, 0.6 + sin(a) * 4.0, 10.0);
		} else {
			target = vec3(sin(t * 1.1 + kn * 2.5 + group * 1.7) * 18.0, -1.6 + kn * 6.0, 10.0);
		}
		vec3 direction = normalize(target - origin);
		vec3 point = origin + direction * vertex.x * 52.0;
		float band = (group + 0.5) / groups;
		float response = shaped(band_level(band));
		float on = mix(0.25, 1.0, step(0.35, hash(beat_count * 1.37 + group * 5.3)));
		point += billboard(point, direction, vertex.y * (0.05 + vertex.x * 0.05));
		float near = smoothstep(0.6, 2.2, length(point));
		p.colour = laser_colour(hash(bar * 1.7 + group * 0.37));
		p.glow = (response * 1.3 + kick() * 0.9) * on * intensity * near * (1.0 - vertex.x * 0.65) * smoothstep(0.0, 0.01, vertex.x);
		p.edge = vertex.y;
		p.point = point;
	} else if (shape == 2) {
		vec3 origin = vec3(0.0, 2.6, -24.0);
		float u = (id + 0.5) / count;
		float yaw = (u - 0.5) * 2.6 + sin(t * 0.3) * 0.25;
		float height = 0.5 + sin(t * 0.37) * 1.1 + mids * 0.8;
		vec3 target = vec3(sin(yaw) * 34.0, height, -24.0 + cos(yaw) * 34.0);
		vec3 direction = normalize(target - origin);
		vec3 point = origin + direction * vertex.x * 60.0;
		point += billboard(point, direction, vertex.y * 0.06);
		float response = shaped(band_level(0.35 + u * 0.3));
		float gain = smoothstep(-0.2, 0.6, sin(t * 0.21 + 1.0));
		p.colour = laser_colour(hash(bar * 2.3 + 11.0));
		p.glow = (0.12 + response * 0.7 + kick() * 0.3) * gain * intensity * smoothstep(0.6, 2.2, length(point)) * (1.0 - vertex.x * 0.5);
		p.edge = vertex.y;
		p.point = point;
	} else if (shape == 1) {
		if (id > 1600.0) {
			return hidden();
		}
		vec3 drift = vec3(sin(clock * 0.05 + custom.w * 9.0), sin(clock * 0.03 + custom.x * 7.0) * 0.3, cos(clock * 0.04 + custom.z * 8.0)) * 0.8;
		vec3 point = vec3((custom.x - 0.5) * 34.0, custom.z * 9.0 - 1.6, (custom.w - 0.5) * 40.0 - 6.0) + drift;
		float twinkle = pow(max(0.0, sin(custom.y * 60.0 + clock * 3.0)), 8.0);
		p.point = point + vertex * 0.012;
		p.colour = vec3(0.7, 0.8, 1.0);
		p.glow = (0.05 + twinkle * treble * 0.6 + transients.z * 0.25) * intensity * smoothstep(1.0, 2.5, length(point));
		p.edge = 0.0;
	} else {
		if (id > 1.0) {
			return hidden();
		}
		float y = id < 0.5 ? -1.2 : 5.6;
		p.point = vec3((vertex.x - 0.5) * 26.0, y + vertex.y * 0.2, -24.0);
		p.colour = mix(vec3(1.0, 0.95, 0.9), laser_colour(hash(bar * 1.7)), 0.4);
		p.glow = (kick() * 1.3 + bass * 0.25) * intensity;
		p.edge = vertex.y;
	}
	return p;
}

Pulse sub_pulse(vec3 vertex, float id, float count, vec4 custom) {
	Pulse p;
	float speed = 18.0;
	float u = (id + 0.5) / count;
	if (shape == 0) {
		float radius = 0.8 + u * 36.0;
		float angle = vertex.x * TAU;
		float side = smoothstep(-0.5, 0.5, sin(angle));
		float delay = radius / speed;
		float wave = bass_wave(delay, side);
		float frequency = 1.0 - abs(vertex.x * 2.0 - 1.0);
		float detail = shaped(mix(spectral_at(frequency, delay, 0.0), spectral_at(frequency, delay, 1.0), side));
		float height = FLOOR + (wave * 1.3 + detail * 0.35) * intensity * (1.0 - u * 0.4);
		float width = 0.02 + wave * 0.05;
		radius += vertex.y * width;
		p.point = vec3(sin(angle) * radius, height, -cos(angle) * radius);
		p.colour = ramp(wave * 0.85 + detail * 0.15, vec3(0.45, 0.03, 0.06), vec3(1.0, 0.35, 0.06), vec3(1.0, 0.9, 0.6));
		p.colour = mix(p.colour, rainbow(palette + 0.6), 0.15);
		p.glow = (0.05 + wave * 1.1 + detail * 0.25) * intensity * smoothstep(0.8, 2.0, radius) * (1.0 - smoothstep(26.0, 37.0, radius));
		p.edge = vertex.y;
	} else if (shape == 2) {
		float elevation = vertex.x * 1.35;
		float azimuth = u * TAU + elevation * (mod(id, 2.0) * 2.0 - 1.0) * 0.9 + spin * 0.05;
		float side = smoothstep(-0.5, 0.5, sin(azimuth));
		float frequency = vertex.x;
		float response = shaped(mix(spectral_at(frequency, 0.0, 0.0), spectral_at(frequency, 0.0, 1.0), side));
		float radius = 16.0 + response * 2.4 * intensity + bass_wave(16.0 / speed, side) * 1.5 * intensity;
		vec3 direction = vec3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation));
		vec3 tangent = vec3(cos(azimuth), 0.0, sin(azimuth));
		p.point = direction * radius + vec3(0.0, FLOOR, 0.0) + tangent * vertex.y * (0.03 + response * 0.06);
		p.colour = mix(vec3(0.1, 0.35, 1.0), vec3(0.6, 0.15, 1.0), frequency);
		p.glow = (0.008 + response * response * 0.8) * intensity * smoothstep(0.0, 0.08, vertex.x) * (1.0 - smoothstep(0.85, 1.0, vertex.x));
		p.edge = vertex.y;
	} else if (shape == 1) {
		if (id > 2600.0) {
			return hidden();
		}
		float radius = 1.5 + custom.x * 34.0;
		float angle = custom.w * TAU;
		float side = smoothstep(-0.5, 0.5, sin(angle));
		float wave = bass_wave(radius / speed, side);
		float lift = wave * 1.3 * intensity + wave * wave * 2.8 * custom.z * intensity;
		p.point = vec3(sin(angle) * radius, FLOOR + lift + 0.05, -cos(angle) * radius) + vertex * (0.015 + wave * 0.03);
		p.colour = vec3(1.0, 0.72, 0.3);
		p.glow = (wave * custom.z * 0.9 + treble * 0.08) * intensity * (1.0 - smoothstep(26.0, 35.0, radius));
		p.edge = 0.0;
	} else {
		if (id > 2.0) {
			return hidden();
		}
		float radius = beat_age * (22.0 + id * 5.0) + vertex.y * (0.12 + bass * 0.1);
		float angle = vertex.x * TAU;
		p.point = vec3(sin(angle) * radius, FLOOR + 0.04 + id * 0.6, -cos(angle) * radius);
		p.colour = id < 0.5 ? vec3(1.0, 0.85, 0.7) : vec3(0.6, 0.4, 1.0);
		p.glow = exp(-beat_age * 1.8) * (0.4 + bass) * (1.0 - id * 0.3) * intensity * smoothstep(0.5, 2.0, radius);
		p.edge = vertex.y;
	}
	return p;
}

const vec3 GALAXY = vec3(0.0, -3.2, -12.0);

vec3 galaxy_point(float radius, float angle, float height) {
	vec3 local = vec3(cos(angle) * radius, height, sin(angle) * radius);
	float tilt = 0.34;
	local = vec3(local.x, local.y * cos(tilt) - local.z * sin(tilt), local.y * sin(tilt) + local.z * cos(tilt));
	return GALAXY + local;
}

Pulse nebula(vec3 vertex, float id, float count, vec4 custom) {
	Pulse p;
	float u = (id + 0.5) / count;
	if (shape == 1) {
		float base = 0.8 + pow(custom.x, 0.7) * 33.0;
		float wave = bass_wave(base / 16.0, 0.5);
		float radius = base * (1.0 + kick() * 0.12 * intensity) + wave * 0.9 * intensity;
		float arm = floor(custom.z * 3.0) / 3.0 * TAU;
		float scatter = (hash(custom.w * 91.7) - 0.5) * (0.5 + custom.x * 0.6);
		float angle = arm + log(base) * 2.1 + scatter - spin * 1.4 / sqrt(base + 1.0);
		float bulge = (hash(custom.w * 13.3) - 0.5) * (0.35 + 3.0 * exp(-base * 0.18));
		float height = bulge + sin(angle * 2.0 + clock * 0.2) * 0.25 + wave * 0.6 * intensity * exp(-base * 0.05);
		float frequency = clamp(base / 34.0, 0.0, 1.0);
		float response = shaped(band_level(frequency));
		float twinkle = pow(max(0.0, sin(custom.y * 80.0 + clock * 2.4)), 6.0) * treble;
		p.point = galaxy_point(radius, angle, height) + vertex * (0.025 + response * 0.06 * intensity + twinkle * 0.03);
		p.colour = ramp(sweep(frequency * 0.6 + palette), vec3(1.0, 0.72, 0.35), vec3(0.95, 0.2, 0.75), vec3(0.2, 0.6, 1.0));
		p.glow = (0.06 + response * 1.5 + twinkle * 0.8 + kick() * 0.3) * intensity * smoothstep(1.2, 3.0, length(p.point));
		p.edge = 0.0;
	} else if (shape == 0) {
		float radius = 1.5 + u * 31.0;
		float response = shaped(band_level(u));
		float angle = vertex.x * TAU;
		radius += sin(angle * (3.0 + floor(u * 5.0)) + clock * 0.4) * 0.15 * response + vertex.y * (0.015 + response * 0.03);
		p.point = galaxy_point(radius, angle, 0.0);
		p.colour = ramp(sweep(u * 0.6 + palette), vec3(1.0, 0.72, 0.35), vec3(0.95, 0.2, 0.75), vec3(0.2, 0.6, 1.0));
		p.glow = response * response * 0.55 * intensity * smoothstep(1.5, 3.0, length(p.point));
		p.edge = vertex.y;
	} else if (shape == 2) {
		float strands = 6.0;
		if (id >= strands * 2.0) {
			return hidden();
		}
		float strand = mod(id, strands);
		float direction = id < strands ? 1.0 : -1.0;
		float h = vertex.x * 22.0;
		float delay = vertex.x * 1.6;
		float energy = bass_wave(delay, 0.5);
		float angle = h * 0.55 - spin * 3.0 * direction + strand / strands * TAU;
		float radius = 0.1 + vertex.x * 0.45 + energy * 0.35 * intensity;
		vec3 local = vec3(cos(angle) * radius, h * direction, sin(angle) * radius);
		p.point = GALAXY + local + vec3(cos(angle), 0.0, sin(angle)) * vertex.y * (0.03 + energy * 0.05);
		p.colour = mix(vec3(0.6, 0.85, 1.0), vec3(1.0, 1.0, 1.0), energy);
		p.glow = (0.02 + energy * 0.6) * intensity * pow(1.0 - vertex.x, 2.0) * smoothstep(0.0, 0.05, vertex.x);
		p.edge = vertex.y;
	} else {
		if (id > 1.0) {
			return hidden();
		}
		float radius = beat_age * (26.0 + id * 8.0) + vertex.y * (0.15 + bass * 0.12);
		p.point = galaxy_point(radius, vertex.x * TAU, id * 0.3);
		p.colour = vec3(0.85, 0.75, 1.0);
		p.glow = exp(-beat_age * 2.0) * (0.4 + bass) * intensity * (1.0 - id * 0.4);
		p.edge = vertex.y;
	}
	return p;
}

vec3 sphere_point(float spread, float around, float radius) {
	float polar = spread;
	return vec3(sin(polar) * cos(around), sin(polar) * sin(around), -cos(polar)) * radius;
}

Pulse kaleidosphere(vec3 vertex, float id, float count, vec4 custom) {
	Pulse p;
	float u = (id + 0.5) / count;
	float folds = 6.0;
	float breath = 1.0 + kick() * 0.06 * intensity;
	if (shape == 0) {
		float petals = folds * (1.0 + mod(id, 2.0));
		float response = shaped(band_level(u));
		float turn = spin * 0.35 / (1.0 + u * 2.0) * (mod(id, 2.0) * 2.0 - 1.0);
		float around = vertex.x * TAU;
		float spread = (0.08 + u * 2.3) * breath * (1.0 + response * 0.16 * intensity * sin(petals * around + turn));
		vec3 point = sphere_point(spread, around, 14.0);
		vec3 next = sphere_point(spread, around + 0.01, 14.0);
		point += billboard(point, normalize(next - point), vertex.y * (0.03 + response * 0.07));
		p.point = point;
		p.colour = rainbow(u * 0.8 + palette * 3.0 + clock * 0.01);
		p.glow = (0.03 + response * response * 1.1 + kick() * 0.15) * intensity;
		p.edge = vertex.y;
	} else if (shape == 2) {
		float around = u * TAU + spin * 0.1;
		float spread = vertex.x * 2.5;
		float response = shaped(spectral_at(vertex.x, vertex.x * 3.0, mod(id, 2.0)));
		vec3 point = sphere_point(spread * breath, around, 14.5);
		vec3 next = sphere_point(spread * breath + 0.01, around, 14.5);
		point += billboard(point, normalize(next - point), vertex.y * (0.025 + response * 0.05));
		p.point = point;
		p.colour = rainbow(vertex.x * 0.5 + palette * 3.0 + 0.5);
		p.glow = (0.01 + response * 0.6) * intensity * smoothstep(0.02, 0.1, vertex.x) * (1.0 - smoothstep(0.85, 1.0, vertex.x));
		p.edge = vertex.y;
	} else if (shape == 1) {
		float group = floor(id / folds);
		float copy = mod(id, folds);
		float base = hash(group * 0.731);
		float mirror = mod(copy, 2.0) * 2.0 - 1.0;
		float around = (copy + 0.5 + mirror * (base - 0.5) * 0.9) / folds * TAU + spin * 0.1;
		float spread = fract(hash(group * 1.913) + travel * 0.03) * 2.5;
		float frequency = spread / 2.5;
		float response = shaped(band_level(frequency));
		float radius = 9.0 + hash(group * 3.37) * 6.0;
		p.point = sphere_point(spread * breath, around, radius) + vertex * (0.02 + response * 0.05 * intensity);
		p.colour = rainbow(frequency * 0.7 + palette * 3.0 + 0.25);
		p.glow = (0.04 + response * 0.9 + transients.z * 0.5) * intensity * smoothstep(0.0, 0.2, spread) * (1.0 - smoothstep(2.2, 2.5, spread));
		p.edge = 0.0;
	} else {
		if (id > 1.0) {
			return hidden();
		}
		float spread = beat_age * (1.6 + id * 0.5);
		float around = vertex.x * TAU;
		vec3 point = sphere_point(spread, around, 13.5);
		vec3 next = sphere_point(spread, around + 0.01, 13.5);
		p.point = point + billboard(point, normalize(next - point), vertex.y * 0.09);
		p.colour = rainbow(palette * 3.0 + beat_count * 0.13);
		p.glow = exp(-beat_age * 2.2) * (0.4 + bass) * intensity * (1.0 - smoothstep(2.4, 3.0, spread));
		p.edge = vertex.y;
	}
	return p;
}

void vertex() {
	float id = float(INSTANCE_ID);
	float count = max(1.0, float(instance_count));
	Pulse p;
	if (pulse_style == 0) {
		p = warp(VERTEX, id, count, INSTANCE_CUSTOM);
	} else if (pulse_style == 1) {
		p = laser(VERTEX, id, count, INSTANCE_CUSTOM);
	} else if (pulse_style == 2) {
		p = sub_pulse(VERTEX, id, count, INSTANCE_CUSTOM);
	} else if (pulse_style == 3) {
		p = nebula(VERTEX, id, count, INSTANCE_CUSTOM);
	} else {
		p = kaleidosphere(VERTEX, id, count, INSTANCE_CUSTOM);
	}
	VERTEX = p.point;
	colour = p.colour;
	edge = p.edge;
	glow = p.glow * (1.0 - smoothstep(42.0, 60.0, length(p.point)));
}

void fragment() {
	float light = glow;
	if (shape != 1) {
		float aa = max(fwidth(edge), 0.001);
		float core = (1.0 - smoothstep(max(0.0, 0.2 - aa), 0.2 + aa, abs(edge))) * min(1.0, 0.4 / aa);
		float halo = pow(max(0.0, 1.0 - abs(edge)), 2.5);
		light *= halo * 0.22 + core;
	}
	light *= dim;
	vec3 hot = mix(colour, vec3(1.0), clamp(light - 0.9, 0.0, 0.5));
	ALBEDO = hot * light;
	EMISSION = hot * light * 0.6;
	ALPHA = 1.0;
}
