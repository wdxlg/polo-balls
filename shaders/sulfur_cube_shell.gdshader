shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Preserve the ORIGINAL Mojang RGBA exactly. In particular the outer face
// contains actual transparent holes and dark facial pixels with their own
// alpha; replacing that alpha with a brightness threshold obscures the block.
uniform sampler2D native_atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 atlas_origin;
uniform vec2 atlas_span;

void fragment() {
	vec2 coord = atlas_origin + UV * atlas_span;
	vec4 native_pixel = texture(native_atlas, coord);
	ALBEDO = native_pixel.rgb;
	ALPHA = native_pixel.a;
}
