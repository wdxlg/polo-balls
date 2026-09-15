shader_type canvas_item;
render_mode unshaded;

uniform vec4 base_color : source_color = vec4(0.04, 0.24, 0.82, 0.97);
uniform vec4 deep_color : source_color = vec4(0.004, 0.012, 0.055, 0.98);
uniform float flow_speed : hint_range(0.0, 2.0, 0.01) = 0.18;
uniform float flow_direction : hint_range(-1.0, 1.0, 1.0) = 1.0;
uniform float noise_scale : hint_range(0.5, 4.0, 0.05) = 1.0;
uniform vec2 local_origin = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(120.0, 26.0);
uniform float dark_strength : hint_range(0.0, 1.0, 0.01) = 0.86;
// 控制暗色主体的面积。它不是简单加黑，而是改变大片暗流的出现阈值。
uniform float dark_coverage : hint_range(0.0, 1.0, 0.01) = 0.70;

vec2 hash22(vec2 p) {
	vec2 q = vec2(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3))
	);
	return -1.0 + 2.0 * fract(sin(q) * 43758.5453123);
}

// 五次平滑梯度噪声，边界连续，避免方块和颗粒跳动。
float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float n00 = dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float n10 = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n01 = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n11 = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));

	float nx0 = mix(n00, n10, u.x);
	float nx1 = mix(n01, n11, u.x);
	return clamp(0.5 + 0.5 * mix(nx0, nx1, u.y), 0.0, 1.0);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.54;
	float weight = 0.0;
	mat2 rotation = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));

	for (int i = 0; i < 5; i++) {
		value += gradient_noise(p) * amplitude;
		weight += amplitude;
		p = rotation * p * 2.01 + vec2(17.13, 9.71);
		amplitude *= 0.50;
	}
	return value / max(weight, 0.0001);
}

void fragment() {
	float direction = flow_direction < 0.0 ? -1.0 : 1.0;
	float t = TIME * flow_speed;

	// 使用整根理智条的局部像素坐标，填充宽度变化时纹理不会伸缩。
	vec2 local_px = local_origin + UV * rect_size;
	// 主体频率进一步降低并横向拉长：得到大块、连贯的墨流，而不是碎噪点。
	vec2 p = vec2(local_px.x * 0.017, local_px.y * 0.045) * noise_scale;

	// 只给非常轻的整体漂移。主要运动来自下面两级随时间变化的域扭曲。
	vec2 q0 = p + vec2(t * 0.07 * direction, 0.0);
	vec2 warp_space = q0 * 0.58;

	vec2 q1 = vec2(
		fbm(warp_space + vec2(1.7 + t * 0.055 * direction, 3.1 + t * 0.075)),
		fbm(warp_space + vec2(-5.2 - t * 0.045 * direction, 7.9 - t * 0.065))
	) - vec2(0.5);

	// 第二级扭曲依赖第一级的结果，暗流轮廓会自己卷动、合并和分离，
	// 不再像一张噪声贴图从左往右滑。
	vec2 q2 = vec2(
		fbm(q0 * 0.82 + q1 * 2.40 + vec2(8.3 + t * 0.040 * direction, -2.0 - t * 0.090)),
		fbm(q0 * 0.82 + q1 * 2.40 + vec2(-6.4 - t * 0.035 * direction, 4.6 + t * 0.080))
	) - vec2(0.5);

	vec2 warped = q0 + q1 * 2.50 + q2 * 1.30;

	// 两个很低频的主体场叠加。第二层只负责改变大轮廓，不制造细碎纹理。
	float body_a = fbm(warped * 0.67 + vec2(t * 0.17 * direction, t * 0.025));
	float body_b = fbm((warped + q1 * 0.80) * 0.48 + vec2(-t * 0.075 * direction, 5.4 + t * 0.040));
	float body = body_a * 0.72 + body_b * 0.28;

	// dark_coverage 越大，阈值越低，大片暗色区域越多。
	float lower = 0.460 - dark_coverage * 0.150;
	float upper = lower + 0.220;
	float mass = smoothstep(lower, upper, body);
	// 略微扩张中间灰阶，让暗区更厚、更连续，同时保留柔和边缘。
	mass = pow(mass, 0.72);

	// 只增加一层更深的内部核心，尺度依然很大；不使用 ridged 高频细丝。
	float core_field = fbm(warped * 0.93 + q2 * 1.10 + vec2(t * 0.12 * direction, -4.2 - t * 0.045));
	float core = smoothstep(0.47, 0.69, core_field) * smoothstep(0.15, 0.74, mass);

	float dark_mask = clamp(mass * 0.86 + core * 0.32, 0.0, 1.0);
	vec3 rgb = mix(base_color.rgb, deep_color.rgb, dark_mask * dark_strength);
	COLOR = vec4(rgb, base_color.a);
}
