shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform int pulse_style = 0;
uniform float clock = 0.0;
uniform float travel = 0.0;
uniform float spin = 0.0;
uniform float beat_age = 4.0;
uniform float beat_count = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform vec3 transients = vec3(0.0);
uniform float sensitivity = 1.75;
uniform float palette = 0.0;
uniform float intensity = 0.75;
uniform float dim = 1.0;
varying vec3 direction;

float band_level(float band) {
	float u = mix(0.5 / 48.0, 47.5 / 48.0, clamp(band, 0.0, 1.0));
	float value = max(textureLod(spectrum_texture, vec2(u, 0.5 / 50.0), 0.0).r, textureLod(spectrum_texture, vec2(u, 1.5 / 50.0), 0.0).r);
	return 1.0 - exp(-pow(max(0.0, value), 1.35) * sensitivity * 1.5);
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec3 rainbow(float x) {
	return 0.5 + 0.5 * cos(TAU * (x + vec3(0.0, 0.33, 0.67)));
}

float stars(vec3 d, float scale) {
	vec3 cell = floor(d * scale);
	vec3 local = fract(d * scale) - 0.5;
	float seed = hash(cell);
	return step(0.965, seed) * smoothstep(0.32, 0.0, length(local)) * (0.4 + 0.6 * hash(cell + 7.0));
}

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	float kick = exp(-beat_age * 5.0);
	vec3 sky = vec3(0.002, 0.002, 0.008);
	if (pulse_style == 0) {
		float axis = length(d.xy);
		float ahead = smoothstep(0.35, 0.0, axis) * step(0.0, -d.z);
		float rays = pow(max(0.0, sin(atan(d.y, d.x) * 24.0 + clock * 0.2)), 6.0) * smoothstep(0.6, 0.05, axis) * step(0.0, -d.z);
		sky += vec3(0.5, 0.2, 1.0) * ahead * (0.04 + bass * 0.12 + kick * 0.08);
		sky += vec3(0.2, 0.4, 1.0) * rays * (0.01 + mids * 0.05);
		sky += vec3(0.8, 0.85, 1.0) * stars(d, 90.0) * (0.04 + treble * 0.08);
	} else if (pulse_style == 1) {
		float stage = exp(-abs(d.y - 0.05) * 9.0) * pow(max(0.0, -d.z), 6.0);
		float haze = exp(-abs(d.y + 0.15) * 4.0);
		vec3 tint = rainbow(floor(beat_count * 0.25) * 0.17 + palette);
		sky += tint * stage * (0.02 + bass * 0.1 + kick * 0.12);
		sky += vec3(0.04, 0.05, 0.09) * haze * (0.2 + mids * 0.5);
	} else if (pulse_style == 2) {
		float horizon = exp(-abs(d.y + 0.08) * 10.0);
		float ripple = 0.5 + 0.5 * sin(atan(d.x, -d.z) * 8.0 + clock * 0.3);
		sky += vec3(0.5, 0.06, 0.02) * horizon * (0.03 + bass * 0.16 + kick * 0.1);
		sky += vec3(0.05, 0.08, 0.3) * smoothstep(0.0, 1.0, d.y) * ripple * (0.01 + mids * 0.04);
	} else if (pulse_style == 3) {
		float cloud = sin(d.x * 4.0 + sin(d.z * 3.0 + clock * 0.01)) * sin(d.y * 5.0 + d.z * 2.0 - clock * 0.008) + sin(d.z * 7.0 - d.x * 3.0) * 0.4;
		float veil = pow(max(0.0, cloud), 2.5);
		vec3 hue = mix(vec3(0.35, 0.06, 0.5), vec3(0.05, 0.3, 0.55), 0.5 + 0.5 * sin(d.x * 2.0 + palette * TAU));
		sky += hue * veil * (0.02 + mids * 0.08);
		sky += vec3(0.9, 0.9, 1.0) * stars(d, 120.0) * (0.05 + treble * 0.25 * (0.5 + 0.5 * sin(clock * 3.0 + d.x * 40.0)));
	} else {
		float folds = 6.0;
		float spread = acos(clamp(-d.z, -1.0, 1.0));
		float around = atan(d.y, d.x) + spin * 0.1;
		float sector = TAU / folds;
		float folded = abs(mod(around, sector) - sector * 0.5);
		vec2 q = vec2(cos(folded), sin(folded)) * spread;
		float flow = fract(spread * 0.28 - travel * 0.03);
		float rings = band_level(flow);
		float lattice = sin(q.x * 9.0 - clock * 0.4) * sin(q.y * 11.0 + clock * 0.3);
		float weave = smoothstep(0.2, 0.9, lattice) * (0.3 + mids * 1.2);
		vec3 hue = rainbow(spread * 0.18 + folded * 0.4 + palette * 3.0 + clock * 0.01);
		sky += hue * (rings * rings * 0.11 + weave * 0.05) * (0.6 + kick * 0.5);
		sky += hue * pow(max(0.0, sin(spread * 14.0 - beat_age * 18.0)), 12.0) * kick * 0.08;
	}
	ALBEDO = (vec3(0.002, 0.002, 0.008) + (sky - vec3(0.002, 0.002, 0.008)) * intensity) * dim;
}
