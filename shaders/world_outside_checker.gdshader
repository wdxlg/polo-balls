shader_type canvas_item;
render_mode unshaded;

uniform vec4 normal_color : source_color = vec4(0.0, 0.5882353, 0.87058824, 1.0);
uniform vec4 dark_color : source_color = vec4(0.0, 0.27, 0.48, 0.18);
uniform float cell_size_px = 64.0;
uniform float parallax_scale = 0.32;
uniform vec2 camera_position = vec2(0.0);
uniform vec2 camera_zoom = vec2(1.0);
uniform vec2 viewport_size = vec2(1152.0, 648.0);

void fragment() {
	vec2 safe_zoom = max(abs(camera_zoom), vec2(0.001));
	// SCREEN_UV 保持格子尺寸在不同地图缩放下稳定；
	// 相机世界位移按 zoom 转成屏幕像素后只取一部分，形成远景视差。
	vec2 camera_phase_px = camera_position * safe_zoom * parallax_scale;
	vec2 pixel_pos = SCREEN_UV * viewport_size + camera_phase_px;
	float safe_cell = max(cell_size_px, 1.0);
	vec2 cell = floor(pixel_pos / safe_cell);
	float checker = mod(cell.x + cell.y, 2.0);
	COLOR = mix(normal_color, dark_color, checker);
}
