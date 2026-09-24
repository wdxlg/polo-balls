shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// Original Mojang UV atlas. Only the pale translucent body is see-through;
// the dark facial pixels stay opaque in front of the independently rendered
// inner block. No generated character texture is sampled in the live model.
uniform sampler2D native_atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 atlas_origin;
uniform vec2 atlas_span;
uniform float shell_opacity = 0.45;

void fragment() {
	vec2 coord = atlas_origin + UV * atlas_span;
	vec4 native_pixel = texture(native_atlas, coord);
	ALBEDO = native_pixel.rgb;
	float darkness = 1.0 - min(native_pixel.r, min(native_pixel.g, native_pixel.b));
	float face = smoothstep(0.55, 0.85, darkness);
	ALPHA = native_pixel.a * mix(shell_opacity, 0.98, face);
}
