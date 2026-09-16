shader_type canvas_item;
render_mode unshaded;
uniform sampler2D ground_regions : filter_nearest, repeat_disable;
uniform int ground_count = 0;
varying vec2 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy; }
void fragment() {
	bool inside = false;
	for (int i=0;i<ground_count;i++) {
		vec4 r = texelFetch(ground_regions,ivec2(i,0),0);
		if (all(greaterThanEqual(world_point,r.xy)) && all(lessThan(world_point,r.zw))) { inside=true; break; }
	}
	if (!inside) { discard; }
}
