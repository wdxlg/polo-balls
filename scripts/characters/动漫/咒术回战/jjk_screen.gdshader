shader_type canvas_item;
// 咒术回战全屏后处理（纯视觉）：径向模糊、色差、反色、去色、色调、暗角、闪光。
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 center = vec2(0.5);
uniform float blur = 0.0;
uniform float aberration = 0.0;
uniform float invert = 0.0;
uniform float desat = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float vignette = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	vec3 col = vec3(0.0);
	// 16 次采样 + 抖动偏移，避免低采样的“重影”感。
	float jitter = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453) / 16.0;
	for (int i = 0; i < 16; i++) {
		float s = 1.0 - blur * (float(i) / 15.0 + jitter) * smoothstep(0.0, 0.25, length(d));
		vec2 u = center + d * s;
		col.r += texture(screen_tex, clamp(u + d * aberration, vec2(0.0), vec2(1.0))).r;
		col.g += texture(screen_tex, clamp(u, vec2(0.0), vec2(1.0))).g;
		col.b += texture(screen_tex, clamp(u - d * aberration, vec2(0.0), vec2(1.0))).b;
	}
	col /= 16.0;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l), desat);
	col = mix(col, vec3(1.0) - col, invert);
	col = mix(col, col * tint.rgb * 1.6, tint.a);
	float v = smoothstep(0.3, 0.85, length(d * vec2(1.0, 0.8)));
	col *= 1.0 - vignette * v;
	col = mix(col, flash_color.rgb, flash_color.a);
	COLOR = vec4(col, 1.0);
}
