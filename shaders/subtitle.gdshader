shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D subtitle_texture : source_color, filter_linear;
uniform float flat_curve = 0.0;

void vertex()
{
	if (flat_curve > 0.0001)
	{
		float radius = 1.0 / flat_curve;
		float theta = VERTEX.x * flat_curve;
		VERTEX.x = radius * sin(theta);
		VERTEX.z += radius * (1.0 - cos(theta));
	}
}

void fragment()
{
	vec2 dx = dFdx(UV) * 0.25;
	vec2 dy = dFdy(UV) * 0.25;
	vec4 c = (
		texture(subtitle_texture, UV + dx + dy) +
		texture(subtitle_texture, UV + dx - dy) +
		texture(subtitle_texture, UV - dx + dy) +
		texture(subtitle_texture, UV - dx - dy)
	) * 0.25;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
