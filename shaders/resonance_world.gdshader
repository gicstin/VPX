shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/resonance_world.gdshaderinc"

varying vec3 tint;
varying float light;
varying vec2 quad_uv;
varying float profile_kind;

struct Part {
	vec3 position;
	vec3 colour;
	float glow;
	vec2 uv;
	float kind;
};

vec3 facing_right(vec3 p) {
	vec3 flat_dir = vec3(p.x, 0.0, p.z);
	return normalize(cross(vec3(0.0, 1.0, 0.0), flat_dir + vec3(0.00001, 0.0, 0.00001)));
}

void billboard(inout vec3 centre, vec2 uv, float size, mat3 view_to_model) {
	vec3 right = normalize(view_to_model * vec3(1.0, 0.0, 0.0));
	vec3 up = normalize(view_to_model * vec3(0.0, 1.0, 0.0));
	centre += right * uv.x * size + up * uv.y * size;
}

Part motes(float id, vec2 uv, mat3 view_to_model) {
	Part part = Part(vec3(0.0), vec3(1.0), 0.0, uv, 2.0);
	float count = float(instance_count);
	float sparks = floor(count * 0.25);
	float t = clock * motion;
	if (id >= count - sparks) {
		float k = id - (count - sparks);
		int slot = int(mod(k, 8.0));
		vec4 b = source_bursts[slot];
		float seed = k * 3.7 + floor(b.x * 97.0 + b.y * 41.0);
		vec3 dir = normalize(vec3(hash(seed) - 0.5, hash(seed + 1.0) - 0.3, hash(seed + 2.0) - 0.5));
		float age = b.z;
		vec3 origin = source_position(slot);
		vec3 p = origin + dir * age * (2.5 + hash(seed + 3.0) * 3.0);
		p.y -= age * age * (world_style == 2 ? 0.15 : 0.9);
		float size = 0.04 + 0.05 * hash(seed + 4.0);
		billboard(p, uv, size, view_to_model);
		part.position = p;
		part.colour = mix(source_colour(slot), vec3(1.0), 0.35);
		part.glow = clamp(b.w, 0.0, 1.0) * exp(-age * 2.2) * source_alive(slot) * 1.6;
		return part;
	}
	float h1 = hash(id + 1.0);
	float h2 = hash(id + 2.0);
	float h3 = hash(id + 3.0);
	float h4 = hash(id + 4.0);
	float radius = mix(2.2, 34.0, pow(h1, 1.4));
	float a = h2 * TAU;
	float y;
	if (world_style == 1) {
		y = ground_level + fract(h3 + t * (0.006 + h4 * 0.01)) * 24.0;
		radius = mix(1.8, 12.5, h1);
	} else if (world_style == 2) {
		y = mix(ground_level + 0.5, 9.0, h3);
	} else {
		y = mix(ground_level + 0.15, 12.0, pow(h3, 1.6));
	}
	vec3 home = vec3(sin(a) * radius, y, -cos(a) * radius);
	vec3 drift = vec3(sin(t * 0.13 + h4 * TAU), sin(t * 0.11 + h1 * TAU) * 0.6, cos(t * 0.17 + h3 * TAU)) * (0.25 + radius * 0.025);
	if (world_style == 2) {
		drift *= 1.6;
	}
	vec3 outward = normalize(home + vec3(0.0001));
	vec3 p = home + drift + outward * percussive * (0.45 - radius * 0.01) * (0.5 + h4);
	float size = (0.018 + 0.035 * h4) * (1.0 + radius * 0.045) * (1.0 + percussive * 0.4 + flash * 0.5);
	billboard(p, uv, size, view_to_model);
	part.position = p;
	float twinkle = 0.65 + 0.35 * sin(t * (1.0 + h1 * 3.0) + h2 * 40.0) * treble;
	float lift = 0.14 + harmonic * 0.45 + section_energy * 0.2 + build * 0.35 + drop_pulse * 0.5 + percussive * 0.55;
	part.colour = palette3(h2 + h3 * 0.3);
	part.glow = lift * twinkle * exp(-radius / 30.0) * (world_style == 2 ? 0.8 : 1.0) * mix(0.35, 1.4, sound_at(a, radius * 0.02));
	return part;
}

Part sources_part(float id, float u, float y) {
	Part part = Part(vec3(0.0), vec3(1.0), 0.0, vec2(0.0, y), 1.0);
	int slot = int(mod(id, 8.0));
	int piece = int(id / 8.0);
	float alive = source_alive(slot);
	vec3 s = source_position(slot);
	float level = sources[slot].z;
	float glow = burst_glow(slot) + source_info[slot].z * 0.5;
	vec3 colour = mix(source_colour(slot), mix(colour_a, colour_c, clamp(sources[slot].y, 0.0, 1.0)), 0.45);
	vec3 forward = normalize(s + vec3(0.0001));
	vec3 right = facing_right(s);
	vec3 up = normalize(cross(forward, right));
	part.colour = colour;
	if (piece == 0) {
		vec3 p;
		float width;
		if (world_style == 2) {
			float hang = u * (4.0 + level * 3.0);
			p = s + vec3(sin(u * 5.0 + clock * motion * 0.8 + float(slot)) * 0.35 * u, -hang, cos(u * 4.0 + clock * motion * 0.6) * 0.25 * u);
			width = 0.05 * (1.0 - u * 0.7);
			part.glow = alive * (0.35 + level * 0.6 + glow) * (1.0 - u * 0.6);
		} else if (world_style == 1) {
			p = vec3(s.x, mix(ground_level, s.y + 24.0, u), s.z);
			width = 0.3 + level * 0.6;
			part.glow = alive * (0.08 + level * 0.25 + glow * 0.3) * exp(-abs(p.y - s.y) * 0.16);
		} else {
			p = vec3(s.x, mix(ground_level, s.y + 7.0, u), s.z);
			width = 0.05 + level * 0.12;
			part.glow = alive * (0.15 + level * 0.5 + glow * 0.6) * exp(-abs(p.y - s.y) * 0.25);
		}
		part.position = p + right * y * width;
		part.uv = vec2(0.0, y);
		part.kind = 1.0;
	} else if (piece == 1) {
		float angle = u * TAU;
		float pulse = world_style == 2 ? 0.25 * sin(beat_phase * TAU) : 0.0;
		float radius = (world_style == 2 ? 0.9 + level * 1.3 : 0.45 + level * 0.9 + burst_glow(slot) * 0.8) * (1.0 + pulse);
		vec3 ring = right * cos(angle) + up * sin(angle);
		vec3 p = s + ring * radius;
		if (world_style == 2) {
			p = s + (right * cos(angle) + forward * sin(angle)) * radius + vec3(0.0, sin(angle * 8.0) * 0.06 - 0.1, 0.0);
		}
		part.position = p + normalize(p - s + vec3(0.00001)) * y * (0.025 + level * 0.03);
		part.glow = alive * (0.35 + level * 0.5 + glow) * 0.8;
		part.uv = vec2(0.0, y);
		part.kind = 1.0;
	} else {
		vec2 q = vec2(u * 2.0 - 1.0, y);
		float size = (0.35 + level * 0.9 + glow * 0.6) * (world_style == 2 ? 1.15 : 1.0);
		part.position = s + right * q.x * size + up * q.y * size;
		part.glow = alive * (0.4 + level * 0.8 + glow * 1.2 + percussive * 0.4) * (world_style == 2 ? 0.9 : 1.0);
		part.colour = mix(colour, vec3(1.0), 0.25);
		part.uv = q;
		part.kind = 2.0;
	}
	return part;
}

Part structures(float id, float u, float y) {
	Part part = Part(vec3(0.0), vec3(1.0), 0.0, vec2(0.0, y), 1.0);
	float t = clock * motion;
	part.kind = 1.0;
	part.uv = vec2(0.0, y);
	if (world_style == 1) {
		float pillar = mod(id, 16.0);
		float a = pillar / 16.0 * TAU;
		vec3 base = vec3(sin(a) * 13.0, ground_level, -cos(a) * 13.0);
		float sound = sound_at(a, 0.0);
		if (id < 16.0) {
			float height = 26.0;
			vec3 p = base + vec3(0.0, u * height, 0.0);
			part.position = p + facing_right(base) * y * (1.1 + sound * 0.4);
			float rise = fract(beat_phase + 0.0);
			float band = exp(-pow((u - rise) * 10.0, 2.0)) * (0.3 + beat_glow() * 0.7);
			part.glow = 0.05 + sound * 0.35 + band * (0.25 + percussive * 0.5) + harmonic * 0.08 + (1.0 - u) * min(bass, 1.0) * 0.35 + u * u * min(treble, 1.0) * 0.6 + build * u * 0.35;
			part.colour = palette3(pillar / 16.0);
		} else {
			vec3 top = base + vec3(0.0, 26.0, 0.0);
			vec3 crown = vec3(0.0, 34.0, 0.0);
			vec3 p = mix(top, crown, u);
			p.y += sin(u * PI) * 4.0;
			vec3 along = normalize(crown - top);
			vec3 across = normalize(cross(along, vec3(0.0, 1.0, 0.0)) + vec3(0.00001));
			part.position = p + across * y * 0.3;
			part.glow = 0.04 + harmonic * 0.18 + bar_pulse * 0.25 + anticipation * 0.4 + drop_pulse * 0.4 + min(treble, 1.0) * 0.3 + build * 0.3;
			part.colour = palette3(pillar / 16.0 + 0.33);
		}
	} else if (world_style == 2) {
		float h1 = hash(id + 11.0);
		float h2 = hash(id + 12.0);
		float a = h1 * TAU;
		float r = mix(5.0, 28.0, h2);
		vec3 base = vec3(sin(a) * r, ground_level, -cos(a) * r);
		float height = mix(6.0, 16.0, hash(id + 13.0));
		float sway = sin(t * 0.35 + h1 * 9.0 + u * 2.2) * (0.3 + u * 1.6) + percussive * u * 0.6;
		vec3 p = base + vec3(sway * cos(a), u * height, sway * sin(a));
		part.position = p + facing_right(base) * y * (0.12 + (1.0 - u) * 0.12);
		float dot_run = exp(-pow((fract(u * 3.0 - beat_phase) - 0.5) * 6.0, 2.0));
		float near_sound = sound_at(a, u);
		part.glow = 0.025 + near_sound * 0.2 + (dot_run * beat_glow() * 0.25 + harmonic * 0.05) * mix(0.25, 1.2, near_sound) + (1.0 - u) * min(bass, 1.0) * 0.12 + u * min(treble, 1.0) * 0.18;
		part.colour = palette3(h1 * 0.5 + u * 0.3);
	} else {
		float a = id / max(1.0, float(instance_count)) * TAU;
		float sound = sound_at(a, 0.1);
		vec3 centre = vec3(sin(a) * 42.0, ground_level + 9.0 + sound * 4.0, -cos(a) * 42.0);
		float radius = 3.0 + sound * 5.0 + section_energy * 2.0 + build * 2.0;
		float angle = u * TAU + t * 0.05 + bar_phase * TAU * 0.25;
		vec3 right = facing_right(centre);
		vec3 ring = right * cos(angle) + vec3(0.0, 1.0, 0.0) * sin(angle);
		vec3 p = centre + ring * radius;
		part.position = p + ring * y * (0.12 + sound * 0.25);
		float sweep = exp(-pow(wrap_angle(a - TAU * fract(bar_phase)) * 2.0, 2.0)) * bar_pulse;
		part.glow = 0.05 + sound * 0.5 + sweep * 0.4 + anticipation * 0.35 * exp(-pow(wrap_angle(a) * 1.5, 2.0));
		part.colour = palette3(a / TAU + section_energy * 0.2);
	}
	return part;
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec2 uv = VERTEX.xy;
	mat3 view_to_model = inverse(mat3(MODEL_MATRIX)) * mat3(INV_VIEW_MATRIX);
	Part part;
	if (shape == 1) {
		part = motes(id, uv, view_to_model);
	} else if (shape == 2) {
		part = sources_part(id, VERTEX.x, VERTEX.y);
	} else {
		part = structures(id, VERTEX.x, VERTEX.y);
	}
	VERTEX = part.position;
	tint = part.colour;
	light = part.glow;
	quad_uv = part.uv;
	profile_kind = part.kind;
}

void fragment() {
	float profile;
	if (profile_kind > 1.5) {
		float r = dot(quad_uv, quad_uv);
		profile = exp(-r * 5.0) * 0.7 + exp(-r * 28.0) * 0.3;
	} else {
		float e = abs(quad_uv.y);
		profile = pow(max(0.0, 1.0 - e), 2.0) * 0.7 + (1.0 - smoothstep(0.1, 0.2, e)) * 0.3;
	}
	float scale = shape == 1 ? 0.9 : (shape == 2 ? 1.0 : 0.8);
	ALBEDO = tint * light * profile * scale * intensity * dim * energy_level() * (1.0 + flash * 0.35);
}
