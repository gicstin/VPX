shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform sampler2D wave_texture : filter_linear, repeat_disable;
uniform sampler2D history_texture : filter_linear, repeat_enable;
uniform int source_count = 2;
uniform int instance_count = 24;
uniform float history_head = 0.0;
uniform float history_fraction = 0.0;
uniform float clock = 0.0;
uniform float intensity = 0.75;
uniform float motion = 0.6;
uniform float presence = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float impulse = 0.0;
uniform vec3 transients = vec3(0.0);
uniform float beat_age = 4.0;
uniform float stereo_width = 0.0;
uniform float palette = 0.0;
uniform vec3 preset = vec3(1.0, 0.0, 0.0);
uniform int shape = 0;
uniform mat3 audio_basis = mat3(1.0);
uniform float dim = 1.0;

varying float response;
varying float colour_phase;
varying float edge;
varying float spark;
varying float along;
varying float depth_fade;

float energy_at(float band, vec3 direction) {
	direction = audio_basis * direction;
	float azimuth = mod(atan(direction.x, -direction.z) / TAU + 1.0, 1.0);
	float elevation = clamp(asin(clamp(direction.y, -1.0, 1.0)) / (PI * 0.25) + 1.0, 0.0, 2.0);
	float row_a = floor(elevation);
	float row_b = min(2.0, row_a + 1.0);
	float cell = azimuth * 16.0;
	float a = mod(floor(cell), 16.0);
	float b = mod(a + 1.0, 16.0);
	float v_a = mix(textureLod(spectrum_texture, vec2(band, (2.5 + row_a * 16.0 + a) / 50.0), 0.0).r, textureLod(spectrum_texture, vec2(band, (2.5 + row_a * 16.0 + b) / 50.0), 0.0).r, fract(cell));
	float v_b = mix(textureLod(spectrum_texture, vec2(band, (2.5 + row_b * 16.0 + a) / 50.0), 0.0).r, textureLod(spectrum_texture, vec2(band, (2.5 + row_b * 16.0 + b) / 50.0), 0.0).r, fract(cell));
	return mix(v_a, v_b, fract(elevation));
}

vec3 tone(float phase) {
	vec3 colour = mix(vec3(0.025, 0.56, 1.0), vec3(0.48, 0.12, 1.0), smoothstep(0.12, 0.58, phase));
	return mix(colour, vec3(1.0, 0.38, 0.1), smoothstep(0.58, 0.98, phase));
}

vec4 source_history(float channel, float delay) {
	float position = history_head + (min(0.0, history_fraction - delay * 90.0) + 0.5) / 192.0;
	return textureLod(history_texture, vec2(position, (channel + 0.5) * 0.5), 0.0);
}

struct SourceVertex {
	vec3 point;
	float response;
	float colour_phase;
	float edge;
	float spark;
	float along;
};

SourceVertex source_vertex(vec3 vertex, float instance_id, float seed, float band, float lane) {
	SourceVertex result;
	result.along = vertex.x;
	float channels = float(source_count);
	float channel = mod(instance_id, channels);
	float index = floor(instance_id / channels);
	float count = max(1.0, float(instance_count) / channels);
	float side = source_count == 1 ? 0.0 : channel * 2.0 - 1.0;
	vec3 origin = vec3(side * 3.0, 0.0, -5.2);
	vec3 forward = normalize(-origin);
	vec3 lateral = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
	vec3 up = vec3(0.0, 1.0, 0.0);
	float travel = fract(index / count + clock / 1.8);
	float distance = travel * 6.0 * motion;
	float delay = travel * 1.8;
	vec4 history = source_history(channel, delay);
	float az = result.along * TAU;
	vec3 point;
	result.colour_phase = channel == 0.0 ? 0.10 : 0.54;
	if (source_count == 1) {
		result.colour_phase = 0.28;
	}
	if (shape == 3) {
		vec4 current = source_history(channel, 0.0);
		result.response = current.a;
		float wave = textureLod(wave_texture, vec2(mix(0.5 / 256.0, 255.5 / 256.0, result.along), (channel + 0.5) * 0.5), 0.0).r;
		float radius = 0.16 + index * 0.11 + clamp(wave, -0.5, 0.5) * 0.06 * intensity * pow(sin(result.along * PI), 2.0);
		radius += vertex.y * (0.018 + min(result.response, 1.0) * 0.018);
		point = origin + (lateral * cos(az) + up * sin(az)) * radius;
		result.spark = 0.12 + min(result.response, 1.5) * 1.6 * intensity;
		result.response = min(result.response, 1.0);
		result.along = 0.5;
	} else if (shape == 1) {
		float travel = fract(seed + clock / 1.8);
		float high = textureLod(spectrum_texture, vec2(mix(0.72, 0.99, band), (channel + 0.5) / 50.0), 0.0).r;
		vec4 past = source_history(channel, travel * 1.8);
		result.response = min(past.b, 1.0) * high;
		float angle = lane * TAU;
		float spread = 0.3 + travel * 3.0;
		vec3 centre = origin + (forward * travel * 5.0 + (lateral * cos(angle) + up * sin(angle)) * spread) * motion;
		point = centre + vertex * (0.008 + result.response * 0.024 * intensity);
		result.spark = result.response * smoothstep(0.0, 0.12, travel) * (1.0 - smoothstep(0.65, 1.0, travel)) * 0.18;
		result.along = 0.5;
	} else {
		result.response = min(shape == 0 ? history.r : history.g, 1.5);
		float radius = 0.26 + distance * (shape == 0 ? 0.5 : 0.38);
		float tilt = shape == 0 ? 0.0 : (lane - 0.5) * 0.65;
		vec3 vertical = up * cos(tilt) + forward * sin(tilt);
		float width = 0.018 + min(result.response, 1.0) * 0.035 * intensity;
		radius += vertex.y * width;
		float wave = textureLod(wave_texture, vec2(mix(0.5 / 256.0, 255.5 / 256.0, result.along), (channel + 0.5) * 0.5), 0.0).r;
		radius += wave * 0.035 * intensity * exp(-distance);
		point = origin + forward * distance * 0.65 + (lateral * cos(az) + vertical * sin(az)) * radius;
		result.spark = result.response * smoothstep(0.0, 0.04, travel) * (1.0 - smoothstep(0.5, 1.0, travel));
		result.spark *= (shape == 0 ? 12.0 : 4.0) / count;
		result.along = 0.5;
	}
	if (shape != 3) {
		result.spark *= smoothstep(0.0, 0.1, motion);
	}
	if (source_count == 2) {
		result.spark *= smoothstep(-0.2, 0.6, point.x * side);
	}
	result.edge = shape == 1 ? 0.0 : vertex.y;
	result.point = point;
	return result;
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float band = INSTANCE_CUSTOM.y;
	float lane = INSTANCE_CUSTOM.z;
	float phase = INSTANCE_CUSTOM.w * TAU;
	float t = clock * motion;
	vec3 point;
	along = VERTEX.x;
	spark = 1.0;
	if (source_count > 0) {
		SourceVertex source = source_vertex(VERTEX, float(INSTANCE_ID), seed, band, lane);
		point = source.point;
		response = source.response;
		colour_phase = source.colour_phase;
		edge = source.edge;
		spark = source.spark;
		along = source.along;
	} else if (shape == 1) {
		float height = lane * 1.96 - 0.98;
		float az = phase + sin(t * 0.025 + seed * 7.0) * 0.06;
		vec3 direction = vec3(sin(az) * sqrt(1.0 - height * height), height, -cos(az) * sqrt(1.0 - height * height));
		float high_band = mix(0.72, 0.99, band);
		response = energy_at(high_band, direction);
		float radius = 6.0 + seed * 27.0;
		float glitter = pow(max(0.0, sin(phase * 23.0 + t * 1.4)), 12.0) * response * treble;
		float size = (0.016 + seed * 0.025 + response * 0.06 * intensity) * (1.0 + transients.z * 1.6);
		point = direction * radius + VERTEX * size;
		spark = 0.35 + glitter * 3.0 + transients.z * response * 2.0;
		edge = 0.0;
		along = 0.5;
		colour_phase = 0.45 + band * 0.4 + palette;
	} else if (shape == 0) {
		float height = (lane * 1.7 - 0.85) * mix(0.65, 1.0, preset.z);
		vec3 direction = vec3(sin(phase) * sqrt(1.0 - height * height), height, -cos(phase) * sqrt(1.0 - height * height));
		vec3 tangent = normalize(cross(vec3(0.0, 1.0, 0.0), direction));
		vec3 upright = normalize(cross(direction, tangent));
		float tilt = (floor(seed * 5.0) - 2.0) * 0.48 * preset.y + sin(phase * 2.0) * 0.5 * preset.z;
		vec3 axis = tangent * cos(tilt) + upright * sin(tilt);
		vec3 bend = upright * cos(tilt) - tangent * sin(tilt);
		float radius = 7.0 + seed * 13.0;
		float span = 13.0 + lane * 12.0;
		vec3 centre = direction * radius;
		response = energy_at(mix(0.015, 0.285, band), direction);
		float left = textureLod(wave_texture, vec2(mix(0.5 / 256.0, 255.5 / 256.0, along), 0.25), 0.0).r;
		float right = textureLod(wave_texture, vec2(mix(0.5 / 256.0, 255.5 / 256.0, along), 0.75), 0.0).r;
		float wave = mix(left, right, smoothstep(-0.5, 0.5, direction.x));
		float gate = smoothstep(0.0015, 0.007, abs(wave));
		float displacement = clamp(wave * 7.0, -2.4, 2.4) * gate * intensity;
		float width = 0.035 + response * 0.07 * intensity + transients.x * 0.02;
		point = centre + axis * ((along - 0.5) * span) + bend * (displacement + VERTEX.y * width);
		edge = VERTEX.y;
		colour_phase = 0.02 + seed * 0.24 + palette;
	} else if (shape == 2) {
		float height = lane * 1.9 - 0.95;
		vec3 normal = vec3(sin(phase) * sqrt(1.0 - height * height), height, -cos(phase) * sqrt(1.0 - height * height));
		vec3 axis = normalize(cross(vec3(0.0, 1.0, 0.0), normal));
		vec3 upright = cross(normal, axis);
		float mid_band = mix(0.3, 0.71, band);
		response = energy_at(mid_band, normal);
		float az = (along - 0.5) * TAU * (0.4 + seed * 0.35) + phase + t * 0.04 * (seed - 0.5);
		float radius = 1.6 + band * 3.2 + response * 0.65 * intensity;
		float width = 0.025 + response * 0.06 * intensity;
		radius += VERTEX.y * width;
		point = normal * (9.0 + seed * 15.0) + (axis * sin(az) + upright * cos(az)) * radius;
		float tracer = pow(max(0.0, cos(along * 18.0 - t * 1.8 + phase)), 18.0);
		spark = 0.65 + tracer * (response + transients.y) * 2.0;
		edge = VERTEX.y;
		colour_phase = 0.32 + band * 0.42 + palette;
	} else {
		float az = along * TAU;
		float radius = 6.0 + beat_age * motion * (7.0 + seed * 3.0) + lane * 2.5;
		float width = 0.035 + bass * 0.08 * intensity;
		point = vec3(sin(az) * (radius + VERTEX.y * width), -3.5 - lane * 3.0, -cos(az) * (radius + VERTEX.y * width));
		point.xz += vec2(sin(phase), cos(phase)) * 2.0;
		response = bass;
		spark = exp(-beat_age * 3.5) * smoothstep(0.0, 0.035, beat_age) * intensity;
		edge = VERTEX.y;
		along = 0.5;
		colour_phase = 0.76 + seed * 0.16 + palette;
	}
	depth_fade = 1.0 - smoothstep(26.0, 40.0, length(point));
	VERTEX = point;
}

void fragment() {
	vec3 colour = tone(fract(colour_phase));
	float aa = max(fwidth(edge), 0.001);
	float filament = (1.0 - smoothstep(max(0.0, 0.18 - aa), 0.18 + aa, abs(edge))) * min(1.0, 0.36 / aa);
	float halo = pow(max(0.0, 1.0 - abs(edge)), 2.5);
	float ends = smoothstep(0.0, 0.08, along) * smoothstep(0.0, 0.08, 1.0 - along);
	float weight;
	if (shape == 0) {
		weight = 0.65 + preset.x * 0.55 + preset.y * 0.2;
	} else if (shape == 1) {
		weight = 0.25 + preset.x * 0.3 + preset.z * 0.9;
	} else if (shape == 2) {
		weight = 0.28 + preset.y * 0.8 + preset.z * 0.35;
	} else {
		weight = 0.8;
	}
	float light = shape == 1 ? (0.2 + response * 2.0 * intensity) * spark : (halo * 0.16 + filament * (0.7 + response * 2.3 * intensity)) * spark;
	light *= weight * (source_count > 0 ? 1.0 : presence) * dim * depth_fade * ends;
	vec3 core = mix(colour, vec3(0.75, 0.92, 1.0), filament * response * 0.35);
	ALBEDO = core * light;
	EMISSION = core * light * 0.8;
	ALPHA = 1.0;
}
