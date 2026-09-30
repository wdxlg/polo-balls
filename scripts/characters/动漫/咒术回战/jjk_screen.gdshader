shader_type canvas_item;
// 咒术回战全屏后处理（纯视觉）：动画冲击帧（黑白二值/反相/双色）、集中线、径向模糊、色差、去色、色调、暗角、闪光。
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 center = vec2(0.5);
uniform vec2 aspect = vec2(1.7778, 1.0);
uniform float time = 0.0;
uniform float blur = 0.0;
uniform float aberration = 0.0;
uniform float desat = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float vignette = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
// 冲击帧：impact=1 时整屏按亮度二值化为 dark/light 双色；threshold 为分界亮度。
uniform float impact = 0.0;
uniform float threshold = 0.42;
uniform vec4 dark : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 集中线（屏幕空间）
uniform float lines = 0.0;
uniform vec4 lines_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float lines_inner = 0.28;

float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	vec3 col = vec3(0.0);
	if (blur > 0.0005 || aberration > 0.0005) {
		float jitter = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453) / 12.0;
		for (int i = 0; i < 12; i++) {
			float s = 1.0 - blur * (float(i) / 11.0 + jitter) * smoothstep(0.0, 0.25, length(d));
			vec2 u = center + d * s;
			col.r += texture(screen_tex, clamp(u + d * aberration, vec2(0.0), vec2(1.0))).r;
			col.g += texture(screen_tex, clamp(u, vec2(0.0), vec2(1.0))).g;
			col.b += texture(screen_tex, clamp(u - d * aberration, vec2(0.0), vec2(1.0))).b;
		}
		col /= 12.0;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l), desat);
	col = mix(col, col * tint.rgb * 1.6, tint.a);
	if (impact > 0.001) {
		// 二值化：边缘 1 像素软化，避免锯齿闪烁
		float w = max(fwidth(l), 0.002);
		float b = smoothstep(threshold - w, threshold + w, l);
		vec3 duo = mix(dark.rgb, light.rgb, b);
		col = mix(col, duo, impact);
	}
	if (lines > 0.001) {
		vec2 q = d * aspect;
		float r = length(q);
		float a = atan(q.y, q.x);
		float bs = floor(time * 24.0);
		float n = 110.0;
		float u = a / 6.28318 * n;
		float fi = floor(u);
		float h1 = hash11(fi * 1.7 + bs * 11.0);
		float h2 = hash11(fi * 3.1 + bs * 5.0);
		float on = step(0.35, hash11(fi * 0.7 + bs * 2.0));
		float start = lines_inner + h1 * 0.35;
		float t = clamp((r - start) / 0.6, 0.0, 1.0);
		float hw = (0.12 + 0.3 * h2) * t;
		float ad = abs(fract(u) - 0.5) - hw * 0.5;
		float pxd = ad * 6.28318 / n * r;
		float cv = clamp(0.5 - pxd / max(fwidth(pxd), 0.00001), 0.0, 1.0) * on * step(start, r);
		col = mix(col, lines_color.rgb, cv * lines * lines_color.a);
	}
	float v = smoothstep(0.3, 0.85, length(d * vec2(1.0, 0.8)));
	col *= 1.0 - vignette * v;
	col = mix(col, flash_color.rgb, flash_color.a);
	COLOR = vec4(col, 1.0);
}
