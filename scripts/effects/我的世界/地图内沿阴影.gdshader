shader_type canvas_item;
render_mode unshaded;
uniform sampler2D segments : filter_nearest, repeat_disable;
uniform int segment_count = 0;
uniform vec2 footprint_size = vec2(160.0);
uniform vec2 spread_size = vec2(16.0);
uniform float opacity : hint_range(0.0,1.0) = 0.36;
varying vec2 local_point;
void vertex() { local_point = VERTEX; }
void fragment() {
	vec2 scale = max(spread_size,vec2(0.001));
	vec2 edge = min(local_point,footprint_size-local_point)/scale;
	if (min(edge.x,edge.y)>=1.0) { discard; }
	vec2 p = local_point/scale;
	float distance_from_edge = 1.0;
	for (int i=0;i<segment_count;i++) {
		vec4 line = texture(segments,vec2((float(i)+0.5)/float(segment_count),0.5));
		vec2 a = line.xy/scale;
		vec2 b = line.zw/scale;
		vec2 ab = b-a;
		float t = clamp(dot(p-a,ab)/max(dot(ab,ab),0.000001),0.0,1.0);
		distance_from_edge = min(distance_from_edge,length(p-a-ab*t));
	}
	// 与地图整体外沿阴影完全相同的距离衰减；整片只混合一次。
	float a = opacity*(1.0-smoothstep(0.0,1.0,distance_from_edge));
	COLOR = vec4(0.0,0.0,0.0,a);
}
