shader_type canvas_item;
render_mode unshaded;
uniform vec2 spread_size = vec2(16.0);
uniform float opacity : hint_range(0.0,1.0) = 0.36;
uniform sampler2D islands : filter_nearest, repeat_disable;
uniform int island_count = 0;
uniform sampler2D cutouts : filter_nearest, repeat_disable;
uniform int cutout_count = 0;
varying vec2 local_point;
void vertex() { local_point = VERTEX; }
float box_distance(vec2 p, vec2 start, vec2 size) {
	vec2 q = abs(p-start-size*0.5)-size*0.5;
	return length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0);
}
void fragment() {
	vec2 scale = max(spread_size,vec2(0.001));
	vec2 p = local_point/scale;
	float distance_from_edge = 1.0;
	// 每岛先扣掉自己的门洞，再取所有实心轮廓的并集；整片只混合一次。
	// 因此同一格宽连接处不会叠出双倍暗影，内部接缝也不再向另一岛投影。
	for (int i=0;i<island_count;i++) {
		float u = (float(i)+0.5)/float(island_count);
		vec4 shape = texture(islands,vec2(u,0.25));
		vec2 cut_range = texture(islands,vec2(u,0.75)).xy;
		float d = box_distance(p,shape.xy/scale,shape.zw/scale);
		// 不可能影响当前像素的岛不必遍历其门洞。
		if (d>=distance_from_edge) { continue; }
		for (int j=0;j<int(cut_range.y);j++) {
			vec4 cut = texture(cutouts,vec2((cut_range.x+float(j)+0.5)/float(max(cutout_count,1)),0.5));
			d = max(d,-box_distance(p,cut.xy/scale,cut.zw/scale));
			if (d>=distance_from_edge) { break; }
		}
		distance_from_edge = min(distance_from_edge,d);
	}
	if (distance_from_edge<=0.0) { discard; }
	float a = opacity*(1.0-smoothstep(0.0,1.0,distance_from_edge));
	COLOR = vec4(0.0,0.0,0.0,a);
}
