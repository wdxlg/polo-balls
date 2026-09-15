shader_type canvas_item;

// V162 若叶睦盆栽成长揭示：通过 progress 连续揭示像素，避免阶段贴图硬切。
// reveal 由脚本按真实生长进度驱动；opacity 用于相邻阶段柔和交叠。
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float edge_softness : hint_range(0.001, 0.25) = 0.055;
uniform float noise_amount : hint_range(0.0, 0.45) = 0.16;
uniform vec4 edge_tint : source_color = vec4(0.55, 1.0, 0.64, 1.0);
uniform float edge_glow : hint_range(0.0, 1.0) = 0.18;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 从下向上生长，叠加细小噪声让轮廓不是整齐水平切开。
	float n = hash21(floor(UV * vec2(96.0, 96.0)));
	float score = UV.y * (1.0 - noise_amount) + n * noise_amount;
	float threshold = 1.0 - clamp(reveal, 0.0, 1.0);
	float mask = smoothstep(threshold - edge_softness, threshold + edge_softness, score);
	float edge = 1.0 - smoothstep(edge_softness, edge_softness * 2.4, abs(score - threshold));
	vec3 rgb = mix(tex.rgb, edge_tint.rgb, edge * edge_glow * (1.0 - step(0.999, reveal)));
	COLOR = vec4(rgb, tex.a * mask * opacity);
}
