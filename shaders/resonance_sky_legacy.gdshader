shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float palette = 0.0;
uniform float intensity = 0.75;
uniform float dim = 1.0;
varying vec3 direction;

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	float cloud = sin(d.x * 5.0 + sin(d.z * 4.0 + clock * 0.012)) * sin(d.y * 5.0 - d.z * 3.0 + clock * 0.008);
	float veil = pow(max(0.0, cloud), 3.0);
	vec3 colour = 0.5 + 0.5 * cos(TAU * (palette + d.y * 0.15 + vec3(0.04, 0.34, 0.64)));
	ALBEDO = (vec3(0.003, 0.004, 0.012) + colour * veil * (0.025 + bass * 0.025) * intensity) * dim;
}
