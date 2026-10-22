shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D spectral_history_texture : filter_linear, repeat_disable;
uniform int spectral_history_head = -1;
uniform float spectral_history_fraction = 0.0;
uniform float spectral_history_valid = 0.0;
uniform int spectral_channel_count = 2;
uniform int spectrogram_style = 0;
uniform int shape = 0;
uniform int instance_count = 8;
uniform float intensity = 0.75;
uniform float sensitivity = 1.75;
uniform float dim = 1.0;

varying vec2 chart_uv;
varying float chart_channel;

float history_at(float band, float delay, float channel) {
	float index = float(spectral_history_head) + min(0.0, spectral_history_fraction - delay * 45.0);
	float row = mod(floor(index), 192.0);
	float next_row = mod(row + 1.0, 192.0);
	float x = clamp(band, 0.5 / 48.0, 47.5 / 48.0);
	float source = spectral_channel_count == 1 ? 0.0 : channel;
	float a = textureLod(spectral_history_texture, vec2(x, (source * 192.0 + row + 0.5) / 384.0), 0.0).r;
	float b = textureLod(spectral_history_texture, vec2(x, (source * 192.0 + next_row + 0.5) / 384.0), 0.0).r;
	float valid = 1.0 - smoothstep(spectral_history_valid * 3.8, spectral_history_valid * 3.8 + 0.025, delay);
	return mix(a, b, fract(index)) * valid * step(0.0, float(spectral_history_head));
}

float band_at(float u) {
	if (spectrogram_style == 1) {
		return mix(log(120.0 / 30.0) / log(600.0), log(8000.0 / 30.0) / log(600.0), u);
	}
	if (spectrogram_style == 2) {
		return u * log(300.0 / 30.0) / log(600.0);
	}
	return u;
}

vec2 measurement(vec2 uv, float channel) {
	float band = band_at(uv.x);
	float delay = uv.y * 3.8;
	float value = history_at(band, delay, channel);
	if (spectrogram_style == 3) {
		float before = history_at(band, delay + 3.0 / 45.0, channel);
		float valid = step(delay + 3.0 / 45.0, spectral_history_valid * 3.8);
		value = clamp((value - before) * 60.0 / 18.0, 0.0, 1.0) * valid;
		return vec2(value);
	}
	if (spectrogram_style == 4) {
		float left = history_at(band, delay, 0.0);
		float right = history_at(band, delay, 1.0);
		float audible = smoothstep(0.0, 0.08, max(left, right));
		return vec2(clamp((right - left) * 60.0 / 24.0, -1.0, 1.0) * audible, max(left, right));
	}
	if (spectrogram_style == 5) {
		value = clamp(value * 60.0 / 36.0, 0.0, 1.0);
	}
	return vec2(value);
}

vec3 chart_point(vec2 uv, float channel, float sector, float value) {
	float side = channel < 0.5 ? -1.0 : 1.0;
	float angle = (uv.x - 0.5) * 1.4;
	float radius = 9.0 + uv.y * 1.6;
	vec3 point;
	if (spectrogram_style == 0) {
		point = vec3(sin(angle) * radius, -side * 2.0 + (0.5 - uv.y) * 3.0, -cos(angle) * radius);
	} else if (spectrogram_style == 1) {
		point = vec3(side * (4.0 + value * 0.8), (uv.x - 0.5) * 6.5, -3.0 - uv.y * 22.0);
	} else if (spectrogram_style == 2) {
		point = vec3(side * (2.0 + uv.x * 6.0), -3.0 + value * 3.2, -3.0 - uv.y * 22.0);
	} else if (spectrogram_style == 3) {
		point = vec3((uv.x - 0.5) * 12.0, -side * 2.2 + value * 1.7, -3.0 - uv.y * 22.0);
	} else if (spectrogram_style == 4) {
		point = vec3((uv.x - 0.5) * 12.0, -1.6 + value * 3.2, -4.0 - uv.y * 22.0);
	} else if (spectrogram_style == 5) {
		radius = 7.0 - value * 0.65;
		point = vec3(sin(angle * 1.07) * radius, -side * 2.4 + (0.5 - uv.y) * 3.8, -cos(angle * 1.07) * radius);
	} else if (spectrogram_style == 6) {
		point = vec3(side * (1.0 + uv.x * 7.2), -2.8 + value * 5.0, -3.0 - uv.y * 24.0);
	} else {
		angle = (uv.x - 0.5) * (PI * 0.5 - 0.035);
		radius = 4.5 + uv.y * 19.0;
		point = vec3(sin(angle) * radius, -side * 1.8 + value * 1.2, -cos(angle) * radius);
	}
	float turn = sector * PI * 0.5;
	return vec3(point.x * cos(turn) - point.z * sin(turn), point.y, point.x * sin(turn) + point.z * cos(turn));
}

void vertex() {
	float groups = spectrogram_style == 4 ? 4.0 : 8.0;
	float traces = float(instance_count) / groups;
	float group = shape == 0 ? float(INSTANCE_ID) : floor(float(INSTANCE_ID) / traces);
	float channel = spectrogram_style == 4 ? 0.0 : mod(group, 2.0);
	float sector = spectrogram_style == 4 ? group : floor(group * 0.5);
	vec2 uv = shape == 0 ? VERTEX.xy : vec2(mod(float(INSTANCE_ID), traces) / max(1.0, traces - 1.0), VERTEX.x);
	float value = measurement(uv, channel).x;
	vec3 point = chart_point(uv, channel, sector, value);
	if (shape == 2) {
		vec2 next_uv = vec2(min(1.0, uv.x + 0.002), uv.y);
		vec2 prev_uv = vec2(max(0.0, uv.x - 0.002), uv.y);
		vec3 across = chart_point(next_uv, channel, sector, measurement(next_uv, channel).x) - chart_point(prev_uv, channel, sector, measurement(prev_uv, channel).x);
		point += normalize(across) * VERTEX.y * 0.012;
	}
	VERTEX = point;
	chart_uv = uv;
	chart_channel = channel;
}

float grid_line(float coordinate, float spacing) {
	float x = coordinate / spacing;
	float distance = abs(fract(x + 0.5) - 0.5);
	float aa = max(fwidth(x), 0.001);
	return 1.0 - smoothstep(aa * 0.35, aa * 1.1, distance);
}

vec3 heat_colour(float level, float channel) {
	vec3 dark = mix(vec3(0.005, 0.025, 0.10), vec3(0.06, 0.005, 0.08), channel);
	vec3 middle = mix(vec3(0.025, 0.7, 0.95), vec3(0.95, 0.09, 0.42), channel);
	vec3 colour = mix(dark, middle, smoothstep(0.0, 0.65, level));
	return mix(colour, vec3(1.0, 0.83, 0.28), smoothstep(0.65, 1.0, level));
}

void fragment() {
	vec2 data = measurement(chart_uv, chart_channel);
	float level = data.y;
	float range_db = spectrogram_style == 5 ? 36.0 : (spectrogram_style == 3 ? 18.0 : 60.0);
	float frequency_grid = grid_line(band_at(chart_uv.x) * log(600.0) / log(2.0), 1.0);
	float time_grid = grid_line(chart_uv.y * 3.8, 0.5);
	float contour = grid_line(data.x * range_db, spectrogram_style == 3 ? 3.0 : 10.0) * step(0.03, level);
	float current = 1.0 - smoothstep(0.0, 0.012, chart_uv.y);
	float border = max(grid_line(chart_uv.x, 1.0), grid_line(chart_uv.y, 1.0));
	vec3 channel_tint = mix(vec3(0.035, 0.7, 1.0), vec3(1.0, 0.08, 0.4), chart_channel);
	vec3 colour = heat_colour(level, chart_channel);
	if (spectrogram_style == 4) {
		channel_tint = data.x < 0.0 ? vec3(0.02, 0.7, 1.0) : vec3(1.0, 0.08, 0.4);
		colour = mix(vec3(0.15, 0.4, 0.33), channel_tint, smoothstep(0.0, 0.35, abs(data.x)));
		contour = grid_line(data.x * 24.0, 6.0) * step(0.03, level);
	}
	float valid = 1.0 - smoothstep(spectral_history_valid, spectral_history_valid + 0.008, chart_uv.y);
	float drive = clamp(sensitivity / 1.75, 0.28, 2.3);
	vec3 light;
	if (shape == 0) {
		float heat = pow(level, 1.5) * (0.35 + drive * 0.55);
		light = colour * (heat + contour * level * 0.22) * valid;
		light += channel_tint * (max(frequency_grid, time_grid) * 0.012 + border * 0.045 + current * 0.1);
	} else {
		light = colour * (0.012 + level * level * 0.5 * drive) * valid;
	}
	light *= intensity * dim;
	ALBEDO = light;
	EMISSION = light * 0.35;
	ALPHA = 1.0;
}
