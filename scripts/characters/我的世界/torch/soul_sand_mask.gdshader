shader_type canvas_item;
// Soul sand pixel coverage: TEXTURE is an L8 mask chunk (one texel per soul sand texture pixel);
// covered texels show the tiled vanilla soul_sand.png, the rest stays transparent.
// source_color: the project uses hdr_2d, so the sRGB texture must be linearized like built-in TEXTURE draws.
uniform sampler2D sand_texture : source_color, filter_nearest, repeat_enable;
uniform float cells_per_chunk = 8.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float covered = step(0.5, texture(TEXTURE, UV).r);
	vec4 sand = texture(sand_texture, fract(UV * cells_per_chunk));
	COLOR = vec4(sand.rgb, sand.a * covered) * tint;
}
