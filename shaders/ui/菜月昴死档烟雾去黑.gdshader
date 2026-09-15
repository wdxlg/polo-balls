shader_type canvas_item;
render_mode unshaded, blend_mix;

// V401：给 TextureRect 显示的视频当前帧做黑底 soft-key。
// 单层 alpha 仍低，但拉开“透明背景 / 烟体核心”的对比，避免 V400 低 alpha 下整段雾肉眼不可见。
uniform vec4 fog_tint : source_color = vec4(0.18, 0.04, 0.24, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.060;
uniform float black_cutoff : hint_range(0.0, 0.15) = 0.016;
uniform float softness : hint_range(0.02, 0.30) = 0.075;
uniform float pulse_phase : hint_range(0.0, 6.283185) = 0.0;
uniform float pulse_speed : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luma = dot(source.rgb, vec3(0.299, 0.587, 0.114));

	// 黑背景快速归零，但保留很暗的烟丝；核心区域获得更清楚的 alpha 层次。
	float mask = smoothstep(black_cutoff, black_cutoff + softness, luma);
	mask = pow(clamp(mask, 0.0, 1.0), 0.62);
	float core = smoothstep(black_cutoff + softness * 0.20, black_cutoff + softness * 2.35, luma);
	core = pow(clamp(core, 0.0, 1.0), 0.72);

	// 颜色仍是黑灰 -> 深紫，不做发光紫；但核心 RGB 对比比 V400 更强，低 alpha 下仍能辨认雾形。
	vec3 dark_gray = vec3(0.018, 0.019, 0.024);
	vec3 purple_body = clamp(fog_tint.rgb * 1.85 + vec3(0.035, 0.025, 0.040), vec3(0.0), vec3(0.62));
	vec3 smoke_color = mix(dark_gray, purple_body, 0.30 + core * 0.70);
	float alpha_shape = mask * mix(0.42, 1.0, core);
	float pulse = 0.93 + 0.07 * sin(TIME * pulse_speed + pulse_phase);

	COLOR = vec4(smoke_color, alpha_shape * opacity * pulse * source.a);
}
