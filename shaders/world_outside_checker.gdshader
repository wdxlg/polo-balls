shader_type canvas_item;
render_mode unshaded;

uniform vec4 normal_color : source_color = vec4(0.0, 0.5882353, 0.87058824, 1.0);
uniform vec4 dark_color : source_color = vec4(0.0, 0.27, 0.48, 0.18);
uniform vec4 accent_color : source_color = vec4(1.0, 1.0, 1.0, 0.12);
uniform sampler2D background_texture : source_color, repeat_enable, filter_nearest;
uniform float cell_size_px = 64.0;
uniform float parallax_scale = 0.32;
uniform vec2 camera_position = vec2(0.0);
uniform vec2 camera_zoom = vec2(1.0);
uniform vec2 viewport_size = vec2(1152.0, 648.0);
// 0：旧棋盘；1-4：程序图案保留备用；5：原版方块贴图复制。
uniform int pattern_style = 0;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 safe_zoom = max(abs(camera_zoom), vec2(0.001));
	// SCREEN_UV 保持格子尺寸在不同地图缩放下稳定；
	// 相机世界位移按 zoom 转成屏幕像素后只取一部分，形成远景视差。
	vec2 camera_phase_px = camera_position * safe_zoom * parallax_scale;
	vec2 pixel_pos = SCREEN_UV * viewport_size + camera_phase_px;
	float safe_cell = max(cell_size_px, 1.0);
	vec2 checker_cell = floor(pixel_pos / safe_cell);
	float checker = mod(checker_cell.x + checker_cell.y, 2.0);
	vec4 color = mix(normal_color, dark_color, checker);

	if (pattern_style == 5) {
		// 原版 16×16 方块顶面纹理：用同样视差世界像素做重复 UV，保持最近邻像素风。
		vec2 texture_uv = pixel_pos / safe_cell;
		color = texture(background_texture, texture_uv);
	} else if (pattern_style == 1) {
		// 大块随机斑块可以是云，也可以是洞穴阴影；不是硬性棋盘。
		vec2 cloud_cell = floor(pixel_pos / (safe_cell * 2.0));
		float cloud = hash12(cloud_cell);
		float patch = smoothstep(0.56, 0.86, cloud);
		color = mix(normal_color, dark_color, patch * 0.78);
		float fleck = step(0.966, hash12(floor(pixel_pos / (safe_cell * 0.5)) + 7.31));
		color = mix(color, accent_color, fleck * 0.30);
	} else if (pattern_style == 2) {
		// 沙丘大波纹：每几行换一个相位，不形成完全重复的格子。
		float row = floor(pixel_pos.y / (safe_cell * 1.7));
		float phase = hash12(vec2(row, 19.73)) * 6.2831853;
		float wave = 0.5 + 0.5 * sin(pixel_pos.x / (safe_cell * 2.4) + pixel_pos.y / (safe_cell * 0.72) + phase);
		color = mix(normal_color, dark_color, smoothstep(0.34, 0.82, wave));
		float crest = smoothstep(0.91, 0.985, wave);
		color = mix(color, accent_color, crest * 0.44);
	} else if (pattern_style == 3) {
		// 下界暗红地层 + 稀疏岩浆块。
		vec2 lava_cell = floor(pixel_pos / (safe_cell * 0.75));
		float lava = hash12(lava_cell);
		float strata = 0.5 + 0.5 * sin(pixel_pos.y / (safe_cell * 0.42) + hash12(vec2(floor(pixel_pos.y / safe_cell), 3.7)) * 5.0);
		color = mix(normal_color, dark_color, smoothstep(0.22, 0.78, strata));
		color = mix(color, accent_color, step(0.84, lava) * 0.46);
	} else if (pattern_style == 4) {
		// 末地深空：大面积渐变，少量星点不做规则平铺。
		float nebula = hash12(floor(pixel_pos / (safe_cell * 2.0)));
		color = mix(normal_color, dark_color, smoothstep(0.38, 0.88, nebula));
		vec2 star_cell = floor(pixel_pos / safe_cell);
		float star_seed = hash12(star_cell + 41.7);
		vec2 local = mod(pixel_pos, safe_cell) / safe_cell;
		vec2 center = vec2(hash12(star_cell + 3.1), hash12(star_cell + 5.2));
		float star = step(0.925, star_seed) * smoothstep(0.055, 0.012, distance(local, center));
		color = mix(color, accent_color, star * 0.72);
	}

	COLOR = color;
}
