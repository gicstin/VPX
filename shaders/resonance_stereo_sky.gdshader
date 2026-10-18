shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D field_texture : filter_linear, repeat_disable;
uniform float field_head = -1.0;
uniform int stereo_style = 0;
uniform float clock = 0.0;
uniform float beat_age = 4.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float sensitivity = 1.75;
uniform float palette = 0.0;
uniform float intensity = 0.75;
uniform float dim = 1.0;
uniform float width = 0.0;
varying vec3 direction;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float stars(vec3 d, float scale) {
	vec3 cell = floor(d * scale);
	vec3 local = fract(d * scale) - 0.5;
	return step(0.965, hash(cell)) * smoothstep(0.32, 0.0, length(local)) * (0.4 + 0.6 * hash(cell + 7.0));
}

vec4 field_now(float pan01) {
	float row = mod(max(field_head, 0.0), 192.0);
	return textureLod(field_texture, vec2(mix(0.5 / 64.0, 63.5 / 64.0, clamp(pan01, 0.0, 1.0)), (row + 0.5) / 192.0), 0.0);
}

vec3 band_colour(float band) {
	vec3 low = vec3(1.0, 0.22, 0.1);
	vec3 mid = vec3(0.15, 1.0, 0.55);
	vec3 high = vec3(0.4, 0.3, 1.0);
	return band < 0.5 ? mix(low, mid, band * 2.0) : mix(mid, high, band * 2.0 - 1.0);
}

float spread_for(int style) {
	if (style == 0) return 1.0;
	if (style == 3) return 1.25;
	if (style == 5) return 1.2;
	if (style == 6) return 1.1;
	if (style == 7) return 1.4;
	if (style == 8) return 1.1;
	if (style == 9) return 1.2;
	if (style == 12) return 1.1;
	if (style == 15) return 2.2;
	if (style == 18) return 0.55;
	return 0.0;
}

bool starry(int style) {
	return style == 3 || style == 5 || style == 6 || style == 7 || style == 12 || style == 17;
}

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	vec3 base = vec3(0.002, 0.002, 0.008);
	vec3 sky = vec3(0.0);
	float az = atan(d.x, -d.z);
	float spread = spread_for(stereo_style);
	if (spread > 0.0) {
		float pan = az / spread;
		if (abs(pan) <= 1.0) {
			vec4 f = field_now(pan * 0.5 + 0.5);
			float e = 1.0 - exp(-f.x * sensitivity * 0.45);
			float height = stereo_style == 7 ? exp(-abs(d.y - 0.45) * 2.5) : exp(-abs(d.y - 0.02) * 16.0);
			sky += band_colour(f.y) * e * height * (stereo_style == 7 ? 0.04 : 0.045) * (1.0 - smoothstep(0.85, 1.0, abs(pan)));
		}
	}
	if (starry(stereo_style)) {
		sky += vec3(0.85, 0.9, 1.0) * stars(d, 110.0) * (0.05 + treble * 0.12);
	}
	if (stereo_style == 1 || stereo_style == 2) {
		float centre = pow(max(0.0, -d.z), 8.0);
		sky += vec3(0.02, 0.08, 0.05) * centre * (0.4 + mids);
	} else if (stereo_style == 10) {
		sky += vec3(0.0, 0.012, 0.005) * (1.0 - smoothstep(-0.6, 0.0, d.y));
	} else if (stereo_style == 14) {
		sky += vec3(0.04, 0.03, 0.09) * pow(max(0.0, -d.z), 4.0) * (0.3 + width * 2.0);
	} else if (stereo_style == 20) {
		sky += vec3(0.01, 0.04, 0.02) * smoothstep(-0.2, 0.6, d.y) * pow(max(0.0, -d.z), 2.0) * (0.4 + mids);
	} else if (stereo_style == 28) {
		float el = asin(clamp(d.y, -1.0, 1.0));
		float sun = length(vec2(az, el - 0.12));
		float radius = 0.2 + bass * 0.03 + exp(-beat_age * 5.0) * 0.02;
		float stripes = step(0.0, sin(el * 90.0 - clock * 1.5)) + step(0.16, el);
		float disc = (1.0 - smoothstep(radius - 0.005, radius + 0.005, sun)) * min(1.0, stripes) * step(0.0, el);
		vec3 sun_colour = mix(vec3(1.0, 0.2, 0.55), vec3(1.0, 0.85, 0.3), smoothstep(0.0, 0.3, el));
		sky += sun_colour * disc * (0.14 + bass * 0.12);
		sky += vec3(0.25, 0.04, 0.2) * exp(-abs(el) * 10.0) * 0.05;
	} else if (stereo_style == 18) {
		float flash = exp(-beat_age * 7.0);
		sky += vec3(0.25, 0.3, 0.6) * flash * 0.06 * smoothstep(-0.2, 0.6, d.y);
	}
	sky += vec3(0.03, 0.01, 0.04) * exp(-abs(d.y + 0.05) * 6.0) * bass * 0.5;
	ALBEDO = (base + sky * intensity) * dim;
}
