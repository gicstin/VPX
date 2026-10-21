shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform int psyche_style = 0;
uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float intensity = 0.75;
uniform float dim = 1.0;
uniform float arousal = 0.0;
uniform float tension = 0.0;
uniform float release = 0.0;
uniform float warmth = 0.4;
uniform float breath = 0.5;
varying vec3 direction;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float stars(vec3 d, float scale) {
	vec3 cell = floor(d * scale);
	vec3 local = fract(d * scale) - 0.5;
	return step(0.965, hash(cell)) * smoothstep(0.32, 0.0, length(local)) * (0.4 + 0.6 * hash(cell + 7.0));
}

vec3 mood(float height) {
	vec3 cool = mix(vec3(0.002, 0.004, 0.016), vec3(0.006, 0.002, 0.018), height);
	vec3 warm = mix(vec3(0.016, 0.004, 0.002), vec3(0.01, 0.002, 0.012), height);
	return mix(cool, warm, warmth) * 0.12;
}

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	float az = atan(d.x, -d.z);
	float up = clamp(d.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 sky = mood(up) * (0.6 + arousal * 0.5 + breath * 0.15 * (1.0 - arousal));
	float horizon = exp(-abs(d.y + 0.02) * 9.0);
	sky += mood(0.2) * horizon * (1.0 + bass * 1.2 + release * 3.0);
	if (psyche_style == 0 || psyche_style == 2 || psyche_style == 7) {
		sky += vec3(0.85, 0.9, 1.0) * stars(d, 120.0) * (0.04 + treble * 0.08) * smoothstep(-0.05, 0.2, d.y);
		float galaxy = exp(-abs(d.y - 0.35 - sin(az) * 0.15) * 7.0);
		sky += mix(vec3(0.012, 0.008, 0.03), vec3(0.03, 0.014, 0.008), warmth) * 0.12 * galaxy * (0.4 + mids * 0.6 + release);
	} else if (psyche_style == 3) {
		sky += vec3(0.002, 0.003, 0.005) * exp(-length(vec2(az, d.y - 0.1)) * 3.0) * (0.4 + breath * 0.4);
	} else if (psyche_style == 4) {
		sky += vec3(0.85, 0.9, 1.0) * stars(d, 140.0) * 0.05 * smoothstep(0.0, 0.3, d.y);
	}
	sky += vec3(0.0012, 0.0004, 0.002) * tension * smoothstep(0.0, 0.8, up);
	ALBEDO = sky * intensity * dim;
}
