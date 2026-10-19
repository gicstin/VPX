shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D band_texture : filter_linear, repeat_disable;
uniform sampler2D field_texture : filter_linear, repeat_disable;
uniform float band_head = -1.0;
uniform float band_fraction = 0.0;
uniform float field_head = -1.0;
uniform float field_fraction = 0.0;
uniform float width = 0.0;
uniform int psyche_style = 0;
uniform int shape = 0;
uniform int instance_count = 64;
uniform float seed_count = 1600.0;
uniform float clock = 0.0;
uniform float travel = 0.0;
uniform float spin = 0.0;
uniform float beat_age = 4.0;
uniform float beat_count = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform vec3 transients = vec3(0.0);
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float motion = 0.6;
uniform float dim = 1.0;
uniform float arousal = 0.0;
uniform float tension = 0.0;
uniform float release = 0.0;
uniform float centroid = 0.5;
uniform float warmth = 0.4;
uniform float groove = 0.0;
uniform float beat_phase = 0.0;
uniform float bar_phase = 0.0;
uniform float breath = 0.5;

varying vec3 colour;
varying float glow;
varying float edge;

const float FLOOR = -1.6;
const float GOLDEN = 2.39996323;

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

Pulse make(vec3 point, vec3 tint, float light, float across) {
	Pulse p;
	p.point = point;
	p.colour = tint;
	p.glow = light;
	p.edge = across;
	return p;
}

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float gate(float value) {
	float x = max(0.0, value - 0.12) / 0.88;
	return 1.0 - exp(-pow(x, 1.35) * sensitivity * 1.5);
}

float kick() {
	return exp(-beat_age * 6.0);
}

float anticipation() {
	return smoothstep(0.7, 1.0, beat_phase) * groove;
}

vec4 ring_at(sampler2D tex, float u, float columns, float rows, float head, float fraction, float delay) {
	float index = head + min(0.0, fraction - delay * 45.0);
	float a = mod(floor(index), rows);
	float b = mod(a + 1.0, rows);
	float x = mix(0.5 / columns, (columns - 0.5) / columns, clamp(u, 0.0, 1.0));
	vec4 first = textureLod(tex, vec2(x, (a + 0.5) / rows), 0.0);
	vec4 second = textureLod(tex, vec2(x, (b + 0.5) / rows), 0.0);
	return mix(first, second, fract(index));
}

vec4 band_at(float band, float delay) {
	if (band_head < 0.0) {
		return vec4(0.0);
	}
	return ring_at(band_texture, band, 48.0, 192.0, band_head, band_fraction, delay);
}

vec4 field_at(float pan01, float delay) {
	if (field_head < 0.0) {
		return vec4(0.0, 0.5, 0.0, 0.0);
	}
	return ring_at(field_texture, pan01, 64.0, 192.0, field_head, field_fraction, delay);
}

float side_level(vec4 f, float side) {
	return gate(mix(f.z, f.w, clamp(side * 0.5 + 0.5, 0.0, 1.0)));
}

vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}

vec3 tone(float band) {
	band = clamp(band, 0.0, 1.0);
	float mood = smoothstep(0.0, 1.0, warmth);
	float h = mix(0.6, 0.02, mood) + band * 0.55;
	float s = (0.94 - band * 0.2) * (0.85 + arousal * 0.15);
	return hsv(h, s, 0.8 + band * 0.2);
}

float bloom() {
	return 1.0 + release * 1.2;
}

float beat(float amount) {
	return 1.0 + kick() * amount;
}

vec3 billboard(vec3 point, vec3 direction, float size) {
	vec3 side = cross(direction, point);
	float length_side = length(side);
	return length_side > 0.0001 ? side / length_side * size : vec3(0.0);
}

vec3 ribbon(vec3 point, vec3 next, float across) {
	return point + billboard(point, normalize(next - point + vec3(0.00001)), across);
}

vec3 sphere_dir(float u, float v) {
	float z = u * 2.0 - 1.0;
	float a = v * TAU;
	float r = sqrt(max(0.0, 1.0 - z * z));
	return vec3(r * cos(a), z, r * sin(a));
}

vec3 rotate_y(vec3 p, float a) {
	return vec3(p.x * cos(a) + p.z * sin(a), p.y, -p.x * sin(a) + p.z * cos(a));
}

vec3 horizon_point(float band, float along, float layer) {
	float az = (along - 0.5) * 3.4;
	float distance = 34.0 - band * 12.0 + layer * 1.5;
	float elevation = 0.03 + band * 0.4;
	vec4 f = band_at(band, layer * 0.1);
	float level = side_level(f, sin(az));
	float ridge = level * (0.8 + band * 0.6) * (0.7 + 0.3 * sin(az * 7.0 + band * 23.0 + clock * motion * 0.2)) * beat(0.5 * (1.0 - band));
	return vec3(sin(az) * distance, tan(elevation) * distance + ridge * 1.8 - 1.0 + release * 1.5 * band, -cos(az) * distance);
}

Pulse awe_horizon(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float layer = mod(id, 2.0);
		float band = floor(id / 2.0) / max(1.0, floor(count / 2.0) - 1.0);
		vec3 p = horizon_point(band, v.x, layer);
		vec3 next = horizon_point(band, v.x + 0.002, layer);
		vec4 f = band_at(band, layer * 0.1);
		float level = side_level(f, sin((v.x - 0.5) * 3.4));
		float fade = smoothstep(0.0, 0.1, v.x) * smoothstep(1.0, 0.9, v.x) / (1.0 + layer * 1.5);
		return make(ribbon(p, next, v.y * (0.04 + level * 0.1)), tone(band), (0.015 + level * 0.5 * beat(0.9 * (1.0 - band))) * bloom() * fade * intensity, v.y);
	} else if (shape == 1) {
		float band = c.x;
		vec4 f = band_at(band, 0.0);
		float az = (c.z - 0.5) * 3.6;
		float elevation = 0.25 + band * 0.95 + sin(az * 1.3 + c.w * 6.0) * 0.08;
		float radius = 46.0 - release * 8.0 * c.w;
		vec3 d = vec3(sin(az) * cos(elevation), sin(elevation), -cos(az) * cos(elevation));
		float level = side_level(f, sin(az));
		float twinkle = 0.5 + 0.5 * sin(clock * motion * (1.5 + c.w * 3.0) + c.y * 40.0);
		float size = 0.04 + (1.0 - band) * 0.05 + level * 0.08;
		return make(d * radius + v * size, mix(tone(band), vec3(1.0), 0.3), (0.015 + level * 0.45 * twinkle) * bloom() * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 6.0) {
			return hidden();
		}
		float angle = v.x * TAU;
		float radius = 8.0 + id * 0.6 + bass * 0.5 + release * 4.0 + breath * 0.5 * (1.0 - arousal);
		vec3 centre = vec3(0.0, 3.0, -40.0);
		vec3 p = centre + vec3(cos(angle) * radius, sin(angle) * radius, 0.0);
		vec3 radial = vec3(cos(angle), sin(angle), 0.0);
		float level = gate(band_at(fract(angle / TAU + 0.25), 0.0).y);
		return make(p + radial * v.y * (0.05 + kick() * 0.06), tone(0.5 + id / 12.0), (0.02 + level * 0.18 + kick() * 0.06) * bloom() * bloom() / (1.0 + id * 0.5) * intensity, v.y);
	} else {
		if (id >= 20.0) {
			return hidden();
		}
		float row = id / 20.0;
		float z = -4.0 - pow(row, 1.5) * 55.0;
		float x = (v.x - 0.5) * 140.0;
		float r = length(vec2(x, z + 4.0));
		float wave = sin(r * 0.35 - travel * 2.5) * exp(-r * 0.03) * (bass * 0.25 + kick() * 0.25);
		vec3 p = vec3(x, FLOOR - 0.6 + wave, z);
		return make(p + vec3(0.0, 0.0, v.y * 0.06), tone(0.05 + row * 0.2), (0.012 + bass * 0.04 + kick() * 0.03) * exp(-abs(x) * 0.03) * (1.0 - row * 0.6) * intensity, v.y);
	}
}

vec4 branch(float id) {
	int index = int(id) + 1;
	int depth = 0;
	for (int i = 0; i < 8; i++) {
		if (index >= (2 << i)) {
			depth = i + 1;
		}
	}
	int k = index - (1 << depth);
	return vec4(float(depth), float(k), 0.0, 0.0);
}

float canopy_growth() {
	return clamp(0.55 + arousal * 0.3 + tension * 0.3 + release * 0.4, 0.0, 1.0) * 8.0;
}

vec3 tree_walk(float depth_f, float k_f, out vec3 dir, out float len) {
	int depth = int(depth_f);
	int k = int(k_f);
	vec3 pos = vec3(0.0, FLOOR - 0.7, -9.0);
	dir = vec3(0.0, 1.0, 0.0);
	len = 2.9 + bass * 0.2;
	float spread = 0.46 + mids * 0.12 + tension * 0.1 + sin(clock * motion * 0.3) * 0.03 + release * 0.12;
	for (int i = 0; i < 8; i++) {
		if (i >= depth) {
			break;
		}
		pos += dir * len;
		int bit = (k >> (depth - 1 - i)) & 1;
		float side = bit == 0 ? -1.0 : 1.0;
		float a = side * spread;
		dir = normalize(vec3(dir.x * cos(a) - dir.y * sin(a), dir.x * sin(a) + dir.y * cos(a), dir.z));
		dir = rotate_y(dir, side * 0.35 + 0.2 * float(i));
		len *= 0.64;
	}
	return pos;
}

Pulse fractal_canopy(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		vec4 b = branch(id);
		vec3 dir;
		float len;
		vec3 start = tree_walk(b.x, b.y, dir, len);
		float band = clamp((b.x + hash(b.y + b.x * 17.0) * 0.9) / 7.5, 0.0, 1.0);
		vec4 f = band_at(band, b.x * 0.04);
		float side = start.x + dir.x * len * 0.5 > 0.0 ? 1.0 : -1.0;
		float level = side_level(f, side * min(1.0, b.x));
		float reveal = clamp(canopy_growth() - b.x, 0.0, 1.0);
		vec3 p = start + dir * len * v.x * reveal;
		vec3 next = p + dir * 0.01;
		float thickness = (0.14 * pow(0.7, b.x) + level * 0.14) * (1.0 - v.x * 0.3);
		float sap = fract(v.x * 0.5 + b.x * 0.5 - beat_age * 2.0);
		float pulse = exp(-sap * 8.0) * kick();
		return make(ribbon(p, next, v.y * thickness), tone(band), (0.03 + level * 0.7 + pulse * 0.35) * beat(1.0) * bloom() * step(0.001, reveal) * intensity, v.y);
	} else if (shape == 1) {
		vec4 b = branch(47.0 + floor(c.x * 48.0));
		vec3 dir;
		float len;
		float growth = canopy_growth();
		vec3 tip = tree_walk(b.x, b.y, dir, len) + dir * len * clamp(growth - b.x, 0.0, 1.0);
		float band = 0.6 + c.y * 0.4;
		vec4 f = band_at(band, 0.0);
		float level = side_level(f, tip.x > 0.0 ? 1.0 : -1.0);
		float fall = fract(c.z + clock * motion * 0.03) * release * 4.0;
		vec3 offset = sphere_dir(c.y, c.w) * (0.3 + c.z * 0.6) + vec3(sin(clock * motion * 0.7 + c.w * 20.0) * 0.1, -fall, 0.0);
		float grown = smoothstep(b.x - 0.5, b.x + 0.5, growth);
		return make(tip + offset + v * (0.018 + level * 0.035), mix(tone(band), vec3(1.0), 0.25), (0.01 + level * 0.4 + transients.z * 0.15) * grown * bloom() * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 10.0) {
			return hidden();
		}
		float angle = v.x * TAU;
		float age = beat_age * 1.6 + id * 0.35;
		float radius = 0.6 + age * 6.0;
		vec3 p = vec3(cos(angle) * radius, FLOOR - 0.68, sin(angle) * radius - 9.0);
		return make(p + vec3(cos(angle), 0.0, sin(angle)) * v.y * 0.04, tone(0.05), (0.03 + bass * 0.12) * exp(-age * 1.2) * intensity, v.y);
	}
	return hidden();
}

vec3 seed_point(float n, float total) {
	float y = 1.0 - 2.0 * (n + 0.5) / total;
	float r = sqrt(max(0.0, 1.0 - y * y));
	float a = n * GOLDEN + spin * 0.02 * motion;
	return vec3(cos(a) * r, -y, sin(a) * r);
}

Pulse phyllotaxis_bloom(vec3 v, float id, float count, vec4 c) {
	vec3 centre = vec3(0.0, 0.9, -10.0);
	float radius = 2.9 + kick() * 0.22 - anticipation() * 0.08 + breath * 0.15 * (1.0 - arousal);
	float seeds = seed_count;
	if (shape == 1) {
		if (id >= seeds) {
			return hidden();
		}
		vec3 n = seed_point(id, seeds);
		float band = n.y * 0.5 + 0.5;
		vec4 f = band_at(band, 0.0);
		float level = side_level(f, n.x * 1.4);
		float burst = release * (0.8 + c.x * 2.2);
		vec3 p = centre + n * (radius + level * 0.5 + burst);
		float size = (0.032 + (1.0 - band) * 0.025) * (1.0 + level * 1.8);
		float facing = 0.35 + 0.65 * smoothstep(-0.2, 0.6, n.z);
		return make(p + v * size, tone(band), (0.012 + level * 0.32 * beat(0.6)) * facing * bloom() * intensity, 0.0);
	} else if (shape == 0) {
		if (id >= 55.0) {
			return hidden();
		}
		float family = id < 21.0 ? 21.0 : 34.0;
		float start = id < 21.0 ? id : id - 21.0;
		float total = seeds;
		float step_index = v.x * (total - start - family) / family;
		float s = start + floor(step_index) * family;
		vec3 d = seed_point(s, total);
		vec3 dn = seed_point(s + family, total);
		vec3 n = normalize(mix(d, dn, fract(step_index)));
		vec3 p = centre + n * (radius + 0.02);
		float band = n.y * 0.5 + 0.5;
		vec4 f = band_at(band, 0.0);
		float level = side_level(f, n.x * 1.4);
		return make(ribbon(p, p + (dn - d) * 0.01, v.y * 0.014), tone(band), (0.01 + level * 0.14) * beat(0.5) * bloom() * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 7.0) {
			return hidden();
		}
		float angle = v.x * TAU;
		float band = id / 6.0;
		vec4 f = band_at(band, 0.0);
		float r = radius * (1.35 + band * 0.25) + release * 3.0;
		vec3 p = vec3(cos(angle) * r, (band - 0.5) * radius * 1.6, sin(angle) * r * 0.35);
		float level = side_level(f, cos(angle));
		return make(centre + p + vec3(cos(angle), 0.0, sin(angle)) * v.y * 0.025, tone(band), (0.012 + level * 0.2) * bloom() * intensity, v.y);
	} else {
		float angle = id / count * TAU;
		vec3 dir = vec3(cos(angle), sin(angle), 0.0);
		float band = sin(angle) * 0.5 + 0.5;
		float level = side_level(band_at(band, 0.0), cos(angle));
		float reach = radius * 1.15 + v.x * (1.2 + level * 2.5 + release * 5.0);
		vec3 p = centre + dir * reach + vec3(0.0, 0.0, -0.5);
		return make(p + vec3(-dir.y, dir.x, 0.0) * v.y * 0.03, tone(band), (0.008 + level * 0.1) * (1.0 - v.x) * bloom() * intensity, v.y);
	}
}

float tide_height(vec2 xz, float band, float side) {
	vec4 f = band_at(band, 0.0);
	float level = side_level(f, side);
	float r = length(xz - vec2(0.0, -14.0));
	float ripple = sin(r * 1.1 - beat_age * 9.0) * exp(-abs(r - beat_age * 7.5) * 0.5) * kick() * 0.6;
	float swell = sin(xz.x * 0.35 + clock * motion * 0.4 + band * 9.0) * (0.06 + breath * 0.12 * (1.0 - arousal));
	return FLOOR + level * (0.7 - band * 0.3) * (1.0 + release) + ripple + swell;
}

Pulse heartbeat_tide(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float row = id / max(1.0, count - 1.0);
		float z = -3.0 - pow(row, 1.35) * 40.0;
		float x = (v.x - 0.5) * (12.0 + row * 70.0);
		float band = row;
		float side = clamp(x / (5.0 + row * 30.0), -1.0, 1.0);
		vec3 p = vec3(x, tide_height(vec2(x, z), band, side), z);
		vec3 next = vec3(x + 0.05, tide_height(vec2(x + 0.05, z), band, side), z);
		float level = side_level(band_at(band, 0.0), side);
		float fade = smoothstep(0.0, 0.1, v.x) * smoothstep(1.0, 0.9, v.x) * (1.0 - row * 0.5);
		float crest = smoothstep(FLOOR + 0.1, FLOOR + 0.6, p.y);
		return make(ribbon(p, next, v.y * (0.02 + row * 0.05)), mix(tone(band), vec3(1.0), crest * 0.3), (0.012 + level * 0.4 * beat(0.8 * (1.0 - band))) * fade * bloom() * intensity, v.y);
	} else if (shape == 1) {
		float row = c.y;
		float z = -3.0 - pow(row, 1.35) * 40.0;
		float x = (c.z - 0.5) * (12.0 + row * 70.0);
		float side = clamp(x / (5.0 + row * 30.0), -1.0, 1.0);
		float band = clamp(row + 0.2, 0.0, 1.0);
		float level = side_level(band_at(band, 0.0), side);
		float glint = pow(0.5 + 0.5 * sin(clock * motion * (2.0 + c.w * 4.0) + c.x * 50.0), 8.0);
		vec3 p = vec3(x, tide_height(vec2(x, z), row, side) + 0.05 + release * c.w * 2.0, z);
		return make(p + v * (0.025 + row * 0.07), mix(tone(band), vec3(1.0), 0.4), (level * glint * 0.6 + treble * glint * 0.08) * bloom() * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 24.0) {
			return hidden();
		}
		float angle = v.x * TAU;
		float r = 0.4 + id * 0.17 + breath * 0.4 * (1.0 - arousal) + kick() * 0.25 + release * 1.0;
		vec3 p = vec3(cos(angle) * r, 6.0 + sin(angle) * r, -62.0);
		float level = gate(band_at(0.12, 0.0).y);
		return make(p + vec3(cos(angle), sin(angle), 0.0) * v.y * 0.08, tone(0.35 + id / 48.0), (0.03 + level * 0.08 + kick() * 0.04) * bloom() * (1.0 - id / 24.0) * intensity, v.y);
	} else {
		if (id >= 4.0) {
			return hidden();
		}
		float angle = v.x * TAU;
		float age = beat_age + id * 0.5;
		float r = age * 7.5;
		vec3 p = vec3(cos(angle) * r, FLOOR + 0.02, sin(angle) * r - 14.0);
		float fade = exp(-age * 1.4);
		return make(p + vec3(cos(angle), 0.0, sin(angle)) * v.y * (0.05 + age * 0.04), tone(0.08), (0.08 + bass * 0.25) * fade * intensity, v.y);
	}
}

Pulse frisson_aurora(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float pan = id / max(1.0, count - 1.0);
		float az = (pan - 0.5) * 2.4;
		vec4 f = field_at(pan, 0.0);
		float energy = 1.0 - exp(-f.x * sensitivity * 0.6);
		float distance = 22.0 + sin(pan * 9.0 + clock * motion * 0.1) * 2.0;
		float sway = sin(pan * 14.0 + clock * motion * 0.25 + v.x * 2.0) * 0.05 + release * sin(pan * 30.0 - clock * motion * 4.0 + v.x * 3.0) * 0.06;
		float a = az + sway;
		float h = v.x;
		float peak = 0.12 + f.y * 0.75;
		float lift = (h - peak) * 3.0;
		float profile = exp(-lift * lift) + exp(-h * 7.0) * 0.4;
		vec3 base = vec3(sin(a) * distance, -1.2, -cos(a) * distance);
		vec3 p = base + vec3(0.0, h * 17.0, 0.0);
		vec3 tangent = vec3(cos(a), 0.0, sin(a));
		float shimmer = 0.7 + 0.3 * sin(h * 40.0 - clock * motion * 3.0 + pan * 60.0) * (0.5 + tension);
		float light = (0.004 + energy * 0.3 * shimmer * beat(0.5)) * profile * bloom();
		return make(p + tangent * v.y * 0.3, tone(clamp(h * 0.8 + f.y * 0.4, 0.0, 1.0)), light * intensity, v.y * 0.25);
	} else if (shape == 1) {
		float pan = c.z;
		float az = (pan - 0.5) * 2.4;
		vec4 f = field_at(pan, 0.0);
		float energy = 1.0 - exp(-f.x * sensitivity * 0.6);
		float h = fract(c.y - clock * motion * (0.02 + c.w * 0.04) + release * c.x * 0.5);
		float distance = 19.0 + c.x * 5.0;
		vec3 p = vec3(sin(az) * distance, -1.2 + h * 16.0, -cos(az) * distance);
		float level = gate(band_at(h, 0.0).y);
		return make(p + v * (0.035 + level * 0.04), mix(tone(h), vec3(1.0), 0.4), (energy * level * 0.35 + transients.z * 0.08 * c.w * energy) * smoothstep(0.0, 0.1, h) * (1.0 - h) * bloom() * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 6.0) {
			return hidden();
		}
		float angle = (v.x - 0.5) * 2.6;
		float r = 13.0 + id * 2.0;
		vec4 f = field_at(sin(angle) * 0.5 + 0.5, 0.0);
		float level = gate(band_at(0.06 + id * 0.03, 0.0).y);
		vec3 p = vec3(sin(angle) * r, FLOOR + 0.05 + level * 0.25 * kick(), -cos(angle) * r);
		return make(p + vec3(0.0, v.y * (0.04 + level * 0.1), 0.0), tone(0.05), (0.012 + level * 0.14 * beat(1.0)) * (1.0 - abs(v.x - 0.5) * 1.6) * intensity, v.y);
	}
	return hidden();
}

vec3 orb_centre(float band) {
	vec4 f = band_at(band, 0.0);
	float x = f.x * 5.5 + sin(band * 31.0) * 0.35;
	float y = -1.3 + band * 5.4;
	float z = -9.0 + cos(band * 23.0) * 0.8;
	return vec3(x, y, z);
}

float orb_size(float band, float level) {
	return (0.85 - band * 0.6) * (0.25 + level * 1.0);
}

Pulse synesthesia(vec3 v, float id, float count, vec4 c) {
	if (shape == 1) {
		float band = floor(c.x * 48.0) / 47.0;
		vec4 f = band_at(band, 0.0);
		float level = gate(f.y);
		vec3 centre = orb_centre(band);
		float size = orb_size(band, level) * beat(0.25 * (1.0 - band));
		vec3 d = sphere_dir(c.z, c.w + spin * 0.01 * motion);
		vec3 p = centre + d * size * (0.85 + 0.15 * sin(clock * motion * 2.0 + c.y * 30.0)) + d * release * 2.0 * c.y;
		return make(p + v * (0.028 + (1.0 - band) * 0.022), tone(band), (0.008 + level * 0.5) * beat(0.9) * bloom() * intensity, 0.0);
	} else if (shape == 0) {
		if (id >= 47.0) {
			return hidden();
		}
		float band = id / 47.0;
		float next_band = (id + 1.0) / 47.0;
		vec3 a = orb_centre(band);
		vec3 b = orb_centre(next_band);
		float la = gate(band_at(band, 0.0).y);
		float lb = gate(band_at(next_band, 0.0).y);
		vec3 bow = vec3(0.0, 0.0, 0.3 * sin(v.x * PI));
		vec3 p = mix(a, b, v.x) + bow;
		vec3 n = mix(a, b, v.x + 0.01) + bow;
		float link = sqrt(la * lb);
		return make(ribbon(p, n, v.y * (0.01 + link * 0.035)), tone(mix(band, next_band, v.x)), (0.004 + link * 0.35) * beat(0.4) * bloom() * intensity, v.y);
	} else if (shape == 2) {
		float band = id / max(1.0, count - 1.0);
		vec4 f = band_at(band, 0.0);
		float level = gate(f.y);
		vec3 centre = orb_centre(band);
		float angle = v.x * TAU;
		vec3 radial = vec3(cos(angle), sin(angle), 0.0);
		float radius = orb_size(band, level) * (1.2 + kick() * 0.15);
		vec3 p = centre + radial * (radius + v.y * (0.04 + level * 0.09));
		return make(p, tone(band), (0.008 + level * 0.5) * beat(0.6) * bloom() * intensity, v.y);
	} else {
		float band = id / max(1.0, count - 1.0);
		vec4 f = band_at(band, 0.0);
		float level = gate(f.y);
		vec3 centre = orb_centre(band);
		float angle = v.x * TAU;
		float r = orb_size(band, level) * 1.4;
		vec3 p = vec3(centre.x + cos(angle) * r, FLOOR, centre.z + sin(angle) * r);
		return make(p + vec3(cos(angle), 0.0, sin(angle)) * v.y * 0.015, tone(band), level * 0.06 * intensity, v.y);
	}
}

vec3 lattice_point(float column, float row, float layer, float columns, float rows) {
	float band = row / (rows - 1.0);
	float side = column / (columns - 1.0) * 2.0 - 1.0;
	vec3 base = vec3(side * 7.0, -1.2 + row * 0.5, -6.0 - layer * 2.5);
	float r = length(base.xz - vec2(0.0, -6.0));
	float wave_age = max(0.0, beat_age - r * 0.03);
	float bounce = exp(-wave_age * 7.0) * (0.1 + (mod(beat_count, 4.0) < 0.5 ? 0.2 : 0.0)) * (1.0 + release);
	float level = side_level(band_at(band, layer * 0.06), side);
	return vec3(base.x * (1.0 - anticipation() * 0.04), base.y + bounce + level * 0.2, base.z);
}

Pulse groove_lattice(vec3 v, float id, float count, vec4 c) {
	float columns = 24.0;
	float rows = 12.0;
	if (shape == 1) {
		if (id >= columns * rows * 6.0) {
			return hidden();
		}
		float column = mod(id, columns);
		float row = mod(floor(id / columns), rows);
		float layer = floor(id / (columns * rows));
		float band = row / (rows - 1.0);
		float side = column / (columns - 1.0) * 2.0 - 1.0;
		vec3 p = lattice_point(column, row, layer, columns, rows);
		float level = side_level(band_at(band, layer * 0.06), side);
		float r = length(vec2(side * 7.0, layer * 2.5));
		float bounce = exp(-max(0.0, beat_age - r * 0.03) * 7.0);
		float phrase = mod(floor(beat_count / 16.0), 4.0) * 0.06;
		return make(p + v * (0.038 + level * 0.06), tone(fract(band + phrase)), (0.012 + level * 0.5 + bounce * 0.25) * bloom() / (1.0 + layer * 0.35) * intensity, 0.0);
	} else if (shape == 0) {
		if (id >= rows * 6.0) {
			return hidden();
		}
		float row = mod(id, rows);
		float layer = floor(id / rows);
		float band = row / (rows - 1.0);
		float column = v.x * (columns - 1.0);
		vec3 p = lattice_point(column, row, layer, columns, rows);
		float level = side_level(band_at(band, layer * 0.06), v.x * 2.0 - 1.0);
		return make(p + vec3(0.0, v.y * (0.01 + level * 0.02), 0.0), tone(band), (0.004 + level * 0.18 * beat(0.6)) * bloom() / (1.0 + layer * 0.4) * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 6.0) {
			return hidden();
		}
		float angle = v.x * TAU;
		float age = beat_age * 4.0 + id * 0.25;
		float r = 1.0 + age * 4.0;
		vec3 p = vec3(cos(angle) * r, FLOOR + 0.05, sin(angle) * r - 8.0);
		float bar = mod(beat_count, 4.0) < 0.5 ? 1.0 : 0.35;
		return make(p + vec3(cos(angle), 0.0, sin(angle)) * v.y * 0.04, tone(0.1), (0.04 + bass * 0.15) * bar * exp(-age * 0.8) * intensity, v.y);
	}
	return hidden();
}

float vortex_angle(float band, float along) {
	return along * TAU + spin * (0.05 + tension * 0.25) * motion + band * (2.0 + tension * 6.0);
}

float vortex_level(float band, float along) {
	return side_level(band_at(band, along * 0.4), -cos(vortex_angle(band, along)));
}

vec3 vortex_point(float band, float along, float channel) {
	float a = vortex_angle(band, along);
	float level = vortex_level(band, along);
	float radius = ((3.6 - band * 2.7) * (1.0 - tension * 0.3 + release * 0.9) + level * 0.5 * beat(0.6)) * (1.0 - channel * 0.06);
	float y = -1.2 + band * 5.4 + sin(a * 3.0 + clock * motion) * 0.04;
	return vec3(-cos(a) * radius, y, sin(a) * radius - 10.0);
}

Pulse tension_vortex(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float band = floor(id / 2.0) / max(1.0, floor(count / 2.0) - 1.0);
		float channel = mod(id, 2.0);
		vec3 p = vortex_point(band, v.x, channel);
		vec3 n = vortex_point(band, v.x + 0.002, channel);
		float level = vortex_level(band, v.x);
		float charge = tension * (0.5 + 0.5 * sin(v.x * 40.0 - clock * motion * 6.0));
		return make(ribbon(p, n, v.y * (0.025 + level * 0.055)), tone(band), (0.008 + level * 0.32 * beat(0.6) + charge * 0.08) * bloom() / (1.0 + channel * 1.5) * intensity, v.y);
	} else if (shape == 1) {
		float band = c.x;
		float orbit = c.z * TAU + spin * (0.2 + tension * 0.8) * motion * (0.5 + c.w);
		float r = (4.0 + c.y * 3.5) * (1.0 - tension * 0.45) + release * (3.0 + c.w * 5.0);
		vec3 p = vec3(-cos(orbit) * r, -1.2 + band * 5.4 + (c.w - 0.5) * 1.2, sin(orbit) * r - 10.0);
		float level = side_level(band_at(band, 0.0), -cos(orbit));
		return make(p + v * (0.016 + level * 0.025), mix(tone(band), vec3(1.0), 0.25), (0.006 + level * 0.25 + tension * 0.05) * bloom() * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 5.0) {
			return hidden();
		}
		float angle = v.x * TAU;
		float age = beat_age * 3.0 + id * 0.2;
		float r = 3.8 + age * 3.0;
		vec3 p = vec3(cos(angle) * r, FLOOR + 0.25, sin(angle) * r - 10.0);
		return make(p + vec3(cos(angle), 0.0, sin(angle)) * v.y * 0.04, tone(0.05), (0.05 + bass * 0.2) * exp(-age * 0.9) * intensity, v.y);
	}
	return hidden();
}

void vertex() {
	float id = float(INSTANCE_ID);
	float count = max(1.0, float(instance_count));
	vec4 c = INSTANCE_CUSTOM;
	Pulse p;
	if (id >= count) {
		p = hidden();
	} else if (psyche_style == 0) {
		p = awe_horizon(VERTEX, id, count, c);
	} else if (psyche_style == 1) {
		p = fractal_canopy(VERTEX, id, count, c);
	} else if (psyche_style == 2) {
		p = phyllotaxis_bloom(VERTEX, id, count, c);
	} else if (psyche_style == 3) {
		p = heartbeat_tide(VERTEX, id, count, c);
	} else if (psyche_style == 4) {
		p = frisson_aurora(VERTEX, id, count, c);
	} else if (psyche_style == 5) {
		p = synesthesia(VERTEX, id, count, c);
	} else if (psyche_style == 6) {
		p = groove_lattice(VERTEX, id, count, c);
	} else if (psyche_style == 7) {
		p = tension_vortex(VERTEX, id, count, c);
	} else {
		p = hidden();
	}
	VERTEX = p.point;
	colour = p.colour;
	edge = p.edge;
	glow = p.glow * (1.0 - smoothstep(48.0, 70.0, length(p.point))) * smoothstep(0.35, 1.0, length(p.point));
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
