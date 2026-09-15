shader_type canvas_item;
render_mode unshaded;

// ball.gd 会持续写这些 instance uniform，必须保留。
instance uniform vec4 default_color : source_color = vec4(1.0);
instance uniform float defualt_color_mix : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 hit_white_color : source_color = vec4(1.0);
instance uniform float power : hint_range(0.0, 1.0) = 0.0;

// morph_role: 0 = 前一个形态；1 = 后一个形态。
// 两张 Sprite 在脚本中共享同一条 Transform 插值轨迹：
// 前一个越扭越厉害并退出，后一个从相反的扭曲中解开。
uniform float morph_amount : hint_range(0.0, 1.0) = 0.0;
uniform float morph_role : hint_range(0.0, 1.0) = 0.0;
uniform float morph_strength : hint_range(0.0, 0.7) = 0.22;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

mat2 rotate2(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

float inside_uv(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0)
		* step(0.0, uv.y) * step(uv.y, 1.0);
}

void fragment() {
	float t = smoothstep(0.0, 1.0, clamp(morph_amount, 0.0, 1.0));
	float role = step(0.5, morph_role);

	// 前一个形态：t 越大扭得越厉害。
	// 后一个形态：t=0 时最扭，随后逐渐解开成目标图。
	float role_warp = mix(t, 1.0 - t, role);
	float middle = sin(t * 3.14159265);
	float strength = 0.55 + morph_strength * 3.8;
	float warp = clamp(role_warp * 0.72 + middle * 0.72, 0.0, 1.35);

	vec2 p = UV - vec2(0.5);
	float radius = length(p) * 2.0;
	float n1 = noise21(UV * 4.5 + vec2(1.7, 8.3)) - 0.5;
	float n2 = noise21(UV * 9.0 + vec2(7.1, 2.4)) - 0.5;
	float direction = mix(1.0, -1.0, role);

	// 核心：不是抖动，而是单方向“拧麻花”。越靠中心旋转越多，边缘较少，
	// 再叠加非均匀拉伸，使轮廓真的发生连续变化。
	float twist = direction * strength * warp * (1.35 - clamp(radius, 0.0, 1.0));
	twist += direction * n1 * 0.42 * warp;
	vec2 q = rotate2(twist) * p;

	float squeeze = 1.0 - 0.28 * warp;
	float stretch = 1.0 + 0.42 * warp;
	q.x *= mix(stretch, squeeze, 0.5 + 0.5 * sin((q.y + n2 * 0.08) * 11.0));
	q.y *= mix(squeeze, stretch, 0.5 + 0.5 * sin((q.x - n1 * 0.08) * 9.0));

	// 切向流动把旧轮廓拖向旋转方向；后一个形态以相反方向“解卷”。
	vec2 tangent = vec2(-q.y, q.x);
	q += tangent * direction * (0.16 + morph_strength * 0.22) * warp * (0.35 + 0.65 * (1.0 - clamp(radius, 0.0, 1.0)));
	q += vec2(n2, -n1) * (0.035 + morph_strength * 0.055) * warp;

	vec2 sample_uv = q + vec2(0.5);
	float bounds = inside_uv(sample_uv);
	vec4 tex = texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0))) * bounds;
	tex *= COLOR;

	// 颜色只沿用角色本来就有的染色/受击白闪，不再用“变色”冒充变形。
	tex.rgb = mix(tex.rgb, default_color.rgb, clamp(defualt_color_mix, 0.0, 1.0));
	tex.rgb = mix(tex.rgb, hit_white_color.rgb, clamp(power, 0.0, 1.0));

	// 交叉区域刻意较宽，让旧轮廓被扭坏的同时能看见新轮廓从里面解出来。
	float old_alpha = 1.0 - smoothstep(0.34, 0.92, t);
	float new_alpha = smoothstep(0.08, 0.66, t);
	tex.a *= mix(old_alpha, new_alpha, role);
	COLOR = tex;
}
