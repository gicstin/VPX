#pragma once
#include <string>

namespace godot {
struct String {
	std::string s;
	String() {}
	String(const char *c) :
			s(c) {}
	static String utf8(const char *c) { return String(c); }
	static String num(double d, int) { return String(std::to_string((int)d).c_str()); }
	String operator+(const String &o) const {
		String r;
		r.s = s + o.s;
		return r;
	}
};
} // namespace godot
