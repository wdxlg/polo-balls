shader_type canvas_item;
render_mode blend_mix, unshaded;

// 0 = 保持原图；1 = 火焰渐变已经从中心推进到整个标记。
uniform float overload_progress : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec4 flame_inner : source_color = vec4(1.0, 0.97, 0.62, 1.0);
uniform vec4 flame_mid : source_color = vec4(1.0, 0.48, 0.035, 1.0);
uniform vec4 flame_outer : source_color = vec4(0.92, 0.055, 0.012, 1.0);
uniform float flame_mix_strength : hint_range(0.0, 1.0, 0.01) = 0.94;
uniform float brightness_gain : hint_range(0.0, 1.5, 0.01) = 0.62;
uniform float reveal_softness : hint_range(0.02, 0.35, 0.01) = 0.13;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float p = clamp(overload_progress, 0.0, 1.0);

	// 用真实纹理像素尺寸修正长宽比，让“由内向外”是圆形推进，而不是 UV 椭圆。
	vec2 texture_size = vec2(1.0) / max(TEXTURE_PIXEL_SIZE, vec2(0.000001));
	vec2 from_center_px = (UV - vec2(0.5)) * texture_size;
	float max_radius_px = max(length(texture_size * 0.5), 0.0001);
	float radial = clamp(length(from_center_px) / max_radius_px, 0.0, 1.0);

	// 火焰内部到外部：亮黄/近白 -> 橙 -> 红。
	vec3 flame = mix(flame_inner.rgb, flame_mid.rgb, smoothstep(0.12, 0.58, radial));
	flame = mix(flame, flame_outer.rgb, smoothstep(0.50, 1.0, radial));

	// 颜色前沿从中心向外扩散；乘 p 保证第一帧完全不跳色。
	float reveal_radius = mix(0.0, 1.12, p);
	float reveal = 1.0 - smoothstep(
		max(reveal_radius - reveal_softness, 0.0),
		reveal_radius + reveal_softness,
		radial
	);
	reveal *= smoothstep(0.0, 0.08, p);

	float color_amount = reveal * flame_mix_strength;
	vec3 result_rgb = mix(base.rgb, flame, color_amount);

	// 核心亮度也随过载进度上升，外层真实轮廓光晕由脚本同步增强。
	float core_light = reveal * p * brightness_gain;
	result_rgb += flame * core_light;

	COLOR = vec4(result_rgb, base.a);
}
