#define GDEXTENSION 1
#include "vpx_spatial_audio.h"

#include <cmath>
#include <cstring>
#include <string>

using namespace godot;

namespace {
struct Handle {
	VpxSpatialAudio audio;
	VpxSpatialAudio::Params params;
	PackedFloat32Array out;
	std::string description;
	std::string layout;
};
} // namespace

extern "C" {

void *vsa_new() { return new Handle(); }

void vsa_free(void *p_handle) { delete (Handle *)p_handle; }

int vsa_configure(void *p_handle, const char *p_layout, int p_rate) {
	Handle *h = (Handle *)p_handle;
	AVChannelLayout layout = {};
	if (av_channel_layout_from_string(&layout, p_layout) < 0) {
		return -1;
	}
	h->audio.configure(layout, p_rate);
	const int channels = layout.nb_channels;
	av_channel_layout_uninit(&layout);
	return channels;
}

int vsa_set_param(void *p_handle, const char *p_key, double p_value) {
	VpxSpatialAudio::Params &p = ((Handle *)p_handle)->params;
	const std::string key = p_key;
	const float v = (float)p_value;
#define NUM(name)       \
	if (key == #name) { \
		p.name = v;     \
		return 0;       \
	}
#define FLAG(name)      \
	if (key == #name) { \
		p.name = v != 0.0; \
		return 0;       \
	}
#define INT(name)       \
	if (key == #name) { \
		p.name = (int)p_value; \
		return 0;       \
	}
	NUM(lfe_gain)
	NUM(bass_db)
	NUM(bass_hz)
	NUM(surround_level)
	NUM(shadow_strength)
	NUM(itd_scale)
	NUM(rear_depth)
	NUM(rear_cutoff)
	NUM(ild)
	FLAG(classic_shadow)
	FLAG(linear_delay)
	FLAG(normalize_downmix)
	INT(stereo_mode)
	NUM(stereo_angle)
	NUM(stereo_amount)
	NUM(crossfeed_db)
	NUM(crossfeed_hz)
	NUM(air_db)
	FLAG(stereo_tracked)
	NUM(head_radius)
	NUM(room_amount)
	NUM(stereo_distance)
	NUM(bass_translate)
	NUM(upmix_centre)
	NUM(upmix_ambience)
	return -1;
}

void vsa_apply(void *p_handle) {
	Handle *h = (Handle *)p_handle;
	h->audio.set_params(h->params);
}

void vsa_set_spatial(void *p_handle, int p_on) { ((Handle *)p_handle)->audio.set_spatial(p_on != 0); }

void vsa_set_mono(void *p_handle, int p_on) { ((Handle *)p_handle)->audio.set_mono(p_on != 0); }

void vsa_set_dialogue(void *p_handle, float p_amount) { ((Handle *)p_handle)->audio.set_dialogue_boost(p_amount); }

void vsa_set_listener(void *p_handle, const float *p_rows) {
	Basis b;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			b.m[i][j] = p_rows[i * 3 + j];
		}
	}
	((Handle *)p_handle)->audio.set_listener(b);
}

void vsa_note_seek(void *p_handle) { ((Handle *)p_handle)->audio.note_seek(); }

int vsa_process(void *p_handle, const float *p_in, int p_frames, float *p_out) {
	Handle *h = (Handle *)p_handle;
	h->audio.process(p_in, p_frames, h->out);
	if (p_frames > 0) {
		memcpy(p_out, h->out.ptr(), sizeof(float) * (size_t)p_frames * 2);
	}
	return 2;
}

int vsa_input_channels(void *p_handle) { return ((Handle *)p_handle)->audio.get_input_channels(); }

int vsa_latency(void *p_handle) { return ((Handle *)p_handle)->audio.get_stereo_latency(); }

int vsa_stereo_mode(void *p_handle) { return ((Handle *)p_handle)->audio.get_stereo_mode(); }

int vsa_spatial_active(void *p_handle) { return ((Handle *)p_handle)->audio.is_spatial_active() ? 1 : 0; }

const char *vsa_describe(void *p_handle) {
	Handle *h = (Handle *)p_handle;
	h->description = h->audio.describe().s;
	return h->description.c_str();
}
}
