shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float width = 8.0;
uniform float length = 100.0;
uniform float source_y = -1.0;
uniform float strength = 1.0;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	// A true additive, soft light halo, independent of textured surface shading.
	float radius = max(width, 0.1);
	float side = exp(-pow(local_position.x / (radius * 0.74), 2.0) * 1.7);
	float end_fade = 1.0 - smoothstep(source_y, source_y + radius * 0.65, local_position.y);
	float top_fade = smoothstep(-length, -length + min(radius * 0.4, length * 0.2), local_position.y);
	float shaft = side * end_fade * top_fade;
	vec2 source = (local_position - vec2(0.0, source_y)) / vec2(radius * 0.9, radius * 0.65);
	float ignition = exp(-dot(source, source) * 2.5);
	float light = (shaft * 0.42 + ignition * 0.4) * strength;
	COLOR = vec4(0.2, 0.68, 1.0, light);
}
