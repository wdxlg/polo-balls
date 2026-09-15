shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float arc_bulge : hint_range(0.0, 0.9) = 0.72;
uniform float arc_width : hint_range(0.04, 0.35) = 0.18;
uniform float wiggle_strength : hint_range(0.0, 0.12) = 0.028;
uniform float wiggle_speed : hint_range(0.0, 20.0) = 8.0;
uniform float flame_pulse : hint_range(0.0, 1.0) = 0.22;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.25;
uniform float opacity : hint_range(0.0, 1.0) = 0.52;

varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	// 本节点的本地 +X 永远朝着目标。这里把火焰塑形成“)”式圆弧：
	// 弧线中部向 +X（敌人方向）鼓出，而不是把原竖直 PNG 直接朝敌人平移。
	vec2 p = UV * 2.0 - 1.0;
	float y = p.y;
	float y2 = clamp(y * y, 0.0, 1.0);
	float motion = sin(TIME * wiggle_speed + y * 10.0) * wiggle_strength;
	motion += sin(TIME * wiggle_speed * 0.61 - y * 17.0) * wiggle_strength * 0.55;
	float center_x = -0.48 + arc_bulge * (1.0 - y2) + motion;
	float width = arc_width * (0.92 + 0.10 * sin(TIME * 6.7 + y * 8.0));
	float d = abs(p.x - center_x);
	float band = 1.0 - smoothstep(width, width + 0.055, d);
	float glow_band = 1.0 - smoothstep(width + 0.025, width + 0.24, d);
	float tip_fade = 1.0 - smoothstep(0.77, 1.0, abs(y));

	// 将原始竖直火焰沿弧线重新采样：y 沿整条弧走，x 只描述弧线厚度。
	float across = clamp(0.5 + (p.x - center_x) / max(width * 2.0, 0.001), 0.0, 1.0);
	float along = clamp(UV.y + sin(TIME * 5.3 + UV.y * 13.0) * 0.015, 0.0, 1.0);
	vec2 src_uv = vec2(across, along);
	src_uv.x += sin(TIME * 11.0 + along * 20.0) * 0.040 * (1.0 - abs(across * 2.0 - 1.0));
	src_uv.x = clamp(src_uv.x, 0.0, 1.0);
	vec4 tex = texture(TEXTURE, src_uv);

	float base_alpha = tex.a * band * tip_fade;
	float pulse = 0.5 + 0.5 * sin(TIME * 10.0 + along * 9.0);
	vec3 flame_rgb = tex.rgb * (1.0 + pulse * flame_pulse);
	vec3 glow_rgb = vec3(1.0, 0.22, 0.015) * glow_band * tip_fade * glow_strength;
	float glow_alpha = glow_band * tip_fade * 0.38;
	float a = clamp(opacity, 0.0, 1.0);

	// blend_add 负责发光感，同时统一压低可见强度，避免火焰成为一块不透明贴图。
	COLOR = vec4((flame_rgb * base_alpha + glow_rgb) * a, max(base_alpha, glow_alpha) * a) * vertex_color;
}
