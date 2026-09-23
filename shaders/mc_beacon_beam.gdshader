shader_type canvas_item;
render_mode unshaded;
uniform float scroll = 0.0;
uniform float tiles = 1.0;
uniform bool faceted = false;
varying vec4 vertex_tint;
void vertex() { vertex_tint = COLOR; }
void fragment() {
	// Authentic nearest-filtered tile on each projected side, repeating vertically.
	vec2 uv = vec2(UV.x, fract(UV.y * tiles + scroll));
	vec4 texel = texture(TEXTURE, uv);
	// Narrow lit edges emphasize the corner without bleaching out face shading.
	float edge = faceted ? pow(1.0 - clamp(min(UV.x, 1.0 - UV.x) * 16.0, 0.0, 1.0), 2.0) : 0.0;
	COLOR = texel * vertex_tint;
	COLOR.rgb *= 1.0 + edge * 0.12;
	if (faceted) { COLOR.rgb += texel.rgb * vec3(0.035, 0.075, 0.12); }
}
