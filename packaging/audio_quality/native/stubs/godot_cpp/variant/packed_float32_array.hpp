#pragma once
#include <cstdint>
#include <vector>

namespace godot {
struct PackedFloat32Array {
	std::vector<float> v;
	void resize(int64_t n) { v.resize(n); }
	float *ptrw() { return v.data(); }
	const float *ptr() const { return v.data(); }
};
} // namespace godot
