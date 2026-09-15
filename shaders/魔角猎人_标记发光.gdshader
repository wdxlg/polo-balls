shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 glow_color : source_color = vec4(0.7, 0.2, 1.0, 0.85);
uniform float outline_size : hint_range(1.0, 5.0, 0.25) = 3.0;
uniform float glow_strength : hint_range(0.0, 1.5, 0.01) = 0.55;
uniform float alpha_threshold : hint_range(0.0, 0.25, 0.005) = 0.035;

const int MAX_RADIUS = 5;

void fragment() {
	float base_alpha = texture(TEXTURE, UV).a;
	float expanded_alpha = 0.0;

	// TEXTURE / UV / TEXTURE_PIXEL_SIZE 都是 fragment built-ins。
	// 必须在 fragment() 内读取，不能在无参数的自定义函数里直接访问 TEXTURE。
	for (int y = -MAX_RADIUS; y <= MAX_RADIUS; y++) {
		for (int x = -MAX_RADIUS; x <= MAX_RADIUS; x++) {
			vec2 pixel_offset = vec2(float(x), float(y));
			float distance_px = length(pixel_offset);
			float in_ring = step(0.5, distance_px) * (1.0 - step(outline_size + 0.001, distance_px));
			float edge_falloff = 1.0 - smoothstep(max(outline_size - 1.25, 0.0), outline_size + 0.001, distance_px);

			vec2 sample_uv = UV + pixel_offset * TEXTURE_PIXEL_SIZE;
			float inside = step(0.0, sample_uv.x) * step(0.0, sample_uv.y) * step(sample_uv.x, 1.0) * step(sample_uv.y, 1.0);
			float sampled_alpha = texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0))).a * inside;
			expanded_alpha = max(expanded_alpha, sampled_alpha * in_ring * mix(1.0, edge_falloff, 0.32));
		}
	}

	float outline_alpha = max(expanded_alpha - base_alpha, 0.0);
	outline_alpha = smoothstep(alpha_threshold, 1.0, outline_alpha);
	COLOR = vec4(glow_color.rgb, outline_alpha * glow_color.a * glow_strength);
}
