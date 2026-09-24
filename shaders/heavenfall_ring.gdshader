shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform sampler2D cosmic_atlas : filter_nearest, repeat_disable;
uniform vec2 cosmic_origin = vec2(0.0);
uniform float cosmic_time = 0.0;
uniform bool linear_output = false;
uniform float radius = 95.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
varying vec2 local_point;
varying vec2 cosmic_plane;
#include "res://shaders/heavenfall_cosmic_common.gdshaderinc"
void vertex() {
	local_point = VERTEX;
	cosmic_plane = ((MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - cosmic_origin) / 180.0;
}
void fragment() {
	// Same 3-world-pixel grid as the original mace's pixel_arc.gd. Stars are
	// strictly INSIDE its innermost band; the rim and external rays have none.
	vec2 cell = (floor(local_point / 3.0) + vec2(0.5)) * 3.0;
	if (length(cell) >= max(radius - 1.5, 0.0) || opacity <= 0.0) { discard; }
	COLOR = vec4(cosmic_colour(cosmic_plane), opacity);
}
