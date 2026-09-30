shader_type canvas_item;
// 咒术回战程序化特效面片（纯视觉，不参与任何判定）。
// 预乘混合：rgb = 发出的光，a = 对背景的遮挡 → 同一张面片既能“加光”也能“压黑描边”，
// 这是日式动画特效（硬边色阶 + 深色描边 + 高亮核心）的关键。
// mode: 0 能量球  1 光束  2 冲击环  3 赛璐璐火焰  4 空间裂缝  5 无量空处虚空
//       6 血池水面  7 集中线  8 卡通烟团  9 满屏斩击
render_mode unshaded, blend_premul_alpha;

uniform int mode = 0;
uniform float time = 0.0;
uniform float alpha = 1.0;
uniform float seed = 0.0;
uniform vec4 c0 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 c1 : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform vec4 c2 : source_color = vec4(0.15, 0.35, 1.0, 1.0);
uniform vec4 c3 : source_color = vec4(0.0, 0.0, 0.02, 1.0);
uniform vec4 p0 = vec4(0.0);
uniform vec4 p1 = vec4(0.0);
uniform vec4 p2 = vec4(0.0);
uniform vec2 px = vec2(128.0, 128.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 2D simplex 噪声（Ashima Arts / Stefan Gustavson，MIT）：没有值噪声那种沿网格的方块轮廓。
vec3 permute3(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
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

float vnoise(vec2 p) {
	return snoise(p) * 0.5 + 0.5;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = r * p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v / 0.9375;
}

vec2 rot2(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// 四阶硬色阶：0→c3  0.25→c2  0.5→c1  0.75→c0（aa 为抗锯齿过渡宽度）
vec3 ramp4(float v, float aa) {
	vec3 col = c3.rgb;
	col = mix(col, c2.rgb, smoothstep(0.25 - aa, 0.25 + aa, v));
	col = mix(col, c1.rgb, smoothstep(0.5 - aa, 0.5 + aa, v));
	col = mix(col, c0.rgb, smoothstep(0.75 - aa, 0.75 + aa, v));
	return col;
}

float band_aa(float v, float soft) {
	return max(fwidth(v) * 0.75, soft) + 0.002;
}

// ------------------------------------------------------------------ 0 能量球
// p0: x=球半径(0..1) y=漩涡强度(负=向内吸) z=外焰尖刺长度 w=外侧墨线强度
// p1: x=自转速度 y=轮廓起伏 z=外发光强度 w=球体遮挡(0=纯发光 1=实心)
// p2: x=色阶柔和度 y=噪声尺度
vec4 m_orb(vec2 uv) {
	vec2 d = (uv - 0.5) * 2.0;
	float r = length(d);
	float R = max(p0.x, 0.001);
	float sc = p2.y > 0.0 ? p2.y : 3.0;
	vec2 q = rot2(d, p0.y * (1.0 - clamp(r / R, 0.0, 1.0)) * 3.0 + time * p1.x);
	float n = fbm(q * sc + vec2(seed, time * 0.6));
	float n2 = fbm(rot2(d, -time * p1.x * 0.6) * sc * 2.0 + vec2(time, seed * 1.7));
	float er = R * (1.0 + (n - 0.5) * p1.y);
	float aa_r = fwidth(r) * 1.2 + 0.001;
	float inside = 1.0 - smoothstep(er - aa_r, er + aa_r, r);
	float v = 1.0 - r / er;
	float heat = v * 0.95 + (n2 - 0.5) * 0.55 + 0.2;
	vec3 body = ramp4(heat, band_aa(heat, p2.x));
	// 内缘高光：赛璐璐球体的轮廓光，让球在任何背景上都读得清
	float rim = (1.0 - smoothstep(0.03, 0.16, v)) * smoothstep(-0.02, 0.03, v);
	body = mix(body, c1.rgb * 1.25, rim * 0.6);
	// 外焰尖刺：沿角度的噪声决定长度
	vec2 dir = r > 0.0001 ? d / r : vec2(1.0, 0.0);
	float an = fbm(rot2(dir, time * p1.x * 0.3) * 4.0 + vec2(time * 1.7, seed));
	float spike_len = p0.z * pow(an, 1.6) * (1.0 - R) + 0.0001;
	float outside = r - er;
	float spike = clamp(1.0 - outside / spike_len, 0.0, 1.0) * step(0.0, outside);
	float sp_band = smoothstep(0.35, 0.4, spike);
	float halo = exp(-max(outside, 0.0) * 7.0 / max(1.0 - R, 0.05)) * p1.z;
	float edge_fade = 1.0 - smoothstep(0.92, 1.0, r);
	vec3 light = body * inside + (c2.rgb * sp_band + c1.rgb * smoothstep(0.7, 0.75, spike) + c2.rgb * halo) * (1.0 - inside);
	float ink_w = 0.035 * p0.w;
	float ink = p0.w > 0.0 ? (1.0 - smoothstep(ink_w * 0.6, ink_w, abs(outside - ink_w * 0.5))) * (1.0 - sp_band) : 0.0;
	float occ = inside * p1.w + ink;
	light = light * (1.0 - ink) + c3.rgb * ink;
	return vec4(light, occ) * edge_fade;
}

// ------------------------------------------------------------------ 1 光束（x 沿长度，y 横向）
// p0: x=半宽(0..1) y=流动速度 z=紊流 w=头部位置(0..1)
// p1: x=尾部擦除位置 y=尾部渐细长度 z=外发光 w=遮挡
// p2: x=色阶柔和度 y=头部圆头长度(0..1 的长度占比)
vec4 m_beam(vec2 uv) {
	float x = uv.x;
	float y = (uv.y - 0.5) * 2.0;
	float L = px.x / max(px.y, 1.0);
	float head = p0.w;
	float tail = p1.x;
	if (x > head + 0.0001 || x < tail) return vec4(0.0);
	float span = max(head - tail, 0.0001);
	float lx = (x - tail) / span;
	float n = fbm(vec2(x * L * 1.6 - time * p0.y, y * 0.8 + seed));
	float w = p0.x * (1.0 + (n - 0.5) * 2.0 * p0.z);
	float taper = smoothstep(0.0, max(p1.y, 0.001), lx);
	float cap_len = max(p2.y, 0.0001);
	float hx = clamp((head - x) / cap_len, 0.0, 1.0);
	float cap = sqrt(1.0 - (1.0 - hx) * (1.0 - hx));
	w *= taper * cap;
	float ay = abs(y);
	float v = 1.0 - ay / max(w, 0.0001);
	float flow = vnoise(vec2(x * L * 5.0 - time * p0.y * 2.5, y * 5.0 + seed * 3.1));
	float heat = v * 1.05 + (flow - 0.5) * 0.4 + 0.12;
	float aa_y = fwidth(y) * 1.2 + 0.001;
	float inside = 1.0 - smoothstep(w - aa_y, w + aa_y, ay);
	vec3 body = ramp4(heat, band_aa(heat, p2.x));
	float halo = exp(-max(ay - w, 0.0) * 6.0) * p1.z * taper;
	vec3 light = body * inside + c2.rgb * halo * (1.0 - inside);
	float occ = inside * p1.w;
	return vec4(light, occ);
}

// ------------------------------------------------------------------ 2 冲击环
// p0: x=半径(0..1) y=厚度 z=破碎度 w=内部填充
// p1: x=外侧墨线宽 y=放射条纹强度 z=外发光 w=遮挡
vec4 m_ring(vec2 uv) {
	vec2 d = (uv - 0.5) * 2.0;
	float r = length(d);
	float R = p0.x;
	float th = max(p0.y, 0.002);
	vec2 dir = r > 0.0001 ? d / r : vec2(1.0, 0.0);
	float n = fbm(dir * 5.0 + vec2(time * 1.3, seed) + d * 1.5);
	float x = (R - r) / th;
	float aa_r = fwidth(r) * 1.2 + 0.001;
	float in_band = (1.0 - smoothstep(R - aa_r, R + aa_r, r)) * (1.0 - smoothstep(0.85, 1.0, x));
	float heat = (1.0 - clamp(x, 0.0, 1.0)) * 1.1 - 0.05;
	float brk = smoothstep(p0.z, p0.z + 0.12, n + (1.0 - clamp(x, 0.0, 1.0)) * 0.25);
	heat *= brk;
	vec3 body = ramp4(heat, band_aa(heat, 0.0));
	float fill = (1.0 - smoothstep(R - aa_r, R + aa_r, r)) * p0.w * (0.5 + 0.5 * n);
	float streak = 0.0;
	if (p1.y > 0.0) {
		float a = atan(d.y, d.x);
		float cell = floor(a / 6.2831853 * 90.0);
		float h = hash21(vec2(cell, seed));
		streak = step(0.72, h) * smoothstep(R * 0.82, R, r) * (1.0 - smoothstep(R - aa_r, R, r)) * p1.y;
	}
	float out_d = r - R;
	float halo = exp(-max(out_d, 0.0) * 18.0) * p1.z * step(0.0, out_d) * brk;
	float ink = p1.x > 0.0 ? (1.0 - smoothstep(p1.x * 0.5, p1.x, abs(out_d - p1.x * 0.5))) * brk : 0.0;
	vec3 light = body * in_band + c2.rgb * (fill + halo) + c1.rgb * streak;
	light = light * (1.0 - ink) + c3.rgb * ink;
	float occ = in_band * brk * p1.w + ink;
	float edge_fade = 1.0 - smoothstep(0.95, 1.0, r);
	return vec4(light, occ) * edge_fade;
}

// ------------------------------------------------------------------ 3 赛璐璐火焰
// p0: x=上升速度 y=紊流 z=高度/规模 w=形状(0 火柱 1 火球/爆炸)
// p1: x=熄灭度(抬高阈值) y=深色描边带宽 z=外发光 w=遮挡
vec4 m_fire(vec2 uv) {
	vec2 q = vec2((uv.x - 0.5) * 2.0, 1.0 - uv.y);
	float asp = px.x / max(px.y, 1.0);
	float h = max(p0.z, 0.001);
	float n = fbm(vec2(q.x * 2.2 * asp, q.y * 2.6 - time * p0.x) + seed);
	float n2 = fbm(vec2(q.x * 4.5 * asp, q.y * 5.5 - time * p0.x * 1.6) + seed * 2.3);
	float hy = clamp(q.y / h, 0.0, 1.5);
	float col_f = (1.0 - hy) * (1.0 - q.x * q.x * (1.0 + hy * 2.5));
	vec2 bd = vec2(q.x, (q.y - 0.42) * 1.15);
	float ball_f = 1.0 - length(bd) / (h * 0.62) + max(0.0, q.y - 0.42) * 0.25;
	float f = mix(col_f, ball_f, p0.w);
	f += (n - 0.5) * p0.y + (n2 - 0.5) * p0.y * 0.55 - p1.x;
	// 靠近四边时把火焰“压”回去，轮廓自然收成圆弧，不会被矩形边界切平
	f -= smoothstep(0.62, 0.98, abs(q.x)) * 1.2 + smoothstep(0.7, 0.98, q.y) * 1.2 + (1.0 - smoothstep(0.0, 0.08, q.y)) * 0.8;
	float aa = band_aa(f, 0.0);
	float t_dark = 0.12;
	float t_red = t_dark + max(p1.y, 0.0);
	float lit = smoothstep(t_red - aa, t_red + aa, f);
	float darkm = smoothstep(t_dark - aa, t_dark + aa, f) * (1.0 - lit);
	float heat = (f - t_red) / 0.55;
	vec3 fire = c2.rgb;
	fire = mix(fire, c1.rgb, smoothstep(0.35 - aa, 0.35 + aa, heat));
	fire = mix(fire, c0.rgb, smoothstep(0.72 - aa, 0.72 + aa, heat));
	float halo = smoothstep(-0.25, t_dark, f) * (1.0 - smoothstep(t_dark - aa, t_dark + aa, f)) * p1.z;
	vec3 light = fire * lit + c3.rgb * darkm + c2.rgb * halo;
	float occ = lit * p1.w + darkm * 0.85;
	float edge = (1.0 - smoothstep(0.9, 1.0, abs(q.x))) * (1.0 - smoothstep(0.92, 1.0, q.y)) * smoothstep(0.0, 0.04, q.y + 0.02);
	return vec4(light, occ) * edge;
}

// ------------------------------------------------------------------ 4 空间裂缝（x 沿长度，y 横向）
// p0: x=裂缝半宽(0..1) y=擦除起点 z=显现终点 w=锯齿
// p1: x=白边像素宽 y=色差光晕像素宽 z=裂缝内星点 w=弯曲(新月)
vec4 m_cut(vec2 uv) {
	float x = uv.x;
	float y = (uv.y - 0.5) * 2.0;
	float from = p0.y;
	float to = p0.z;
	if (x < from || x > to) return vec4(0.0);
	float lx = (x - from) / max(to - from, 0.0001);
	float taper = pow(max(sin(3.14159265 * lx), 0.0), 0.55);
	float L = px.x / max(px.y, 1.0);
	float jag = (vnoise(vec2(x * L * 9.0, seed)) - 0.5) * p0.w + (vnoise(vec2(x * L * 30.0, seed + 5.0)) - 0.5) * p0.w * 0.35;
	float g = p0.x * taper;
	float bend = p1.w * 4.0 * lx * (1.0 - lx);
	float yy = y - bend - jag * g;
	float ay = abs(yy);
	float ypx = 2.0 / max(px.y, 1.0);
	float edge_w = max(p1.x, 0.5) * ypx;
	float aa = fwidth(yy) * 1.2 + 0.0005;
	float gap = 1.0 - smoothstep(g - aa, g + aa, ay);
	float edge = (1.0 - smoothstep(edge_w * 0.5, edge_w * 0.5 + aa * 1.5, abs(ay - g))) * step(0.001, taper);
	float halo_w = max(p1.y, 0.5) * ypx;
	float halo = exp(-max(ay - g, 0.0) / halo_w) * (1.0 - gap) * taper;
	vec3 side_col = yy > 0.0 ? c1.rgb : c2.rgb;
	float stars = 0.0;
	if (p1.z > 0.0) {
		vec2 sg = vec2(x * px.x, y * px.y * 0.5) / 5.0;
		float hs = hash21(floor(sg) + seed);
		stars = step(0.93, hs) * p1.z * (1.0 - smoothstep(0.3, 0.5, length(fract(sg) - 0.5)));
	}
	vec3 light = c3.rgb * gap + c0.rgb * edge + side_col * halo * 0.9 + c0.rgb * stars * gap;
	float occ = gap;
	return vec4(light, occ);
}

// ------------------------------------------------------------------ 5 无量空处（圆内的虚空）
// p0: x=结界半径(0..1) y=吸入速度 z=星点密度 w=遮挡
// p1: x=中心之眼强度 y=边缘亮度 z=星云亮度
vec4 m_void(vec2 uv) {
	vec2 d = (uv - 0.5) * 2.0;
	float R = max(p0.x, 0.001);
	vec2 e = d / R;
	float rn = length(e);
	float aa = fwidth(rn) * 1.2 + 0.001;
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, rn);
	float lr = log(max(rn, 0.002));
	float a = atan(e.y, e.x);
	vec2 q = rot2(e, lr * 1.4 + time * 0.12);
	float neb = fbm(q * 2.2 + vec2(time * 0.04, seed));
	float neb2 = fbm(q * 5.0 + vec2(seed * 1.3, -time * 0.08));
	float arms = 0.5 + 0.5 * sin(a * 2.0 + lr * 3.2 + time * 0.5);
	float dens = neb * 0.75 + arms * neb2 * 0.45;
	vec3 col = c3.rgb;
	col += c2.rgb * smoothstep(0.42, 0.85, dens) * p1.z;
	col += c1.rgb * smoothstep(0.66, 0.98, dens) * p1.z * 0.8;
	// 信息流：对数极坐标网格中向中心奔流的星点（越近中心越亮、越拉长）
	float stars = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		vec2 g = vec2((a / 6.2831853 + 0.5) * (40.0 + fl * 28.0), lr * (5.0 + fl * 3.0) + time * p0.y * (1.0 + fl * 0.6));
		vec2 gi = floor(g);
		vec2 gf = fract(g);
		float h = hash21(gi + vec2(seed + fl * 11.0, fl * 3.0));
		if (h > 1.0 - p0.z) {
			vec2 c = vec2(0.3 + 0.4 * hash21(gi + 1.7), 0.3 + 0.4 * hash21(gi + 4.1));
			vec2 dd = gf - c;
			float stretch = 1.0 + (1.0 - clamp(rn, 0.0, 1.0)) * 5.0;
			stars += exp(-dd.x * dd.x * 60.0 - dd.y * dd.y * 60.0 / (stretch * stretch)) * (0.6 + 0.4 * sin(time * 5.0 + h * 40.0));
		}
	}
	col += c0.rgb * stars * (0.7 + (1.0 - clamp(rn, 0.0, 1.0)) * 1.3);
	col += c0.rgb * exp(-rn * 16.0) * 1.6 * p1.x + c1.rgb * exp(-rn * 5.0) * 0.55 * p1.x;
	float rim = smoothstep(0.78, 1.0, rn) * inside;
	col += c1.rgb * rim * rim * p1.y;
	float outside_glow = exp(-max(rn - 1.0, 0.0) * 40.0) * (1.0 - inside) * p1.y * 0.6;
	vec3 light = col * inside + c1.rgb * outside_glow;
	float occ = inside * p0.w;
	return vec4(light, occ);
}

// ------------------------------------------------------------------ 6 血池水面（矩形）
// p0: x=底色遮挡 y=边缘暗角 z=涟漪强度 w=高光强度
vec4 m_pool(vec2 uv) {
	vec2 w = uv * px / 110.0;
	float n = fbm(w * 0.7 + vec2(time * 0.05, time * 0.03) + seed);
	float rip = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float ph = fract(time * 0.22 + hash21(vec2(fi, seed + 3.0)));
		float cyc = floor(time * 0.22 + hash21(vec2(fi, seed + 3.0)));
		vec2 c = vec2(hash21(vec2(fi + cyc * 7.0, seed)), hash21(vec2(seed + 1.0, fi + cyc * 5.0))) * px / 110.0;
		float dd = length((w - c) * vec2(1.0, 1.8));
		float x = (dd - ph * 3.5) * 5.0;
		rip += exp(-x * x) * (1.0 - ph);
	}
	float cau = pow(abs(sin((fbm(w * 1.3 + vec2(time * 0.08, -time * 0.05)) + n * 0.5) * 11.0)), 10.0);
	vec2 m = min(uv, 1.0 - uv) * px;
	float vig = 1.0 - smoothstep(0.0, min(px.x, px.y) * 0.3, min(m.x, m.y));
	float base = p0.x * (0.85 + 0.3 * n) + vig * p0.y;
	vec3 light = c3.rgb * base + c1.rgb * (rip * p0.z + cau * p0.w) * (1.0 - vig * 0.6) + c2.rgb * n * n * 0.1 * p0.x;
	return vec4(light, clamp(base, 0.0, 1.0));
}

// ------------------------------------------------------------------ 7 集中线（漫画速度线）
// p0: x=中心留空半径 y=线条数 z=粗细 w=墨线模式(0 白光 1 黑墨)
// p1: x=每秒刷新帧数 y=整体随机长度
vec4 m_focus(vec2 uv) {
	vec2 d = (uv - 0.5) * 2.0;
	d.x *= px.x / max(px.y, 1.0);
	float r = length(d);
	float a = atan(d.y, d.x);
	float fps = p1.x > 0.0 ? p1.x : 24.0;
	float frame = floor(time * fps);
	float dens = max(p0.y, 8.0);
	float u = (a / 6.2831853 + 0.5) * dens;
	float cell = floor(u);
	float fu = fract(u);
	float h = hash21(vec2(cell, frame + seed));
	float h2 = hash21(vec2(cell + 7.1, frame * 1.3 + seed));
	float start = p0.x + h2 * p1.y;
	float grow = smoothstep(start, start + 0.35, r);
	float width = p0.z * (0.35 + 0.65 * h) * grow;
	float line = step(0.3, h) * (1.0 - smoothstep(width - fwidth(fu) * 1.5, width + fwidth(fu) * 1.5, abs(fu - 0.5) * 2.0));
	float ru = length(uv - 0.5) * 2.0;
	float m = line * grow * (1.0 - smoothstep(0.5, 0.97, ru));
	vec3 light = c0.rgb * m * (1.0 - p0.w) + c3.rgb * m * p0.w;
	return vec4(light, m * p0.w);
}

// ------------------------------------------------------------------ 8 卡通烟团
// p0: x=半径 y=消散度 z=不透明度 w=描边
vec4 m_smoke(vec2 uv) {
	vec2 d = (uv - 0.5) * 2.0;
	float r = length(d);
	float n = fbm(d * 2.2 + vec2(seed, seed * 0.7) + vec2(time * 0.15, -time * 0.25));
	float shape = p0.x * 0.8 * (0.7 + 0.5 * n) - r;
	float aa = fwidth(shape) * 1.2 + 0.001;
	float inside = smoothstep(-aa, aa, shape);
	float n2 = fbm(d * 3.5 + vec2(seed * 3.0, 1.0));
	float vis = smoothstep(p0.y - 0.1, p0.y + 0.1, n2 + (1.0 - p0.y) * 0.2);
	vec2 dir = r > 0.001 ? d / r : vec2(0.0, -1.0);
	float lit = dot(dir, vec2(-0.55, -0.83)) * clamp(r / max(p0.x, 0.01), 0.0, 1.0) + (n - 0.5) * 0.8;
	vec3 col = mix(c2.rgb, c1.rgb, smoothstep(0.0, 0.18, lit));
	float ink = p0.w > 0.0 ? (1.0 - smoothstep(0.0, 0.03 * p0.w, abs(shape))) : 0.0;
	float m = max(inside, ink * 0.8) * vis;
	col = mix(col, c3.rgb, ink * (1.0 - inside * 0.5));
	float edge_fade = 1.0 - smoothstep(0.92, 1.0, r);
	return vec4(col * m * p0.z, m * p0.z) * edge_fade;
}

// ------------------------------------------------------------------ 9 满屏斩击（矩形区域）
// p0: x=格子像素 y=每秒批次 z=出现概率 w=斩痕像素宽
// p1: x=红色斩痕比例 y=黑缝强度 z=1 时裁成内切圆
vec4 m_storm(vec2 uv) {
	vec2 w = uv * px;
	float S = max(p0.x, 20.0);
	vec2 cell = floor(w / S);
	vec2 f = w - cell * S;
	vec3 light = vec3(0.0);
	float occ = 0.0;
	float rate = max(p0.y, 1.0);
	float tb = time * rate;
	for (int b = 0; b < 3; b++) {
		float bucket = floor(tb) - float(b);
		float age = (fract(tb) + float(b)) / 3.0;
		float h = hash21(cell + vec2(bucket * 13.13, bucket * 7.71) + seed);
		if (h > p0.z) continue;
		float h1 = hash21(cell * 1.7 + vec2(bucket, seed + 2.0));
		float h2 = hash21(cell * 2.3 + vec2(seed + 5.0, bucket));
		float h3 = hash21(cell * 3.1 + vec2(bucket * 0.7, seed + 9.0));
		vec2 c = S * vec2(0.3 + 0.4 * h1, 0.3 + 0.4 * h2);
		float ang = h3 * 3.14159265;
		vec2 dir = vec2(cos(ang), sin(ang));
		float hl = S * (0.45 + 0.35 * h);
		vec2 rel = f - c;
		float along = dot(rel, dir) / hl;
		float perp = dot(rel, vec2(-dir.y, dir.x));
		if (abs(along) > 1.0) continue;
		float reveal = smoothstep(0.0, 0.12, age);
		if (along > reveal * 2.0 - 1.0) continue;
		float taper = 1.0 - along * along;
		float wid = p0.w * taper * (1.0 - age * 0.6);
		float core = 1.0 - smoothstep(wid * 0.5, wid * 0.5 + 1.0, abs(perp));
		float halo = exp(-abs(perp) / (2.5 + wid)) * taper;
		float fade = 1.0 - age;
		bool red = hash21(cell + vec2(bucket * 3.3, 1.0)) < p1.x;
		vec3 cc = red ? c1.rgb : c0.rgb;
		light += (cc * core + c2.rgb * halo * 0.6) * fade;
		float gap = (1.0 - smoothstep(wid * 0.5 + 0.5, wid * 0.5 + 2.0, abs(perp))) * (1.0 - core) * p1.y;
		light += c3.rgb * gap * fade;
		occ = max(occ, gap * fade);
	}
	if (p1.z > 0.5) {
		float rc = length(uv - 0.5) * 2.0;
		float cm = 1.0 - smoothstep(0.9, 1.0, rc);
		light *= cm;
		occ *= cm;
	}
	return vec4(light, occ);
}

void fragment() {
	vec4 o = vec4(0.0);
	if (mode == 0) o = m_orb(UV);
	else if (mode == 1) o = m_beam(UV);
	else if (mode == 2) o = m_ring(UV);
	else if (mode == 3) o = m_fire(UV);
	else if (mode == 4) o = m_cut(UV);
	else if (mode == 5) o = m_void(UV);
	else if (mode == 6) o = m_pool(UV);
	else if (mode == 7) o = m_focus(UV);
	else if (mode == 8) o = m_smoke(UV);
	else o = m_storm(UV);
	o *= alpha * COLOR.a;
	o.a = clamp(o.a, 0.0, 1.0);
	COLOR = o;
}
