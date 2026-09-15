shader_type canvas_item;
render_mode unshaded;
uniform vec2 footprint_size = vec2(160.0);
uniform vec2 spread_size = vec2(16.0);
uniform float opacity : hint_range(0.0,1.0) = 0.36;
varying vec2 local_point;
void vertex() { local_point = VERTEX; }
void fragment() {
	vec2 q = abs(local_point-footprint_size*0.5)-footprint_size*0.5;
	// 渐变从可见轮廓外缘开始，内部完全不绘制，不能提前在被地图遮住的部分消耗渐变。
	if (max(q.x,q.y)<=0.0) { discard; }
	float distance_from_edge = length(max(q,vec2(0.0))/max(spread_size,vec2(0.001)));
	float a = opacity*(1.0-smoothstep(0.0,1.0,distance_from_edge));
	COLOR = vec4(0.0,0.0,0.0,a);
}
