shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D spectrum_texture : filter_linear, repeat_disable;
uniform float clock = 0.0;
uniform float intensity = 0.75;
uniform float motion = 0.6;
uniform float presence = 0.0;
uniform float bass = 0.0;
uniform float mids = 0.0;
uniform float treble = 0.0;
uniform float impulse = 0.0;
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

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float band = INSTANCE_CUSTOM.y;
	float lane = INSTANCE_CUSTOM.z;
	float phase = INSTANCE_CUSTOM.w * TAU;
	float t = clock * motion;
	vec3 point;
	if (shape == 1) {
		float az = phase + sin(t * 0.045 + seed * 7.0) * 0.14;
		float height = lane * 1.8 - 0.9;
		vec3 direction = vec3(sin(az) * sqrt(1.0 - height * height), height, -cos(az) * sqrt(1.0 - height * height));
		response = energy_at(band, direction);
		float radius = 4.5 + seed * 23.0 + sin(t * 0.12 + phase) * 0.25;
		float flash = pow(max(0.0, sin(clock * (0.4 + seed) + phase)), 14.0);
		float size = (0.035 + seed * 0.04 + response * 0.08 * intensity) * (1.0 + impulse * 0.7);
		point = direction * radius + VERTEX * size;
		spark = 0.5 + flash * treble;
		edge = 0.0;
	} else {
		float az = VERTEX.x * TAU + phase;
		float radius = 4.0 + lane * 13.0;
		float y = sin(phase * 2.0) * (2.3 + lane * 4.0);
		vec3 direction = normalize(vec3(sin(az) * radius, y, -cos(az) * radius));
		response = energy_at(band, direction);
		float wave = sin(az * (2.0 + floor(seed * 3.0)) + t * 0.28 + phase) * 0.3;
		wave += sin(az * 7.0 - t * 0.18 + phase) * 0.09;
		if (shape == 0) {
			radius += (wave * motion + response * 1.9 + bass * 0.4) * intensity;
			y += sin(az * 3.0 + t * 0.2 + phase) * (0.35 + response * intensity) * motion;
			float width = (0.025 + response * 0.15 * intensity + mids * 0.035) * (0.5 + preset.x * 0.85 + preset.y * 0.7 + preset.z * 0.3);
			y += VERTEX.y * width * (1.0 + stereo_width * 0.3);
			point = vec3(sin(az) * radius, y, -cos(az) * radius);
			vec3 architecture = vec3(sin(az) * cos(phase) * radius, cos(az) * radius, sin(az) * sin(phase) * radius);
			architecture += vec3(-sin(phase), 0.0, cos(phase)) * VERTEX.y * width;
			point = mix(point, architecture, preset.y);
			float tilt = sin(phase) * 0.9;
			vec3 orbit = vec3(point.x, point.y * cos(tilt) - point.z * sin(tilt), point.y * sin(tilt) + point.z * cos(tilt));
			point = mix(point, orbit, preset.z);
			point.xz += vec2(sin(t * 0.08 + phase), cos(t * 0.1 + phase)) * motion * 0.22;
		} else {
			radius += (bass * 0.7 + impulse * 0.3) * intensity;
			float width = 0.018 + response * 0.055 * intensity;
			radius += VERTEX.y * width * (1.0 + stereo_width * 0.3);
			point = vec3(sin(az) * radius, cos(phase) * 0.35, -cos(az) * radius);
			float tilt = phase + sin(t * 0.04 + phase) * 0.12;
			point = vec3(point.x, point.y * cos(tilt) - point.z * sin(tilt), point.y * sin(tilt) + point.z * cos(tilt));
		}
		edge = VERTEX.y;
		spark = 1.0;
	}
	if (shape != 1) {
		response = energy_at(band, normalize(point));
	}
	VERTEX = point;
	colour_phase = band * 0.48 + phase * 0.08 + palette;
}

void fragment() {
	float hue = fract(colour_phase);
	vec3 colour = mix(vec3(0.03, 0.72, 1.0), vec3(0.72, 0.12, 1.0), smoothstep(0.0, 0.65, hue));
	colour = mix(colour, vec3(1.0, 0.32, 0.12), smoothstep(0.65, 1.0, hue) * 0.7);
	float aa = max(fwidth(edge), 0.001);
	float filament = (1.0 - smoothstep(max(0.0, 0.14 - aa), 0.14 + aa, abs(edge))) * min(1.0, 0.28 / aa);
	float halo = pow(max(0.0, 1.0 - abs(edge)), 2.0);
	float weight = shape == 1 ? preset.x * 0.35 + preset.y * 0.12 + preset.z : (shape == 0 ? 0.45 + preset.x * 0.75 : 0.35 + preset.y * 0.9);
	float light = shape == 1 ? (0.35 + response * 2.0 * intensity) * spark : (0.12 * halo + filament * (0.65 + response * 2.5 * intensity + impulse * response));
	light *= weight * presence * dim;
	ALBEDO = colour * light;
	EMISSION = colour * light * 0.7;
	ALPHA = 1.0;
}
