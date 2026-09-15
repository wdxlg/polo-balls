shader_type canvas_item;
render_mode unshaded;

uniform float crack_progress : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
	return length(pa - ba * h);
}

float crack_distance(vec2 uv) {
	float d = 10.0;
	// 主干
	d = min(d, segment_distance(uv, vec2(0.45,0.03), vec2(0.42,0.20)));
	d = min(d, segment_distance(uv, vec2(0.42,0.20), vec2(0.50,0.32)));
	d = min(d, segment_distance(uv, vec2(0.50,0.32), vec2(0.47,0.47)));
	d = min(d, segment_distance(uv, vec2(0.47,0.47), vec2(0.55,0.60)));
	d = min(d, segment_distance(uv, vec2(0.55,0.60), vec2(0.52,0.76)));
	d = min(d, segment_distance(uv, vec2(0.52,0.76), vec2(0.60,0.96)));
	// 左上分叉
	d = min(d, segment_distance(uv, vec2(0.42,0.20), vec2(0.35,0.15)));
	d = min(d, segment_distance(uv, vec2(0.35,0.15), vec2(0.27,0.06)));
	d = min(d, segment_distance(uv, vec2(0.50,0.32), vec2(0.37,0.26)));
	d = min(d, segment_distance(uv, vec2(0.37,0.26), vec2(0.24,0.30)));
	d = min(d, segment_distance(uv, vec2(0.24,0.30), vec2(0.12,0.23)));
	// 右侧分叉
	d = min(d, segment_distance(uv, vec2(0.47,0.47), vec2(0.63,0.41)));
	d = min(d, segment_distance(uv, vec2(0.63,0.41), vec2(0.76,0.49)));
	d = min(d, segment_distance(uv, vec2(0.76,0.49), vec2(0.91,0.46)));
	d = min(d, segment_distance(uv, vec2(0.55,0.60), vec2(0.69,0.68)));
	d = min(d, segment_distance(uv, vec2(0.69,0.68), vec2(0.84,0.79)));
	// 左下分叉
	d = min(d, segment_distance(uv, vec2(0.52,0.76), vec2(0.39,0.83)));
	d = min(d, segment_distance(uv, vec2(0.39,0.83), vec2(0.27,0.95)));
	return d;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float width = mix(0.018, 0.032, clamp(crack_progress, 0.0, 1.0));
	float source_mask = step(0.080001, source.a);
	float progress_mask = step(0.000001, crack_progress);
	float crack_mask = 1.0 - step(width, crack_distance(UV));

	// 每个贴图像素独立随机灰白～白色。这里不使用 processor return，
	// 而是把所有可见条件乘进 alpha，兼容 Godot 4.7 的 fragment() 处理器。
	vec2 safe_pixel_size = max(TEXTURE_PIXEL_SIZE, vec2(0.000001));
	vec2 pixel_coord = floor(UV / safe_pixel_size);
	float step_count = 6.0;
	float shade_step = floor(hash21(pixel_coord) * step_count);
	float shade = mix(0.80, 1.0, shade_step / (step_count - 1.0));
	float alpha = 0.98 * source.a * source_mask * progress_mask * crack_mask;
	COLOR = vec4(vec3(shade), alpha);
}
