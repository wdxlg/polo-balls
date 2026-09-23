shader_type canvas_item;
render_mode unshaded;
uniform float scroll = 0.0;
uniform float tiles = 1.0;
varying vec4 vertex_tint;
void vertex() { vertex_tint = COLOR; }
void fragment() {
	// UV scroll repeats the authentic 16x16 texture along world-space height,
	// rather than stretching/smearing one tile over the whole column.
	vec2 uv = vec2(UV.x, fract(UV.y * tiles + scroll));
	COLOR = texture(TEXTURE, uv) * vertex_tint;
}
