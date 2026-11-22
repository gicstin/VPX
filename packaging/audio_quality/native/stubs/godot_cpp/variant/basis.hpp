#pragma once
#include "vector3.hpp"

namespace godot {
struct Basis {
	float m[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
	Basis() {}
	Basis transposed() const {
		Basis b;
		for (int i = 0; i < 3; i++) {
			for (int j = 0; j < 3; j++) {
				b.m[i][j] = m[j][i];
			}
		}
		return b;
	}
	Vector3 xform(const Vector3 &v) const {
		return Vector3(
				m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
				m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
				m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z);
	}
	Basis orthonormalized() const { return *this; }
};
} // namespace godot
