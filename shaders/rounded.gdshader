shader_type canvas_item;

uniform vec2 size = vec2(100.0);
uniform float radius = 12.0;

void fragment()
{
	vec2 p = (UV - 0.5) * size;
	vec2 q = abs(p) - size * 0.5 + radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	COLOR.a *= clamp(0.5 - d / max(fwidth(d), 1e-4), 0.0, 1.0);
}
