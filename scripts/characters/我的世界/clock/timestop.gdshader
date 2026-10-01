shader_type canvas_item;
// 时钟停时圈：方块化的圆边（时钟表盘的金框与刻度），圈内画面按像素格黑白化、抖色分阶，
// 叠录像带暂停画面（成格错位的跟踪条、扫描线、雪花），整体按游戏刻跳帧。
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float radius = 0.0;
uniform float cell = 2.0; // 圆边与表盘的方块尺寸
uniform float pix = 1.0; // 圈内画面的像素格

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
const vec3 GOLD = vec3(0.91, 0.71, 0.16);
const vec3 GOLD_HI = vec3(1.0, 0.89, 0.48);
const vec3 GOLD_LO = vec3(0.69, 0.47, 0.06);
const vec3 OUTLINE = vec3(0.17, 0.11, 0.02);

varying vec2 v_local;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// 局部坐标到屏幕坐标的比例（无旋转，仿射常量）；放在分支前求导。
	vec2 kx = dFdx(SCREEN_UV) / max(abs(dFdx(v_local).x), 1e-5);
	vec2 ky = dFdy(SCREEN_UV) / max(abs(dFdy(v_local).y), 1e-5);
	vec2 k = vec2(kx.x * sign(dFdx(v_local).x + 1e-9), ky.y * sign(dFdy(v_local).y + 1e-9));

	vec2 cc = (floor(v_local / cell) + 0.5) * cell;
	float rq = floor(radius / cell) * cell;
	float dc = length(cc);
	if (rq < cell * 2.0 || dc > rq) {
		discard;
	}
	float ring = rq - dc;
	vec3 rgb;
	if (ring < cell) {
		rgb = OUTLINE;
	} else if (ring < cell * 3.0) {
		float lit = dot(normalize(cc + vec2(1e-4)), vec2(-0.7071, -0.7071));
		rgb = lit > 0.35 ? GOLD_HI : (lit < -0.35 ? GOLD_LO : GOLD);
	} else if (ring < cell * 4.0) {
		rgb = OUTLINE;
	} else {
		// 表盘刻度：十二格，四个正点更长。
		float ang = atan(cc.y, cc.x);
		float step_a = 6.2831853 / 12.0;
		float idx = floor(ang / step_a + 0.5);
		float off = abs(ang - idx * step_a) * dc;
		float major = mod(idx, 3.0) == 0.0 ? 1.0 : 0.0;
		float tick_len = cell * (major > 0.5 ? 6.0 : 3.5);
		bool tick = off < cell * (major > 0.5 ? 1.0 : 0.6) && ring < cell * 4.0 + tick_len;

		vec2 cellp = floor(v_local / pix);
		vec2 p = (cellp + 0.5) * pix;
		float frame = floor(TIME * 20.0);
		float row = cellp.y;
		float band = floor(row / 3.0);
		float jit = step(0.93, h2(vec2(band, frame))) * floor((h2(vec2(band * 1.7, frame)) - 0.5) * 6.0) * pix;
		float sweep = (fract(-TIME * 0.3) * 2.0 - 1.0) * rq;
		float bar = 1.0 - step(cell * 1.5, abs(p.y - sweep));
		p.x += jit + bar * pix * 2.0 * sign(sin(row * 1.3 + frame));
		vec3 col = texture(screen_tex, SCREEN_UV + (p - v_local) * k).rgb;
		float lum = dot(col, vec3(0.299, 0.587, 0.114)) * 0.92 + 0.1;
		lum += (h2(cellp + frame) - 0.5) * 0.05;
		lum += bar * 0.12;
		lum -= mod(row, 2.0) < 1.0 ? 0.0 : 0.05;
		int bi = int(mod(cellp.x, 4.0)) + int(mod(cellp.y, 4.0)) * 4;
		float dith = (BAYER[bi] + 0.5) / 16.0 - 0.5;
		float g = clamp(floor(lum * 5.0 + 0.5 + dith) / 5.0, 0.0, 1.0);
		rgb = tick ? (major > 0.5 ? GOLD_HI : GOLD) : vec3(g);
	}
	COLOR = vec4(rgb, 1.0);
}
