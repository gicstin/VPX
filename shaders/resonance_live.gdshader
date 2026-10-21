shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/visualizer_loop.gdshaderinc"

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform sampler2D wave_texture : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_enable;
uniform sampler2D spectral_history_texture : filter_linear, repeat_disable;
uniform int spectral_history_head = -1;
uniform float spectral_history_fraction = 0.0;
uniform float spectral_history_valid = 0.0;
uniform int spectral_channel_count = 2;
uniform float history_head = 0.0;
uniform int live_style = 0;
uniform int shape = 0;
uniform int instance_count = 72;
uniform float clock = 0.0;
uniform float travel = 0.0;
uniform float spin = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float impulse = 0.0;
uniform vec3 transients = vec3(0.0);
uniform float beat_age = 4.0;
uniform float stereo_width = 0.0;
uniform float release = 0.0;
uniform float arousal = 0.0;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float motion = 0.6;
uniform float dim = 1.0;

varying vec3 tint;
varying float light;
varying float edge;
varying vec2 mote_uv;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float gate(float value) {
	return 1.0 - exp(-pow(max(0.0, value - 0.12) / 0.88, 2.1) * sensitivity * 1.8);
}

float energy(float u, float channel, float delay) {
	float x = mix(0.5 / 48.0, 47.5 / 48.0, clamp(u, 0.0, 1.0));
	if (delay < 0.001) {
		return gate(textureLod(spectrum_texture, vec2(x, (channel + 0.5) / 50.0), 0.0).r);
	}
	float index = float(spectral_history_head) + min(0.0, spectral_history_fraction - delay * 45.0);
	float row = spectral_channel_count == 1 ? 0.0 : channel * 192.0;
	float first = mod(floor(index), 192.0);
	float second = mod(first + 1.0, 192.0);
	float value = mix(textureLod(spectral_history_texture, vec2(x, (row + first + 0.5) / 384.0), 0.0).r, textureLod(spectral_history_texture, vec2(x, (row + second + 0.5) / 384.0), 0.0).r, fract(index));
	return gate(value) * (1.0 - smoothstep(spectral_history_valid * 3.8, spectral_history_valid * 3.8 + 0.08, delay));
}

vec3 history(float delay, float channel) {
	return textureLod(history_texture, vec2(fract(history_head - delay * 90.0 / 192.0), (channel + 0.5) * 0.5), 0.0).rgb;
}

float wave(float u, float channel) {
	return textureLod(wave_texture, vec2(clamp(u, 0.002, 0.998), (channel + 0.5) * 0.5), 0.0).r;
}

vec3 rotate_y(vec3 p, float a) {
	return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

vec3 palette(float pitch, float channel, float t) {
	vec3 a = vec3(0.05, 0.55, 1.0);
	vec3 b = vec3(1.0, 0.12, 0.42);
	if (live_style == 1) {
		a = vec3(0.02, 1.0, 0.64);
		b = vec3(0.75, 0.12, 1.0);
	} else if (live_style == 2) {
		a = vec3(0.12, 0.5, 1.0);
		b = vec3(1.0, 0.35, 0.04);
	} else if (live_style == 3) {
		a = vec3(0.4, 0.1, 1.0);
		b = vec3(1.0, 0.18, 0.36);
	} else if (live_style == 4) {
		a = vec3(0.02, 0.85, 1.0);
		b = vec3(0.8, 0.12, 1.0);
	} else if (live_style == 5) {
		a = vec3(0.1, 0.25, 1.0);
		b = vec3(1.0, 0.45, 0.08);
	}
	float blend = clamp(channel * 0.65 + pitch * 0.3 + sin(t * 0.08) * 0.05, 0.0, 1.0);
	vec3 base = mix(a, b, blend);
	base /= max(0.001, max(base.r, max(base.g, base.b)));
	base = pow(base, vec3(1.15 + arousal * 0.35));
	return mix(base, vec3(0.7, 0.9, 1.0), transients.z * pitch * 0.15);
}

vec3 stream(float u, float lane, float signal, float t, float hit) {
	vec3 p;
	float a = u * TAU;
	float ribbon = lane * TAU;
	float flow = travel * 0.23;
	if (live_style == 0) {
		float depth = fract(lane * 2.0);
		float r = (2.4 + depth * 10.0) * (1.0 + bass * 0.32 + hit * 0.18);
		r += sin(a * 6.0 + flow - depth * 9.0) * signal * (0.35 + mids * 0.8);
		p = vec3(cos(a) * r, sin(a) * r, -3.0 - depth * 30.0);
		p.xy += vec2(sin(depth * 6.0 + t * 0.15), cos(depth * 5.0 + t * 0.13)) * (0.5 + mids);
		if (lane >= 0.5) {
			p = rotate_y(p, PI);
		}
	} else if (live_style == 1) {
		float radius = 5.0 + lane * 20.0;
		a += lane * 1.9 + t * 0.075;
		float crest = sin(a * 2.0 + flow + lane * 8.0) + 0.45 * sin(a * 5.0 - flow * 0.7);
		float y = sin(lane * 15.0) * 3.5 + crest * (0.8 + mids * 2.2 + signal * 1.8);
		y += sin(a * 3.0 - beat_age * 7.0) * hit * 1.3;
		p = vec3(cos(a) * radius, y, sin(a) * radius);
	} else if (live_style == 2) {
		float sector = floor(lane * 12.0);
		float tier = fract(lane * 12.0);
		float distance = 3.0 + u * 29.0;
		float zigzag = abs(fract(u * 5.0 + tier * 0.5) * 2.0 - 1.0) * 2.0 - 1.0;
		float height = (tier - 0.5) * 9.0 + zigzag * (0.6 + signal * 2.6 + hit * 1.2);
		a = sector * TAU / 12.0 + zigzag * (0.08 + signal * 0.22) + sin(u * 3.0 + spin * 0.2) * mids * 0.12;
		p = vec3(sin(a) * distance, height, -cos(a) * distance);
	} else if (live_style == 3) {
		a = ribbon * 2.0 + u * (2.0 + mids * 2.0) + t * 0.07;
		float r = 0.4 + u * (9.0 + bass * 5.0 + hit * 4.0);
		float pitch = sin(ribbon * 7.0);
		p = vec3(cos(a) * r, sin(a) * r * 0.8 + pitch * (0.4 + signal * 1.5), -10.0 + u * u * 13.0 + sin(ribbon * 3.0) * 3.0);
		p = rotate_y(p, floor(lane * 2.0) * PI);
	} else if (live_style == 4) {
		float z = -30.0 + lane * 44.0;
		float x = (u * 2.0 - 1.0) * 25.0;
		float r = length(vec2(x, z + 8.0));
		float swell = sin(r * 0.7 - flow * 2.0) * (bass * 0.8 + hit * 0.8);
		float curl = sin(x * 0.24 + flow) * cos(z * 0.23 - flow * 0.6);
		float y = -2.8 + curl * (0.3 + mids * 1.1) + swell + signal * 1.1;
		p = vec3(x, y, z);
		if (mod(floor(lane * float(instance_count)), 4.0) < 0.5) {
			p.y = -y + 1.8;
		}
	} else {
		float depth = u * 31.0;
		a = ribbon + u * (4.0 + bass * 1.5) + spin * 0.12;
		float r = (4.0 + u * 5.5) * (1.0 + signal * 0.18 + hit * 0.22);
		vec2 bend = vec2(sin(depth * 0.13 + t * 0.14), cos(depth * 0.1 - t * 0.11)) * (mids * 2.2 + stereo_width);
		p = vec3(vec2(cos(a), sin(a)) * r + bend, -1.5 - depth);
		if (lane >= 0.5) {
			p = rotate_y(p, PI);
		}
	}
	return p;
}

void vertex() {
	float id = float(INSTANCE_ID);
	float lane = (id + 0.5) / max(float(instance_count), 1.0);
	float u = VERTEX.x;
	float t = clock * motion;
	float hit = exp(-beat_age * 7.0) * min(1.0, bass * 1.5) + impulse * 0.3 + release * 0.8;
	bool closed = shape == 2 || (shape == 0 && (live_style == 0 || live_style == 1)) || (shape == 3 && (live_style == 0 || live_style == 3 || live_style == 5));
	edge = VERTEX.y;
	mote_uv = vec2(0.0);
	if (shape == 1) {
		u = fract(hash(id + 7.0) + travel * (0.012 + hash(id + 3.0) * 0.018));
		lane = hash(id + 19.0);
	}
	vec3 rest = stream(u, lane, 0.0, t, 0.0);
	if (shape == 2 || (shape == 3 && closed)) {
		float radius = shape == 2 ? 1.1 + lane * 25.0 : 4.5 + floor(id * 0.5) * 1.4;
		rest = vec3(cos(u * TAU) * radius, sin(u * TAU) * radius, -8.0 - lane * 15.0);
		if (shape == 2 && (live_style == 1 || live_style == 4)) {
			rest = vec3(cos(u * TAU) * radius, -2.5, sin(u * TAU) * radius - 7.0);
		}
	}
	float channel = smoothstep(-0.3, 0.3, rest.x);
	float frequency = clamp((rest.y + 7.0) / 14.0, 0.0, 1.0);
	if (live_style == 4) {
		frequency = clamp((-rest.z - 2.0) / 28.0, 0.0, 1.0);
	}
	float delay = shape == 0 ? lane * 0.65 : 0.0;
	float fresh = energy(frequency, channel, 0.0);
	float signal = mix(energy(frequency, channel, delay), fresh, 0.7);
	float pulse = max(transients.x, max(transients.y * 0.75, transients.z * 0.5));
	tint = palette(frequency, channel, t);
	float power = clamp(bass * 0.55 + mids * 0.3 + treble * 0.15, 0.0, 1.0);
	light = (0.002 + power * 0.08 + signal * (0.55 + fresh * 0.35)) * (0.85 + min(1.0, bass) * 0.3) * (1.0 + hit * 0.85);
	vec3 p = stream(u, lane, signal, t, hit);
	if (shape == 1) {
		vec2 uv = VERTEX.xy;
		fresh = max(fresh, power * 0.35);
		float spread = 0.2 + u * u * (2.0 + pulse * 3.0);
		p += vec3(hash(id + 29.0) - 0.5, hash(id + 43.0) - 0.5, hash(id + 59.0) - 0.5) * spread;
		float size = (0.016 + fresh * 0.055 + transients.z * hash(id) * 0.065) * (0.5 + hash(id + 83.0));
		if (live_style == 3) {
			size = 0.06 + fresh * (0.5 + hash(id + 83.0) * 1.4);
		} else if (live_style == 2) {
			size = 0.025 + fresh * 0.18 + transients.z * 0.12;
		}
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), p) + vec3(0.00001));
		vec3 up = normalize(cross(p, right) + vec3(0.00001));
		VERTEX = p + right * uv.x * size + up * uv.y * size;
		mote_uv = uv;
		edge = 0.0;
		light = fresh * (0.3 + pulse * 0.6) * (0.4 + 0.6 * sin(u * PI));
		if (live_style == 3) {
			light *= 0.6;
		}
	} else if (shape == 2) {
		float age = lane * 1.9;
		vec3 past = history(age, channel);
		float old_hit = clamp(past.x * 1.6, 0.0, 1.0);
		float radius = 1.1 + lane * 25.0;
		float angle = u * TAU;
		if (live_style == 2 || live_style == 5) {
			float sides = live_style == 2 ? 6.0 : 8.0;
			radius *= cos(PI / sides) / max(0.1, cos(mod(angle, TAU / sides) - PI / sides));
		}
		p = vec3(cos(angle) * radius, sin(angle) * radius, -8.0 - lane * 15.0);
		if (live_style == 4) {
			p = vec3(cos(angle) * radius, -2.5 + sin(radius * 0.5 - travel) * bass * 0.8, sin(angle) * radius - 7.0);
		}
		if (live_style == 1) {
			p = vec3(cos(angle) * radius, sin(angle * 3.0 + travel * 0.2) * (1.0 + past.y * 2.0), sin(angle) * radius);
		} else if (live_style == 3) {
			p = rotate_y(p, sin(age * 2.0 + spin * 0.1) * 0.7);
		}
		vec3 across = normalize(p + vec3(0.0, 0.0, 8.0) + vec3(0.00001));
		VERTEX = p + across * VERTEX.y * (0.04 + old_hit * 0.16);
		light = old_hit * exp(-age * 1.2) * 0.22;
		tint = palette(lane, smoothstep(-0.3, 0.3, p.x), t);
	} else if (shape == 3) {
		channel = mod(id, 2.0);
		float radius = 4.5 + floor(id * 0.5) * 1.4;
		float angle = u * TAU;
		float sample = closed ? loop_sample(wave_texture, u, (channel + 0.5) * 0.5, 256.0) : wave(u, channel);
		p = vec3(cos(angle) * radius, sin(angle) * radius, -8.0 - floor(id * 0.5) * 3.0);
		p.xy *= 1.0 + sample * (0.35 + bass * 0.8);
		p.z += sample * (1.5 + stereo_width * 2.0);
		vec3 across = normalize(vec3(cos(angle), sin(angle), 0.0));
		if (live_style == 1 || live_style == 4) {
			p = vec3((u * 2.0 - 1.0) * 24.0, (channel * 2.0 - 1.0) * (1.0 + floor(id * 0.5)) + sample * (2.0 + bass * 3.0), -7.0 - floor(id * 0.5) * 5.0);
			across = vec3(0.0, 1.0, 0.0);
		} else if (live_style == 2) {
			p = vec3((u * 2.0 - 1.0) * 18.0, sample * (4.0 + bass * 4.0) + (channel * 2.0 - 1.0) * 3.0, -8.0 - floor(id * 0.5) * 4.0);
			across = vec3(0.0, 1.0, 0.0);
		}
		VERTEX = p + across * VERTEX.y * (0.045 + fresh * 0.11);
		light = (fresh + abs(sample) * 0.6) * 0.22;
		tint = palette(closed ? 0.5 - 0.5 * cos(u * TAU) : u, channel, t);
	} else {
		vec3 tangent = stream(u + 0.0007, lane, signal, t, hit) - stream(u - 0.0007, lane, signal, t, hit);
		vec3 across = cross(tangent, normalize(p + vec3(0.00001)));
		across /= max(length(across), 0.00001);
		float width = live_style == 1 ? 0.22 + signal * 1.1 + power * 0.25 : live_style == 4 ? 0.16 + signal * 0.65 : live_style == 2 ? 0.055 + signal * 0.24 : 0.045 + signal * 0.14;
		p += across * VERTEX.y * width;
		float sample = closed ? loop_sample(wave_texture, u, (channel + 0.5) * 0.5, 256.0) : wave(u, channel);
		p.y += sample * (0.35 + signal * 1.2) * (live_style == 4 ? 0.8 : 0.5);
		VERTEX = p;
	}
}

void fragment() {
	float profile;
	if (shape == 1) {
		float r = dot(mote_uv, mote_uv);
		profile = exp(-r * 4.5) * 0.65 + exp(-r * 24.0) * 0.35;
		if (live_style == 2) {
			profile *= max(0.0, 1.0 - abs(mote_uv.x) - abs(mote_uv.y));
		}
	} else {
		float aa = max(fwidth(edge), 0.002);
		float core = 1.0 - smoothstep(max(0.0, 0.09 - aa), 0.09 + aa, abs(edge));
		profile = core * 0.35 + pow(max(0.0, 1.0 - abs(edge)), 2.0) * 0.65;
	}
	float budget = shape == 0 ? 48.0 : shape == 1 ? 900.0 : shape == 2 ? 12.0 : 4.0;
	float density = budget / max(1.0, float(instance_count));
	float absorption = light * profile * intensity * dim * density * 1.8;
	ALBEDO = tint * 0.85;
	ALPHA = 1.0 - exp(-absorption);
}
