#define GDEXTENSION 1
#include "vpx_spatial_audio.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>

using namespace godot;

int main(int argc, char **argv) {
	const unsigned seed = argc > 1 ? (unsigned)atoi(argv[1]) : 1u;
	const int operations = argc > 2 ? atoi(argv[2]) : 4000;
	std::mt19937 rng(seed);
	const char *layouts[] = { "mono", "stereo", "quad", "5.1", "7.1", "5.1.2", "7.1.4", "ambisonic 1", "3.0", "2.1" };
	const int rates[] = { 8000, 22050, 44100, 48000, 96000, 192000 };
	VpxSpatialAudio audio;
	VpxSpatialAudio::Params params;
	PackedFloat32Array out;
	std::vector<float> in;
	int channels = 2;
	AVChannelLayout layout = {};
	av_channel_layout_from_string(&layout, "stereo");
	audio.configure(layout, 48000);
	auto uniform = [&](double a, double b) { return a + (b - a) * (rng() / 4294967296.0); };
	long finite_failures = 0;
	for (int op = 0; op < operations; op++) {
		switch (rng() % 14) {
			case 0: {
				const char *name = layouts[rng() % (sizeof(layouts) / sizeof(layouts[0]))];
				av_channel_layout_uninit(&layout);
				av_channel_layout_from_string(&layout, name);
				channels = layout.nb_channels;
				audio.configure(layout, rates[rng() % (sizeof(rates) / sizeof(rates[0]))]);
			} break;
			case 1:
				params.stereo_mode = (int)(rng() % 4);
				params.head_radius = (float)uniform(0.06, 0.12);
				params.room_amount = (float)uniform(0, 1);
				params.stereo_distance = (float)uniform(0, 1);
				params.bass_translate = (float)uniform(0, 1);
				params.upmix_centre = (float)uniform(0, 1);
				params.upmix_ambience = (float)uniform(0, 1);
				params.stereo_angle = (float)uniform(15, 60);
				params.stereo_amount = (float)uniform(0, 1);
				params.crossfeed_db = (float)uniform(-12, -1);
				params.crossfeed_hz = (float)uniform(300, 2000);
				params.air_db = (float)uniform(0, 9);
				params.stereo_tracked = rng() & 1;
				audio.set_params(params);
				break;
			case 2:
				params.lfe_gain = (float)uniform(0, 2);
				params.bass_db = (float)uniform(-12, 18);
				params.bass_hz = (float)uniform(40, 400);
				params.surround_level = (float)uniform(0.5, 4);
				params.shadow_strength = (float)uniform(0, 1.5);
				params.itd_scale = (float)uniform(0, 1.5);
				params.rear_depth = (float)uniform(0, 1);
				params.rear_cutoff = (float)uniform(500, 12000);
				params.ild = (float)uniform(0, 0.8);
				params.classic_shadow = rng() & 1;
				params.linear_delay = rng() & 1;
				params.normalize_downmix = rng() & 1;
				audio.set_params(params);
				break;
			case 3:
				audio.set_spatial(rng() & 1);
				break;
			case 4:
				audio.set_mono(rng() & 1);
				break;
			case 5:
				audio.set_dialogue_boost((float)uniform(0, 1));
				break;
			case 6:
				audio.note_seek();
				break;
			case 7: {
				Basis b;
				const float yaw = (float)uniform(-3.14, 3.14);
				b.m[0][0] = std::cos(yaw);
				b.m[0][2] = std::sin(yaw);
				b.m[2][0] = -std::sin(yaw);
				b.m[2][2] = std::cos(yaw);
				audio.set_listener(b);
			} break;
			default: {
				const int frames = 1 + (int)(rng() % 4096);
				in.resize((size_t)frames * channels);
				const int kind = (int)(rng() % 6);
				for (float &v : in) {
					switch (kind) {
						case 0: v = (float)uniform(-1, 1); break;
						case 1: v = 0.0f; break;
						case 2: v = (rng() & 1) ? 1.0f : -1.0f; break;
						case 3: v = (float)uniform(-4, 4); break;
						case 4: v = (rng() % 997 == 0) ? (float)uniform(-1, 1) : 0.0f; break;
						default: v = (float)(0.5 * std::sin(0.05 * (double)op * (&v - in.data()))); break;
					}
				}
				audio.process(in.data(), frames, out);
				for (int i = 0; i < frames * 2; i++) {
					if (!std::isfinite(out.v[i])) {
						finite_failures++;
					}
				}
			} break;
		}
	}
	printf("fuzz seed=%u operations=%d finite_failures=%ld\n", seed, operations, finite_failures);
	return finite_failures == 0 ? 0 : 1;
}
