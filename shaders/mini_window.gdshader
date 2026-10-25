shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 bounds = vec2(840.0, 519.0);
uniform float corner_radius = 18.0;
uniform float opacity = 1.0;

void fragment() {
	vec4 source = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec2 position = SCREEN_UV * bounds;
	vec2 edge = abs(position - bounds * 0.5) - bounds * 0.5 + corner_radius;
	float distance = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - corner_radius;
	float coverage = (1.0 - smoothstep(-0.75, 0.75, distance)) * opacity;
	COLOR = source * coverage;
}
