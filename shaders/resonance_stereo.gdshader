shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D correlation_texture : filter_linear, repeat_disable;
uniform float correlation_head = -1.0;
uniform float correlation_fraction = 0.0;
uniform sampler2D band_texture : filter_linear, repeat_disable;
uniform sampler2D field_texture : filter_linear, repeat_disable;
uniform sampler2D source_texture : filter_nearest, repeat_disable;
uniform sampler2D scope_texture : filter_linear, repeat_disable;
uniform float band_head = -1.0;
uniform float band_fraction = 0.0;
uniform float field_head = -1.0;
uniform float field_fraction = 0.0;
uniform float source_head = -1.0;
uniform float source_fraction = 0.0;
uniform float scope_head = 0.0;
uniform vec4 sources[8];
uniform vec4 source_info[8];
uniform vec4 source_bursts[8];
uniform vec2 channel_balance = vec2(0.0);
uniform float balance = 0.0;
uniform float width = 0.0;
uniform float correlation = 1.0;
uniform int stereo_style = 0;
uniform int shape = 0;
uniform int instance_count = 64;
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
uniform float palette = 0.0;
uniform float dim = 1.0;

varying vec3 colour;
varying float glow;
varying float edge;

const float FLOOR = -1.6;

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

float shaped(float value) {
	return 1.0 - exp(-pow(max(0.0, value), 1.35) * sensitivity * 1.5);
}

float gate(float value) {
	return shaped(max(0.0, value - 0.12) / 0.88);
}

float energy(float value) {
	return 1.0 - exp(-max(0.0, value) * sensitivity * 0.45);
}

float gaussian(float x) {
	return exp(-x * x);
}

float kick() {
	return exp(-beat_age * 5.0);
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
	return ring_at(band_texture, band, 48.0, 192.0, band_head, band_fraction, delay);
}

vec4 field_at(float pan01, float delay) {
	return ring_at(field_texture, pan01, 64.0, 192.0, field_head, field_fraction, delay);
}

vec4 trail(float slot, float delay) {
	float index = source_head + min(0.0, source_fraction - delay * 45.0);
	float row = mod(floor(index), 64.0);
	return textureLod(source_texture, vec2((slot + 0.5) / 8.0, (row + 0.5) / 64.0), 0.0);
}

float scope_value(float frame, float channel, float along) {
	float row = mod(scope_head - frame, 48.0) * 2.0 + channel;
	return textureLod(scope_texture, vec2(mix(0.5 / 256.0, 255.5 / 256.0, clamp(along, 0.0, 1.0)), (row + 0.5) / 96.0), 0.0).r;
}

vec2 scope_point(float frame, float along) {
	float left = scope_value(frame, 0.0, along);
	float right = scope_value(frame, 1.0, along);
	return vec2(right - left, right + left) * 0.7071;
}

vec3 hue(float h) {
	vec3 c = 0.5 + 0.5 * cos(TAU * (h + vec3(0.0, 0.33, 0.67)));
	return clamp((c - 0.5) * 1.35 + 0.55, 0.0, 1.0);
}

vec3 band_colour(float band) {
	band = clamp(band, 0.0, 1.0);
	vec3 low = vec3(1.0, 0.22, 0.1);
	vec3 mid = vec3(0.15, 1.0, 0.55);
	vec3 high = vec3(0.4, 0.3, 1.0);
	vec3 c = band < 0.5 ? mix(low, mid, band * 2.0) : mix(mid, high, band * 2.0 - 1.0);
	return mix(c, hue(palette * 2.0 + band * 0.5), 0.2);
}

vec3 dir_az(float az) {
	return vec3(sin(az), 0.0, -cos(az));
}

vec3 dome(float az, float el) {
	return vec3(sin(az) * cos(el), sin(el), -cos(az) * cos(el));
}

vec3 billboard(vec3 point, vec3 direction, float size) {
	vec3 side = cross(direction, point);
	float length_side = length(side);
	return length_side > 0.0001 ? side / length_side * size : vec3(0.0);
}

vec3 ribbon(vec3 point, vec3 next, float across) {
	return point + billboard(point, normalize(next - point + vec3(0.00001)), across);
}

vec3 facing_circle(vec3 centre, float radius, float angle) {
	vec3 forward = normalize(centre);
	vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)) + vec3(0.00001, 0.0, 0.0));
	vec3 up = cross(right, forward);
	return centre + (right * cos(angle) + up * sin(angle)) * radius;
}

vec3 floor_circle(vec3 centre, float radius, float angle) {
	return centre + vec3(cos(angle), 0.0, sin(angle)) * radius;
}

vec3 stage_point(vec4 s, float spread, float distance, float low, float high) {
	return dir_az(s.x * spread) * distance + vec3(0.0, mix(low, high, s.y), 0.0);
}

float slot_count(float count) {
	return max(1.0, floor(count / 8.0));
}

Pulse source_stage(vec3 v, float id, float count, vec4 c) {
	float slot = mod(id, 8.0);
	int i = int(slot);
	vec4 s = sources[i];
	if (s.z < 0.01) {
		return hidden();
	}
	float level = gate(s.z);
	vec3 centre = stage_point(s, 1.0, 9.0, -0.6, 3.4);
	vec3 tint = hue(source_info[i].x);
	if (shape == 1) {
		float z = c.z * 2.0 - 1.0;
		float a = c.w * TAU + spin * 0.4;
		vec3 d = vec3(sqrt(1.0 - z * z) * cos(a), z, sqrt(1.0 - z * z) * sin(a));
		float shimmer = gate(band_at(s.y + (c.x - 0.5) * max(0.05, s.w), 0.0).y);
		float radius = (0.12 + level * 0.55 * intensity) * (0.75 + shimmer * 0.4 + source_info[i].z * 0.3);
		return make(centre + d * radius + v * 0.018, mix(tint, vec3(1.0), shimmer * 0.3), (0.12 + level * 0.9 + source_info[i].z * 0.6) * intensity, 0.0);
	} else if (shape == 0) {
		float k = floor(id / 8.0);
		float total = slot_count(count);
		float a = k / total * TAU + spin * 0.25;
		vec3 top = vec3(centre.x * 0.9, 7.0, centre.z * 0.9);
		vec3 bottom = floor_circle(vec3(centre.x, FLOOR, centre.z), 0.5 + level * 0.9, a);
		vec3 point = mix(top, bottom, v.x);
		return make(point + billboard(point, normalize(bottom - top), v.y * 0.03), tint, level * 0.14 * intensity * (0.4 + v.x * 0.6), v.y);
	} else if (shape == 2) {
		float k = floor(id / 8.0);
		float total = slot_count(count);
		float radius = (0.35 + (k + fract(clock * 0.4)) * 0.3) * (1.0 + level * 0.5);
		vec3 point = floor_circle(vec3(centre.x, FLOOR + 0.01, centre.z), radius + v.y * 0.02, v.x * TAU);
		return make(point, tint, level * 0.5 * intensity * (1.0 - (k + fract(clock * 0.4)) / total), v.y);
	}
	if (id > 0.5) {
		return hidden();
	}
	vec3 point = dir_az((v.x * 2.0 - 1.0) * 1.0) * 9.0 + vec3(0.0, FLOOR, 0.0);
	return make(point + vec3(0.0, v.y * 0.04, 0.0), vec3(0.7, 0.8, 1.0), (0.06 + bass * 0.3) * intensity, v.y);
}

Pulse vectorscope(vec3 v, float id, float count, vec4 c) {
	vec3 centre = vec3(0.0, 0.5, -7.0);
	float scale = 3.0;
	if (shape == 0) {
		float frame = id;
		if (frame > 23.0) {
			return hidden();
		}
		float zoom = 1.0 + frame * 0.045;
		vec2 a = scope_point(frame, v.x) * scale * zoom;
		vec2 b = scope_point(frame, v.x + 1.0 / 255.0) * scale * zoom;
		vec2 t = normalize(b - a + vec2(0.00001, 0.0));
		vec2 n = vec2(-t.y, t.x);
		vec3 point = centre + vec3(a + n * v.y * 0.02, -frame * 0.05);
		vec3 tint = mix(vec3(0.3, 1.0, 0.55), vec3(0.2, 0.6, 1.0), frame / 23.0);
		return make(point, mix(tint, hue(palette * 2.0), 0.15), 0.85 / (1.0 + frame * 0.5) * intensity, v.y);
	} else if (shape == 1) {
		float frame = floor(id / 256.0);
		if (frame > 5.0) {
			return hidden();
		}
		float along = mod(id, 256.0) / 255.0;
		vec2 a = scope_point(frame, along) * scale * (1.0 + frame * 0.045);
		return make(centre + vec3(a, 0.02) + v * 0.016, vec3(0.7, 1.0, 0.8), (0.25 + treble * 0.4) / (1.0 + frame) * intensity, 0.0);
	} else if (shape == 2) {
		vec3 tint = vec3(0.2, 0.5, 0.3);
		float light = 0.05 * intensity;
		if (id < 0.5) {
			vec3 point = centre + vec3(cos(v.x * TAU), sin(v.x * TAU), 0.0) * (scale + v.y * 0.015);
			return make(point, tint, light, v.y);
		}
		vec2 axis;
		if (id < 1.5) {
			axis = normalize(vec2(-1.0, 1.0));
		} else if (id < 2.5) {
			axis = normalize(vec2(1.0, 1.0));
		} else if (id < 3.5) {
			axis = vec2(0.0, 1.0);
		} else if (id < 4.5) {
			axis = vec2(1.0, 0.0);
		} else {
			return hidden();
		}
		vec2 n = vec2(-axis.y, axis.x);
		vec3 point = centre + vec3(axis * (v.x * 2.0 - 1.0) * scale + n * v.y * 0.012, 0.0);
		return make(point, id < 2.5 ? vec3(0.3, 0.6, 1.0) : tint, light * (id < 2.5 ? 1.6 : 1.0), v.y);
	}
	if (id < 1.5) {
		float side = id < 0.5 ? -1.0 : 1.0;
		float level = shaped(id < 0.5 ? channel_balance.x : channel_balance.y);
		vec3 point = centre + vec3(side * (scale + 0.8) + v.y * 0.08, -scale + v.x * level * scale * 2.0, 0.0);
		return make(point, id < 0.5 ? vec3(0.2, 0.7, 1.0) : vec3(1.0, 0.35, 0.3), 0.6 * intensity, v.y);
	} else if (id < 2.5) {
		vec3 point = centre + vec3(balance * scale + v.y * 0.05, -scale - 0.4 + v.x * 0.4, 0.0);
		return make(point, vec3(1.0, 0.9, 0.5), 0.8 * intensity, v.y);
	}
	return hidden();
}

Pulse lissajous_tunnel(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float frame = id;
		if (frame > 47.0) {
			return hidden();
		}
		float z = -4.0 - frame * 0.62;
		float angle = frame * 0.07 + spin * 0.12;
		mat2 turn = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
		float scale = 1.6 + frame * 0.08;
		vec2 a = turn * scope_point(frame, v.x) * scale;
		vec2 b = turn * scope_point(frame, v.x + 1.0 / 255.0) * scale;
		vec2 t = normalize(b - a + vec2(0.00001, 0.0));
		vec3 point = vec3(a + vec2(-t.y, t.x) * v.y * 0.025, z) + vec3(0.0, 0.3, 0.0);
		float fade = (1.0 - smoothstep(30.0, 47.0, frame));
		return make(point, hue(frame * 0.02 + palette * 2.0 + 0.5), (0.7 - frame * 0.008) * fade * intensity, v.y);
	} else if (shape == 1) {
		float frame = floor(c.z * 48.0);
		vec2 a = scope_point(frame, c.w) * (1.6 + frame * 0.08);
		float angle = frame * 0.07 + spin * 0.12;
		a = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * a;
		return make(vec3(a, -4.0 - frame * 0.62) + vec3(0.0, 0.3, 0.0) + v * 0.02, vec3(1.0), (0.04 + treble * 0.3) * intensity * (1.0 - smoothstep(20.0, 47.0, frame)), 0.0);
	}
	return hidden();
}

vec3 star(float pan, float band, float radius) {
	return dome(pan * 1.25, -0.08 + band * 0.85) * radius;
}

Pulse constellation(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float k = id;
		if (k > 11.0) {
			return hidden();
		}
		float delay = k * 0.12;
		vec4 a = band_at(v.x, delay);
		vec4 b = band_at(v.x + 0.01, delay);
		vec3 point = star(a.x, v.x, 18.0 - k * 0.3);
		vec3 next = star(b.x, v.x + 0.01, 18.0 - k * 0.3);
		float level = gate(a.y);
		return make(ribbon(point, next, v.y * 0.03), band_colour(v.x), level * level * 0.7 * (1.0 - k / 12.0) * intensity, v.y);
	} else if (shape == 1) {
		if (id < 960.0) {
			float band = mod(id, 48.0) / 47.0;
			float k = floor(id / 48.0);
			vec4 a = band_at(band, k * 0.05);
			float level = gate(a.y);
			return make(star(a.x, band, 18.0) + v * (0.03 + level * 0.08), mix(band_colour(band), vec3(1.0), 0.3), level * level * (1.0 - k / 20.0) * 1.2 * intensity, 0.0);
		}
		float z = c.z * 2.0 - 1.0;
		float a = c.w * TAU;
		vec3 d = vec3(sqrt(1.0 - z * z) * cos(a), z, sqrt(1.0 - z * z) * sin(a));
		float twinkle = pow(max(0.0, sin(c.x * 50.0 + clock * 2.0)), 8.0);
		return make(d * 40.0 + v * 0.05, vec3(0.8, 0.85, 1.0), (0.03 + twinkle * treble * 0.4) * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 7.5) {
			return hidden();
		}
		int i = int(id);
		vec4 s = sources[i];
		if (s.z < 0.01) {
			return hidden();
		}
		float level = gate(s.z);
		vec3 point = facing_circle(star(s.x, s.y, 17.5), 0.5 + level * 0.9 + v.y * 0.03, v.x * TAU);
		return make(point, hue(source_info[i].x), level * 0.7 * intensity, v.y);
	}
	return hidden();
}

float terrain_height(float x01, float delay) {
	return energy(field_at(x01, delay).x);
}

Pulse terrain(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float delay = id / count * 3.6;
		float z = -2.5 - delay * 9.0;
		vec4 f = field_at(v.x, delay);
		float h = energy(f.x);
		vec3 point = vec3((v.x * 2.0 - 1.0) * 11.0, FLOOR + h * 2.8 * intensity + v.y * 0.025, z);
		float fade = (1.0 - smoothstep(2.6, 3.6, delay));
		return make(point, band_colour(f.y), (0.03 + h * 0.9) * fade * intensity, v.y);
	} else if (shape == 2) {
		float x = (id + 0.5) / count;
		float delay = v.x * 3.6;
		float h = terrain_height(x, delay);
		vec3 point = vec3((x * 2.0 - 1.0) * 11.0 + v.y * 0.02, FLOOR + h * 2.8 * intensity, -2.5 - delay * 9.0);
		return make(point, band_colour(field_at(x, delay).y), (0.015 + h * 0.4) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 1500.0) {
			return hidden();
		}
		float delay = c.z * 0.4;
		vec4 f = field_at(c.x, delay);
		float h = energy(f.x);
		float rise = fract(c.w + clock * 0.3);
		vec3 point = vec3((c.x * 2.0 - 1.0) * 11.0, FLOOR + h * 2.8 * intensity + rise * h * 1.5, -2.5 - delay * 9.0);
		return make(point + v * 0.02, mix(band_colour(f.y), vec3(1.0), 0.4), h * h * (1.0 - rise) * 0.8 * intensity, 0.0);
	}
	return hidden();
}

vec3 burst_origin(vec4 b) {
	return dir_az(b.x * 1.2) * 16.0 + vec3(0.0, 2.0 + b.y * 7.0, 0.0);
}

vec3 burst_path(vec3 origin, vec3 direction, float speed, float age) {
	return origin + direction * speed * (1.0 - exp(-age * 1.6)) / 1.6 + vec3(0.0, -0.9 * age * age, 0.0);
}

vec3 sphere_dir(float a, float b) {
	float z = a * 2.0 - 1.0;
	float angle = b * TAU;
	return vec3(sqrt(1.0 - z * z) * cos(angle), z, sqrt(1.0 - z * z) * sin(angle));
}

Pulse fireworks(vec3 v, float id, float count, vec4 c) {
	float slot = mod(id, 8.0);
	int i = int(slot);
	vec4 b = source_bursts[i];
	float age = b.z;
	if (age > 3.2 || shape == 2) {
		return hidden();
	}
	vec3 origin = burst_origin(b);
	vec3 tint = hue(source_info[i].x);
	float strength = 0.4 + gate(b.w);
	float life = 1.0 - smoothstep(0.6, 3.0, age);
	if (shape == 1) {
		vec3 d = sphere_dir(c.z, c.w);
		float speed = (3.5 + c.x * 3.0) * (0.6 + strength * 0.6);
		vec3 point = burst_path(origin, d, speed, age);
		vec3 ahead = burst_path(origin, d, speed, age + 0.05);
		vec3 local = v * 0.03;
		local += normalize(ahead - point + vec3(0.00001)) * dot(v, vec3(0.0, 1.0, 0.0)) * 0.12;
		float crackle = age > 1.2 ? step(0.45, hash(id + floor(clock * 20.0))) : 1.0;
		return make(point + local, mix(vec3(1.0), tint, smoothstep(0.0, 0.4, age)), life * crackle * strength * 0.9 * intensity, 0.0);
	} else if (shape == 0) {
		float k = floor(id / 8.0);
		vec3 d = sphere_dir(hash(k * 13.1 + slot), hash(k * 7.7 + slot * 3.0));
		float speed = (4.0 + hash(k * 3.3) * 2.0) * (0.6 + strength * 0.6);
		float tau = v.x * age;
		vec3 point = burst_path(origin, d, speed, tau);
		vec3 next = burst_path(origin, d, speed, tau + 0.02);
		return make(ribbon(point, next, v.y * 0.025), tint, v.x * v.x * life * strength * 0.5 * intensity, v.y);
	}
	if (id > 7.5) {
		return hidden();
	}
	vec3 point = facing_circle(origin, age * 7.0 + v.y * 0.08, v.x * TAU);
	return make(point, mix(tint, vec3(1.0), 0.5), exp(-age * 4.0) * strength * intensity, v.y);
}

Pulse planets(vec3 v, float id, float count, vec4 c) {
	float slot = mod(id, 8.0);
	int i = int(slot);
	vec4 s = sources[i];
	if (s.z < 0.01) {
		return hidden();
	}
	float level = gate(s.z);
	vec3 centre = stage_point(s, 1.1, 10.0, -0.4, 3.6);
	float radius = 0.35 + level * 1.0 * intensity;
	vec3 tint = hue(source_info[i].x);
	float k = floor(id / 8.0);
	if (shape == 0) {
		float total = min(slot_count(count), 10.0);
		if (k >= total) {
			return hidden();
		}
		float lat = ((k + 0.5) / total - 0.5) * PI;
		float wobble = 1.0 + gate(band_at(s.y + ((k + 0.5) / total - 0.5) * max(0.1, s.w) * 2.0, 0.0).y) * 0.15;
		float a = v.x * TAU + spin * 0.3;
		vec3 point = centre + vec3(cos(a) * cos(lat), sin(lat), sin(a) * cos(lat)) * radius * wobble;
		vec3 next = centre + vec3(cos(a + 0.02) * cos(lat), sin(lat), sin(a + 0.02) * cos(lat)) * radius * wobble;
		return make(ribbon(point, next, v.y * 0.02), tint, (0.1 + level * 0.6) * intensity, v.y);
	} else if (shape == 2) {
		if (k > 5.0) {
			return hidden();
		}
		float a = v.x * TAU + spin * 0.1;
		float r = radius * (1.6 + k * 0.2);
		float tilt = 0.45;
		vec3 local = vec3(cos(a) * r, sin(a) * r * sin(tilt), sin(a) * r * cos(tilt));
		vec3 next = vec3(cos(a + 0.02) * r, sin(a + 0.02) * r * sin(tilt), sin(a + 0.02) * r * cos(tilt));
		float ring_level = gate(band_at(s.y + (k / 5.0 - 0.5) * 0.3, 0.0).y);
		return make(ribbon(centre + local, centre + next, v.y * 0.015), mix(tint, vec3(1.0, 0.9, 0.7), 0.4), ring_level * 0.45 * intensity, v.y);
	} else if (shape == 1) {
		if (id > 320.0) {
			return hidden();
		}
		float r = radius * (2.2 + c.x * 1.6);
		float a = c.w * TAU + spin * 1.2 / (1.0 + c.x);
		float tilt = (c.z - 0.5) * 1.2;
		vec3 local = vec3(cos(a) * r, sin(a) * r * sin(tilt), sin(a) * r * cos(tilt));
		return make(centre + local + v * 0.035, mix(tint, vec3(1.0), 0.5), level * 0.7 * intensity, 0.0);
	}
	return hidden();
}

Pulse aurora(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float u = (id + 0.5) / count;
		float az = (u * 2.0 - 1.0) * 1.4;
		vec4 f = field_at(u, v.x * 0.9);
		float h = energy(f.x);
		float radius = 22.0 + sin(u * 31.0 + clock * 0.35) * 1.4;
		float el = 0.18 + v.x * (0.35 + h * 0.5);
		vec3 point = dome(az + sin(v.x * 3.0 + clock * 0.2 + u * 9.0) * 0.03, el) * radius;
		vec3 across = vec3(cos(az), 0.0, sin(az)) * v.y * 0.22;
		vec3 tint = mix(mix(band_colour(f.y), vec3(0.2, 1.0, 0.5), 0.35), vec3(0.6, 0.2, 1.0), v.x * 0.7);
		return make(point + across, tint, h * pow(1.0 - v.x, 0.6) * 0.32 * intensity, v.y);
	} else if (shape == 1) {
		float z = c.z * 0.9 + 0.1;
		float a = c.w * TAU;
		vec3 d = vec3(sqrt(1.0 - z * z) * cos(a), z, sqrt(1.0 - z * z) * sin(a));
		float twinkle = pow(max(0.0, sin(c.x * 40.0 + clock * 1.5)), 6.0);
		return make(d * 38.0 + v * 0.05, vec3(0.85, 0.9, 1.0), (0.03 + twinkle * 0.08 + treble * twinkle * 0.2) * intensity, 0.0);
	} else if (shape == 2) {
		float u = (id + 0.5) / count;
		float az = (u * 2.0 - 1.0) * 1.4;
		float h = energy(field_at(u, 0.0).x);
		vec3 point = dir_az(az) * (14.0 + v.x * 8.0) + vec3(0.0, FLOOR, 0.0);
		return make(point + vec3(cos(az), 0.0, sin(az)) * v.y * 0.1, vec3(0.2, 0.8, 0.6), h * 0.08 * (1.0 - v.x) * intensity, v.y);
	}
	return hidden();
}

vec3 pool_point(vec4 s) {
	return dir_az(s.x * 1.1) * 7.0 + vec3(0.0, FLOOR, 0.0);
}

Pulse ripples(vec3 v, float id, float count, vec4 c) {
	float slot = mod(id, 8.0);
	int i = int(slot);
	vec4 s = sources[i];
	vec3 centre = pool_point(s);
	vec3 tint = hue(source_info[i].x);
	if (shape == 0) {
		if (source_info[i].w < 0.5 && s.z < 0.01) {
			return hidden();
		}
		float total = slot_count(count);
		float k = floor(id / 8.0);
		float phase = (k + fract(clock * 0.45 * (0.5 + motion))) / total;
		float r = phase * 9.0;
		float amplitude = energy(field_at(s.x * 0.5 + 0.5, phase * 3.0).x);
		vec3 point = floor_circle(centre, r + v.y * (0.02 + amplitude * 0.04), v.x * TAU);
		point.y += sin(v.x * TAU * 8.0 + clock) * amplitude * 0.05;
		return make(point, mix(tint, band_colour(s.y), 0.3), amplitude * (1.0 - phase) * smoothstep(0.0, 0.08, phase) * 0.8 * intensity, v.y);
	} else if (shape == 1) {
		if (id > 480.0) {
			return hidden();
		}
		vec4 b = source_bursts[i];
		float age = b.z;
		if (age > 1.6) {
			return hidden();
		}
		vec3 origin = pool_point(b);
		float a = c.w * TAU;
		float up = 2.5 + c.x * 2.5;
		float outward = 0.6 + c.z * 1.4;
		vec3 point = origin + vec3(cos(a) * outward * age, up * age - 4.9 * age * age, sin(a) * outward * age);
		return make(point + v * 0.025, mix(tint, vec3(1.0), 0.5), step(FLOOR, point.y) * (1.0 - age / 1.6) * gate(b.w) * 0.9 * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 7.5 || s.z < 0.01) {
			return hidden();
		}
		float level = gate(s.z);
		vec3 point = centre + vec3(0.0, v.x * (0.3 + level * 3.2), 0.0);
		return make(point + billboard(point, vec3(0.0, 1.0, 0.0), v.y * 0.05), tint, level * 0.8 * intensity * (1.0 - v.x * 0.7), v.y);
	}
	return hidden();
}

Pulse harp(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float u = (id + 0.5) / count;
		float az = (u * 2.0 - 1.0) * 1.2;
		vec4 f = field_at(u, 0.0);
		float a = energy(f.x);
		float mode = 1.0 + floor(f.y * 5.0);
		vec3 base = dir_az(az) * 6.0;
		vec3 tangent = vec3(cos(az), 0.0, sin(az));
		float swing = sin(v.x * PI * mode) * sin(clock * (9.0 + f.y * 30.0) + u * 20.0) * a * 0.35 * intensity;
		vec3 point = base + vec3(0.0, mix(FLOOR, 4.4, v.x), 0.0) + tangent * swing;
		return make(point + tangent * v.y * (0.012 + a * 0.02), band_colour(f.y), (0.03 + a * 1.0) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 2000.0) {
			return hidden();
		}
		vec4 f = field_at(c.x, 0.0);
		float a = energy(f.x);
		float mode = 1.0 + floor(f.y * 5.0);
		float az = (c.x * 2.0 - 1.0) * 1.2;
		float node = pow(abs(sin(c.z * PI * mode)), 6.0);
		vec3 point = dir_az(az) * 5.9 + vec3(0.0, mix(FLOOR, 4.4, c.z), 0.0) + (vec3(cos(az), 0.0, sin(az)) * (c.w - 0.5) * a * 0.6);
		return make(point + v * 0.015, mix(band_colour(f.y), vec3(1.0), 0.5), a * a * node * 0.6 * intensity, 0.0);
	} else if (shape == 2) {
		if (id > 1.5) {
			return hidden();
		}
		float az = (v.x * 2.0 - 1.0) * 1.25;
		vec3 point = dir_az(az) * 6.0 + vec3(0.0, id < 0.5 ? FLOOR : 4.4, 0.0);
		return make(point + vec3(0.0, v.y * 0.05, 0.0), vec3(0.9, 0.75, 0.5), (0.06 + bass * 0.25) * intensity, v.y);
	}
	return hidden();
}

vec3 radar_point(float pan, float band) {
	return dir_az(pan * 1.0) * (1.5 + band * 8.5) + vec3(0.0, FLOOR + 0.25, 0.0);
}

float sweep_glow(vec3 point) {
	float az = atan(point.x, -point.z);
	float behind = mod(spin * 1.2 - az, TAU);
	return exp(-behind * 1.1);
}

Pulse radar(vec3 v, float id, float count, vec4 c) {
	vec3 green = vec3(0.25, 1.0, 0.45);
	float y = FLOOR + 0.25;
	if (shape == 0) {
		if (id < 4.5) {
			vec3 point = floor_circle(vec3(0.0, y, 0.0), (id + 1.0) * 2.0 + v.y * 0.02, v.x * TAU);
			return make(point, green, 0.05 * intensity, v.y);
		} else if (id < 16.5) {
			float az = (id - 5.0) / 12.0 * TAU;
			vec3 point = dir_az(az) * v.x * 10.0 + vec3(0.0, y, 0.0) + vec3(cos(az), 0.0, sin(az)) * v.y * 0.015;
			return make(point, green, 0.035 * intensity, v.y);
		} else if (id < 28.5) {
			float j = id - 17.0;
			float az = spin * 1.2 - j * 0.035;
			vec3 point = dir_az(az) * v.x * 10.0 + vec3(0.0, y, 0.0) + vec3(cos(az), 0.0, sin(az)) * v.y * 0.03;
			return make(point, green, (j < 0.5 ? 0.9 : 0.25 * exp(-j * 0.3)) * intensity * smoothstep(0.0, 0.1, v.x), v.y);
		}
		return hidden();
	} else if (shape == 1) {
		float band = mod(id, 48.0) / 47.0;
		float k = floor(id / 48.0);
		if (k > 11.0) {
			return hidden();
		}
		vec4 a = band_at(band, k * 0.08);
		vec3 point = radar_point(a.x, band);
		float level = gate(a.y);
		return make(point + v * (0.04 + level * 0.06), mix(green, band_colour(band), 0.45), level * level * (0.25 + sweep_glow(point)) * (1.0 - k / 12.0) * 1.1 * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 7.5) {
			return hidden();
		}
		int i = int(id);
		vec4 s = sources[i];
		if (s.z < 0.01) {
			return hidden();
		}
		float level = gate(s.z);
		vec3 point = floor_circle(radar_point(s.x, s.y), 0.35 + level * 0.6 + v.y * 0.03, v.x * TAU);
		return make(point, hue(source_info[i].x), level * 0.8 * intensity, v.y);
	}
	return hidden();
}

float analyzer_angle(float u, out float rear) {
	rear = step(0.5, u);
	float pan = fract(u * 2.0) * 2.0 - 1.0;
	return rear < 0.5 ? pan * 1.5 : (pan < 0.0 ? -1.0 : 1.0) * (PI - abs(pan) * 1.5);
}

Pulse analyzer(vec3 v, float id, float count, vec4 c) {
	float u = (id + 0.5) / count;
	float rear;
	float az = analyzer_angle(u, rear);
	float pan01 = fract(u * 2.0);
	vec4 f = field_at(pan01, 0.0);
	float h = energy(f.x);
	vec3 base = dir_az(az) * 5.5;
	vec3 tangent = vec3(cos(az), 0.0, sin(az));
	float strength = rear > 0.5 ? 0.45 : 1.0;
	if (shape == 0) {
		vec3 point = base + vec3(0.0, FLOOR + v.x * (0.08 + h * 4.0 * intensity), 0.0) + tangent * v.y * 0.07;
		vec3 tint = mix(band_colour(f.y), vec3(1.0), smoothstep(0.7, 1.0, v.x) * h * 0.5);
		return make(point, tint, (0.04 + h * 0.9) * strength * intensity, v.y);
	} else if (shape == 2) {
		vec3 point = base + vec3(0.0, FLOOR - v.x * h * 1.5, 0.0) + tangent * v.y * 0.07;
		return make(point, band_colour(f.y), h * 0.12 * (1.0 - v.x) * strength * intensity, v.y);
	} else if (shape == 1) {
		if (id > 1200.0) {
			return hidden();
		}
		float uu = c.x;
		float az2 = analyzer_angle(uu, rear);
		float peak = 0.0;
		for (int k = 0; k < 6; k++) {
			peak = max(peak, energy(field_at(fract(uu * 2.0), float(k) * 0.1).x));
		}
		vec3 point = dir_az(az2) * 5.5 + vec3(0.0, FLOOR + 0.12 + peak * 4.0 * intensity + c.z * 0.05, 0.0);
		return make(point + v * 0.025, vec3(1.0, 0.95, 0.85), peak * 0.35 * (rear > 0.5 ? 0.45 : 1.0) * intensity, 0.0);
	}
	return hidden();
}

vec3 comet_point(vec4 t, float delay) {
	return dir_az(t.x * 1.1) * (12.0 - delay * 5.5) + vec3(0.0, mix(-0.4, 4.0, t.y) - delay * 0.4, 0.0);
}

Pulse comets(vec3 v, float id, float count, vec4 c) {
	float slot = mod(id, 8.0);
	if (shape == 0) {
		float k = floor(id / 8.0);
		if (k > 3.0) {
			return hidden();
		}
		float delay = v.x * 1.4;
		vec4 t = trail(slot, delay);
		vec4 n = trail(slot, delay + 0.03);
		float twist = v.x * 9.0 + clock * 2.0 + k * PI * 0.5;
		vec3 offset = vec3(cos(twist), sin(twist), 0.0) * v.x * k * 0.06;
		vec3 point = comet_point(t, delay) + offset;
		vec3 next = comet_point(n, delay + 0.03) + offset;
		float level = gate(t.z);
		return make(ribbon(point, next, v.y * (0.04 + level * 0.1) * (1.0 - v.x * 0.6)), hue(t.w), level * pow(1.0 - v.x, 1.3) * (k < 0.5 ? 1.2 : 0.45) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 2400.0) {
			return hidden();
		}
		float delay = c.z * 1.4;
		vec4 t = trail(slot, delay);
		vec3 point = comet_point(t, delay) + sphere_dir(c.x, c.w) * delay * 0.7;
		return make(point + v * 0.02, mix(hue(t.w), vec3(1.0), 0.4), gate(t.z) * (1.0 - c.z) * 0.45 * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 7.5) {
			return hidden();
		}
		vec4 t = trail(slot, 0.0);
		float level = gate(t.z);
		vec3 point = facing_circle(comet_point(t, 0.0), 0.2 + level * 0.5 + v.y * 0.03, v.x * TAU);
		return make(point, mix(hue(t.w), vec3(1.0), 0.5), level * 0.8 * intensity, v.y);
	}
	return hidden();
}

vec3 petal_point(float theta, float along, float len, float edge_side) {
	float phi = theta + sin(along * PI) * 0.13 * edge_side;
	float r = along * len;
	return vec3(sin(phi) * r, cos(phi) * r, along * len * 0.25) + vec3(0.0, 0.6, -5.5);
}

float petal_length(float theta) {
	float band = 0.5 + 0.5 * cos(theta);
	vec4 b = band_at(band, 0.0);
	float side = sin(theta) < 0.0 ? -1.0 : 1.0;
	float lean = clamp(1.0 + b.x * side * 1.3, 0.12, 1.8);
	return 0.4 + gate(b.y) * 3.0 * lean * intensity;
}

Pulse bloom(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float petal = floor(id / 2.0);
		float petals = max(1.0, floor(count / 2.0));
		float edge_side = mod(id, 2.0) * 2.0 - 1.0;
		float theta = (petal + 0.5) / petals * TAU;
		float len = petal_length(theta);
		vec3 point = petal_point(theta, v.x, len, edge_side);
		vec3 next = petal_point(theta, v.x + 0.01, len, edge_side);
		float band = 0.5 + 0.5 * cos(theta);
		float level = clamp((len - 0.4) / (3.0 * intensity + 0.001), 0.0, 1.5);
		vec3 tint = mix(band_colour(band), sin(theta) < 0.0 ? vec3(0.2, 0.6, 1.0) : vec3(1.0, 0.3, 0.5), 0.35);
		return make(ribbon(point, next, v.y * 0.022), tint, (0.05 + level * 0.9) * smoothstep(0.0, 0.1, v.x) * intensity, v.y);
	} else if (shape == 2) {
		float theta = hash(id * 1.7) * TAU;
		float len = 0.25 + bass * 0.9 + kick() * 0.3;
		vec3 point = petal_point(theta, v.x, len, 0.0);
		vec3 next = petal_point(theta, v.x + 0.02, len, 0.0);
		return make(ribbon(point, next, v.y * 0.015), vec3(1.0, 0.85, 0.5), (0.1 + bass * 0.4) * smoothstep(0.6, 1.0, v.x) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 1600.0) {
			return hidden();
		}
		float age = fract(c.z + clock * 0.12);
		vec4 b = band_at(c.y, 0.0);
		vec3 d = normalize(sphere_dir(c.x, c.w) + vec3(b.x * 1.6, 0.0, 0.0));
		vec3 point = vec3(0.0, 0.6, -5.5) + d * age * 5.0;
		return make(point + v * 0.02, band_colour(c.y), gate(b.y) * (1.0 - age) * 0.5 * intensity, 0.0);
	}
	return hidden();
}

vec3 width_ring(float theta, float progress, float spread) {
	float z = mix(-40.0, 3.0, progress);
	return vec3(sin(theta) * spread, 0.4 - cos(theta) * 2.6, z);
}

Pulse width_tunnel(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float progress = fract((id + 0.5) / count + travel * 0.04);
		float delay = progress * 3.4;
		float w = field_at(0.5, delay).w;
		float spread = 2.2 + w * 6.0 * intensity;
		float theta = v.x * TAU;
		vec4 f = field_at(sin(theta) * 0.5 + 0.5, delay);
		float e = energy(f.x);
		vec3 point = width_ring(theta, progress, spread);
		vec3 next = width_ring(theta + 0.02, progress, spread);
		float fade = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.82, 0.94, progress));
		return make(ribbon(point, next, v.y * (0.02 + e * 0.05)), band_colour(f.y), (0.03 + e * 1.1) * fade * intensity, v.y);
	} else if (shape == 2) {
		if (id > 1.5) {
			return hidden();
		}
		float side = id < 0.5 ? -1.0 : 1.0;
		float progress = mix(0.05, 0.85, v.x);
		float w = field_at(0.5, progress * 3.4).w;
		vec3 point = width_ring(side * PI * 0.5, progress, 2.2 + w * 6.0 * intensity);
		return make(point + vec3(0.0, v.y * 0.04, 0.0), vec3(1.0, 0.95, 0.8), (0.1 + w * 0.6) * intensity * smoothstep(0.05, 0.2, progress) * (1.0 - smoothstep(0.7, 0.85, progress)), v.y);
	} else if (shape == 1) {
		if (id > 2500.0) {
			return hidden();
		}
		float progress = fract(c.z + travel * 0.09);
		float theta = c.w * TAU;
		float w = field_at(0.5, progress * 3.4).w;
		float e = energy(field_at(sin(theta) * 0.5 + 0.5, progress * 3.4).x);
		vec3 point = width_ring(theta, progress, (2.2 + w * 6.0 * intensity) * (0.6 + c.x * 0.5));
		return make(point + v * 0.02, vec3(0.9, 0.9, 1.0), e * 0.4 * smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.8, 0.9, progress)) * intensity, 0.0);
	}
	return hidden();
}

vec3 choir_point(vec4 t) {
	return dir_az(t.x * 2.2) * 6.0;
}

Pulse choir(vec3 v, float id, float count, vec4 c) {
	float slot = mod(id, 8.0);
	if (shape == 0) {
		float total = slot_count(count);
		float k = floor(id / 8.0);
		float delay = k / total * 1.3;
		vec4 t = trail(slot, delay);
		float level = gate(t.z);
		if (level < 0.005) {
			return hidden();
		}
		vec3 centre = choir_point(t) + vec3(0.0, FLOOR + k / total * 4.4, 0.0);
		float radius = 0.15 + level * 0.65 * (1.0 - k / total * 0.5) + sin(v.x * TAU * 3.0 + clock * 2.0) * 0.025;
		vec3 point = floor_circle(centre, radius + v.y * 0.02, v.x * TAU);
		return make(point, hue(t.w), level * 0.75 * (1.0 - k / total) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 1600.0) {
			return hidden();
		}
		float rise = fract(c.z + clock * 0.3);
		vec4 t = trail(slot, rise * 1.3);
		float level = gate(t.z);
		vec3 point = choir_point(t) + vec3(cos(c.w * TAU), 0.0, sin(c.w * TAU)) * c.x * (0.15 + level * 0.5) + vec3(0.0, FLOOR + rise * 4.4, 0.0);
		return make(point + v * 0.018, mix(hue(t.w), vec3(1.0), 0.5), level * (1.0 - rise) * 0.6 * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 7.5) {
			return hidden();
		}
		vec4 t = trail(slot, 0.0);
		float level = gate(t.z);
		vec3 point = floor_circle(choir_point(t) + vec3(0.0, FLOOR + 0.01, 0.0), 0.7 + level * 0.8 + v.y * 0.03, v.x * TAU);
		return make(point, hue(t.w), level * 0.6 * intensity, v.y);
	}
	return hidden();
}

Pulse point_cloud(vec3 v, float id, float count, vec4 c) {
	if (shape == 1) {
		float band = floor(c.y * 48.0) / 47.0;
		float delay = c.z * 3.2;
		vec4 a = band_at(band, delay);
		float level = gate(a.y);
		vec3 jitter = (vec3(c.x, c.w, hash(id)) - 0.5) * 0.25;
		vec3 point = vec3(a.x * 9.0, -1.2 + band * 5.2, -3.0 - delay * 8.0) + jitter;
		return make(point + v * (0.02 + level * 0.03), band_colour(band), level * level * 0.9 * (1.0 - smoothstep(2.4, 3.2, delay)) * intensity, 0.0);
	} else if (shape == 0) {
		if (id > 2.5) {
			return hidden();
		}
		float x = (id - 1.0) * 9.0;
		vec3 point = vec3(x + v.y * 0.03, FLOOR, -3.0 - v.x * 26.0);
		return make(point, id < 0.5 ? vec3(0.2, 0.6, 1.0) : (id < 1.5 ? vec3(0.8, 0.8, 0.8) : vec3(1.0, 0.35, 0.3)), 0.07 * intensity * (1.0 - v.x), v.y);
	}
	return hidden();
}

const vec3 STAR_LEFT = vec3(-4.2, 0.6, -8.0);
const vec3 STAR_RIGHT = vec3(4.2, 0.6, -8.0);

float star_level(float side) {
	float level = shaped(max(channel_balance.x, channel_balance.y));
	return level * clamp(1.0 + balance * (side < 0.5 ? -1.6 : 1.6), 0.1, 1.9);
}

Pulse binary(vec3 v, float id, float count, vec4 c) {
	if (shape == 1) {
		if (id < 1440.0) {
			float band = mod(id, 48.0) / 47.0;
			float k = floor(id / 48.0);
			vec4 a = band_at(band, k * 0.04);
			float t = a.x * 0.5 + 0.5;
			float swirl = c.w * TAU + clock * 2.0;
			vec3 point = mix(STAR_LEFT, STAR_RIGHT, t) + vec3(0.0, sin(t * PI) * (band - 0.5) * 3.0, 0.0) + vec3(0.0, cos(swirl), sin(swirl)) * 0.2;
			float level = gate(a.y);
			return make(point + v * 0.03, band_colour(band), level * level * (1.0 - k / 30.0) * 1.1 * intensity, 0.0);
		}
		float side = mod(id, 2.0);
		float level = star_level(side);
		vec3 centre = side < 0.5 ? STAR_LEFT : STAR_RIGHT;
		float r = 0.3 + c.x * c.x * 4.5 * (0.4 + level);
		float a = c.w * TAU + spin * 2.0 / (r + 0.5) * (side < 0.5 ? 1.0 : -1.0);
		float tilt = 0.5;
		vec3 local = vec3(cos(a) * r, sin(a) * r * sin(tilt) + (c.z - 0.5) * 0.2, sin(a) * r * cos(tilt));
		return make(centre + local + v * 0.02, side < 0.5 ? vec3(0.3, 0.6, 1.0) : vec3(1.0, 0.4, 0.3), (0.08 + level * 0.9) * (1.0 - r / 5.5) * intensity, 0.0);
	} else if (shape == 0) {
		float side = mod(id, 2.0);
		float k = floor(id / 2.0);
		if (k > 9.0) {
			return hidden();
		}
		float level = star_level(side);
		vec3 centre = side < 0.5 ? STAR_LEFT : STAR_RIGHT;
		float r = (0.5 + k * 0.4) * (1.0 + level * 0.4);
		float a = v.x * TAU;
		float tilt = 0.5;
		vec3 point = centre + vec3(cos(a) * r, sin(a) * r * sin(tilt), sin(a) * r * cos(tilt));
		vec3 next = centre + vec3(cos(a + 0.02) * r, sin(a + 0.02) * r * sin(tilt), sin(a + 0.02) * r * cos(tilt));
		return make(ribbon(point, next, v.y * 0.02), side < 0.5 ? vec3(0.3, 0.6, 1.0) : vec3(1.0, 0.4, 0.3), level * 0.3 * (1.0 - k / 10.0) * intensity, v.y);
	} else if (shape == 3) {
		if (id > 1.5) {
			return hidden();
		}
		float level = star_level(id);
		vec3 point = facing_circle(id < 0.5 ? STAR_LEFT : STAR_RIGHT, 0.25 + level * 0.5 + v.y * 0.05, v.x * TAU);
		return make(point, vec3(1.0, 0.95, 0.9), (0.2 + level * 1.0) * intensity, v.y);
	}
	return hidden();
}

vec3 tesla_target(vec4 s) {
	return vec3(s.x * 6.0, mix(-1.2, 3.0, s.y), -10.0);
}

Pulse tesla(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float slot = mod(id, 8.0);
		float side = mod(floor(id / 8.0), 2.0);
		float k = floor(id / 16.0);
		if (k > 2.0) {
			return hidden();
		}
		int i = int(slot);
		vec4 s = sources[i];
		if (s.z < 0.01) {
			return hidden();
		}
		vec3 start = vec3(side < 0.5 ? -6.5 : 6.5, 4.3, -10.0);
		vec3 end = tesla_target(s);
		float strength = side < 0.5 ? 0.5 - s.x * 0.5 : 0.5 + s.x * 0.5;
		float seed = slot * 17.0 + side * 5.0 + k * 3.0 + floor(clock * 16.0);
		float segment = v.x * 20.0;
		float jag_a = hash(floor(segment) + seed) - 0.5;
		float jag_b = hash(floor(segment) + 1.0 + seed) - 0.5;
		float jag_c = hash(floor(segment) + seed + 50.0) - 0.5;
		float jag_d = hash(floor(segment) + 51.0 + seed) - 0.5;
		float envelope = sin(v.x * PI) * (0.7 + k * 0.4);
		vec3 offset = vec3(0.0, mix(jag_a, jag_b, fract(segment)), mix(jag_c, jag_d, fract(segment))) * envelope;
		vec3 point = mix(start, end, v.x) + offset;
		float level = gate(s.z);
		float flicker = 0.4 + 0.6 * step(0.3, hash(floor(clock * 24.0) + slot + side * 9.0));
		vec3 tint = mix(vec3(0.6, 0.75, 1.0), hue(source_info[i].x), 0.35);
		return make(point + billboard(point, normalize(end - start), v.y * 0.035), tint, level * strength * flicker * (k < 0.5 ? 1.4 : 0.5) * (1.0 + source_info[i].z) * intensity, v.y);
	} else if (shape == 2) {
		float side = mod(id, 2.0);
		float k = floor(id / 2.0);
		if (k > 22.0) {
			return hidden();
		}
		float level = star_level(side);
		vec3 centre = vec3(side < 0.5 ? -6.5 : 6.5, FLOOR + k * 0.25, -10.0);
		float r = k > 21.5 ? 0.7 : 0.35;
		return make(floor_circle(centre, r + v.y * 0.02, v.x * TAU), vec3(0.6, 0.7, 1.0), (0.04 + level * 0.3) * intensity, v.y);
	} else if (shape == 1) {
		float slot = mod(id, 8.0);
		int i = int(slot);
		vec4 s = sources[i];
		if (id > 960.0 || s.z < 0.01) {
			return hidden();
		}
		float level = gate(s.z);
		float jitter = hash(id + floor(clock * 20.0));
		vec3 point = tesla_target(s) + sphere_dir(c.z, c.w) * (0.1 + jitter * 0.4) * (0.5 + level);
		return make(point + v * 0.02, vec3(0.8, 0.9, 1.0), level * step(0.5, jitter) * 0.6 * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 7.5) {
			return hidden();
		}
		int i = int(id);
		vec4 s = sources[i];
		if (s.z < 0.01) {
			return hidden();
		}
		float level = gate(s.z);
		return make(facing_circle(tesla_target(s), 0.15 + level * 0.4 + v.y * 0.03, v.x * TAU), hue(source_info[i].x), level * 0.8 * intensity, v.y);
	}
	return hidden();
}

vec3 pivot(float band) {
	return vec3((band * 2.0 - 1.0) * 7.0, 4.6, -8.0 - sin(band * PI) * 1.5);
}

vec3 bob(float band, float pan) {
	float angle = pan * 1.15;
	return pivot(band) + vec3(sin(angle), -cos(angle), 0.0) * 5.0;
}

Pulse pendulums(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		if (id < 47.5) {
			float band = id / 47.0;
			vec4 a = band_at(band, 0.0);
			float level = gate(a.y);
			vec3 top = pivot(band);
			vec3 bottom = bob(band, a.x);
			vec3 point = mix(top, bottom, v.x);
			return make(point + billboard(point, normalize(bottom - top), v.y * 0.012), band_colour(band), (0.04 + level * 0.25) * intensity, v.y);
		} else if (id < 95.5) {
			float band = (id - 48.0) / 47.0;
			float delay = v.x * 1.0;
			vec4 a = band_at(band, delay);
			vec4 b = band_at(band, delay + 0.02);
			float level = gate(a.y);
			return make(ribbon(bob(band, a.x), bob(band, b.x), v.y * 0.03), band_colour(band), level * (1.0 - v.x) * 0.45 * intensity, v.y);
		}
		return hidden();
	} else if (shape == 1) {
		if (id > 960.0) {
			return hidden();
		}
		float band = mod(id, 48.0) / 47.0;
		vec4 a = band_at(band, 0.0);
		float level = gate(a.y);
		vec3 point = bob(band, a.x) + sphere_dir(c.z, c.w) * (0.06 + level * 0.22) * sqrt(c.x);
		return make(point + v * (0.025 + level * 0.03), mix(band_colour(band), vec3(1.0), 0.3), (0.1 + level * 1.4) * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 0.5) {
			return hidden();
		}
		vec3 point = pivot(v.x);
		return make(point + vec3(0.0, v.y * 0.05, 0.0), vec3(0.8, 0.8, 0.9), (0.08 + bass * 0.2) * intensity, v.y);
	}
	return hidden();
}

vec3 scope_tint(float frame, float shift) {
	return hue(frame * 0.025 + palette * 2.0 + shift);
}

Pulse phosphor_dome(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float frame = id;
		if (frame > 23.0) {
			return hidden();
		}
		float radius = 14.0 + frame * 0.6;
		vec2 a = scope_point(frame, v.x);
		vec2 b = scope_point(frame, v.x + 1.0 / 255.0);
		vec3 point = dome(a.x * 1.1, 0.25 + a.y * 0.6) * radius;
		vec3 next = dome(b.x * 1.1, 0.25 + b.y * 0.6) * radius;
		vec3 tint = mix(vec3(0.35, 1.0, 0.5), vec3(1.0, 0.65, 0.2), frame / 23.0);
		return make(ribbon(point, next, v.y * (0.06 + frame * 0.01)), tint, 0.85 / (1.0 + frame * 0.4) * intensity, v.y);
	} else if (shape == 1) {
		float frame = floor(id / 256.0);
		if (frame > 5.0) {
			return hidden();
		}
		vec2 a = scope_point(frame, mod(id, 256.0) / 255.0);
		return make(dome(a.x * 1.1, 0.25 + a.y * 0.6) * (14.0 + frame * 0.6) + v * 0.06, vec3(0.8, 1.0, 0.85), (0.2 + treble * 0.5) / (1.0 + frame) * intensity, 0.0);
	} else if (shape == 2) {
		if (id < 8.5) {
			float el = 0.25 + (id / 8.0 * 2.0 - 1.0) * 0.6;
			vec3 point = dome((v.x * 2.0 - 1.0) * 1.1, el) * 14.2;
			return make(point + vec3(0.0, v.y * 0.03, 0.0), vec3(0.15, 0.4, 0.25), 0.04 * intensity, v.y);
		} else if (id < 17.5) {
			float az = ((id - 9.0) / 8.0 * 2.0 - 1.0) * 1.1;
			vec3 point = dome(az, 0.25 + (v.x * 2.0 - 1.0) * 0.6) * 14.2;
			return make(point + vec3(cos(az), 0.0, sin(az)) * v.y * 0.03, vec3(0.15, 0.4, 0.25), 0.04 * intensity, v.y);
		}
	}
	return hidden();
}

vec2 polar_sample(float frame, float along) {
	vec2 s = scope_point(frame, along);
	float r = length(s);
	float flip = s.y < 0.0 ? -1.0 : 1.0;
	float angle = atan(s.x * flip, abs(s.y) + 0.00001);
	return vec2(angle, r);
}

vec3 polar_position(vec2 polar, float scale) {
	return vec3(sin(polar.x), cos(polar.x), 0.0) * polar.y * scale + vec3(0.0, -1.0, -4.8);
}

vec3 polar_colour(float angle) {
	float side = angle / (PI * 0.5);
	return side < 0.0 ? mix(vec3(1.0), vec3(0.2, 0.55, 1.0), -side) : mix(vec3(1.0), vec3(1.0, 0.3, 0.25), side);
}

Pulse polar_scope(vec3 v, float id, float count, vec4 c) {
	float scale = 3.4;
	if (shape == 1) {
		float frame = floor(id / 256.0);
		if (frame > 15.0) {
			return hidden();
		}
		vec2 polar = polar_sample(frame, mod(id, 256.0) / 255.0);
		vec3 point = polar_position(polar, scale) + vec3(0.0, 0.0, -frame * 0.08);
		return make(point + v * 0.022, polar_colour(polar.x), 0.5 / (1.0 + frame * 0.45) * intensity, 0.0);
	} else if (shape == 0) {
		vec2 polar = polar_sample(0.0, (id + 0.5) / count);
		vec3 tip = polar_position(polar, scale);
		vec3 origin = vec3(0.0, -1.0, -4.8);
		vec3 point = mix(origin, tip, v.x);
		return make(point + billboard(point, normalize(tip - origin + vec3(0.00001)), v.y * 0.012), polar_colour(polar.x), 0.22 * v.x * intensity, v.y);
	} else if (shape == 2) {
		vec3 origin = vec3(0.0, -1.0, -4.8);
		if (id < 2.5) {
			float r = (id + 1.0) / 3.0 * scale;
			float angle = (v.x * 2.0 - 1.0) * PI * 0.5;
			return make(origin + vec3(sin(angle), cos(angle), 0.0) * (r + v.y * 0.015), vec3(0.3, 0.35, 0.45), 0.05 * intensity, v.y);
		} else if (id < 5.5) {
			float angle = (id - 4.0) * PI * 0.25;
			vec3 point = origin + vec3(sin(angle), cos(angle), 0.0) * v.x * scale + vec3(cos(angle), -sin(angle), 0.0) * v.y * 0.012;
			return make(point, polar_colour(angle), 0.07 * intensity, v.y);
		}
	} else if (shape == 3) {
		if (id > 0.5) {
			return hidden();
		}
		float angle = (v.x * 2.0 - 1.0) * PI * 0.5;
		float reach = 0.0;
		for (int i = 0; i < 64; i++) {
			vec2 polar = polar_sample(0.0, float(i) / 63.0);
			reach = max(reach, polar.y * gaussian((polar.x - angle) / 0.12));
		}
		vec3 point = vec3(0.0, -1.0, -4.8) + vec3(sin(angle), cos(angle), 0.0) * (reach * scale + v.y * 0.03);
		return make(point, mix(polar_colour(angle), vec3(1.0), 0.3), (0.15 + reach * 0.6) * intensity, v.y);
	}
	return hidden();
}

vec3 halo_point(float frame, float along) {
	vec2 s = scope_point(frame, along);
	float az = along * TAU + spin * 0.15;
	return dir_az(az) * (5.0 + s.x * 1.6) + vec3(0.0, 0.4 + s.y * 1.3 - frame * 0.17, 0.0);
}

Pulse scope_halo(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float frame = id;
		if (frame > 23.0) {
			return hidden();
		}
		vec3 point = halo_point(frame, v.x);
		vec3 next = halo_point(frame, v.x + 1.0 / 255.0);
		return make(ribbon(point, next, v.y * 0.025), hue(v.x + palette * 2.0 + frame * 0.02), 0.75 / (1.0 + frame * 0.35) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 767.0) {
			return hidden();
		}
		float frame = floor(id / 256.0);
		vec3 point = halo_point(frame, mod(id, 256.0) / 255.0);
		float twinkle = pow(max(0.0, sin(id * 1.7 + clock * 6.0)), 8.0);
		return make(point + v * 0.03, vec3(1.0), (0.05 + twinkle * (0.2 + treble)) / (1.0 + frame) * intensity, 0.0);
	} else if (shape == 2) {
		if (id > 1.5) {
			return hidden();
		}
		vec3 point = floor_circle(vec3(0.0, id < 0.5 ? FLOOR : 0.4, 0.0), 5.0 + v.y * 0.02, v.x * TAU);
		return make(point, vec3(0.3, 0.4, 0.6), (id < 0.5 ? 0.05 + bass * 0.2 : 0.025) * intensity, v.y);
	}
	return hidden();
}

vec2 kaleido_point(float frame, float along, float copy) {
	vec2 s = scope_point(frame, along) * 2.6 * (1.0 + frame * 0.06);
	float angle = copy / 6.0 * TAU + spin * 0.1;
	return mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * (s + vec2(0.0, 0.35));
}

Pulse scope_kaleidoscope(vec3 v, float id, float count, vec4 c) {
	vec3 centre = vec3(0.0, 0.5, -7.5);
	if (shape == 0) {
		float copy = mod(id, 6.0);
		float frame = floor(id / 6.0);
		if (frame > 11.0) {
			return hidden();
		}
		vec2 a = kaleido_point(frame, v.x, copy);
		vec2 b = kaleido_point(frame, v.x + 1.0 / 255.0, copy);
		vec2 t = normalize(b - a + vec2(0.00001, 0.0));
		vec3 point = centre + vec3(a + vec2(-t.y, t.x) * v.y * 0.02, -frame * 0.1);
		return make(point, hue(copy / 6.0 + frame * 0.03 + palette * 2.0), 0.6 / (1.0 + frame * 0.5) * intensity, v.y);
	} else if (shape == 1) {
		float copy = mod(id, 6.0);
		float sample_index = floor(id / 6.0);
		if (sample_index > 255.0) {
			return hidden();
		}
		vec2 a = kaleido_point(0.0, sample_index / 255.0, copy);
		return make(centre + vec3(a, 0.02) + v * 0.02, vec3(1.0), (0.08 + treble * 0.4) * intensity, 0.0);
	} else if (shape == 3) {
		if (id > 0.5) {
			return hidden();
		}
		float radius = 0.5 + (1.0 - exp(-beat_age * 3.0)) * 4.0;
		vec3 point = centre + vec3(cos(v.x * TAU), sin(v.x * TAU), 0.0) * (radius + v.y * 0.04);
		return make(point, hue(beat_count * 0.13 + palette), kick() * 0.6 * intensity, v.y);
	}
	return hidden();
}

vec3 helix_point(float frame, float along) {
	vec2 s = scope_point(frame, along) * 2.8;
	float angle = frame * 0.3 + spin * 0.3;
	s = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * s;
	return vec3(s.x, 0.5 + s.y, -3.0 - along * 22.0);
}

Pulse stereo_helix(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float frame = id;
		if (frame > 15.0) {
			return hidden();
		}
		vec3 point = helix_point(frame, v.x);
		vec3 next = helix_point(frame, v.x + 1.0 / 255.0);
		vec3 tint = mix(vec3(0.2, 0.9, 1.0), vec3(1.0, 0.3, 0.8), v.x);
		return make(ribbon(point, next, v.y * 0.04), mix(tint, hue(palette * 2.0 + frame * 0.05), 0.3), 0.95 / (1.0 + frame * 0.35) * smoothstep(0.0, 0.05, v.x) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 1023.0) {
			return hidden();
		}
		float frame = floor(id / 256.0);
		vec3 point = helix_point(frame, mod(id, 256.0) / 255.0);
		return make(point + v * 0.03, vec3(1.0), (0.06 + treble * 0.3) / (1.0 + frame) * intensity, 0.0);
	} else if (shape == 2) {
		if (id > 0.5) {
			return hidden();
		}
		vec3 point = vec3(0.0, 0.5, -3.0 - v.x * 22.0);
		return make(point + vec3(v.y * 0.02, 0.0, 0.0), vec3(0.5, 0.5, 0.7), 0.05 * intensity, v.y);
	}
	return hidden();
}

vec3 canyon_point(float x01, float delay, float h) {
	float x = (x01 * 2.0 - 1.0) * 11.0;
	float slope = 12.0 * x / 121.0;
	vec3 normal = normalize(vec3(-slope, 1.0, 0.0));
	vec3 base = vec3(x, FLOOR + pow(abs(x) / 11.0, 2.0) * 6.0, -2.5 - delay * 9.0);
	return base + normal * h * 2.4 * intensity;
}

Pulse terrain_canyon(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float delay = id / count * 3.6;
		vec4 f = field_at(v.x, delay);
		float h = energy(f.x);
		vec3 point = canyon_point(v.x, delay, h) + vec3(0.0, v.y * 0.025, 0.0);
		return make(point, band_colour(f.y), (0.03 + h * 0.9) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, v.y);
	} else if (shape == 2) {
		float x = (id + 0.5) / count;
		float delay = v.x * 3.6;
		float h = terrain_height(x, delay);
		vec3 point = canyon_point(x, delay, h) + vec3(v.y * 0.02, 0.0, 0.0);
		return make(point, band_colour(field_at(x, delay).y), (0.015 + h * 0.4) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 1500.0) {
			return hidden();
		}
		float rise = fract(c.w + clock * 0.25);
		float delay = c.z * 3.0;
		float h = terrain_height(c.x, delay);
		vec3 point = canyon_point(c.x, delay, h) + vec3(0.0, rise * (0.5 + h * 2.0), 0.0);
		return make(point + v * 0.025, vec3(1.0, 0.9, 0.7), h * h * (1.0 - rise) * 0.6 * intensity, 0.0);
	}
	return hidden();
}

Pulse pan_ridges(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		if (id > 47.5) {
			return hidden();
		}
		float band = id / 47.0;
		vec4 a = band_at(band, 0.0);
		float level = gate(a.y);
		float x = v.x * 2.0 - 1.0;
		float bump = level * gaussian((x - a.x) / 0.11) * 3.0 * intensity;
		float ripple = level * 0.06 * sin(x * 30.0 + clock * 3.0 + band * 9.0) * gaussian((x - a.x) / 0.4);
		vec3 point = vec3(x * 7.0, FLOOR + 0.3 + band * 3.2 + bump + ripple + v.y * 0.025, -2.5 - band * 10.0);
		return make(point, band_colour(band), (0.07 + level * 0.25 + bump * 0.35) * intensity, v.y);
	} else if (shape == 1) {
		float band = mod(id, 48.0) / 47.0;
		float k = floor(id / 48.0);
		if (k > 15.0) {
			return hidden();
		}
		vec4 a = band_at(band, k * 0.06);
		float level = gate(a.y);
		vec3 point = vec3(a.x * 7.0, FLOOR + 0.3 + band * 3.2 + level * 3.0 * intensity + k * 0.08, -2.5 - band * 10.0);
		return make(point + v * (0.03 + level * 0.04), mix(band_colour(band), vec3(1.0), 0.4), level * level * (1.0 - k / 16.0) * 0.9 * intensity, 0.0);
	} else if (shape == 2) {
		if (id > 0.5) {
			return hidden();
		}
		return make(vec3(v.y * 0.03, FLOOR + 0.3 + v.x * 3.2, -2.5 - v.x * 10.0), vec3(0.6), 0.04 * intensity, v.y);
	}
	return hidden();
}

vec3 tube_point(float pan01, float delay, float h) {
	float theta = mix(-0.88, 0.88, pan01) * PI;
	float radius = 4.2 - h * 2.0 * intensity;
	return vec3(sin(theta) * radius, 0.8 - cos(theta) * radius, -2.5 - delay * 9.0);
}

Pulse terrain_tunnel(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float delay = id / count * 3.6;
		vec4 f = field_at(v.x, delay);
		float h = energy(f.x);
		vec3 point = tube_point(v.x, delay, h);
		vec3 next = tube_point(v.x + 0.01, delay, energy(field_at(v.x + 0.01, delay).x));
		return make(ribbon(point, next, v.y * 0.025), band_colour(f.y), (0.03 + h * 0.9) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, v.y);
	} else if (shape == 2) {
		float x = (id + 0.5) / count;
		float delay = v.x * 3.6;
		float h = terrain_height(x, delay);
		vec3 point = tube_point(x, delay, h);
		vec3 next = tube_point(x, delay + 0.02, terrain_height(x, delay + 0.02));
		return make(ribbon(point, next, v.y * 0.02), band_colour(field_at(x, delay).y), (0.015 + h * 0.4) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, v.y);
	} else if (shape == 1) {
		if (id > 1500.0) {
			return hidden();
		}
		float delay = fract(c.z - clock * 0.12) * 3.6;
		float h = terrain_height(c.x, delay);
		vec3 point = mix(tube_point(c.x, delay, h), vec3(0.0, 0.8, -2.5 - delay * 9.0), 0.15 + c.w * 0.3);
		return make(point + v * 0.02, vec3(0.9, 0.95, 1.0), (0.03 + h * h * 0.5) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, 0.0);
	}
	return hidden();
}

vec3 neon_colour(float x01, float h) {
	return mix(mix(vec3(0.95, 0.15, 0.85), vec3(0.1, 0.85, 1.0), x01), vec3(1.0, 0.85, 0.5), smoothstep(0.6, 1.0, h) * 0.5);
}

Pulse neon_mirror(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float ceiling = mod(id, 2.0);
		float row = floor(id / 2.0);
		float rows = max(1.0, floor(count / 2.0));
		float delay = row / rows * 3.6;
		float h = terrain_height(v.x, delay);
		float y = ceiling < 0.5 ? FLOOR + h * 2.6 * intensity : 5.6 - h * 2.0 * intensity;
		vec3 point = vec3((v.x * 2.0 - 1.0) * 12.0, y + v.y * 0.025, -2.5 - delay * 9.0);
		return make(point, neon_colour(v.x, h), (0.035 + h * 0.8) * (ceiling < 0.5 ? 1.0 : 0.45) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, v.y);
	} else if (shape == 2) {
		float x = (id + 0.5) / count;
		float delay = v.x * 3.6;
		float h = terrain_height(x, delay);
		vec3 point = vec3((x * 2.0 - 1.0) * 12.0 + v.y * 0.02, FLOOR + h * 2.6 * intensity, -2.5 - delay * 9.0);
		return make(point, neon_colour(x, h), (0.02 + h * 0.4) * (1.0 - smoothstep(2.6, 3.6, delay)) * intensity, v.y);
	} else if (shape == 3) {
		if (id > 0.5) {
			return hidden();
		}
		vec3 point = vec3((v.x * 2.0 - 1.0) * 30.0, FLOOR + 0.02 + v.y * 0.05, -35.0);
		return make(point, vec3(1.0, 0.4, 0.7), (0.15 + bass * 0.5) * intensity, v.y);
	}
	return hidden();
}

Pulse crystal_city(vec3 v, float id, float count, vec4 c) {
	if (shape == 1) {
		float columns = 48.0;
		float rows = max(1.0, floor(count / columns));
		float ix = mod(id, columns);
		float it = floor(id / columns);
		float x01 = ix / (columns - 1.0);
		float delay = it / rows * 3.4;
		vec4 f = field_at(x01, delay);
		float h = energy(f.x);
		if (h < 0.08) {
			return hidden();
		}
		vec3 base = vec3((x01 * 2.0 - 1.0) * 11.0, FLOOR, -2.5 - delay * 9.0);
		float tall = 0.05 + h * 3.6 * intensity;
		vec3 point = base + vec3(v.x * 0.06, (v.y * 0.5 + 0.5) * tall, v.z * 0.06);
		vec3 tint = mix(band_colour(f.y), vec3(1.0), (v.y * 0.5 + 0.5) * h * 0.5);
		return make(point, tint, (0.01 + h * h * 0.2) * (1.0 - smoothstep(2.4, 3.4, delay)) * intensity, 0.0);
	} else if (shape == 2) {
		float delay = (id + 0.5) / count * 3.4;
		vec3 point = vec3((v.x * 2.0 - 1.0) * 11.5, FLOOR + v.y * 0.015, -2.5 - delay * 9.0);
		return make(point, vec3(0.3, 0.35, 0.6), 0.025 * (1.0 - smoothstep(2.4, 3.4, delay)) * intensity, v.y);
	}
	return hidden();
}

vec3 studio_channel(float channel) {
	return channel < 0.5 ? vec3(0.08, 0.8, 1.0) : vec3(1.0, 0.22, 0.55);
}

Pulse spectrum_observatory(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 96.0) return hidden();
		float channel = floor(id / 48.0);
		float band = mod(id, 48.0) / 47.0;
		vec4 f = band_at(band, 0.0);
		float level = channel < 0.5 ? f.z : f.w;
		float az = mix(-1.35, 1.35, band) + (channel - 0.5) * 0.025;
		vec3 base = dir_az(az) * (7.0 + channel * 0.8);
		base.y = -1.4;
		vec3 point = base + vec3(0.0, v.x * level * 5.5, 0.0);
		return make(point + vec3(cos(az), 0.0, sin(az)) * v.y * 0.055, mix(studio_channel(channel), band_colour(band), 0.3), (0.12 + level * 0.8) * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 7.0) return hidden();
		float az = mix(-1.4, 1.4, v.x);
		vec3 point = dir_az(az) * (7.0 + v.y * 0.025);
		point.y = -1.4 + id * 5.5 / 6.0;
		return make(point, vec3(0.2, 0.4, 0.6), (id == 0.0 ? 0.24 : 0.065) * intensity, v.y);
	} else if (shape == 1) {
		if (id >= 96.0) return hidden();
		float channel = floor(id / 48.0);
		float band = mod(id, 48.0) / 47.0;
		vec4 f = band_at(band, 0.0);
		vec3 point = dir_az(mix(-1.35, 1.35, band) + (channel - 0.5) * 0.025) * (7.0 + channel * 0.8);
		point.y = -1.4 + (channel < 0.5 ? f.z : f.w) * 5.5;
		return make(point + v * 0.055, vec3(0.85, 0.95, 1.0), 0.6 * max(f.z, f.w) * intensity, 0.0);
	}
	return hidden();
}

Pulse phase_cathedral(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 40.0) return hidden();
		vec2 s = scope_point(id, v.x);
		vec2 next = scope_point(id, v.x + 1.0 / 255.0);
		vec3 point = vec3(s.x * 3.0, s.y * 3.0 + 0.5, -5.0 - id * 0.45);
		vec3 tangent = vec3((next - s) * 3.0, 0.0);
		vec3 tint = mix(vec3(1.0, 0.28, 0.12), vec3(0.12, 1.0, 0.65), clamp(correlation * 0.5 + 0.5, 0.0, 1.0));
		return make(ribbon(point, point + tangent, v.y * 0.035), tint, 0.95 / (1.0 + id * 0.15) * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 12.0) return hidden();
		float frame = floor(id / 3.0);
		float axis = mod(id, 3.0);
		float a = (v.x * 2.0 - 1.0) * 3.8;
		vec3 point = axis < 0.5 ? vec3(a, 0.5, -5.1 - frame * 4.0) : (axis < 1.5 ? vec3(0.0, a + 0.5, -5.1 - frame * 4.0) : vec3(cos(v.x * TAU) * 3.8, sin(v.x * TAU) * 3.8 + 0.5, -5.1 - frame * 4.0));
		return make(point + vec3(v.y * 0.015, v.y * 0.015, 0.0), axis < 0.5 ? vec3(1.0, 0.28, 0.12) : vec3(0.15, 0.6, 0.55), 0.09 / (1.0 + frame) * intensity, v.y);
	}
	return hidden();
}

Pulse stereo_ribbonfall(vec3 v, float id, float count) {
	if (shape == 0) {
		float channel = mod(id, 2.0);
		float delay = floor(id / 2.0) / max(1.0, floor(count / 2.0) - 1.0) * 3.8;
		vec4 f = band_at(v.x, delay);
		float level = channel < 0.5 ? f.z : f.w;
		float x = (channel < 0.5 ? -1.0 : 1.0) * (1.0 + v.x * 8.0);
		vec3 point = vec3(x, -1.6 + level * 4.0, -3.2 - delay * 7.5);
		return make(point + vec3(0.0, v.y * 0.035, 0.0), mix(studio_channel(channel), band_colour(v.x), 0.4), (0.035 + level * level * 0.9) * (1.0 - smoothstep(3.0, 3.8, delay)) * intensity, v.y);
	} else if (shape == 2) {
		float channel = mod(id, 2.0);
		float band = floor(id / 2.0) / max(1.0, floor(count / 2.0) - 1.0);
		vec4 f = band_at(band, v.x * 3.8);
		float level = channel < 0.5 ? f.z : f.w;
		vec3 point = vec3((channel < 0.5 ? -1.0 : 1.0) * (1.0 + band * 8.0) + v.y * 0.018, -1.6 + level * 4.0, -3.2 - v.x * 28.5);
		return make(point, studio_channel(channel), (0.02 + level * 0.2) * (1.0 - smoothstep(0.8, 1.0, v.x)) * intensity, v.y);
	}
	return hidden();
}

Pulse pan_meridian(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 96.0) return hidden();
		float band = mod(id, 48.0) / 47.0;
		float frame = floor(id / 48.0);
		vec4 f = band_at(band, frame * 0.25);
		float x = (v.x * 2.0 - 1.0) * 7.0;
		float level = gate(f.y);
		float peak = gaussian((x / 7.0 - f.x) / 0.065) * level;
		vec3 point = vec3(x, -1.5 + band * 5.0 + peak * 0.18, -6.0 - frame * 2.0 - peak * 0.8);
		return make(point + vec3(0.0, v.y * (0.018 + peak * 0.045), 0.0), band_colour(band), (0.018 + peak * 1.5) / (1.0 + frame) * intensity, v.y);
	} else if (shape == 1) {
		if (id >= 1536.0) return hidden();
		float band = mod(id, 48.0) / 47.0;
		float age = floor(id / 48.0) / 31.0;
		vec4 f = band_at(band, age * 2.5);
		return make(vec3(f.x * 7.0, -1.5 + band * 5.0, -6.0 - age * 13.0) + v * (0.035 + gate(f.y) * 0.04), band_colour(band), gate(f.y) * (1.0 - age) * 0.6 * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 5.0) return hidden();
		return make(vec3((id / 4.0 * 2.0 - 1.0) * 7.0 + v.y * 0.02, -1.5 + v.x * 5.0, -6.1), vec3(0.3, 0.45, 0.6), (id == 2.0 ? 0.22 : 0.06) * intensity, v.y);
	}
	return hidden();
}

Pulse transient_loom(vec3 v, float id, float count) {
	if (shape == 0 || shape == 2) {
		float band = shape == 0 ? (id + 0.5) / count : v.x;
		float delay = shape == 0 ? v.x * 3.8 : id / count * 3.8;
		vec4 f = band_at(band, delay);
		vec4 old = band_at(band, delay + 0.045);
		float attack = max(0.0, f.y - old.y) * 5.0;
		float height = f.y * 2.0 + min(1.5, attack) * 2.0;
		vec3 point = vec3((band * 2.0 - 1.0) * 10.0, -1.8 + height, -3.0 - delay * 8.0);
		point += shape == 0 ? vec3(v.y * 0.025, 0.0, 0.0) : vec3(0.0, v.y * 0.025, 0.0);
		vec3 tint = mix(band_colour(band) * 0.65, vec3(1.0, 0.85, 0.35), min(1.0, attack));
		return make(point, tint, (0.025 + f.y * 0.22 + attack * 0.8) * (1.0 - smoothstep(3.0, 3.8, delay)) * intensity, v.y);
	}
	return hidden();
}

Pulse stereo_difference(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 96.0) return hidden();
		float band = mod(id, 48.0) / 47.0;
		float frame = floor(id / 48.0);
		vec4 f = band_at(band, frame * 0.15);
		float left = pow(10.0, (f.z * 60.0 - 60.0) / 20.0);
		float right = pow(10.0, (f.w * 60.0 - 60.0) / 20.0);
		float delta = (right - left) / max(0.00001, left + right);
		float az = mix(-1.3, 1.3, band);
		vec3 point = dir_az(az) * (8.0 + frame * 2.0);
		point.y = 0.5 + v.x * delta * gate(f.y) * 3.5;
		vec3 tint = delta < 0.0 ? studio_channel(0.0) : studio_channel(1.0);
		return make(point + vec3(cos(az), 0.0, sin(az)) * v.y * 0.07, tint, (0.04 + abs(delta) * gate(f.y)) / (1.0 + frame) * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 7.0) return hidden();
		vec3 point = dir_az(mix(-1.35, 1.35, v.x)) * (8.0 + v.y * 0.02);
		point.y = 0.5 + (id - 3.0);
		return make(point, id == 3.0 ? vec3(0.85, 0.8, 0.6) : vec3(0.2, 0.3, 0.5), (id == 3.0 ? 0.24 : 0.055) * intensity, v.y);
	} else if (shape == 1) {
		if (id >= 48.0) return hidden();
		float band = id / 47.0;
		vec4 f = band_at(band, 0.0);
		vec3 point = dir_az(mix(-1.3, 1.3, band)) * 8.0;
		point.y = 0.5;
		return make(point + v * (0.025 + gate(f.y) * 0.075), vec3(0.9, 0.85, 0.6), gate(f.y) * 0.7 * intensity, 0.0);
	}
	return hidden();
}

vec3 atrium_point(float channel, float frame, float along) {
	vec2 s = scope_point(frame, along);
	float sample_value = channel < 0.5 ? s.y : s.x;
	float angle = along * TAU;
	float radius = 2.3 + sample_value * 0.9 + frame * 0.055;
	return vec3(sin(angle) * radius, (channel < 0.5 ? -0.9 : 1.8) + sample_value * 0.5, -7.0 + cos(angle) * radius - frame * 0.15);
}

Pulse mid_side_atrium(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 48.0) return hidden();
		float channel = mod(id, 2.0);
		float frame = floor(id / 2.0);
		vec3 point = atrium_point(channel, frame, v.x);
		vec3 next = atrium_point(channel, frame, v.x + 1.0 / 255.0);
		vec2 s = scope_point(frame, v.x);
		float level = abs(channel < 0.5 ? s.y : s.x);
		vec3 tint = channel < 0.5 ? vec3(0.1, 0.8, 1.0) : vec3(1.0, 0.65, 0.12);
		return make(ribbon(point, next, v.y * 0.035), tint, (0.025 + level * 0.75) / (1.0 + frame * 0.12) * intensity, v.y);
	} else if (shape == 1) {
		if (id >= 512.0) return hidden();
		float channel = floor(id / 256.0);
		float along = mod(id, 256.0) / 255.0;
		vec2 s = scope_point(0.0, along);
		float level = abs(channel < 0.5 ? s.y : s.x);
		return make(atrium_point(channel, 0.0, along) + v * 0.025, vec3(0.9, 0.95, 1.0), level * 0.55 * intensity, 0.0);
	}
	return hidden();
}

vec4 phase_at(float delay) {
	return ring_at(correlation_texture, 0.5, 1.0, 192.0, correlation_head, correlation_fraction, delay);
}

vec3 causeway_point(float delay, float offset) {
	vec4 f = phase_at(delay);
	return vec3(f.x * 3.2 + offset, -0.5, -3.0 - delay * 8.0);
}

Pulse correlation_causeway(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 20.0) return hidden();
		float delay = v.x * 3.8;
		vec4 f = phase_at(delay);
		float offset = (id / 19.0 * 2.0 - 1.0) * 0.35;
		vec3 point = causeway_point(delay, offset);
		vec3 next = causeway_point(delay + 0.015, offset);
		vec3 tint = mix(vec3(1.0, 0.12, 0.08), vec3(0.15, 1.0, 0.55), f.x * 0.5 + 0.5);
		return make(ribbon(point, next, v.y * 0.025), tint, gate(f.y) * (0.32 + 0.2 * abs(f.x)) * (1.0 - smoothstep(3.0, 3.8, delay)) * intensity, v.y);
	} else if (shape == 1) {
		if (id >= 172.0) return hidden();
		float delay = id / 171.0 * 3.8;
		vec4 f = phase_at(delay);
		vec3 point = causeway_point(delay, 0.0);
		return make(point + v * 0.045, vec3(0.9, 1.0, 0.9), gate(f.y) * (1.0 - delay / 3.8) * 0.6 * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 9.0) return hidden();
		float x = (mod(id, 3.0) - 1.0) * 3.2;
		float height = floor(id / 3.0) * 0.7 - 1.2;
		vec3 tint = x < -0.1 ? vec3(1.0, 0.2, 0.1) : (x > 0.1 ? vec3(0.1, 0.8, 0.5) : vec3(0.8, 0.55, 0.2));
		return make(vec3(x + v.y * 0.02, height, -3.0 - v.x * 30.4), tint, 0.07 * intensity, v.y);
	}
	return hidden();
}

Pulse stereo_spectrogram(vec3 v, float id, float count) {
	if (shape == 0) {
		float channel = mod(id, 2.0);
		float age = floor(id / 2.0) / max(1.0, floor(count / 2.0) - 1.0);
		vec4 f = band_at(v.x, age * 3.8);
		float level = channel < 0.5 ? f.z : f.w;
		vec3 tint = mix(studio_channel(channel) * 0.3, vec3(1.0, 0.85, 0.3), level);
		vec3 point = vec3((v.x * 2.0 - 1.0) * 6.0, 3.3 - channel * 3.5 - age * 3.0 + v.y * 0.035, -8.0);
		return make(point, tint, level * level * 2.4 * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 18.0) return hidden();
		float channel = floor(id / 9.0);
		float line = mod(id, 9.0);
		vec3 point = line < 5.0 ? vec3((v.x * 2.0 - 1.0) * 6.0, 3.3 - channel * 3.5 - line * 0.75, -8.03) : vec3((line - 5.0) * 4.0 - 6.0, 3.3 - channel * 3.5 - v.x * 3.0, -8.03);
		return make(point + vec3(v.y * 0.012, v.y * 0.012, 0.0), studio_channel(channel), 0.2 * intensity, v.y);
	}
	return hidden();
}

Pulse dual_waveform(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 48.0) return hidden();
		float channel = mod(id, 2.0);
		float frame = floor(id / 2.0);
		float sample_value = scope_value(frame, channel, v.x);
		float next_value = scope_value(frame, channel, v.x + 1.0 / 255.0);
		vec3 point = vec3((v.x * 2.0 - 1.0) * 6.0, 2.0 - channel * 3.2 + sample_value * 1.25, -7.0 - frame * 0.22);
		vec3 next = vec3(point.x + 12.0 / 255.0, 2.0 - channel * 3.2 + next_value * 1.25, point.z);
		return make(ribbon(point, next, v.y * 0.045), studio_channel(channel), (0.5 + abs(sample_value) * 0.9) / (1.0 + frame * 0.2) * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 6.0) return hidden();
		float channel = floor(id / 3.0);
		float line = mod(id, 3.0) - 1.0;
		vec3 point = vec3((v.x * 2.0 - 1.0) * 6.0, 2.0 - channel * 3.2 + line * 1.25 + v.y * 0.015, -7.03);
		return make(point, studio_channel(channel), (line == 0.0 ? 0.45 : 0.2) * intensity, v.y);
	}
	return hidden();
}

Pulse spectral_balance(vec3 v, float id, float count) {
	if (shape == 0) {
		float delay = id / max(1.0, count - 1.0) * 3.8;
		vec4 f = band_at(v.x, delay);
		float difference = clamp((f.w - f.z) * 60.0, -24.0, 24.0);
		vec3 point = vec3((v.x * 2.0 - 1.0) * 6.0, 0.5 + difference / 24.0 * 3.0, -6.0 - delay * 6.0);
		vec3 tint = difference < 0.0 ? studio_channel(0.0) : studio_channel(1.0);
		return make(point + vec3(0.0, v.y * 0.03, 0.0), tint, gate(f.y) * (0.55 + abs(difference) / 24.0) * (1.0 - smoothstep(3.0, 3.8, delay)) * intensity, v.y);
	} else if (shape == 2) {
		if (id >= 9.0) return hidden();
		vec3 point = vec3((v.x * 2.0 - 1.0) * 6.0, 0.5 + (id - 4.0) * 0.75 + v.y * 0.015, -6.03);
		return make(point, id == 4.0 ? vec3(0.9, 0.85, 0.6) : vec3(0.2, 0.35, 0.5), (id == 4.0 ? 0.45 : 0.2) * intensity, v.y);
	}
	return hidden();
}

vec3 pan_trail_point(float band, float delay) {
	vec4 f = band_at(band, delay);
	vec3 point = dome(f.x * 0.62, -0.15 + band * 0.7) * (5.5 + delay * 6.0);
	point.y -= 0.5;
	return point;
}

Pulse pan_trails(vec3 v, float id, float count) {
	if (shape == 0) {
		if (id >= 48.0) return hidden();
		float band = id / 47.0;
		float delay = v.x * 3.8;
		vec4 f = band_at(band, delay);
		vec3 point = pan_trail_point(band, delay);
		vec3 next = pan_trail_point(band, delay + 0.015);
		return make(ribbon(point, next, v.y * 0.035), band_colour(band), gate(f.y) * (1.0 - smoothstep(2.8, 3.8, delay)) * 0.8 * intensity, v.y);
	} else if (shape == 1) {
		if (id >= 1536.0) return hidden();
		float band = mod(id, 48.0) / 47.0;
		float delay = floor(id / 48.0) / 31.0 * 3.8;
		vec4 f = band_at(band, delay);
		return make(pan_trail_point(band, delay) + v * (0.025 + gate(f.y) * 0.03), band_colour(band), gate(f.y) * (1.0 - delay / 3.8) * 0.65 * intensity, 0.0);
	} else if (shape == 2) {
		if (id >= 6.0) return hidden();
		vec3 point = dome(mix(-0.62, 0.62, v.x), -0.15) * (5.5 + id * 3.8 + v.y * 0.025);
		point.y -= 0.5;
		return make(point, vec3(0.2, 0.4, 0.6), 0.055 * intensity, v.y);
	}
	return hidden();
}

vec3 orrery_point(float band, float layer, float along, float channel) {
	vec4 f = band_at(band, along * 2.6);
	float level = gate(channel < 0.5 ? f.z : f.w);
	float angle = along * TAU + layer * 0.42 + spin * 0.13 * (channel < 0.5 ? 1.0 : -1.0);
	float radius = 2.2 + band * 5.6 + level * 0.65;
	vec3 p = vec3(cos(angle) * radius, sin(angle) * radius, 0.0);
	float tilt = layer * 0.31 + 0.35;
	p.yz = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt))) * p.yz;
	p.xz = mat2(vec2(0.9, 0.4359), vec2(-0.4359, 0.9)) * p.xz;
	return p + vec3(0.0, 0.8, -11.0);
}

Pulse celestial_orrery(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float channel = mod(id, 2.0);
		float band = floor(id / 2.0) / max(1.0, floor(count / 2.0) - 1.0);
		float layer = floor(id / 12.0);
		vec4 f = band_at(band, v.x * 2.6);
		float level = gate(channel < 0.5 ? f.z : f.w);
		vec3 p = orrery_point(band, layer, v.x, channel);
		vec3 next = orrery_point(band, layer, v.x + 0.002, channel);
		vec3 tint = mix(channel < 0.5 ? vec3(0.08, 0.65, 1.0) : vec3(1.0, 0.6, 0.18), band_colour(band), 0.28);
		return make(ribbon(p, next, v.y * (0.02 + level * 0.045)), tint, (0.035 + level * 0.65) * intensity, v.y);
	} else if (shape == 1) {
		float band = c.x;
		vec4 f = band_at(band, c.z * 3.2);
		float level = gate(mod(id, 2.0) < 0.5 ? f.z : f.w);
		vec3 p = orrery_point(band, floor(c.y * 12.0), fract(c.z + spin * 0.02), mod(id, 2.0));
		return make(p + v * (0.015 + level * 0.045), mix(band_colour(band), vec3(0.85, 0.95, 1.0), 0.55), level * (0.3 + c.w * 0.8) * intensity, 0.0);
	} else if (shape == 2) {
		float angle = v.x * TAU;
		float radius = 1.1 + id / count * 0.75 + bass * 0.45;
		vec3 p = vec3(cos(angle) * radius, sin(angle) * radius, sin(angle * 3.0 + spin * 0.2 + id) * 0.3);
		return make(p + vec3(0.0, 0.8, -11.0) + normalize(p) * v.y * 0.018, mix(vec3(0.3, 0.5, 1.0), vec3(1.0, 0.8, 0.4), id / count), (0.045 + bass * 0.16) * intensity, v.y);
	} else {
		float angle = v.x * TAU;
		vec3 p = dome(angle, sin(angle * 2.0 + id) * 0.3) * (13.0 + id * 0.3);
		return make(p + vec3(0.0, 0.0, -5.0) + normalize(p) * v.y * 0.025, vec3(0.15, 0.3, 0.55), (0.025 + mids * 0.035) * intensity, v.y);
	}
}

vec3 garden_point(float seed, float band, float along, float channel) {
	float angle = seed * TAU;
	float radius = 5.0 + hash(seed * 81.0) * 15.0;
	vec4 f = band_at(band, (1.0 - along) * 3.2);
	float level = gate(channel < 0.5 ? f.z : f.w);
	float height = 3.0 + hash(seed * 37.0) * 5.0;
	vec3 root = vec3(sin(angle) * radius, -3.2, cos(angle) * radius - 4.0);
	float sway = sin(along * 4.5 + clock * motion * 0.35 + seed * 31.0);
	return root + vec3(sway * along * along * (0.5 + level * 1.8), along * height, cos(along * 5.0 + seed * 19.0 + spin * 0.2) * along * 0.8);
}

Pulse abyssal_garden(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float seed = (id + 0.5) / count;
		float channel = mod(id, 2.0);
		float band = fract(id * 0.618034);
		vec4 f = band_at(band, (1.0 - v.x) * 3.2);
		float level = gate(channel < 0.5 ? f.z : f.w);
		vec3 p = garden_point(seed, band, v.x, channel);
		vec3 next = garden_point(seed, band, v.x + 0.002, channel);
		float nodes = pow(0.5 + 0.5 * cos(v.x * 90.0 - spin * 0.3 + seed * 12.0), 6.0);
		vec3 tint = mix(channel < 0.5 ? vec3(0.02, 0.95, 0.65) : vec3(0.55, 0.16, 1.0), vec3(0.5, 1.0, 1.0), nodes * v.x);
		return make(ribbon(p, next, v.y * (0.02 + sin(v.x * PI) * (0.07 + level * 0.12))), tint, (0.03 + level * (0.15 + nodes * 1.1)) * intensity, v.y);
	} else if (shape == 1) {
		vec4 f = band_at(c.x, c.w * 3.0);
		float level = gate(mod(id, 2.0) < 0.5 ? f.z : f.w);
		float angle = c.z * TAU + spin * 0.015;
		float rise = fract(c.y + clock * motion * (0.006 + c.w * 0.012));
		vec3 p = vec3(sin(angle) * (4.0 + c.x * 22.0), -3.0 + rise * 12.0, cos(angle) * (4.0 + c.x * 22.0) - 4.0);
		float fade = smoothstep(0.0, 0.12, rise) * (1.0 - smoothstep(0.75, 1.0, rise));
		return make(p + v * (0.018 + level * 0.045), mix(vec3(0.05, 0.8, 0.65), vec3(0.5, 0.45, 1.0), c.x), fade * level * (0.3 + c.w) * intensity, 0.0);
	} else if (shape == 2) {
		float angle = v.x * TAU;
		float radius = 2.5 + id / count * 28.0;
		vec4 f = band_at(fract(id * 0.618034), 0.0);
		vec3 p = vec3(sin(angle) * radius, -3.3 + sin(angle * 8.0 + radius - travel * 0.3) * (0.08 + bass * 0.2), cos(angle) * radius - 4.0);
		return make(p + vec3(0.0, v.y * 0.022, 0.0), mix(vec3(0.015, 0.2, 0.3), vec3(0.02, 0.8, 0.65), f.y), (0.05 + gate(f.y) * 0.16) * intensity, v.y);
	}
	return hidden();
}

vec3 sanctuary_point(float layer, float along, float channel) {
	float angle = along * TAU;
	vec4 f = band_at(fract(along * 2.0), layer / 19.0 * 3.2);
	float level = gate(channel < 0.5 ? f.z : f.w);
	float facets = 8.0;
	float polygon = cos(PI / facets) / cos(mod(angle, TAU / facets) - PI / facets);
	float radius = (4.2 + width * 0.8 + level * 0.35) * polygon;
	return vec3(cos(angle) * radius, sin(angle) * radius + 1.0, 8.5 - layer * 2.2);
}

Pulse prism_sanctuary(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float channel = mod(id, 2.0);
		float layer = floor(id / 8.0);
		float inset = mod(floor(id / 2.0), 4.0) * 0.045;
		vec3 p = sanctuary_point(layer, v.x, channel);
		p.xy *= 1.0 + inset;
		p.z -= channel * 0.22;
		vec3 next = sanctuary_point(layer, v.x + 0.002, channel);
		next.xy *= 1.0 + inset;
		next.z -= channel * 0.22;
		vec4 f = band_at(fract(v.x * 2.0), layer * 0.14);
		float level = gate(channel < 0.5 ? f.z : f.w);
		vec3 tint = mix(channel < 0.5 ? vec3(0.12, 0.7, 1.0) : vec3(1.0, 0.18, 0.5), vec3(0.9, 0.7, 1.0), inset * 3.0);
		return make(ribbon(p, next, v.y * (0.035 + level * 0.04)), tint, (0.04 + level * 0.8) / (1.0 + layer * 0.08) * intensity, v.y);
	} else if (shape == 1) {
		float depth = c.y * 30.0;
		vec4 f = band_at(c.x, depth / 30.0 * 3.2);
		float level = gate(mod(id, 2.0) < 0.5 ? f.z : f.w);
		float angle = c.z * TAU + spin * 0.025;
		float radius = 0.8 + c.w * 3.1;
		vec3 p = vec3(cos(angle) * radius, sin(angle) * radius + 1.0, -5.0 - depth);
		return make(p + v * (0.015 + level * 0.06), mix(vec3(0.2, 0.65, 1.0), vec3(1.0, 0.4, 0.7), c.x), level * (0.2 + pow(c.w, 6.0) * 1.4) * intensity, 0.0);
	} else if (shape == 2) {
		float angle = floor(id / 3.0) / max(1.0, floor(count / 3.0)) * TAU;
		float offset = mod(id, 3.0) * 0.035;
		float radius = 4.3 + offset + width * 0.8;
		vec3 p = vec3(cos(angle) * radius, sin(angle) * radius + 1.0, 8.5 - v.x * 44.0);
		return make(p + vec3(cos(angle), sin(angle), 0.0) * v.y * 0.02, mix(vec3(0.2, 0.4, 0.9), vec3(0.9, 0.5, 0.3), mod(id, 3.0) / 2.0), (0.055 + mids * 0.14) * (1.0 - v.x * 0.65) * intensity, v.y);
	} else {
		float angle = v.x * TAU;
		float petal = 1.6 + 0.65 * cos(angle * 8.0 + id * 0.15 + spin * 0.1);
		vec3 p = vec3(cos(angle) * petal, sin(angle) * petal + 1.0, -16.0 - id * 0.7);
		return make(p + vec3(cos(angle), sin(angle), 0.0) * v.y * 0.035, mix(vec3(0.2, 0.8, 1.0), vec3(1.0, 0.55, 0.15), id / count), (0.08 + bass * 0.3) * intensity, v.y);
	}
}

vec3 plasma_point(float band, float along, float channel) {
	vec4 f = band_at(band, along * 3.2);
	float level = gate(channel < 0.5 ? f.z : f.w);
	float angle = along * TAU * 2.5 + band * TAU + spin * 0.16 * (channel < 0.5 ? 1.0 : -1.0);
	float radius = 1.8 + along * 7.0 + level * 0.5 + bass * 0.3;
	return vec3(cos(angle) * radius, sin(angle) * radius * 0.36 + sin(along * PI) * level * 1.4, sin(angle) * radius * 0.65) + vec3(0.0, 0.7, -12.0);
}

Pulse solar_crucible(vec3 v, float id, float count, vec4 c) {
	if (shape == 0) {
		float band = floor(id / 2.0) / max(1.0, floor(count / 2.0) - 1.0);
		float channel = mod(id, 2.0);
		vec4 f = band_at(band, v.x * 3.2);
		float level = gate(channel < 0.5 ? f.z : f.w);
		vec3 p = plasma_point(band, v.x, channel);
		vec3 next = plasma_point(band, v.x + 0.002, channel);
		vec3 tint = mix(channel < 0.5 ? vec3(1.0, 0.27, 0.025) : vec3(0.85, 0.06, 0.48), vec3(1.0, 0.9, 0.45), level * (1.0 - v.x));
		return make(ribbon(p, next, v.y * (0.025 + level * 0.06)), tint, (0.025 + level * 0.6) * (1.0 - v.x * 0.6) * intensity, v.y);
	} else if (shape == 1) {
		float age = fract(c.y + clock * motion * (0.025 + c.z * 0.025));
		vec4 f = band_at(c.x, age * 3.0);
		float level = gate(mod(id, 2.0) < 0.5 ? f.z : f.w);
		float angle = c.w * TAU + age * 0.5;
		float radius = 1.8 + age * (9.0 + c.z * 8.0);
		vec3 p = dome(angle, (c.x - 0.5) * 1.4) * radius + vec3(0.0, 0.7, -12.0);
		float fade = sin(age * PI);
		return make(p + v * (0.02 + level * 0.04), mix(vec3(1.0, 0.16, 0.03), vec3(1.0, 0.8, 0.4), 1.0 - age), fade * level * (0.25 + treble * 0.5) * intensity, 0.0);
	} else if (shape == 2) {
		float angle = v.x * TAU;
		float az = id / count * TAU + spin * 0.07;
		vec4 f = band_at(id / count, 0.0);
		float level = gate(f.y);
		float radius = 1.5 + bass * 0.4 + sin(angle * 3.0 + az * 5.0) * 0.12;
		vec3 p = vec3(cos(angle) * cos(az), sin(angle), cos(angle) * sin(az)) * radius;
		return make(p + normalize(p) * v.y * 0.025 + vec3(0.0, 0.7, -12.0), mix(vec3(1.0, 0.2, 0.025), vec3(1.0, 0.85, 0.35), level), (0.055 + level * 0.28) * intensity, v.y);
	} else {
		float angle = id / count * TAU;
		float arch = v.x * PI;
		vec3 radial = vec3(cos(angle), 0.0, sin(angle));
		vec3 p = radial * (1.5 + sin(arch) * (2.0 + mids * 2.0));
		p.y = cos(arch) * (1.9 + bass * 0.5);
		return make(p + radial * v.y * 0.04 + vec3(0.0, 0.7, -12.0), vec3(1.0, 0.4, 0.08), (0.08 + mids * 0.3) * intensity, v.y);
	}
}

void vertex() {
	float id = float(INSTANCE_ID);
	float count = max(1.0, float(instance_count));
	vec4 c = INSTANCE_CUSTOM;
	Pulse p;
	if (stereo_style == 0) {
		p = source_stage(VERTEX, id, count, c);
	} else if (stereo_style == 1) {
		p = vectorscope(VERTEX, id, count, c);
	} else if (stereo_style == 2) {
		p = lissajous_tunnel(VERTEX, id, count, c);
	} else if (stereo_style == 3) {
		p = constellation(VERTEX, id, count, c);
	} else if (stereo_style == 4) {
		p = terrain(VERTEX, id, count, c);
	} else if (stereo_style == 5) {
		p = fireworks(VERTEX, id, count, c);
	} else if (stereo_style == 6) {
		p = planets(VERTEX, id, count, c);
	} else if (stereo_style == 7) {
		p = aurora(VERTEX, id, count, c);
	} else if (stereo_style == 8) {
		p = ripples(VERTEX, id, count, c);
	} else if (stereo_style == 9) {
		p = harp(VERTEX, id, count, c);
	} else if (stereo_style == 10) {
		p = radar(VERTEX, id, count, c);
	} else if (stereo_style == 11) {
		p = analyzer(VERTEX, id, count, c);
	} else if (stereo_style == 12) {
		p = comets(VERTEX, id, count, c);
	} else if (stereo_style == 13) {
		p = bloom(VERTEX, id, count, c);
	} else if (stereo_style == 14) {
		p = width_tunnel(VERTEX, id, count, c);
	} else if (stereo_style == 15) {
		p = choir(VERTEX, id, count, c);
	} else if (stereo_style == 16) {
		p = point_cloud(VERTEX, id, count, c);
	} else if (stereo_style == 17) {
		p = binary(VERTEX, id, count, c);
	} else if (stereo_style == 18) {
		p = tesla(VERTEX, id, count, c);
	} else if (stereo_style == 19) {
		p = pendulums(VERTEX, id, count, c);
	} else if (stereo_style == 20) {
		p = phosphor_dome(VERTEX, id, count, c);
	} else if (stereo_style == 21) {
		p = polar_scope(VERTEX, id, count, c);
	} else if (stereo_style == 22) {
		p = scope_halo(VERTEX, id, count, c);
	} else if (stereo_style == 23) {
		p = scope_kaleidoscope(VERTEX, id, count, c);
	} else if (stereo_style == 24) {
		p = stereo_helix(VERTEX, id, count, c);
	} else if (stereo_style == 25) {
		p = terrain_canyon(VERTEX, id, count, c);
	} else if (stereo_style == 26) {
		p = pan_ridges(VERTEX, id, count, c);
	} else if (stereo_style == 27) {
		p = terrain_tunnel(VERTEX, id, count, c);
	} else if (stereo_style == 28) {
		p = neon_mirror(VERTEX, id, count, c);
	} else if (stereo_style == 29) {
		p = crystal_city(VERTEX, id, count, c);
	} else if (stereo_style == 30) {
		p = spectrum_observatory(VERTEX, id, count);
	} else if (stereo_style == 31) {
		p = phase_cathedral(VERTEX, id, count);
	} else if (stereo_style == 32) {
		p = stereo_ribbonfall(VERTEX, id, count);
	} else if (stereo_style == 33) {
		p = pan_meridian(VERTEX, id, count);
	} else if (stereo_style == 34) {
		p = transient_loom(VERTEX, id, count);
	} else if (stereo_style == 35) {
		p = stereo_difference(VERTEX, id, count);
	} else if (stereo_style == 36) {
		p = mid_side_atrium(VERTEX, id, count);
	} else if (stereo_style == 37) {
		p = correlation_causeway(VERTEX, id, count);
	} else if (stereo_style == 38) {
		p = stereo_spectrogram(VERTEX, id, count);
	} else if (stereo_style == 39) {
		p = pan_trails(VERTEX, id, count);
	} else if (stereo_style == 40) {
		p = dual_waveform(VERTEX, id, count);
	} else if (stereo_style == 41) {
		p = spectral_balance(VERTEX, id, count);
	} else if (stereo_style == 42) {
		p = celestial_orrery(VERTEX, id, count, c);
	} else if (stereo_style == 43) {
		p = abyssal_garden(VERTEX, id, count, c);
	} else if (stereo_style == 44) {
		p = prism_sanctuary(VERTEX, id, count, c);
	} else if (stereo_style == 45) {
		p = solar_crucible(VERTEX, id, count, c);
	} else {
		p = hidden();
	}
	VERTEX = p.point;
	colour = p.colour;
	edge = p.edge;
	glow = p.glow * (1.0 - smoothstep(42.0, 60.0, length(p.point))) * smoothstep(0.35, 1.0, length(p.point));
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
