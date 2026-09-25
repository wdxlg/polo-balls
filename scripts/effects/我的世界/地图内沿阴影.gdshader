shader_type canvas_item;
render_mode unshaded;
uniform sampler2D segments : filter_nearest, repeat_disable;
uniform int segment_count = 0;
uniform vec2 footprint_size = vec2(160.0);
uniform vec2 spread_size = vec2(16.0);
uniform float opacity : hint_range(0.0,1.0) = 0.36;
uniform bool directional_enabled = false;
uniform vec2 shadow_vector = vec2(-24.0,24.0); // right/up light casts toward left/down
uniform float contact_opacity : hint_range(0.0,1.0) = 0.10;
varying vec2 local_point;
void vertex() { local_point = VERTEX; }
void fragment() {
	vec2 scale = max(spread_size,vec2(0.001));
	vec2 p = local_point/scale;
	float distance_from_edge = 1.0;
	float projected_shadow = 0.0;
	for (int i=0;i<segment_count;i++) {
		vec4 line = texture(segments,vec2((float(i)+0.5)/float(segment_count),0.5));
		vec2 a = line.xy/scale;
		vec2 b = line.zw/scale;
		vec2 ab = b-a;
		float t = clamp(dot(p-a,ab)/max(dot(ab,ab),0.000001),0.0,1.0);
		distance_from_edge = min(distance_from_edge,length(p-a-ab*t));
		if (directional_enabled) {
			// 线段与位移形成平行四边形；只在其内部、并且只在真实地面 polygon 上投影。
			// 使用世界坐标求交，避免非方格/缩放地图的方向被 spread_size 扭曲。
			vec2 v = line.zw-line.xy;
			vec2 r = local_point-line.xy;
			float det = v.x*shadow_vector.y-v.y*shadow_vector.x;
			if (abs(det)>0.00001) {
				float along = (r.x*shadow_vector.y-r.y*shadow_vector.x)/det;
				float depth = (v.x*r.y-v.y*r.x)/det;
				if (along>=0.0 && along<=1.0 && depth>=0.0 && depth<=1.0) {
					float end_fade = smoothstep(0.0,2.0,along*length(v))*smoothstep(0.0,2.0,(1.0-along)*length(v));
					float softness = 1.0-smoothstep(0.22,1.0,depth);
					projected_shadow = max(projected_shadow,opacity*end_fade*softness);
				}
			}
		}
	}
	// max 合成：相邻边在转角处不会双倍叠黑；门洞处没有不存在的墙投影。
	float ambient = directional_enabled ? contact_opacity*(1.0-smoothstep(0.0,0.55,distance_from_edge)) : 0.0;
	float a = directional_enabled ? max(ambient,projected_shadow) : opacity*(1.0-smoothstep(0.0,1.0,distance_from_edge));
	COLOR = vec4(0.0,0.0,0.0,a);
}
