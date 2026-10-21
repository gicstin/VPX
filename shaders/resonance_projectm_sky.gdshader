shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform int projectm_style = 0;
uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float dim = 1.0;
varying vec3 direction;

float stars(vec3 d) {
	vec3 p = d * 95.0;
	vec3 cell = floor(p);
	float seed = fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
	float star = 1.0 - smoothstep(0.0, 0.2, length(fract(p) - 0.5));
	return star * step(0.96, seed);
}

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	float az = atan(d.x, -d.z);
	float h = asin(clamp(d.y, -1.0, 1.0));
	float t = clock;
	float channel = smoothstep(-0.2, 0.2, d.x);
	float band = clamp(h * 0.6 + 0.5, 0.0, 1.0);
	float sample = texture(spectrum_texture, vec2(mix(0.5 / 48.0, 47.5 / 48.0, band), (channel + 0.5) / 50.0)).r;
	float energy = 1.0 - exp(-pow(max(sample, 0.0), 1.6) * sensitivity * 1.8);
	vec3 tint = vec3(0.02, 0.18, 0.13);
	float veil = 0.0;
	if (projectm_style == 0) {
		veil = pow(0.5 + 0.5 * sin(az * 9.0 + sin(h * 10.0 + t * 0.459) + sin(h * 14.0 + t * 0.325)), 8.0);
		tint = mix(vec3(0.02, 0.17, 0.13), vec3(0.18, 0.015, 0.07), channel);
	} else if (projectm_style == 1) {
		float field = az * 2.0 - 1.5 + t * 0.15;
		veil = exp(-abs(h) * 5.0) * (0.2 + 0.8 * pow(abs(sin(field + h * 10.0)), 6.0));
		tint = mix(vec3(0.24, 0.03, 0.002), vec3(0.08, 0.01, 0.2), d.y * 0.5 + 0.5);
	} else if (projectm_style == 2) {
		vec3 p = d * 9.0;
		vec3 grid = abs(fract(p + 0.5) - 0.5);
		float line = min(max(grid.x, grid.y), min(max(grid.y, grid.z), max(grid.z, grid.x)));
		veil = exp(-line * 65.0) * 0.5;
		tint = vec3(0.03, 0.08, 0.24);
	} else if (projectm_style == 3) {
		float horizon = exp(-abs(d.y) * 18.0);
		float swell = 0.5 + 0.5 * sin(az * 3.0 + t * 0.163 + sin(az * 6.0 + t * 0.376));
		veil = horizon * (0.3 + swell * 0.7);
		tint = vec3(0.005, 0.2, 0.24);
	} else if (projectm_style == 4) {
		float seed = 0.5 + 0.5 * sin(dot(d, vec3(11.0, 9.0, 7.0)));
		veil = stars(d) * 8.0 + exp(-abs(d.y + sin(az) * 0.2) * 15.0) * 0.04;
		tint = mix(vec3(0.1, 0.16, 0.3), vec3(0.4, 0.18, 0.015), seed);
	} else {
		float shear = asin(clamp(d.x * (abs(d.y) - 0.2), -0.9, 0.9)) * sign(d.y);
		float storm = sin(az * 7.0 + shear * 8.0 + t * 0.12) * sin(h * 10.0 - t * 0.2);
		veil = pow(clamp(storm * 0.5 + 0.5, 0.0, 1.0), 5.0);
		tint = max(vec3(0.01), vec3(0.05, 0.08, 0.14) + 0.08 * sin(t * vec3(0.666, 0.777, 0.888)));
	}
	ALBEDO = (vec3(0.00015, 0.0002, 0.0004) + tint * veil * (0.002 + energy * (0.18 + bass * 0.04))) * intensity * dim;
}
