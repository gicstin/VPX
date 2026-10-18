shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D panel_texture : source_color, filter_linear;
uniform float opacity = 1.0;

void fragment()
{
	vec2 dx = dFdx(UV) * 0.25;
	vec2 dy = dFdy(UV) * 0.25;
	vec4 c = (
		texture(panel_texture, UV + dx + dy) +
		texture(panel_texture, UV + dx - dy) +
		texture(panel_texture, UV - dx + dy) +
		texture(panel_texture, UV - dx - dy)
	) * 0.25;
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
}
