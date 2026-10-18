uniform sampler2D plane_y : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D plane_c : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D plane_c2 : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D plane_a : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool semiplanar = false;
uniform bool chroma_in_alpha = false;
uniform bool has_alpha = false;
uniform float sample_scale = 1.0;
uniform int color_matrix = 1;
uniform bool full_range = false;
uniform int transfer_function = 0;
uniform bool wide_gamut = false;
uniform vec2 chroma_offset = vec2(0.0);
uniform bool packed_rgb = false;

vec4 sample_yuva_set(sampler2D y_tex, sampler2D c_tex, sampler2D c2_tex, sampler2D a_tex, vec2 uv)
{
	if (packed_rgb)
		return texture(y_tex, uv);
	vec2 chroma_uv = uv + chroma_offset;
	float y = texture(y_tex, uv).r;
	vec2 c;
	if (semiplanar)
	{
		vec4 t = texture(c_tex, chroma_uv);
		c = vec2(t.r, chroma_in_alpha ? t.a : t.g);
	}
	else
		c = vec2(texture(c_tex, chroma_uv).r, texture(c2_tex, chroma_uv).r);
	float a = has_alpha ? texture(a_tex, uv).r : 1.0;
	return vec4(vec3(y, c) * sample_scale, a);
}

vec4 sample_yuva(vec2 uv)
{
	return sample_yuva_set(plane_y, plane_c, plane_c2, plane_a, uv);
}

vec4 sample_yuva_lod(vec2 uv, float lod)
{
	if (packed_rgb)
		return textureLod(plane_y, uv, lod);
	vec2 chroma_uv = uv + chroma_offset;
	float y = textureLod(plane_y, uv, lod).r;
	vec2 c;
	if (semiplanar)
	{
		vec4 t = textureLod(plane_c, chroma_uv, lod);
		c = vec2(t.r, chroma_in_alpha ? t.a : t.g);
	}
	else
		c = vec2(textureLod(plane_c, chroma_uv, lod).r, textureLod(plane_c2, chroma_uv, lod).r);
	float a = has_alpha ? textureLod(plane_a, uv, lod).r : 1.0;
	return vec4(vec3(y, c) * sample_scale, a);
}

vec4 sample_yuva_grad(vec2 uv, vec2 dx, vec2 dy)
{
	if (packed_rgb)
		return textureGrad(plane_y, uv, dx, dy);
	vec2 chroma_uv = uv + chroma_offset;
	float y = textureGrad(plane_y, uv, dx, dy).r;
	vec2 c;
	if (semiplanar)
	{
		vec4 t = textureGrad(plane_c, chroma_uv, dx, dy);
		c = vec2(t.r, chroma_in_alpha ? t.a : t.g);
	}
	else
		c = vec2(textureGrad(plane_c, chroma_uv, dx, dy).r, textureGrad(plane_c2, chroma_uv, dx, dy).r);
	float a = has_alpha ? textureGrad(plane_a, uv, dx, dy).r : 1.0;
	return vec4(vec3(y, c) * sample_scale, a);
}

vec3 yuv_to_rgb_gamma(vec3 yuv)
{
	float y = yuv.x;
	vec2 c = yuv.yz;
	if (full_range)
	{
		c -= 128.0 / 255.0;
	}
	else
	{
		y = (y - 16.0 / 255.0) * (255.0 / 219.0);
		c = (c - 128.0 / 255.0) * (255.0 / 224.0);
	}
	vec3 rgb;
	if (color_matrix == 0)
		rgb = vec3(y + 1.402 * c.y, y - 0.344136 * c.x - 0.714136 * c.y, y + 1.772 * c.x);
	else if (color_matrix == 2)
		rgb = vec3(y + 1.4746 * c.y, y - 0.164553 * c.x - 0.571353 * c.y, y + 1.8814 * c.x);
	else
		rgb = vec3(y + 1.5748 * c.y, y - 0.187324 * c.x - 0.468124 * c.y, y + 1.8556 * c.x);
	return clamp(rgb, 0.0, 1.0);
}

vec3 srgb_to_linear(vec3 c)
{
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
	return mix(lo, hi, step(0.04045, c));
}

vec3 pq_to_linear(vec3 e)
{
	const float m1 = 0.1593017578125;
	const float m2 = 78.84375;
	const float c1 = 0.8359375;
	const float c2 = 18.8515625;
	const float c3 = 18.6875;
	vec3 p = pow(max(e, vec3(0.0)), vec3(1.0 / m2));
	vec3 l = pow(max(p - c1, vec3(0.0)) / (c2 - c3 * p), vec3(1.0 / m1));
	return l * (10000.0 / 203.0);
}

vec3 hlg_to_linear(vec3 e)
{
	const float a = 0.17883277;
	const float b = 0.28466892;
	const float c = 0.55991073;
	vec3 lo = e * e / 3.0;
	vec3 hi = (exp((e - c) / a) + b) / 12.0;
	vec3 scene = mix(lo, hi, step(0.5, e));
	float luma = dot(scene, vec3(0.2627, 0.6780, 0.0593));
	vec3 display = scene * pow(max(luma, 1e-6), 0.2);
	return display * (1000.0 / 203.0);
}

vec3 tonemap_hdr(vec3 c)
{
	const float white = 6.0;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float mapped = luma * (1.0 + luma / (white * white)) / (1.0 + luma);
	return c * (mapped / max(luma, 1e-6));
}

vec3 bt2020_to_bt709(vec3 c)
{
	return vec3(
		1.6605 * c.r - 0.5876 * c.g - 0.0728 * c.b,
		-0.1246 * c.r + 1.1329 * c.g - 0.0083 * c.b,
		-0.0182 * c.r - 0.1006 * c.g + 1.1187 * c.b);
}

vec3 video_to_linear(vec3 rgb_gamma)
{
	vec3 linear;
	if (transfer_function == 1)
		linear = tonemap_hdr(pq_to_linear(rgb_gamma));
	else if (transfer_function == 2)
		linear = tonemap_hdr(hlg_to_linear(rgb_gamma));
	else
		linear = srgb_to_linear(rgb_gamma);
	if (wide_gamut)
		linear = max(bt2020_to_bt709(linear), vec3(0.0));
	return linear;
}
