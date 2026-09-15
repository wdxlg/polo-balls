shader_type canvas_item;
render_mode unshaded;

// V400：保留明显桶形扭曲、RGB 色差、扫描线、颗粒、亮度漂移、横向同步抖动、偶发撕裂与轻微重影。
// 明确移除“从上到下滚动的扫光/亮带”；斜向持续移动纹理仍维持极低强度。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float effect_strength : hint_range(0.0, 1.0) = 0.94;
uniform float curvature : hint_range(0.0, 0.20) = 0.108;
uniform float wave_distortion : hint_range(0.0, 0.02) = 0.0048;
uniform float chromatic_aberration : hint_range(0.0, 6.0) = 1.80;
uniform float scanline_strength : hint_range(0.0, 0.50) = 0.155;
uniform float noise_strength : hint_range(0.0, 0.20) = 0.028;
uniform float black_static_strength : hint_range(0.0, 0.12) = 0.016;
uniform float horizontal_jitter : hint_range(0.0, 0.02) = 0.0032;
uniform float tear_strength : hint_range(0.0, 0.04) = 0.0135;
uniform float ghost_strength : hint_range(0.0, 0.25) = 0.065;
uniform float flicker_strength : hint_range(0.0, 0.12) = 0.026;
// 用户指定要减少的“斜着一直动的纹理花屏”只由这个参数控制；其余 CRT 效果不再跟着一起削弱。
uniform float diagonal_interference_strength : hint_range(0.0, 0.08) = 0.0045;
uniform float screen_shake_pixels : hint_range(0.0, 4.0) = 1.10;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.66;
uniform float vignette_progress : hint_range(0.0, 1.0) = 0.0;

float rand2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	// V401：最终后处理层做约 1px 的持续微颤。因为它读取的是最终 BackBuffer，
	// 地图、人物、烟雾、UI/文字会作为一张完整画面一起颤抖，而不是只抖 Camera2D 世界层。
	vec2 shake_wave = vec2(
		sin(TIME * 18.7) + sin(TIME * 31.3 + 1.2) * 0.42,
		sin(TIME * 22.1 + 2.0) + sin(TIME * 37.9) * 0.34
	);
	vec2 source_uv = SCREEN_UV + shake_wave * SCREEN_PIXEL_SIZE * screen_shake_pixels * 0.62 * effect_strength;
	vec2 centered = source_uv * 2.0 - 1.0;

	// 老电视玻璃桶形弯曲：恢复到接近早期版本的明显程度。
	float radius2 = dot(centered, centered);
	centered *= 1.0 + curvature * radius2 * effect_strength;

	// 模拟水平同步/行场不稳。幅度明显，但不是覆盖画面的纹理花屏。
	float edge_weight = 0.40 + 0.60 * clamp(abs(centered.y), 0.0, 1.0);
	centered.x += sin(centered.y * 11.5 + TIME * 2.15) * wave_distortion * edge_weight * effect_strength;
	centered.y += sin(centered.x * 6.2 - TIME * 0.82) * wave_distortion * 0.22 * effect_strength;

	vec2 uv = centered * 0.5 + 0.5;
	float band = floor(uv.y * 190.0);
	float time_step = floor(TIME * 19.0);
	float band_noise = rand2(vec2(band, time_step));
	uv.x += (band_noise - 0.5) * horizontal_jitter * effect_strength;

	// 偶发横向撕裂恢复，但频率低于 V395，避免长期把背景切碎。
	float tear_gate = step(0.976, band_noise);
	uv.x += tear_gate * sin(TIME * 71.0 + band * 1.83) * tear_strength * effect_strength;

	bool outside_screen = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
	vec3 color = vec3(0.0);
	if (!outside_screen) {
		vec2 chroma_px = vec2(SCREEN_PIXEL_SIZE.x * chromatic_aberration * effect_strength, 0.0);
		vec2 uv_r = clamp(uv + chroma_px, vec2(0.0), vec2(1.0));
		vec2 uv_b = clamp(uv - chroma_px, vec2(0.0), vec2(1.0));
		float red = texture(screen_texture, uv_r).r;
		float green = texture(screen_texture, uv).g;
		float blue = texture(screen_texture, uv_b).b;
		color = vec3(red, green, blue);

		// 极轻的横向重影，让失真层次回来，但不会像模糊滤镜一样糊掉地图。
		vec2 ghost_uv = clamp(uv + vec2(SCREEN_PIXEL_SIZE.x * 3.5, 0.0), vec2(0.0), vec2(1.0));
		vec3 ghost = texture(screen_texture, ghost_uv).rgb;
		color = mix(color, ghost, ghost_strength * effect_strength);

		// CRT 扫描线。
		float pixel_y = uv.y / max(SCREEN_PIXEL_SIZE.y, 0.000001);
		float scan = 0.5 + 0.5 * sin(pixel_y * 3.14159265);
		color *= 1.0 - scanline_strength * scan * effect_strength;

		// 动态颗粒恢复到中等强度。
		vec2 safe_pixel_size = max(SCREEN_PIXEL_SIZE, vec2(0.000001));
		vec2 pixel = floor(uv / safe_pixel_size);
		float grain = rand2(pixel + vec2(floor(TIME * 47.0), floor(TIME * 31.0))) - 0.5;
		color += grain * noise_strength * effect_strength;

		// V400：不再生成从上到下滚动的亮带；只保留很轻的全局亮度漂移。
		float flicker = sin(TIME * 8.1) * 0.55 + sin(TIME * 13.7 + 1.7) * 0.45;
		color *= 1.0 + flicker * flicker_strength * effect_strength;

		// 只把用户指出的“斜向持续移动纹理”压到极低；它现在只是很淡的底层干扰。
		float diagonal = sin((uv.x * 1.65 + uv.y) * 78.0 - TIME * 1.25);
		color += vec3(diagonal * diagonal_interference_strength * effect_strength);

		// 黑屏阶段也能看到 CRT 的扫描/静电，而不是等黑屏结束才突然出现。
		float static_luma = (grain + 0.5) * black_static_strength * effect_strength;
		float scan_luma = (1.0 - scan) * black_static_strength * 0.28 * effect_strength;
		color += vec3(static_luma + scan_luma);
	}

	// 黑屏结束后 vignette_progress 才从 0 -> 1，继续按既有时序向中心扩大。
	vec2 vp = source_uv * 2.0 - 1.0;
	float dist = length(vp);
	float inner_radius = mix(1.03, 0.42, vignette_progress);
	float outer_radius = mix(1.42, 1.00, vignette_progress);
	float vignette = smoothstep(inner_radius, outer_radius, dist);
	color *= 1.0 - vignette * vignette_strength;

	COLOR = vec4(max(color, vec3(0.0)), 1.0);
}
