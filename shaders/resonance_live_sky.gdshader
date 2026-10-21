shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform int live_style = 0;
uniform float clock = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float beat_age = 4.0;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float dim = 1.0;
varying vec3 direction;

float field(vec3 p) {
	return sin(p.x + sin(p.z * 1.3)) * cos(p.y - sin(p.x * 0.8)) + sin(p.z * 1.6 + p.y) * 0.4;
}

void vertex() {
	direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(direction);
	float az = atan(d.x, -d.z);
	float height = asin(clamp(d.y, -1.0, 1.0));
	float pitch = clamp(height * 0.7 + 0.5, 0.0, 1.0);
	float channel = smoothstep(-0.15, 0.15, d.x);
	float sample = texture(spectrum_texture, vec2(mix(0.5 / 48.0, 47.5 / 48.0, pitch), (channel + 0.5) / 50.0)).r;
	float energy = 1.0 - exp(-pow(max(0.0, sample - 0.12) / 0.88, 2.1) * sensitivity * 1.8);
	float hit = exp(-beat_age * 7.0) * bass;
	float t = clock * 0.055;
	vec3 p = d * 4.0 + vec3(t, -t * 0.4, t * 0.7);
	float cloud = field(p + field(p * 1.7) * 0.55);
	float veil = pow(clamp(cloud * 0.38 + 0.4, 0.0, 1.0), 3.0);
	vec3 cool = vec3(0.025, 0.12, 0.36);
	vec3 warm = vec3(0.35, 0.018, 0.11);
	if (live_style == 1) {
		cool = vec3(0.015, 0.32, 0.22);
		warm = vec3(0.2, 0.025, 0.35);
		veil *= exp(-abs(d.y - sin(az * 2.0 + t) * 0.2) * 2.5);
	} else if (live_style == 2) {
		cool = vec3(0.015, 0.08, 0.24);
		warm = vec3(0.28, 0.055, 0.005);
		veil *= pow(abs(sin(az * 6.0 + height * 3.0)), 5.0);
	} else if (live_style == 3) {
		cool = vec3(0.14, 0.015, 0.38);
		warm = vec3(0.4, 0.025, 0.1);
		veil = pow(clamp(cloud * 0.42 + 0.4, 0.0, 1.0), 2.0);
	} else if (live_style == 4) {
		cool = vec3(0.005, 0.15, 0.26);
		warm = vec3(0.19, 0.015, 0.25);
		veil *= exp(-abs(d.y) * 4.0);
	} else if (live_style == 5) {
		float twist = az + log(max(0.08, length(d.xy))) * 2.0;
		veil *= 0.4 + 0.6 * pow(abs(sin(twist * 3.0 + t)), 3.0);
	}
	vec3 colour = mix(cool, warm, clamp(channel * 0.65 + cloud * 0.15 + 0.15, 0.0, 1.0));
	float pressure = 0.001 + energy * (0.14 + mids * 0.06) + hit * 0.008;
	ALBEDO = (vec3(0.0002, 0.0003, 0.0008) + colour * veil * pressure) * intensity * dim;
}
