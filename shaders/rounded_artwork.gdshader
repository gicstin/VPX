shader_type canvas_item;

uniform vec2 bounds = vec2(128.0);
uniform float corner_radius = 18.0;

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float radius = min(corner_radius, min(bounds.x, bounds.y) * 0.5);
	vec2 edge = abs(local_position - bounds * 0.5) - bounds * 0.5 + radius;
	float distance = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - radius;
	float width = max(fwidth(distance), 0.001);
	COLOR.a *= 1.0 - smoothstep(-width * 0.5, width * 0.5, distance);
}
