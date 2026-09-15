shader_type canvas_item;
render_mode unshaded;
uniform sampler2D occupancy : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(10.0);
uniform float opacity = 0.48;
uniform vec2 footprint_size = vec2(160.0);
varying vec2 stone_point;
void vertex() { stone_point = VERTEX; }
float stone(vec2 cell) {
	if (any(lessThan(cell,vec2(0.0))) || any(greaterThanEqual(cell,grid_size))) { return 0.0; }
	return texture(occupancy,(cell+0.5)/grid_size).r;
}
void fragment() {
	vec2 p = stone_point/footprint_size*grid_size;
	vec2 cell = floor(p);
	// 只在已破开的空格内绘制，完整砖和裂纹砖都保留原色。
	if (stone(cell)>0.5) { discard; }
	float nearest = 1.0;
	for (int y=-1;y<=1;y++) {
		for (int x=-1;x<=1;x++) {
			vec2 other = cell+vec2(float(x),float(y));
			if (stone(other)>0.5) {
				vec2 q = max(abs(p-(other+0.5))-0.5,vec2(0.0));
				nearest = min(nearest,length(q));
			}
		}
	}
	// 最近存留砖的真实边缘起算，一格距离淡出；交汇处不累加成黑块。
	COLOR = vec4(0.0,0.0,0.0,opacity*(1.0-smoothstep(0.0,1.0,nearest)));
}
