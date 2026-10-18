shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D spectral_history_texture : filter_linear, repeat_disable;
uniform int spectral_history_head = -1;
uniform float spectral_history_fraction = 0.0;
uniform float spectral_history_valid = 0.0;
uniform int spectral_channel_count = 2;
uniform int instance_count = 96;
uniform int depth_style = 0;
uniform int shape = 0;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float motion = 0.6;
uniform float dim = 1.0;

varying float response;
varying float edge;
varying float fade;
varying float frequency_colour;
varying float channel_colour;

float spectral_at(float frequency, float delay, float channel) {
	float index = float(spectral_history_head) + min(0.0, spectral_history_fraction - delay * 45.0);
	float a = mod(floor(index), 192.0);
	float b = mod(a + 1.0, 192.0);
	float band = mix(0.5 / 48.0, 47.5 / 48.0, frequency);
	float row_a = (channel * 192.0 + a + 0.5) / 384.0;
	float row_b = (channel * 192.0 + b + 0.5) / 384.0;
	float value = mix(textureLod(spectral_history_texture, vec2(band, row_a), 0.0).r, textureLod(spectral_history_texture, vec2(band, row_b), 0.0).r, fract(index));
	return value * (1.0 - smoothstep(spectral_history_valid * 3.8, spectral_history_valid * 3.8 + 0.08, delay));
}

vec3 depth_point(float frequency, float progress, float side, float height) {
	float z = mix(-30.0, -1.8, progress);
	if (depth_style == 0) {
		return vec3(side * frequency * 10.0, -2.2 + height, z);
	} else if (depth_style == 1) {
		float bank = mix(9.0, 2.0, smoothstep(0.1, 1.0, progress));
		return vec3(side * frequency * bank, -1.3 + height * 0.7 + frequency * frequency * 1.3, z);
	} else if (depth_style == 2) {
		float merge = smoothstep(0.55, 1.0, progress);
		return vec3(side * (3.8 + height) * (1.0 - merge * 0.72), (frequency - 0.5) * 9.0, z);
	} else if (depth_style == 3) {
		float radius = 2.6 + progress * 1.4 + height * 0.55;
		return vec3(side * sin(frequency * PI) * radius, cos(frequency * PI) * radius, z);
	} else if (depth_style == 4) {
		float bank = 7.5 + sin(progress * PI) * 1.5;
		return vec3(side * frequency * bank, -2.3 + pow(frequency, 2.4) * 5.0 + height * 0.9, z);
	} else if (depth_style == 5) {
		return vec3(side * sin(frequency * PI * 0.5) * 9.0, 3.4 - pow(frequency, 1.5) * 2.8 - height * 0.8, z);
	} else if (depth_style == 6) {
		float weave = sin(progress * TAU * 1.25);
		float bank = 5.8 - sin(progress * PI) * 2.0;
		return vec3(side * frequency * bank, -0.9 + frequency * side * weave * 1.2 + frequency * frequency * 0.8 + height * 0.65, z);
	} else if (depth_style == 7) {
		return vec3(side * frequency * 8.5, -1.8 + sin(frequency * PI) * (2.8 + progress * 0.6) + height * 0.7, z);
	} else if (depth_style == 8) {
		float bank = mix(8.0, 5.5, progress);
		float lift = 2.2 + cos(progress * PI) * 1.2;
		return vec3(side * frequency * bank, -0.7 + frequency * lift + height * 0.7, z);
	}
	float angle = frequency * PI;
	float x = side * pow(max(0.0, sin(angle)), 0.35) * (3.2 + height * 0.5);
	float y = sign(cos(angle)) * pow(abs(cos(angle)), 0.35) * (2.5 + height * 0.4);
	return vec3(x, y, z);
}

void vertex() {
	float channel = mod(float(INSTANCE_ID), 2.0);
	float index = floor(float(INSTANCE_ID) * 0.5);
	float count = max(2.0, float(instance_count) * 0.5);
	float side = channel * 2.0 - 1.0;
	float frequency = shape == 0 ? index / (count - 1.0) : VERTEX.x;
	float progress = shape == 0 ? VERTEX.x : VERTEX.y;
	float delay = progress * 3.8;
	float left = spectral_at(frequency, delay, 0.0);
	float right = spectral_at(frequency, delay, spectral_channel_count == 1 ? 0.0 : 1.0);
	float value = channel == 0.0 ? left : right;
	float merge = 1.0 - smoothstep(0.0, 0.16, frequency);
	if (depth_style == 2) {
		merge = smoothstep(0.55, 1.0, progress);
	} else if (depth_style == 3 || depth_style == 9) {
		merge = 1.0 - smoothstep(0.0, 0.2, sin(frequency * PI));
	}
	value = mix(value, (left + right) * 0.5, merge);
	response = 1.0 - exp(-pow(max(0.0, value), 1.35) * sensitivity * 1.5);
	float height = response * (0.9 + motion * 1.7) * intensity;
	vec3 point = depth_point(frequency, progress, side, height);
	float width = 0.014 + response * 0.025 * intensity;
	vec3 normal = vec3(1.0, 0.0, 0.0);
	if (shape == 0) {
		vec3 before = depth_point(max(0.0, frequency - 0.002), progress, side, height);
		vec3 after = depth_point(min(1.0, frequency + 0.002), progress, side, height);
		normal = normalize(after - before);
	}
	edge = VERTEX.y;
	if (shape == 0) {
		point += normal * VERTEX.y * width;
	}
	VERTEX = point;
	frequency_colour = frequency;
	channel_colour = mix(channel, 0.5, merge);
	fade = smoothstep(0.0, 0.045, progress) * (1.0 - smoothstep(0.88, 1.0, progress));
}

void fragment() {
	vec3 colour = mix(vec3(0.025, 0.56, 0.95), vec3(0.52, 0.16, 0.95), channel_colour);
	colour = mix(colour, vec3(0.85, 0.5, 0.18), smoothstep(0.75, 1.0, frequency_colour) * 0.3);
	float aa = max(fwidth(edge), 0.001);
	float core = (1.0 - smoothstep(max(0.0, 0.2 - aa), 0.2 + aa, abs(edge))) * min(1.0, 0.4 / aa);
	float halo = pow(max(0.0, 1.0 - abs(edge)), 2.5);
	float light = (halo * 0.16 + core * 0.85) * (0.012 + response * 2.0 * intensity) * fade * dim;
	if (shape == 2) {
		light = (0.002 + pow(response, 1.3) * 0.32 * intensity) * fade * dim;
	}
	ALBEDO = colour * light;
	EMISSION = colour * light * 0.6;
	ALPHA = 1.0;
}
