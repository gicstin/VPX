shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform int source_count = 2;
uniform vec3 channel_left = vec3(0.0);
uniform vec3 channel_right = vec3(0.0);
uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform vec3 transients = vec3(0.0);
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
	float ribbon = d.y + sin(d.x * 3.0 + d.z * 2.0 + clock * 0.018) * 0.2;
	float aurora = exp(-abs(ribbon) * 11.0) * (0.35 + 0.65 * pow(max(0.0, sin(d.z * 9.0 - d.x * 5.0 + clock * 0.025)), 2.0));
	vec3 glow = mix(vec3(0.02, 0.25, 0.42), vec3(0.22, 0.04, 0.38), smoothstep(-0.6, 0.6, d.x));
	float low_glow = exp(-abs(d.y + 0.45) * 6.0) * bass;
	vec3 atmosphere = colour * veil * (0.018 + mids * 0.035);
	atmosphere += glow * aurora * (0.03 + mids * 0.16 + transients.y * 0.06);
	atmosphere += vec3(0.18, 0.035, 0.012) * low_glow * 0.18;
	atmosphere += colour * pow(veil, 3.0) * treble * transients.z * 0.045;
	if (source_count > 0) {
		vec3 left_direction = normalize(vec3(source_count == 1 ? 0.0 : -3.0, 0.0, -5.2));
		vec3 right_direction = normalize(vec3(3.0, 0.0, -5.2));
		float left_glow = pow(max(0.0, dot(d, left_direction)), 18.0);
		float right_glow = source_count == 1 ? 0.0 : pow(max(0.0, dot(d, right_direction)), 18.0);
		atmosphere = vec3(0.025, 0.22, 0.38) * left_glow * min(1.0, dot(channel_left, vec3(0.4, 0.45, 0.15))) * 0.14;
		atmosphere += vec3(0.20, 0.06, 0.38) * right_glow * min(1.0, dot(channel_right, vec3(0.4, 0.45, 0.15))) * 0.14;
	}
	ALBEDO = (vec3(0.002, 0.003, 0.009) + atmosphere * intensity) * dim;
}
