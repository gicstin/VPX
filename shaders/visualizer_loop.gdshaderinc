float loop_weight(float u) {
	float phase = fract(u);
	return smoothstep(0.0, 0.06, min(phase, 1.0 - phase));
}

float loop_join(float value, float first, float last, float u) {
	return mix((first + last) * 0.5, value, loop_weight(u));
}

float loop_sample(sampler2D source, float u, float row, float samples) {
	float start = 0.5 / samples;
	float end = 1.0 - start;
	float value = textureLod(source, vec2(mix(start, end, fract(u)), row), 0.0).r;
	if (loop_weight(u) >= 1.0) {
		return value;
	}
	return loop_join(value, textureLod(source, vec2(start, row), 0.0).r, textureLod(source, vec2(end, row), 0.0).r, u);
}
