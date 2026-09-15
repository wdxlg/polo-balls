shader_type canvas_item;
render_mode unshaded;

// 局部录像带倒放效果：只处理挂载这个 Material 的 Sprite/CanvasItem。
// 不读取 SCREEN_TEXTURE，因此不会再影响整个屏幕或其他角色。
uniform float distortion_strength : hint_range(0.0, 2.0) = 1.0;
uniform float jitter_strength : hint_range(0.0, 0.08) = 0.018;
uniform float tear_strength : hint_range(0.0, 0.12) = 0.040;
uniform float scanline_strength : hint_range(0.0, 0.45) = 0.16;
uniform float noise_strength : hint_range(0.0, 0.25) = 0.065;
uniform float chroma_pixels : hint_range(0.0, 8.0) = 1.4;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// 以贴图自身的行做 VHS 横向抖动和波纹，不再使用屏幕坐标。
	float row = floor(uv.y * 96.0);
	float row_noise = hash12(vec2(row, floor(t * 24.0))) - 0.5;
	float fine_wave = sin(uv.y * 74.0 + t * 18.0)
		+ 0.45 * sin(uv.y * 181.0 - t * 11.0);
	uv.x += distortion_strength * (
		row_noise * jitter_strength
		+ fine_wave * TEXTURE_PIXEL_SIZE.x * 1.8
	);

	// 一条滚动的局部磁带撕裂带。
	float tear_center = fract(t * 0.23);
	float tear_distance = abs(uv.y - tear_center);
	tear_distance = min(tear_distance, 1.0 - tear_distance);
	float tear_band = 1.0 - smoothstep(0.012, 0.075, tear_distance);
	uv.x += tear_band * tear_strength * distortion_strength
		* sin(t * 8.0 + uv.y * 35.0);

	uv = clamp(uv, vec2(0.001), vec2(0.999));

	float chroma = chroma_pixels * TEXTURE_PIXEL_SIZE.x * distortion_strength;
	vec4 center = texture(TEXTURE, uv);
	float r = texture(TEXTURE, clamp(uv + vec2(chroma, 0.0), vec2(0.001), vec2(0.999))).r;
	float g = center.g;
	float b = texture(TEXTURE, clamp(uv - vec2(chroma, 0.0), vec2(0.001), vec2(0.999))).b;
	float gray = dot(vec3(r, g, b), vec3(0.299, 0.587, 0.114));

	float scan = 1.0 - scanline_strength * (0.5 + 0.5 * sin(uv.y * 520.0));
	float grain = (hash12(vec2(floor(uv.x * 160.0), row + floor(t * 60.0) * 13.0)) - 0.5)
		* noise_strength;
	gray = clamp(gray * scan + grain + tear_band * 0.055, 0.0, 1.0);

	// 保留原贴图透明度；效果只存在于人物/子弹自身的可见像素里。
	COLOR = vec4(vec3(gray), center.a);
}
