shader_type canvas_item;
// 咒术回战赛璐璐特效面片：硬边 3 阶色（c0 核心 / c1 / c2）+ c3 墨线描边，形状噪声按 12fps 跳帧（动画的“一拍二”）。
// 预乘混合：rgb 已乘 alpha。坐标以像素计（px 为面片像素尺寸），描边宽度在屏幕上保持一致。
// mode: 0 能量球  1 爆闪星  2 冲击环  3 集中线  4 光束  5 斩痕  6 火焰  7 裂纹  8 无量空处  9 伏魔御厨子地面
render_mode unshaded, blend_premul_alpha;

uniform int mode = 0;
uniform float time = 0.0;
uniform float alpha = 1.0;
uniform float seed = 0.0;
uniform vec4 c0 : source_color = vec4(1.0);
uniform vec4 c1 : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform vec4 c2 : source_color = vec4(0.15, 0.35, 1.0, 1.0);
uniform vec4 c3 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 p0 = vec4(0.0);
uniform vec4 p1 = vec4(0.0);
uniform vec4 p2 = vec4(0.0);
uniform vec2 px = vec2(128.0);


float hash11(float n) { return fract(sin(n * 127.1 + seed * 13.7) * 43758.5453); }
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed * 0.37);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
vec3 permute3(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
// 2D simplex 噪声（Ashima Arts / Stefan Gustavson，MIT）
float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = mod(i, 289.0);
	vec3 p = permute3(permute3(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * snoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v * 0.5 + 0.5;
}

// 覆盖率：d<0 为内部，1 像素抗锯齿（硬边，不糊）。
float cov(float d) { return clamp(0.5 - d / max(fwidth(d), 0.0001), 0.0, 1.0); }

// 三阶色 + 墨线。d 为像素有符号距离；w2/w1 为 c2、c1 色带向内的像素宽度；ow 为描边像素宽度。
vec4 cel(float d, float w2, float w1, float ow) {
	float o = cov(d - ow);
	float i2 = cov(d);
	float i1 = cov(d + w2);
	float i0 = cov(d + w2 + w1);
	vec3 col = c3.rgb;
	col = mix(col, c2.rgb, i2);
	col = mix(col, c1.rgb, i1);
	col = mix(col, c0.rgb, i0);
	float a = max(o * c3.a, i2 * mix(c2.a, 1.0, i1));
	return vec4(col * a, a);
}

float step_seed(float fps) { return fps > 0.0 ? floor(time * fps) : 0.0; }

// 0 能量球：沸腾轮廓 + 尖刺 + 螺旋色带；hollow>0 为黑色空心（苍）。
vec4 orb(vec2 P, float R) {
	float r = length(P);
	float a = atan(P.y, P.x);
	float bs = step_seed(12.0);
	vec2 cs = vec2(cos(a), sin(a));
	float boil = snoise(cs * 1.8 + vec2(bs * 3.1, seed)) * p0.y;
	float n = max(p0.w, 1.0);
	float u = a / TAU * n + hash11(bs * 1.3) ;
	float fi = floor(u);
	float prof = pow(1.0 - abs(fract(u) - 0.5) * 2.0, 3.0) * (0.4 + 0.6 * hash11(fi + bs * 7.0));
	float rr = R * p0.x * (1.0 + boil + p0.z * prof);
	float d = r - rr;
	float wave = sin(a * 3.0 + log(max(r, 1.0)) * 5.0 - time * p1.x) * 0.12 * rr * step(0.01, abs(p1.x));
	vec4 c = cel(d, rr * p1.y + wave, rr * p1.z + wave, p1.w);
	if (p2.x > 0.0) {
		float hr = rr * p2.x * (1.0 + 0.5 * boil);
		float h = cov(r - hr);
		float rim = cov(r - hr - max(1.5, rr * 0.06));
		vec3 col = mix(c.rgb, c0.rgb * c.a, rim);
		col = mix(col, c3.rgb * c.a, h);
		c.rgb = col;
	}
	// 外圈咒力电弧（锯齿短线）
	if (p2.y > 0.0) {
		float k = 7.0;
		float u2 = a / TAU * k + hash11(bs + 3.0) * 3.0;
		float i2 = floor(u2);
		float ok = step(0.45, hash11(i2 * 2.1 + bs));
		float alen = rr * (1.0 + p2.y * (0.4 + 0.6 * hash11(i2 + bs * 5.0)));
		float jag = snoise(vec2(r * 0.12, i2 * 3.3 + bs)) * 0.18;
		float ad = abs(fract(u2) - 0.5 + jag) * TAU / k * r;
		float along = step(rr * 0.95, r) * step(r, alen);
		float w = max(1.2, rr * 0.05) * (1.0 - smoothstep(rr, alen, r) * 0.7);
		float arc = cov(ad - w) * along * ok;
		float arc_o = cov(ad - w - p1.w) * along * ok;
		vec3 ac = mix(c3.rgb, c0.rgb, arc);
		float aa = max(arc_o * c3.a, arc);
		c = vec4(mix(c.rgb, ac * aa, aa * (1.0 - c.a)), max(c.a, aa));
	}
	if (p2.w > 0.0) {
		float g = exp(-max(d, 0.0) / max(rr * 0.35, 1.0)) * p2.w * (1.0 - c.a);
		c.rgb += c2.rgb * g;
	}
	return c;
}

// 1 爆闪星：动画里的尖刺状爆炸闪光，每拍重掷尖刺长度。
vec4 burst(vec2 P, float R) {
	float r = length(P);
	float a = atan(P.y, P.x) + p2.x;
	float bs = step_seed(p0.w);
	float n = max(p0.y, 3.0);
	float u = a / TAU * n;
	float fi = floor(u);
	float L = 0.45 + 0.55 * hash11(mod(fi, n) * 1.37 + bs * 3.7);
	float prof = pow(1.0 - abs(fract(u) - 0.5) * 2.0, 1.8);
	float s = p0.z + (1.0 - p0.z) * L * prof;
	float rr = R * p0.x * s;
	float o = cov(r - rr - p1.w);
	float i2 = cov(r - rr);
	float i1 = cov(r - rr * (1.0 - p1.y));
	float i0 = cov(r - rr * (1.0 - p1.y - p1.z));
	vec3 col = mix(mix(mix(c3.rgb, c2.rgb, i2), c1.rgb, i1), c0.rgb, i0);
	float al = max(o * c3.a, i2);
	return vec4(col * al, al);
}

// 2 冲击环：前沿粗、随角度断裂的硬边环。
vec4 ring(vec2 P, float R) {
	float r = length(P);
	float a = atan(P.y, P.x);
	float bs = step_seed(12.0);
	float rr = R * p0.x;
	float th = R * p0.y;
	float segs = max(p0.w, 1.0);
	float nb = snoise(vec2(cos(a), sin(a)) * segs * 0.35 + vec2(bs * 2.3, seed));
	float keep = mix(1.0, smoothstep(-0.2, 0.4, nb), p0.z);
	th *= keep;
	// 外沿厚、内沿薄：向外偏移
	float d = abs(r - rr + th * 0.25) - th * 0.5;
	if (th < 0.5) return vec4(0.0);
	return cel(d, th * p1.y, th * p1.z, p1.w * keep);
}

// 3 集中线：从外向内收窄的墨线，每拍重掷；中间留空。
vec4 lines(vec2 P, float R) {
	float r = length(P);
	float a = atan(P.y, P.x);
	float bs = step_seed(p0.w);
	float n = max(p0.y, 8.0);
	float u = a / TAU * n;
	float fi = floor(u);
	float h1 = hash11(fi * 1.7 + bs * 11.0);
	float h2 = hash11(fi * 3.1 + bs * 5.0);
	float h3 = hash11(fi * 0.7 + bs * 2.0);
	float start = R * (p0.x + h1 * 0.28 - time * p1.y);
	float outer = R * max(p1.x, 1.0);
	float t = clamp((r - start) / max(outer - start, 1.0), 0.0, 1.0);
	float half_w = p0.z * (0.3 + 0.7 * h2) * 0.5 * t;
	float ad = abs(fract(u) - 0.5);
	float on = step(0.3, h3) * step(start, r);
	float cv = cov((ad - half_w) * TAU / n * r) * on;
	float al = cv * c2.a;
	return vec4(c2.rgb * al, al);
}

// 4 光束：沿 x 的硬边光束，带流动的内部色带和圆头；p1.x 为尾部消散位置。
vec4 beam(vec2 P) {
	float L = px.x;
	float H = px.y * 0.5;
	float x = P.x + L * 0.5;
	float head = L * p0.x;
	float bs = step_seed(12.0);
	float wob = snoise(vec2(x / max(H, 1.0) * 1.3 - time * p1.w, bs * 0.7 + seed)) * p0.z;
	float hw = H * p0.y * (1.0 + wob) * smoothstep(0.0, H * 1.5, x);
	float d = abs(P.y) - hw;
	if (x > head - hw) d = length(vec2(x - (head - hw), P.y)) - hw;
	float tail = L * p1.x;
	float tj = snoise(vec2(P.y / max(H, 1.0) * 2.0, bs)) * H * 0.6;
	d = max(d, tail + tj - x);
	float streak = snoise(vec2(x / max(H, 1.0) * 0.5 - time * p1.w * 1.5, P.y / max(hw, 1.0) * 1.7 + seed)) * 0.25 * hw;
	return cel(d, hw * p1.y + streak, hw * p1.z + streak, p0.w);
}

// 5 斩痕：两端尖的新月形白刃，reveal 从 a 划到 b，tail 从 a 开始消失。
vec4 slash(vec2 P) {
	float L = px.x;
	float H = px.y * 0.5;
	float xn = P.x / L + 0.5;
	float yc = p0.z * H * (1.0 - pow(2.0 * xn - 1.0, 2.0));
	float head = p0.x;
	float tl = p0.y;
	float span = clamp((xn - tl) / max(head - tl, 0.001), 0.0, 1.0);
	float shape = pow(sin(3.14159 * span), 0.8);
	float hw = H * p1.x * shape;
	float d = abs(P.y - yc) - hw;
	d = max(d, max(tl - xn, xn - head) * L);
	return cel(d, max(hw * 0.35, 0.6), max(hw * p1.y, 0.4), p0.w);
}

// 6 火焰：色阶化 fbm，p1.x=0 向上的火柱/火墙，1 球形火团。
vec4 fire(vec2 P, float R) {
	vec2 q = P / R;
	float ts = floor(time * 12.0) / 12.0;
	float s;
	if (p1.x < 0.5) {
		// 火柱：底宽顶尖的泪滴形，向上翻卷
		float h = clamp((q.y + 1.0) * 0.5, 0.0, 1.0);
		float wdt = mix(0.18, 0.78, pow(h, 0.7));
		s = min(1.0 - abs(q.x) / wdt, (1.0 - abs(q.y - 0.15) / 0.95) * 1.4);
	} else s = 1.0 - length(q);
	float n = fbm(q * p0.z + vec2(seed, ts * p0.y));
	float f = s * 1.25 + (n - 0.5) * 1.1 - (1.0 - p0.x) * 1.2 + p1.y;
	// 面片边缘强制熄灭（圆形遮罩），火焰轮廓永远不会被方形边界切平
	f -= smoothstep(0.6, 0.97, length(q)) * 2.0;
	float w = fwidth(f);
	float o = clamp((f - (0.12 - p0.w)) / w + 0.5, 0.0, 1.0);
	float i2 = clamp((f - 0.12) / w + 0.5, 0.0, 1.0);
	float i1 = clamp((f - 0.36) / w + 0.5, 0.0, 1.0);
	float i0 = clamp((f - 0.6) / w + 0.5, 0.0, 1.0);
	vec3 col = mix(mix(mix(c3.rgb, c2.rgb, i2), c1.rgb, i1), c0.rgb, i0);
	float al = max(o * c3.a, i2);
	return vec4(col * al, al);
}

// 7 裂纹：从中心放射的锯齿墨线（地面龟裂 / 空间裂缝），带细亮边。
vec4 crack(vec2 P, float R) {
	float r = length(P);
	float a = atan(P.y, P.x);
	float n = max(p0.x, 3.0);
	float best = 1e5;
	float wbest = 0.0;
	for (int k = -1; k <= 1; k++) {
		float i = floor(a / TAU * n) + float(k);
		float im = mod(i, n);
		float rlen = R * p0.y * (0.45 + 0.55 * hash11(im * 1.9));
		float ai = (i + 0.5 + (hash11(im * 2.7) - 0.5) * 0.6) / n * TAU;
		ai += snoise(vec2(r / max(R, 1.0) * 5.0, im * 7.3)) * p0.w;
		float da = a - ai;
		da = mod(da + 3.14159, TAU) - 3.14159;
		float dist = abs(da) * r;
		float w = p0.z * (1.0 - clamp(r / max(rlen, 1.0), 0.0, 1.0));
		float dd = max(dist - w, r - rlen);
		if (dd < best) { best = dd; wbest = w; }
	}
	float core = cov(best);
	float edge = cov(best - max(1.0, p0.z * 0.5));
	vec3 col = mix(c1.rgb, c3.rgb, core);
	float al = max(edge * c1.a, core * c3.a);
	return vec4(col * al, al);
}

// 8 无量空处：圆形内部是向外流动的星光（信息洪流）与色阶星云，边缘为白色光环 + 墨线。
vec4 void_domain(vec2 P, float R) {
	float r = length(P) / R;
	float a = atan(P.y, P.x);
	float edge = p0.x;
	if (r > edge + 0.06) return vec4(0.0);
	float ts = floor(time * 12.0) / 12.0;
	float neb = fbm(vec2(a * 1.2, log(max(r, 0.02)) * 1.4 - ts * 0.3) + seed);
	vec3 col = c3.rgb;
	col = mix(col, c2.rgb * 0.22, step(0.56, neb) * p0.z);
	col = mix(col, c2.rgb * 0.42, step(0.7, neb) * p0.z);
	// 静止的细小星点
	vec2 sg = P / 9.0;
	vec2 si = floor(sg);
	float sh = hash21(si);
	float star = step(0.93, sh) * cov((length(fract(sg) - 0.5) - 0.07 - 0.08 * fract(sh * 13.0)) * 9.0);
	col = mix(col, c0.rgb, star * (0.5 + 0.5 * step(0.5, fract(sh * 7.0 + ts))));
	// 放射星流
	float n = 160.0;
	float u = a / TAU * n;
	float fi = floor(u);
	float h = hash11(fi);
	float z = fract(h * 7.0 + time * p0.y * (0.4 + h));
	float sr = z * edge;
	float slen = 0.02 + 0.12 * z * z;
	float ad = abs(fract(u) - 0.5) * TAU / n * r * R;
	float on = step(0.35, hash11(fi * 3.3)) * step(sr - slen, r) * step(r, sr);
	float st = cov(ad - (0.35 + 0.8 * z)) * on;
	col = mix(col, c0.rgb, st);
	// 中心奇点
	float core = cov((r - 0.03 * (1.0 + 0.3 * sin(time * 9.0))) * R);
	col = mix(col, c0.rgb, core);
	// 边缘光环（白核 + 彩边 + 墨线）
	float dd = (r - edge) * R;
	float ringv = abs(dd) - R * 0.012;
	float ro = cov(ringv - 2.0);
	float r2 = cov(ringv);
	float r1 = cov(ringv + R * 0.005);
	vec3 rc = mix(mix(c3.rgb, c1.rgb, r2), c0.rgb, r1);
	float inside = cov(dd);
	float al = max(inside * p0.w, ro);
	col = mix(col, rc, ro);
	return vec4(col * al, al);
}

// 9 伏魔御厨子地面：暗红血池色阶 + 满地随机闪现的斩痕（每拍重掷）。
vec4 shrine_floor(vec2 P) {
	if (p0.w > 0.5 && length(P) > 0.5 * min(px.x, px.y)) return vec4(0.0);
	vec2 uv = P / 240.0;
	float ts = floor(time * 12.0) / 12.0;
	float n = fbm(uv + vec2(seed, ts * 0.03));
	vec3 col = c3.rgb;
	col = mix(col, c2.rgb * 0.8, step(0.58, n));
	col = mix(col, c1.rgb * 0.55, step(0.72, n));
	float al = p0.x * (0.6 + 0.4 * step(0.58, n));
	// 斩痕网格
	float cells = p0.y;
	vec2 g = P / max(cells, 1.0);
	vec2 gi = floor(g);
	float bs = floor(time * 12.0);
	float hc = hash21(gi + bs * 0.37);
	if (hc > 1.0 - p0.z) {
		vec2 f = fract(g) - 0.5;
		float ang = hash21(gi * 1.7 + bs) * 3.14159;
		vec2 dir = vec2(cos(ang), sin(ang));
		float along = dot(f, dir);
		float across = abs(dot(f, vec2(-dir.y, dir.x)));
		float taper = 1.0 - abs(along) * 2.0;
		float w = 0.035 * taper;
		float c = cov((across - w) * cells) * step(0.0, taper);
		float o = cov((across - w - 0.03) * cells) * step(0.0, taper);
		col = mix(col, c0.rgb, c);
		col = mix(col, mix(c3.rgb * 0.2, col, c), o - c);
		al = max(al, o);
	}
	return vec4(col * al, al);
}

void fragment() {
	vec2 P = (UV - 0.5) * px;
	float R = 0.5 * min(px.x, px.y);
	vec4 c = vec4(0.0);
	if (mode == 0) c = orb(P, R);
	else if (mode == 1) c = burst(P, R);
	else if (mode == 2) c = ring(P, R);
	else if (mode == 3) c = lines(P, R);
	else if (mode == 4) c = beam(P);
	else if (mode == 5) c = slash(P);
	else if (mode == 6) c = fire(P, R);
	else if (mode == 7) c = crack(P, R);
	else if (mode == 8) c = void_domain(P, R);
	else if (mode == 9) c = shrine_floor(P);
	COLOR = c * clamp(alpha, 0.0, 1.0);
}
