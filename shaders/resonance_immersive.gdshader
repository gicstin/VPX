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
uniform int immersive_style = 0;
uniform int shape = 0;
uniform int instance_count = 18;
uniform int object_count = 18;
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
varying vec2 surface_uv;
varying vec3 local_point;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float energy(float pitch, float channel, float age) {
	float band = mix(0.5 / 48.0, 47.5 / 48.0, clamp(pitch, 0.0, 1.0));
	float row = (spectral_channel_count == 1 ? 0.0 : channel) * 192.0;
	float index = float(spectral_history_head) + min(0.0, spectral_history_fraction - age * 45.0);
	float first = mod(floor(index), 192.0);
	float second = mod(first + 1.0, 192.0);
	float past = mix(textureLod(spectral_history_texture, vec2(band, (row + first + 0.5) / 384.0), 0.0).r,
		textureLod(spectral_history_texture, vec2(band, (row + second + 0.5) / 384.0), 0.0).r, fract(index));
	past *= 1.0 - smoothstep(spectral_history_valid * 3.8, spectral_history_valid * 3.8 + 0.05, age);
	float current = textureLod(spectrum_texture, vec2(band, (channel + 0.5) / 50.0), 0.0).r;
	return 1.0 - exp(-pow(max(mix(current, past, smoothstep(0.0, 0.12, age)), 0.0), 1.6) * sensitivity * 1.8);
}

vec3 colour(float seed, float channel) {
	vec3 a = vec3(1.0, 0.38, 0.055);
	vec3 b = vec3(0.06, 0.7, 1.0);
	if (immersive_style == 1) { a = vec3(0.06, 0.9, 1.0); b = vec3(0.85, 0.12, 0.9); }
	if (immersive_style == 2) { a = vec3(0.25, 1.0, 0.45); b = vec3(0.55, 0.2, 1.0); }
	if (immersive_style == 3) { a = vec3(1.0, 0.65, 0.035); b = vec3(1.0, 0.12, 0.28); }
	if (immersive_style == 4) { a = vec3(0.02, 0.7, 0.42); b = vec3(0.08, 0.35, 1.0); }
	if (immersive_style == 5) { a = vec3(1.0, 0.08, 0.32); b = vec3(0.1, 0.55, 1.0); }
	if (immersive_style == 6) { a = vec3(0.7, 0.25, 1.0); b = vec3(0.02, 1.0, 0.68); }
	if (immersive_style == 7) { a = vec3(0.1, 0.35, 1.0); b = vec3(1.0, 0.72, 0.12); }
	if (immersive_style == 8) { a = vec3(0.1, 0.8, 1.0); b = vec3(1.0, 0.18, 0.35); }
	if (immersive_style == 9) { a = vec3(1.0, 0.16, 0.04); b = vec3(0.45, 0.1, 1.0); }
	return mix(a, b, channel) * (0.75 + seed * 0.25);
}

vec3 orient(vec3 p, float az, vec3 centre) {
	return centre + vec3(cos(az) * p.z + sin(az) * p.x, p.y, sin(az) * p.z - cos(az) * p.x);
}

vec3 polygon(float u, float sides) {
	float side = floor(u * sides);
	float a = side * TAU / sides;
	float b = a + TAU / sides;
	return mix(vec3(cos(a), sin(a), 0.0), vec3(cos(b), sin(b), 0.0), fract(u * sides));
}

vec3 tetra(float digit) {
	if (digit < 0.5) { return vec3(0.0, 1.4, 0.0); }
	float a = (digit - 1.0) * TAU / 3.0;
	return vec3(cos(a) * 1.3, -0.7, sin(a) * 1.3);
}

vec3 surface(float u, float v, float id, float signal, float wave, float t) {
	float a = u * TAU;
	float w = v * 2.0 - 1.0;
	float hit = impulse + transients.x * 0.45;
	float az = id / max(1.0, float(object_count)) * TAU;
	vec3 centre = vec3(cos(az), 0.0, sin(az)) * 11.0;
	if (immersive_style == 0) {
		az = mod(id, 6.0) * TAU / 6.0;
		centre = vec3(cos(az) * 10.5, (floor(id / 6.0) - 1.0) * 5.5, sin(az) * 10.5);
		a += t * 0.18 * (mod(id, 2.0) * 2.0 - 1.0) + hit * 0.12;
		float tooth = smoothstep(-0.35, 0.35, cos(u * TAU * 16.0));
		float r = mix(0.85, 2.15 + tooth * 0.4, v) * (1.0 + signal * 0.16 + bass * 0.1);
		return orient(vec3(cos(a) * r, sin(a) * r, sin(v * PI) * 0.28 + wave * 0.2), az, centre);
	}
	if (immersive_style == 1) {
		az = mod(id, 6.0) * TAU / 6.0;
		centre = vec3(cos(az) * 10.0, (floor(id / 6.0) - 0.5) * 6.5 + sin(t * 0.7 + id) * 0.55 + 1.5, sin(az) * 10.0);
		float pump = 1.0 + bass * 0.2 + sin(t * 1.4 + id) * 0.08 + hit * 0.16;
		float r = sin(v * PI * 0.5) * (1.5 + signal * 0.4) * pump;
		r += wave * 0.17 * v;
		return centre + vec3(cos(a) * r, cos(v * PI * 0.5) * 1.8 + sin(a * 12.0) * pow(v, 6.0) * 0.12, sin(a) * r);
	}
	if (immersive_style == 2) {
		az += (u - 0.5) * 2.7 + t * 0.09;
		float r = 9.0 + sin(u * 12.0 + id + t * 0.6) * 1.5 + signal * 0.6;
		centre = vec3(cos(az) * r, sin(u * TAU + id * 2.1 + t * 0.3) * 5.5, sin(az) * r);
		float girth = (0.08 + pow(max(0.0, sin(u * PI)), 0.6) * (0.45 + signal * 0.28)) * (1.0 + hit * 0.15);
		return centre + vec3(cos(az) * cos(v * TAU) * girth, sin(v * TAU) * girth + wave * 0.35, sin(az) * cos(v * TAU) * girth);
	}
	if (immersive_style == 3) {
		float row = floor(id / 9.0);
		az = (mod(id, 9.0) + mod(row, 2.0) * 0.5) * TAU / 9.0;
		centre = vec3(cos(az) * 12.0, (row - 2.5) * 3.2, sin(az) * 12.0);
		vec3 hex = polygon(u, 6.0);
		float r = mix(0.82, 1.85, v) * (0.92 + signal * 0.12);
		return orient(vec3(hex.xy * r, sin(v * PI) * (0.6 + bass) + wave * 0.25 + hit * (0.3 + hash(id))), az, centre);
	}
	if (immersive_style == 4) {
		float fan = floor(id / 7.0);
		float feather = mod(id, 7.0) - 3.0;
		az = fan * TAU / 4.0;
		centre = vec3(cos(az) * 8.0, -4.0, sin(az) * 8.0);
		float spread = feather * (0.30 + bass * 0.055 + hit * 0.035);
		float length = 8.0 + signal * 1.2;
		float width = sin(u * PI) * (0.78 + signal * 0.18) * w;
		vec3 p = vec3(sin(spread) * u * length + cos(spread) * width, cos(spread) * u * length - sin(spread) * width, sin(u * PI) * 0.7 + wave * 0.35 + sin(t * 0.45 + feather) * u * 0.25);
		return orient(p, az, centre);
	}
	if (immersive_style == 5) {
		az = mod(id, 4.0) * TAU / 4.0 - PI * 0.5;
		centre = vec3(cos(az) * 9.0, (floor(id / 4.0) - 0.5) * 6.0, sin(az) * 9.0);
		float r = 2.5 + bass * 0.4;
		float width = w * (0.8 + signal * 0.25);
		vec3 p = vec3((r + width * cos(a * 0.5)) * cos(a), (r + width * cos(a * 0.5)) * sin(a), width * sin(a * 0.5));
		p.z += wave * 0.15 * sin(a) + hit * sin(a * 3.0) * 0.25;
		float roll = t * 0.14 + id;
		p.xz = mat2(vec2(cos(roll), sin(roll)), vec2(-sin(roll), cos(roll))) * p.xz;
		return orient(p, az, centre);
	}
	if (immersive_style == 6) {
		az = floor(id / 16.0) * TAU / 4.0;
		centre = vec3(cos(az) * 11.0, 0.0, sin(az) * 11.0);
		float address = mod(id, 16.0);
		vec3 offset = tetra(mod(address, 4.0)) * 2.8 + tetra(floor(address / 4.0)) * 1.4;
		vec3 rim = vec3(polygon(u, 3.0).x, -0.7, polygon(u, 3.0).y) * 0.85;
		vec3 p = mix(rim, vec3(0.0, 1.2, 0.0), v) * (0.9 + signal * 0.2);
		p += offset * (1.0 + hit * 0.12) + vec3(0.0, wave * 0.2, 0.0);
		float turn = t * 0.12;
		p.xz = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * p.xz;
		return orient(p, az, centre);
	}
	if (immersive_style == 7) {
		centre.y = (mod(id, 2.0) - 0.5) * 3.0;
		vec2 p = vec2(cos(a), sin(a)) * v * (3.3 + bass * 0.3);
		float nodes = sin(p.x * 2.2) * sin(p.y * 3.3) - sin(p.x * 3.3) * sin(p.y * 2.2);
		float vibration = nodes * (signal * 0.55 + wave * 0.8 + hit * 0.5);
		float roll = sin(t * 0.25 + id) * 0.18;
		p = mat2(vec2(cos(roll), sin(roll)), vec2(-sin(roll), cos(roll))) * p;
		return orient(vec3(p, vibration), az, centre);
	}
	if (immersive_style == 8) {
		az = id * 2.399963;
		float r = 8.0 + hash(id + 3.0) * 7.0 + hit * 0.7;
		centre = vec3(cos(az) * r, (hash(id + 8.0) - 0.5) * 15.0, sin(az) * r);
		vec3 p = vec3(w * (1.0 - u) * (0.8 + signal * 0.45), u * (3.5 + bass) - 1.5, abs(w) * (1.0 - u) * (0.45 + hit) + wave * sin(u * PI) * 0.45);
		float turn = t * 0.18 * (hash(id + 4.0) * 2.0 - 1.0) + id;
		p.xy = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * p.xy;
		return orient(p, az, centre);
	}
	az = floor(id / 4.0) * TAU / 4.0;
	centre = vec3(cos(az) * 12.0, 0.0, sin(az) * 12.0);
	float layer = mod(id, 4.0);
	float phase = t * 0.12 + layer * 0.23;
	float lobe = 1.0 + bass * 0.2 + wave * 0.12 + hit * 0.2;
	vec3 p = vec3(3.4 * cos(a * 2.0) + lobe * 1.4 * cos(5.0 * a), 3.4 * sin(a * 2.0) - lobe * 1.4 * sin(5.0 * a), sin(a * 3.0 + phase) * 1.4 + (layer - 1.5) * 0.7);
	p.xy = mat2(vec2(cos(phase), sin(phase)), vec2(-sin(phase), cos(phase))) * p.xy;
	p += vec3(cos(a) * cos(v * TAU), sin(a) * cos(v * TAU), sin(v * TAU)) * (0.045 + signal * 0.09);
	return orient(p, az, centre);
}

vec3 tentacle(float u, float id, float signal, float wave, float t) {
	float jelly = floor(id / 8.0);
	float a = mod(id, 8.0) * TAU / 8.0;
	vec3 rim = surface(a / TAU, 1.0, jelly, signal, 0.0, t);
	float sway = u * u * (0.5 + signal * 0.5);
	return rim + vec3(sin(u * 9.0 + t * 1.2 + a) * sway + wave * u * 0.55, -u * (3.0 + hash(id) * 1.7), cos(u * 7.0 - t * 0.8 + a) * sway);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float t = clock * motion;
	float u = VERTEX.x;
	float ribbon_edge = VERTEX.y;
	float v = shape == 0 ? VERTEX.y : 0.5;
	float object = shape == 0 ? id : mod(id, float(object_count));
	if (shape == 2 && immersive_style == 1) { object = floor(id / 8.0); }
	float channel = mod(object, 2.0);
	float pitch = hash(object + 11.0);
	float age = shape == 2 ? floor(id / float(object_count)) * 0.12 : 0.0;
	float signal = energy(pitch, channel, age);
	bool closed = immersive_style != 2 && immersive_style != 4 && immersive_style != 8;
	float wave = closed ? loop_sample(wave_texture, u, (channel + 0.5) * 0.5, 256.0) : textureLod(wave_texture, vec2(mix(0.5 / 256.0, 255.5 / 256.0, u), (channel + 0.5) * 0.5), 0.0).r;
	surface_uv = vec2(u, v);
	tint = colour(pitch, channel);
	light = 0.004 + signal * 1.15 + impulse * 0.32 + dot(transients, vec3(0.08));
	local_point = vec3(0.0);
	if (shape == 1) {
		float seed = hash(id + 5.0);
		float az = hash(id + 7.0) * TAU;
		float phase = fract(seed + t * 0.025);
		signal = energy(seed, mod(id, 2.0), 0.0);
		vec3 p = vec3(cos(az) * (7.0 + seed * 16.0), (phase - 0.5) * 22.0, sin(az) * (7.0 + seed * 16.0));
		VERTEX = p + VERTEX * (0.012 + signal * 0.025 + treble * 0.012);
		tint = colour(seed, mod(id, 2.0));
		light = signal * (0.1 + treble * 0.4) * sin(phase * PI);
	} else if (shape == 2) {
		float trail = floor(id / float(object_count));
		v = mod(trail, 2.0) < 0.5 ? 0.015 : 0.985;
		if (immersive_style == 2 || immersive_style == 9) { v = trail / max(1.0, floor(float(instance_count) / float(object_count))); }
		if (immersive_style == 7) { v = 0.4 + trail * 0.19; }
		vec3 p;
		vec3 tangent;
		if (immersive_style == 1) {
			p = tentacle(u, id, signal, wave, t);
			tangent = tentacle(u + 0.001, id, signal, wave, t) - tentacle(u - 0.001, id, signal, wave, t);
		} else {
			float phase = immersive_style == 5 ? u * 2.0 : u;
			if (immersive_style == 5) { v = 0.985; }
			p = surface(phase, v, object, signal, wave, t - age);
			tangent = surface(phase + 0.001, v, object, signal, wave, t - age) - surface(phase - 0.001, v, object, signal, wave, t - age);
		}
		vec3 across = cross(tangent, normalize(-p + vec3(0.0001)));
		across /= max(length(across), 0.00001);
		VERTEX = p + across * VERTEX.y * (0.018 + signal * 0.026 + impulse * 0.016);
		surface_uv = vec2(u, ribbon_edge);
		local_point.x = ribbon_edge;
		light *= exp(-trail * 0.3);
	} else {
		VERTEX = surface(u, v, object, signal, wave, t);
		local_point = vec3(cos(u * TAU), sin(u * TAU), 0.0) * v * (3.3 + bass * 0.3);
	}
}

void fragment() {
	vec2 uv = surface_uv;
	float ink = 1.0;
	vec3 pigment = tint;
	if (shape == 0) {
		float edge = min(uv.y, 1.0 - uv.y);
		float rim = exp(-edge * 65.0);
		ink = 0.025 + rim * 0.7;
		if (immersive_style == 0) {
			float spoke = pow(0.5 + 0.5 * cos(uv.x * TAU * 8.0), 18.0);
			ink = 0.08 + rim * 0.8 + spoke * 0.2;
			pigment *= 0.6 + 0.4 * sin(uv.y * PI);
		} else if (immersive_style == 1) {
			float rib = pow(0.5 + 0.5 * cos(uv.x * TAU * 12.0), 22.0);
			ink = 0.035 + rib * 0.28 + rim * 0.4;
		} else if (immersive_style == 2) {
			float rib = pow(0.5 + 0.5 * sin(uv.x * 160.0), 8.0);
			ink = (0.08 + rib * 0.42) * sin(uv.x * PI);
			pigment = mix(tint, vec3(0.6, 0.8, 1.0), pow(0.5 + 0.5 * sin(uv.y * TAU), 8.0) * 0.7);
		} else if (immersive_style == 3) {
			ink = 0.035 + rim * 0.8 + pow(0.5 + 0.5 * cos(uv.x * TAU * 6.0), 40.0) * 0.2;
		} else if (immersive_style == 4) {
			vec2 eye = vec2((uv.x - 0.78) * 12.0, (uv.y - 0.5) * 2.5);
			float radius = length(eye);
			float iris = exp(-pow((radius - 0.45) * 10.0, 2.0));
			float gold = exp(-pow((radius - 0.8) * 10.0, 2.0));
			float vane = pow(0.5 + 0.5 * cos(uv.x * 200.0 + abs(uv.y - 0.5) * 24.0), 12.0);
			ink = 0.04 + vane * 0.2 + iris * 0.8 + gold * 0.8 + exp(-abs(uv.y - 0.5) * 90.0) * 0.35;
			pigment = mix(tint, vec3(0.05, 0.2, 1.0), iris);
			pigment = mix(pigment, vec3(1.0, 0.7, 0.08), gold);
		} else if (immersive_style == 5) {
			ink = 0.06 + rim * 0.6 + pow(0.5 + 0.5 * cos(uv.y * 26.0 + uv.x * TAU * 4.0), 14.0) * 0.24;
			pigment = mix(tint, vec3(0.55, 0.8, 1.0), pow(sin(uv.y * PI), 8.0) * 0.4);
		} else if (immersive_style == 6) {
			float side = min(fract(uv.x * 3.0), 1.0 - fract(uv.x * 3.0));
			ink = 0.045 + rim * 0.35 + exp(-side * 65.0) * 0.55;
		} else if (immersive_style == 7) {
			vec2 p = local_point.xy;
			float nodes = sin(p.x * 2.2) * sin(p.y * 3.3) - sin(p.x * 3.3) * sin(p.y * 2.2);
			float aa = max(fwidth(nodes), 0.025);
			float line = 1.0 - smoothstep(0.0, aa * 1.5, abs(nodes));
			ink = 0.015 + line * 0.55 + exp(-(1.0 - uv.y) * 80.0) * 0.5;
			pigment = mix(tint, vec3(1.0, 0.72, 0.12), line * 0.8);
		} else if (immersive_style == 8) {
			ink = 0.07 + rim * 0.7 + exp(-abs(uv.y - 0.5) * 75.0) * 0.5;
			pigment *= uv.y < 0.5 ? vec3(0.45, 0.7, 1.0) : vec3(1.0, 0.65, 0.7);
		} else {
			ink = 0.12 + pow(0.5 + 0.5 * sin(uv.y * TAU), 6.0) * 0.8;
		}
	} else if (shape == 2) {
		ink = pow(max(0.0, 1.0 - abs(local_point.x)), 1.5);
	}
	vec3 c = pigment * light * ink * intensity * dim;
	ALBEDO = c;
	EMISSION = c * 0.3;
	ALPHA = 1.0;
}
