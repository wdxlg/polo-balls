shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float glow_strength : hint_range(0.0, 4.0) = 1.55;
uniform float glow_radius_px : hint_range(0.0, 16.0) = 6.0;
uniform float pulse_speed : hint_range(0.0, 12.0) = 3.2;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.22;
uniform float opacity : hint_range(0.0, 1.0) = 0.40;
uniform float visual_fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 base = COLOR;
	vec2 px = TEXTURE_PIXEL_SIZE * glow_radius_px;
	float halo = 0.0;
	halo = max(halo, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	halo = max(halo, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	halo = max(halo, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	halo = max(halo, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	halo = max(halo, texture(TEXTURE, UV + px * 0.72).a);
	halo = max(halo, texture(TEXTURE, UV - px * 0.72).a);
	halo = max(halo, texture(TEXTURE, UV + vec2(px.x, -px.y) * 0.72).a);
	halo = max(halo, texture(TEXTURE, UV + vec2(-px.x, px.y) * 0.72).a);

	// V57：外圈必须和原始纹理 alpha 比较，不能和正在淡出的 base.a 比较。
	// 否则 CanvasItem alpha 越低，outer = halo - base.a 反而会越大，造成消失前突然变亮。
	float raw_alpha = texture(TEXTURE, UV).a;
	float outer = max(halo - raw_alpha, 0.0);
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	float boost = 1.10 + pulse * pulse_amount;
	vec3 hot = base.rgb * boost;
	vec3 fire_glow = vec3(1.0, 0.20, 0.015) * outer * glow_strength;
	float a = clamp(opacity, 0.0, 1.0);
	float fade = clamp(visual_fade, 0.0, 1.0);
	// additive 材质必须同时压低 RGB 与 Alpha，才能得到真正的渐隐。
	COLOR = vec4((hot + fire_glow) * a * fade, max(raw_alpha, outer * 0.78) * a * fade);
}
