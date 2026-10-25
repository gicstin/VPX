shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

#include "res://shaders/resonance_world.gdshaderinc"

varying vec3 direction;

void vertex() {
	direction = normalize(VERTEX);
}

float stars(vec3 d) {
	vec3 cell = floor(d * 160.0);
	float n = hash(dot(cell, vec3(1.0, 57.0, 113.0)));
	vec3 centre = (cell + 0.5) / 160.0;
	float near = smoothstep(0.0026, 0.0, length(d - normalize(centre)));
	return step(0.985, n) * near * (0.6 + 0.4 * sin(clock * (1.0 + n * 4.0) + n * 30.0));
}

void fragment() {
	vec3 d = normalize(direction);
	float elevation = asin(clamp(d.y, -1.0, 1.0));
	float a = atan(d.x, -d.z);
	float t = clock * motion;
	float horizon = exp(-abs(elevation) * 6.0);
	float front = exp(-pow(wrap_angle(a) / (1.4 - build * 0.9), 2.0));
	float level = energy_level();
	float toward = mix(0.35, 1.45, sound_at(a, 0.15));
	float lofty = 0.5 + min(treble, 1.0) * 1.3 + brightness * 0.4;
	vec3 zenith = colour_a * 0.004;
	vec3 band = mix(colour_a, colour_b, 0.5 + 0.5 * sin(a + t * 0.02)) * 0.035;
	vec3 colour = zenith + band * horizon * (0.5 + harmonic * 0.6) * toward;
	if (world_style == 0) {
		colour += vec3(0.6, 0.7, 1.0) * stars(d) * 0.35 * smoothstep(0.05, 0.4, elevation) * (1.0 - build * 0.5);
		float curtain = sin(a * 3.0 + sin(a * 7.0 + t * 0.05) * 0.8 + t * 0.03) * 0.5 + 0.5;
		float aurora = exp(-pow((elevation - 0.55 - curtain * 0.2) * 5.0, 2.0)) * pow(curtain, 2.0);
		colour += palette3(a / TAU + t * 0.003) * aurora * (0.02 + harmonic * 0.09 + brightness * 0.04) * level * toward * lofty;
	} else if (world_style == 1) {
		float vault = smoothstep(0.6, 1.4, elevation);
		colour += colour_c * vault * (0.006 + harmonic * 0.03 * toward * lofty + anticipation * 0.04);
		colour += vec3(0.6, 0.7, 1.0) * stars(d) * 0.18 * vault;
	} else {
		float surface = smoothstep(0.3, 1.3, elevation);
		float caustic = pow(abs(sin(d.x * 18.0 + t * 0.3) * sin(d.z * 15.0 - t * 0.25)), 6.0);
		colour = mix(colour_a * 0.006, colour_a * 0.03, surface) + colour_c * caustic * surface * (0.01 + (harmonic * 0.05 + percussive * 0.03) * toward * lofty);
		colour *= 1.0 - smoothstep(0.0, -0.5, elevation) * 0.7;
	}
	colour += colour_b * front * horizon * build * 0.16;
	colour *= 1.0 - build * 0.35 * (1.0 - front);
	float wave_height = drop_age * 0.9;
	colour += colour_c * exp(-pow((elevation + 0.1 - wave_height) * 4.0, 2.0)) * exp(-drop_age * 0.8) * smoothstep(0.0, 0.3, drop_age) * 0.14;
	colour += mix(colour_b, vec3(1.0), 0.3) * flash * 0.05 * (0.4 + horizon);
	colour += colour_a * section_change * 0.01;
	ALBEDO = colour * intensity * dim;
}
