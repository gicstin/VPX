shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform int immersive_style = 0;
uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float dim = 1.0;
varying vec3 direction;

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	float az = atan(d.x, -d.z);
	float h = asin(clamp(d.y, -1.0, 1.0));
	float t = clock;
	float pitch = clamp(d.y * 0.5 + 0.5, 0.0, 1.0);
	float channel = smoothstep(-0.2, 0.2, d.x);
	float sample = texture(spectrum_texture, vec2(mix(0.5 / 48.0, 47.5 / 48.0, pitch), (channel + 0.5) / 50.0)).r;
	float energy = 1.0 - exp(-pow(max(sample, 0.0), 1.6) * sensitivity * 1.8);
	float field = 0.0;
	vec3 tint = vec3(0.15, 0.05, 0.015);
	if (immersive_style == 0) {
		field = pow(0.5 + 0.5 * cos(az * 24.0 + t * 0.08), 18.0) * exp(-abs(h) * 3.0);
		tint = mix(vec3(0.18, 0.055, 0.01), vec3(0.015, 0.1, 0.17), d.y * 0.5 + 0.5);
	} else if (immersive_style == 1) {
		float caustic = sin(d.x * 18.0 + t * 0.15 + sin(d.z * 11.0)) * sin(d.z * 20.0 - t * 0.12 + d.y * 9.0);
		field = pow(0.5 + caustic * 0.5, 7.0) * (0.3 + 0.7 * abs(d.y));
		tint = vec3(0.008, 0.1, 0.15);
	} else if (immersive_style == 2) {
		field = pow(0.5 + 0.5 * sin(az * 4.0 + sin(h * 8.0 + t * 0.2)), 10.0);
		tint = mix(vec3(0.015, 0.1, 0.04), vec3(0.065, 0.015, 0.15), d.y * 0.5 + 0.5);
	} else if (immersive_style == 3) {
		vec2 p = vec2(az * 9.0 / 6.283185, h * 3.0);
		p.x += mod(floor(p.y), 2.0) * 0.5;
		vec2 q = abs(fract(p) - 0.5);
		field = exp(-abs(max(q.x * 0.866 + q.y * 0.5, q.y) - 0.45) * 80.0);
		tint = vec3(0.16, 0.065, 0.006);
	} else if (immersive_style == 4) {
		float eye = sin(az * 8.0 + sin(h * 6.0)) * cos(h * 12.0);
		field = pow(0.5 + 0.5 * eye, 9.0);
		tint = mix(vec3(0.005, 0.13, 0.07), vec3(0.02, 0.035, 0.14), channel);
	} else if (immersive_style == 5) {
		field = pow(0.5 + 0.5 * cos(az * 6.0 + sin(h * 4.0) * 3.0 + t * 0.1), 22.0) * exp(-abs(h) * 2.0);
		tint = mix(vec3(0.16, 0.01, 0.04), vec3(0.01, 0.06, 0.18), channel);
	} else if (immersive_style == 6) {
		vec3 p = abs(d * 12.0);
		float triangle = abs(sin(p.x + p.y) * sin(p.y + p.z) * sin(p.z + p.x));
		field = pow(triangle, 10.0);
		tint = vec3(0.075, 0.02, 0.14);
	} else if (immersive_style == 7) {
		float nodes = sin(d.x * 18.0) * sin(d.z * 12.0) - sin(d.z * 18.0) * sin(d.x * 12.0);
		field = exp(-abs(nodes) * 35.0) * exp(-abs(d.y) * 3.0);
		tint = vec3(0.025, 0.045, 0.15);
	} else if (immersive_style == 8) {
		field = pow(abs(sin(d.x * 13.0 + d.z * 5.0 + t * 0.04) * cos(d.y * 17.0 - d.z * 8.0)), 14.0);
		tint = mix(vec3(0.005, 0.09, 0.14), vec3(0.14, 0.015, 0.04), channel);
	} else {
		field = pow(0.5 + 0.5 * cos(az * 8.0 + sin(h * 6.0 + t * 0.1)), 16.0);
		tint = vec3(0.15, 0.02, 0.055);
	}
	ALBEDO = (vec3(0.0001, 0.00015, 0.0003) + tint * field * (0.001 + energy * (0.13 + bass * 0.025))) * intensity * dim;
}
