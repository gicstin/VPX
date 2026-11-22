#pragma once
#include <algorithm>
#include <cmath>

namespace godot {
struct Vector3 {
	float x = 0.0f;
	float y = 0.0f;
	float z = 0.0f;
	Vector3() {}
	Vector3(float p_x, float p_y, float p_z) :
			x(p_x), y(p_y), z(p_z) {}
	float dot(const Vector3 &o) const { return x * o.x + y * o.y + z * o.z; }
	float length() const { return std::sqrt(dot(*this)); }
	Vector3 normalized() const {
		const float l = length();
		return l > 0.0f ? Vector3(x / l, y / l, z / l) : *this;
	}
	Vector3 operator+(const Vector3 &o) const { return Vector3(x + o.x, y + o.y, z + o.z); }
	Vector3 operator-(const Vector3 &o) const { return Vector3(x - o.x, y - o.y, z - o.z); }
	Vector3 operator*(float f) const { return Vector3(x * f, y * f, z * f); }
};
} // namespace godot

#ifndef CLAMP
#define CLAMP(m_a, m_min, m_max) (((m_a) < (m_min)) ? (m_min) : (((m_a) > (m_max)) ? (m_max) : (m_a)))
#endif
