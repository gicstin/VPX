shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

#include "res://shaders/yuv.gdshaderinc"

uniform int projection = 0;
uniform int stereo_layout = 0;
uniform bool swap_eyes = false;
uniform bool single_eye = false;
uniform float fisheye_fov = 180.0;
uniform float brightness = 1.0;
uniform float sharpness = 0.0;
uniform float gamma = 1.0;
uniform float saturation = 1.0;
uniform int background_mode = 0;
uniform vec3 cut_color : source_color = vec3(0.0, 0.12, 0.24);
uniform bool cut_enabled = false;
uniform bool cut_invert = false;
uniform float cut_similarity = 0.08;
uniform float cut_feather = 0.08;
uniform float edge_fade = 0.04;
uniform float menu_dim = 1.0;
uniform int alpha_mask = 0;
uniform float mask_threshold = 0.5;
uniform float mask_trim = 0.0;
uniform float mask_darken = 2.0;
uniform int picture_source = 0;
uniform sampler2DArray tile_y : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2DArray tile_cb : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2DArray tile_cr : filter_linear_mipmap_anisotropic, repeat_disable;
uniform samplerCube cube_y : filter_linear_mipmap_anisotropic;
uniform samplerCube cube_cb : filter_linear_mipmap_anisotropic;
uniform samplerCube cube_cr : filter_linear_mipmap_anisotropic;
uniform vec4 tile_geometry = vec4(1.0, 1.0, 0.0, 1.0);
uniform int tile_count = 1;
uniform vec2 picture_size = vec2(1.0);
uniform bool rgb_planes = false;
uniform bool picture_supersample = true;
uniform float flat_curve = 0.0;
uniform float stereo_depth = 0.0;
uniform float stereo_vertical = 0.0;
uniform float picture_zoom = 1.0;
uniform vec3 zoom_forward = vec3(0.0, 0.0, -1.0);
uniform int flat_repeat = 1;
uniform vec2 photo_pan = vec2(0.0);
uniform vec2 flat_angles = vec2(60.0, 34.0);
uniform mat3 content_rotation = mat3(1.0);
uniform float equirect_fov = 180.0;
uniform float eye_roll = 0.0;
uniform vec2 lens_k = vec2(0.0);
uniform vec4 crop = vec4(0.0);
uniform float cube_padding = 0.0;
uniform vec2 deband = vec2(0.0);
uniform bool dither = true;
uniform float frame_seed = 0.0;
instance uniform int layer_output = 0;
instance uniform int layer_eye = 0;
instance uniform vec4 layer_angles = vec4(0.0);

varying vec3 local_position;


vec2 equirect_uv(vec3 d)
{
	float u = 0.5 + atan(d.x, -d.z) / (2.0 * PI);
	float v = 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI;
	return vec2(u, v);
}

vec3 adjust_direction(vec3 d, float eye_sign)
{
	vec3 center = (projection == 1 || projection == 4 || projection == 5) ? normalize(zoom_forward) : vec3(0.0, 0.0, -1.0);
	float cosine = clamp(dot(d, center), -1.0, 1.0);
	vec3 tangent = d - center * cosine;
	float zoom = max(picture_zoom, 0.01);
	float denominator = max(zoom * zoom * (1.0 + cosine) + 1.0 - cosine, 0.00001);
	float zoomed_cosine = (zoom * zoom * (1.0 + cosine) - 1.0 + cosine) / denominator;
	d = center * zoomed_cosine + tangent * (2.0 * zoom / denominator);
	float yaw = radians(stereo_depth) * 0.5 * eye_sign;
	float pitch = radians(stereo_vertical) * 0.5 * eye_sign;
	float roll = radians(eye_roll) * 0.5 * eye_sign;
	d = vec3(d.x * cos(roll) - d.y * sin(roll), d.x * sin(roll) + d.y * cos(roll), d.z);
	d = vec3(d.x * cos(yaw) + d.z * sin(yaw), d.y, -d.x * sin(yaw) + d.z * cos(yaw));
	d = vec3(d.x, d.y * cos(pitch) - d.z * sin(pitch), d.y * sin(pitch) + d.z * cos(pitch));
	return content_rotation * d;
}

vec2 adjust_flat(vec2 uv, float eye_sign)
{
	uv = 0.5 + (uv - 0.5) / max(picture_zoom, 0.01);
	uv.x -= stereo_depth * 0.5 * eye_sign / max(flat_angles.x, 1.0);
	uv.y += stereo_vertical * 0.5 * eye_sign / max(flat_angles.y, 1.0);
	float roll = radians(eye_roll) * 0.5 * eye_sign;
	vec2 centered = (uv - 0.5) * flat_angles;
	centered = vec2(centered.x * cos(roll) + centered.y * sin(roll), -centered.x * sin(roll) + centered.y * cos(roll));
	return 0.5 + centered / max(flat_angles, vec2(1.0));
}

int cube_face(vec3 d)
{
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z)
		return d.x > 0.0 ? 0 : 1;
	if (a.y >= a.z)
		return d.y > 0.0 ? 2 : 3;
	return d.z < 0.0 ? 4 : 5;
}

vec2 cube_face_uv(vec3 d, int face, bool eac)
{
	vec3 n;
	vec3 u;
	vec3 v;
	vec2 cell;
	if (eac)
	{
		if (face == 0) { n = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, 1.0); v = vec3(0.0, -1.0, 0.0); cell = vec2(2.0, 0.0); }
		else if (face == 1) { n = vec3(-1.0, 0.0, 0.0); u = vec3(0.0, 0.0, -1.0); v = vec3(0.0, -1.0, 0.0); cell = vec2(0.0, 0.0); }
		else if (face == 2) { n = vec3(0.0, 1.0, 0.0); u = vec3(0.0, 0.0, -1.0); v = vec3(-1.0, 0.0, 0.0); cell = vec2(2.0, 1.0); }
		else if (face == 3) { n = vec3(0.0, -1.0, 0.0); u = vec3(0.0, 0.0, 1.0); v = vec3(-1.0, 0.0, 0.0); cell = vec2(0.0, 1.0); }
		else if (face == 4) { n = vec3(0.0, 0.0, -1.0); u = vec3(1.0, 0.0, 0.0); v = vec3(0.0, -1.0, 0.0); cell = vec2(1.0, 0.0); }
		else { n = vec3(0.0, 0.0, 1.0); u = vec3(0.0, 1.0, 0.0); v = vec3(-1.0, 0.0, 0.0); cell = vec2(1.0, 1.0); }
	}
	else
	{
		if (face == 0) { n = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, 1.0); v = vec3(0.0, -1.0, 0.0); cell = vec2(0.0, 0.0); }
		else if (face == 1) { n = vec3(-1.0, 0.0, 0.0); u = vec3(0.0, 0.0, -1.0); v = vec3(0.0, -1.0, 0.0); cell = vec2(1.0, 0.0); }
		else if (face == 2) { n = vec3(0.0, 1.0, 0.0); u = vec3(1.0, 0.0, 0.0); v = vec3(0.0, 0.0, 1.0); cell = vec2(2.0, 0.0); }
		else if (face == 3) { n = vec3(0.0, -1.0, 0.0); u = vec3(1.0, 0.0, 0.0); v = vec3(0.0, 0.0, -1.0); cell = vec2(0.0, 1.0); }
		else if (face == 4) { n = vec3(0.0, 0.0, -1.0); u = vec3(1.0, 0.0, 0.0); v = vec3(0.0, -1.0, 0.0); cell = vec2(1.0, 1.0); }
		else { n = vec3(0.0, 0.0, 1.0); u = vec3(-1.0, 0.0, 0.0); v = vec3(0.0, -1.0, 0.0); cell = vec2(2.0, 1.0); }
	}
	float depth = max(dot(d, n), 1e-5);
	vec2 st = vec2(dot(d, u), dot(d, v)) / depth;
	if (eac)
		st = atan(st) * (4.0 / PI);
	vec2 local = clamp(st * 0.5 + 0.5, 0.0, 1.0);
	local = cube_padding + local * (1.0 - 2.0 * cube_padding);
	return (cell + local) / vec2(3.0, 2.0);
}

float fisheye_radius(float theta)
{
	float half_fov = radians(fisheye_fov) * 0.5;
	float x = theta / max(half_fov, 0.0001);
	float x2 = x * x;
	float shaped = x * (1.0 + lens_k.x * x2 + lens_k.y * x2 * x2);
	return 0.5 * shaped / max(1.0 + lens_k.x + lens_k.y, 0.05);
}

vec2 project(vec3 d, vec2 mesh_uv)
{
	if (projection == 0)
		return mesh_uv;
	if (projection == 1)
		return equirect_uv(d);
	if (projection == 2)
	{
		vec2 e = equirect_uv(d);
		return vec2(0.5 + (e.x - 0.5) * 360.0 / max(equirect_fov, 1.0), e.y);
	}
	if (projection == 4 || projection == 5)
		return cube_face_uv(d, cube_face(d), projection == 4);
	float theta = acos(clamp(-d.z, -1.0, 1.0));
	float r = fisheye_radius(theta);
	float phi = atan(d.y, d.x);
	return vec2(0.5 + r * cos(phi), 0.5 - r * sin(phi));
}

float coverage(vec3 d, vec2 uv)
{
	if (projection == 0 && (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0))
		return 0.0;
	if (projection == 2 && (uv.x < 0.0 || uv.x > 1.0))
		return 0.0;
	if (projection == 3)
	{
		float theta = acos(clamp(-d.z, -1.0, 1.0));
		float half_fov = radians(fisheye_fov) * 0.5;
		float rim = 1.0 - theta / max(half_fov, 0.0001);
		return smoothstep(0.0, max(edge_fade, 0.0001), rim);
	}
	if (projection == 1 || projection >= 4 || edge_fade < 0.0001)
		return 1.0;
	float f = edge_fade;
	return smoothstep(0.0, f, uv.x) * smoothstep(0.0, f, uv.y)
		* smoothstep(0.0, f, 1.0 - uv.x) * smoothstep(0.0, f, 1.0 - uv.y);
}

float key_alpha(vec3 linear_color)
{
	if (!cut_enabled)
		return 1.0;
	float dist = distance(linear_color, cut_color);
	float a = smoothstep(cut_similarity, cut_similarity + max(cut_feather, 0.0001), dist);
	return cut_invert ? 1.0 - a : a;
}

vec3 soft_clip(vec3 c)
{
	const float knee = 0.8;
	float peak = max(max(c.r, c.g), c.b);
	if (peak <= knee)
		return c;
	float compressed = knee + (1.0 - knee) * (1.0 - exp(-(peak - knee) / (1.0 - knee)));
	return c * (compressed / peak);
}

vec3 grade(vec3 linear_color)
{
	float luma = dot(linear_color, vec3(0.2126, 0.7152, 0.0722));
	vec3 c = mix(vec3(luma), linear_color, saturation);
	c = pow(max(c, vec3(0.0)), vec3(1.0 / max(gamma, 0.01))) * menu_dim * brightness;
	if (brightness > 1.0 || saturation > 1.0)
		c = soft_clip(c);
	return c;
}

vec2 eye_uv(vec2 uv, bool right_view)
{
	vec2 texel = 0.5 / (picture_source == 0 ? vec2(textureSize(plane_y, 0)) : picture_size);
	bool right = (right_view && !single_eye) != swap_eyes;
	uv = crop.xy + uv * (1.0 - crop.xy - crop.zw);
	if (stereo_layout == 1)
	{
		float x = uv.x * 0.5 + (right ? 0.5 : 0.0);
		x = right ? max(x, 0.5 + texel.x) : min(x, 0.5 - texel.x);
		return vec2(clamp(x, texel.x, 1.0 - texel.x), clamp(uv.y, texel.y, 1.0 - texel.y));
	}
	if (stereo_layout == 2)
	{
		float y = uv.y * 0.5 + (right ? 0.5 : 0.0);
		y = right ? max(y, 0.5 + texel.y) : min(y, 0.5 - texel.y);
		return vec2(clamp(uv.x, texel.x, 1.0 - texel.x), clamp(y, texel.y, 1.0 - texel.y));
	}
	return clamp(uv, texel, 1.0 - texel);
}

vec2 packed_alpha_uv(vec2 uv)
{
	vec2 texel = 1.0 / vec2(textureSize(plane_y, 0));
	float x = fract(0.4 * uv.x + 0.7);
	float y = fract(0.4 * uv.y + 0.8);
	if (uv.x < 0.5)
		x = clamp(0.4 * uv.x + 0.4, 0.4 + texel.x, 0.6 - texel.x);
	else if (x < 0.5)
		x = clamp(x, texel.x, 0.1 - texel.x);
	else
		x = clamp(x, 0.9 + texel.x, 1.0 - texel.x);
	if (y < 0.5)
		y = clamp(y, texel.y, 0.2 - texel.y);
	else
		y = clamp(y, 0.8 + texel.y, 1.0 - texel.y);
	return vec2(x, y);
}

float mask_luma(vec2 uv, vec2 dx, vec2 dy)
{
	float y = textureGrad(plane_y, uv, dx, dy).r * sample_scale;
	return full_range ? y : (y - 16.0 / 255.0) * (255.0 / 219.0);
}

float mask_alpha(vec2 uv, vec2 source_uv, vec2 scale)
{
	vec2 dx = dFdx(source_uv) * scale;
	vec2 dy = dFdy(source_uv) * scale;
	vec3 rgb = yuv_to_rgb_gamma(sample_yuva_grad(uv, dx, dy).xyz);
	float luma = mask_luma(uv, dx, dy);
	if (mask_trim > 0.01)
	{
		vec2 step_uv = mask_trim / vec2(textureSize(plane_y, 0));
		luma = min(luma, min(
			min(mask_luma(uv + vec2(step_uv.x, 0.0), dx, dy), mask_luma(uv - vec2(step_uv.x, 0.0), dx, dy)),
			min(mask_luma(uv + vec2(0.0, step_uv.y), dx, dy), mask_luma(uv - vec2(0.0, step_uv.y), dx, dy))));
	}
	float value = min(rgb.r, luma / 0.16);
	float soft = background_mode == 0 ? 0.05 : 0.35;
	return smoothstep(mask_threshold - soft, mask_threshold + soft, value);
}

float hash12(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec4 deband_yuva(vec4 center, vec2 uv, vec2 gx, vec2 gy)
{
	vec2 texel = 1.0 / vec2(textureSize(plane_y, 0));
	float angle = hash12(uv * 4096.0 + frame_seed) * 6.2831853;
	float distance = deband.y * (0.5 + 0.5 * hash12(uv * 2048.0 + frame_seed + 17.0));
	vec2 offset = vec2(cos(angle), sin(angle)) * distance * texel;
	vec2 side = vec2(-offset.y, offset.x);
	vec4 a = sample_yuva_grad(uv + offset, gx, gy);
	vec4 b = sample_yuva_grad(uv - offset, gx, gy);
	vec4 c = sample_yuva_grad(uv + side, gx, gy);
	vec4 e = sample_yuva_grad(uv - side, gx, gy);
	vec4 average = (a + b + c + e) * 0.25;
	vec3 spread = max(max(abs(a.xyz - center.xyz), abs(b.xyz - center.xyz)), max(abs(c.xyz - center.xyz), abs(e.xyz - center.xyz)));
	vec3 keep = step(vec3(deband.x), spread);
	return vec4(mix(average.xyz, center.xyz, keep), center.w);
}

vec3 dither_linear(vec3 c, vec2 coord)
{
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	vec3 encoded = mix(lo, hi, step(0.0031308, c));
	float noise = hash12(coord + frame_seed) + hash12(coord.yx + frame_seed * 1.37 + 5.3) - 1.0;
	encoded = clamp(encoded + noise / 255.0, 0.0, 1.0);
	return srgb_to_linear(encoded);
}

vec3 cube_direction(vec3 d)
{
	return vec3(d.x, d.y, -d.z);
}

vec3 tile_coord(vec2 uv)
{
	float x = uv.x * tile_geometry.x;
	float tile = clamp(floor(x / tile_geometry.y), 0.0, float(tile_count - 1));
	return vec3((x - tile * tile_geometry.y + tile_geometry.z) / tile_geometry.w, uv.y, tile);
}

vec3 sample_tiles(vec3 coord, vec2 gx, vec2 gy)
{
	return vec3(textureGrad(tile_y, coord, gx, gy).r, textureGrad(tile_cb, coord, gx, gy).r, textureGrad(tile_cr, coord, gx, gy).r);
}

vec3 sample_cube(vec3 q, vec3 qx, vec3 qy)
{
	return vec3(textureGrad(cube_y, q, qx, qy).r, textureGrad(cube_cb, q, qx, qy).r, textureGrad(cube_cr, q, qx, qy).r);
}

vec2 wrap_uv(vec2 uv)
{
	if (projection == 0 && flat_repeat > 1)
		return fract(uv);
	return projection == 1 ? vec2(fract(uv.x), uv.y) : uv;
}

vec3 sample_picture(vec3 q, vec3 qx, vec3 qy, vec2 uv, vec2 gx, vec2 gy)
{
	const vec2 SUBSAMPLES[4] = vec2[](vec2(0.125, 0.375), vec2(-0.375, 0.125), vec2(0.375, -0.125), vec2(-0.125, -0.375));
	vec3 planes = vec3(0.0);
	float blur;
	vec2 scale = vec2(tile_geometry.x / tile_geometry.w, 1.0);
	if (picture_source == 2)
	{
		if (picture_supersample)
		{
			for (int i = 0; i < 4; i++)
				planes += sample_cube(q + qx * SUBSAMPLES[i].x + qy * SUBSAMPLES[i].y, qx * 0.5, qy * 0.5);
			planes *= 0.25;
		}
		else
			planes = sample_cube(q, qx, qy);
		blur = sharpness > 0.001 ? textureGrad(cube_y, q, qx * 2.0, qy * 2.0).r : planes.x;
	}
	else
	{
		if (picture_supersample)
		{
			for (int i = 0; i < 4; i++)
				planes += sample_tiles(tile_coord(wrap_uv(uv + gx * SUBSAMPLES[i].x + gy * SUBSAMPLES[i].y)), gx * scale * 0.5, gy * scale * 0.5);
			planes *= 0.25;
		}
		else
			planes = sample_tiles(tile_coord(uv), gx * scale, gy * scale);
		blur = sharpness > 0.001 ? textureGrad(tile_y, tile_coord(uv), gx * scale * 2.0, gy * scale * 2.0).r : planes.x;
	}
	if (rgb_planes)
		return planes;
	planes.x += (planes.x - blur) * sharpness;
	return yuv_to_rgb_gamma(planes);
}

void vertex()
{
	if (layer_output == 0 && projection == 0 && flat_curve > 0.0001)
	{
		float radius = 1.0 / flat_curve;
		float theta = VERTEX.x * flat_curve;
		VERTEX.x = radius * sin(theta);
		VERTEX.z += radius * (1.0 - cos(theta));
	}
	local_position = VERTEX;
	if (layer_output == 0 && projection != 0)
		VERTEX += (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX[3]).xyz;
}

void fragment()
{
	bool right_view = layer_eye == 0 ? VIEW_INDEX == VIEW_RIGHT : layer_eye == 2;
	float eye_sign = right_view ? 1.0 : -1.0;
	vec3 direction = normalize(local_position);
	if (layer_output == 2)
	{
		float lon = (UV.x - 0.5) * layer_angles.x;
		float lat = mix(layer_angles.y, -layer_angles.z, UV.y);
		direction = vec3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat));
	}
	if (projection != 0)
		direction = adjust_direction(direction, eye_sign);
	vec2 flat_uv = (UV - 0.5) * float(flat_repeat) + 0.5;
	vec2 uv = projection == 0 ? adjust_flat(flat_uv, eye_sign) + photo_pan : project(direction, UV);
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	if (projection == 0 && flat_repeat > 1)
		uv = fract(uv);
	float cover = coverage(direction, uv);
	vec3 color = vec3(0.0);
	vec3 raw = vec3(0.0);
	float video_alpha = 1.0;
	if (projection == 1)
	{
		gx.x -= round(gx.x);
		gy.x -= round(gy.x);
	}
	if (projection == 4 || projection == 5)
	{
		int face = cube_face(direction);
		gx = cube_face_uv(direction + dFdx(direction), face, projection == 4) - uv;
		gy = cube_face_uv(direction + dFdy(direction), face, projection == 4) - uv;
	}
	vec2 pack = stereo_layout == 1 ? vec2(0.5, 1.0) : (stereo_layout == 2 ? vec2(1.0, 0.5) : vec2(1.0));
	pack *= 1.0 - crop.xy - crop.zw;
	vec3 q = cube_direction(direction);
	vec3 qx = dFdx(q);
	vec3 qy = dFdy(q);
	if (cover > 0.0001 && picture_source != 0)
	{
		raw = video_to_linear(sample_picture(q, qx, qy, eye_uv(uv, right_view), gx * pack, gy * pack));
		color = grade(raw);
	}
	else if (cover > 0.0001)
	{
		vec2 packed_uv = eye_uv(uv, right_view);
		float mask = 1.0;
		if (alpha_mask == 1)
			mask = mask_alpha(packed_alpha_uv(packed_uv), packed_uv, vec2(0.4));
		else if (alpha_mask == 2)
		{
			mask = mask_alpha(vec2(packed_uv.x, 0.5 + packed_uv.y * 0.5), packed_uv, vec2(1.0, 0.5));
			packed_uv.y *= 0.5;
		}
		bool explicit_grad = projection >= 4 || deband.x > 0.0;
		vec2 grad_x = gx * pack;
		vec2 grad_y = gy * pack;
		vec4 yuva = explicit_grad ? sample_yuva_grad(packed_uv, grad_x, grad_y) : sample_yuva(packed_uv);
		if (!packed_rgb && deband.x > 0.0)
			yuva = deband_yuva(yuva, packed_uv, grad_x, grad_y);
		if (!packed_rgb && sharpness > 0.001)
		{
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
			float blur = texture(plane_y, packed_uv, 1.0).r * sample_scale;
#else
			float lod = textureQueryLod(plane_y, packed_uv).y;
			float blur = textureLod(plane_y, packed_uv, max(lod, 0.0) + 1.0).r * sample_scale;
#endif
			yuva.x += (yuva.x - blur) * sharpness;
		}
		raw = video_to_linear(packed_rgb ? yuva.xyz : yuv_to_rgb_gamma(yuva.xyz));
		video_alpha = yuva.w * mask;
		color = grade(raw);
		if (alpha_mask != 0 && background_mode != 0)
			color *= pow(mask, mask_darken);
	}
	if (dither)
		color = dither_linear(color, FRAGCOORD.xy);
	float alpha = cover * video_alpha * key_alpha(raw);
	if (background_mode == 1)
	{
		ALBEDO = color;
		ALPHA = alpha;
	}
	else if (background_mode == 0)
	{
		ALBEDO = mix(cut_color, color, alpha);
		ALPHA = 1.0;
	}
	else
	{
		ALBEDO = color * alpha;
		ALPHA = 1.0;
	}
}
