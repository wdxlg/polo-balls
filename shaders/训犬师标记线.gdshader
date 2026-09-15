shader_type canvas_item;
render_mode unshaded;

// V206：纯红虚线整体向前流动，动态线长只裁剪几何，不参与相位。
// dash/gap 永远按固定世界像素周期运行，所以目标距离变化不会导致整条虚线重排、压缩或跳相位。
uniform float dash_length : hint_range(3.0, 30.0) = 10.0;
uniform float gap_length : hint_range(2.0, 24.0) = 6.0;
uniform float flow_speed_pixels : hint_range(0.0, 180.0) = 46.0;

varying float line_local_x;

void vertex() {
	// MarkLine 是水平线；abs() 让左右朝向都以“从训犬师向外”为正方向。
	line_local_x = abs(VERTEX.x);
}

void fragment() {
	float safe_dash = max(dash_length, 1.0);
	float safe_gap = max(gap_length, 0.0);
	float period = max(safe_dash + safe_gap, 1.0);

	// 相位只依赖固定 dash 周期与 TIME。f(x-vt) 让整套虚线沿前方连续移动。
	// Line2D 末端变化只裁掉/露出末端像素；新虚线会按同一周期从起点进入，视觉上持续循环。
	float cell = mod(line_local_x - TIME * flow_speed_pixels, period);
	if (cell < 0.0) {
		cell += period;
	}
	float edge = min(0.65, safe_dash * 0.18);
	float dash_mask = 1.0 - smoothstep(safe_dash - edge, safe_dash + edge, cell);

	vec4 out_color = COLOR;
	out_color.rgb = vec3(1.0, 0.0, 0.0);
	out_color.a *= dash_mask;
	COLOR = out_color;
}
