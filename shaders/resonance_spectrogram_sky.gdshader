shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform int spectrogram_style = 0;
uniform float intensity = 0.75;
uniform float dim = 1.0;
varying vec3 direction;

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	float horizon = exp(-abs(d.y) * 12.0);
	vec3 tint = mix(vec3(0.001, 0.006, 0.015), vec3(0.012, 0.002, 0.009), smoothstep(-0.3, 0.3, -d.y));
	float meridian = pow(max(0.0, 1.0 - abs(sin(atan(d.x, -d.z) * 4.0))), 80.0);
	vec3 light = tint * (0.5 + horizon * 1.5) + vec3(0.004, 0.009, 0.015) * meridian * horizon;
	ALBEDO = light * intensity * dim;
}
