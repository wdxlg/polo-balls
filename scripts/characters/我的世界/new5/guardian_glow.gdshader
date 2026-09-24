shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float glow_strength=0.0;
varying vec4 glow_color;
void vertex() { glow_color=COLOR; }
void fragment() {
	float edge=clamp(1.0-abs(UV.y*2.0-1.0),0.0,1.0);
	float falloff=edge*edge;
	COLOR=vec4(glow_color.rgb,glow_color.a*falloff*glow_strength);
}
