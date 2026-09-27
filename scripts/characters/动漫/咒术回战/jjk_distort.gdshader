shader_type canvas_item;
// 咒术回战空间扭曲（纯视觉）：0=冲击波折射环 1=漩涡吸入（苍） 2=空间错位（世界斩）
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform int mode = 0;
uniform float radius = 0.3;
uniform float thickness = 0.08;
uniform float strength = 20.0;
uniform float aberration = 0.0;
uniform float fade = 1.0;
uniform float rot = 0.0;
uniform vec2 px_per_uv = vec2(200.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d);
	vec2 dir = r > 0.0001 ? d / r : vec2(0.0);
	vec2 off = vec2(0.0);
	float edge = 1.0 - smoothstep(0.4, 0.5, r);
	float w = 0.0;
	if (mode == 0) {
		float x = (r - radius) / max(thickness, 0.0001);
		w = exp(-x * x * 2.5);
		off = -dir * strength * x * w;
	} else if (mode == 1) {
		float k = 1.0 - smoothstep(0.0, 0.5, r);
		float ang = strength * 0.03 * k * k;
		vec2 rd = vec2(cos(ang) * d.x - sin(ang) * d.y, sin(ang) * d.x + cos(ang) * d.y);
		rd *= 1.0 + thickness * k;
		off = (rd - d) * px_per_uv;
		w = k;
	} else {
		float s = d.y >= 0.0 ? 1.0 : -1.0;
		float band = 1.0 - smoothstep(0.0, 0.5, abs(d.y));
		edge = (1.0 - smoothstep(0.4, 0.5, abs(d.x))) * (1.0 - smoothstep(0.35, 0.5, abs(d.y)));
		off = vec2(s * strength * band, -s * strength * 0.2 * band);
		w = band;
	}
	float c = cos(rot);
	float sn = sin(rot);
	off = vec2(c * off.x - sn * off.y, sn * off.x + c * off.y);
	vec2 ouv = off * SCREEN_PIXEL_SIZE;
	vec2 ab = dir * aberration * w * 6.0 * SCREEN_PIXEL_SIZE;
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + ouv + ab).r;
	col.g = texture(screen_tex, SCREEN_UV + ouv).g;
	col.b = texture(screen_tex, SCREEN_UV + ouv - ab).b;
	COLOR = vec4(col, edge * fade);
}
