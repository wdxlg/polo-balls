shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Samples the FINISHED world (after characters and the map's own visual mask).
// No opacity erasure, background substitution, tint or additive fog.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float closure : hint_range(0.0, 1.0) = 1.0;
uniform float opening_progress : hint_range(0.0, 1.0) = 1.0;
uniform float opening_feather = 0.05;
varying float growth_coordinate;
uniform float rift_time = 0.0;
uniform float warp_strength : hint_range(0.0, 8.0) = 5.0;
uniform float root_half_width = 2.0;
uniform int segment_count = 0;
uniform vec4 aperture_segments[128];
uniform vec2 aperture_widths[128];

varying float across_rift;
varying float support_radius;
varying float half_width;
varying vec2 normal_pixels;
varying vec2 normal_world;
varying vec2 world_position;
#include "res://shaders/heavenfall_union.gdshaderinc"

void vertex() {
	growth_coordinate = COLOR.g;
	float born = smoothstep(0.0, max(opening_feather, 0.0001), opening_progress - growth_coordinate);
	float aperture = closure * born;
	float side = COLOR.r * 2.0 - 1.0;
	across_rift = side;
	support_radius = length(UV) * aperture;
	half_width = COLOR.a * root_half_width * aperture;
	vec2 normal = length(UV) > 0.0001 ? normalize(UV) * side : vec2(0.0, 1.0);
	normal_pixels = (CANVAS_MATRIX * MODEL_MATRIX * vec4(normal, 0.0, 0.0)).xy;
	normal_world = (MODEL_MATRIX * vec4(normal, 0.0, 0.0)).xy;
	VERTEX -= UV * (1.0 - aperture);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	COLOR = vec4(1.0);
}

bool touches_aperture(vec2 point) {
	// Protect neighbouring impacts/pierce cracks too, not only this rift.
	if (union_coverage(point, 0.12).y > 0.001) { return true; }
	for (int i = 0; i < 128; i++) {
		if (i >= segment_count) { break; }
		vec4 segment = aperture_segments[i];
		vec2 ray = segment.zw - segment.xy;
		float t = clamp(dot(point - segment.xy, ray) / max(dot(ray, ray), 0.00001), 0.0, 1.0);
		vec2 delta = point - (segment.xy + ray * t);
		float radius = mix(aperture_widths[i].x, aperture_widths[i].y, t) * closure * 1.55 + 0.65;
		if (dot(delta, delta) < radius * radius) { return true; }
	}
	return false;
}

void fragment() {
	if (opening_progress <= 0.0 || growth_coordinate >= opening_progress) { discard; }
	if (support_radius <= 0.0001) { discard; }
	float distance_from_center = abs(across_rift) * support_radius;
	float outside = smoothstep(half_width + 0.7, half_width + 2.0, distance_from_center);
	float reach = max(support_radius - half_width, 0.001);
	float band = clamp((distance_from_center - half_width) / reach, 0.0, 1.0);
	float envelope = outside * (1.0 - smoothstep(0.05, 1.0, band));
	float aperture_weight = clamp(half_width / max(root_half_width, 0.001), 0.0, 1.0);
	float pulse = sin(dot(world_position, vec2(0.14, 0.09)) - rift_time * 2.6);
	float curl = sin(dot(world_position, vec2(-0.08, 0.16)) + rift_time * 1.9);
	float amount = warp_strength * sqrt(aperture_weight) * envelope;
	vec2 flow = vec2(sign(across_rift) * (0.76 + 0.24 * pulse), curl * 0.22) * amount;
	vec2 displacement_world = normal_world * flow.x + vec2(-normal_world.y, normal_world.x) * flow.y;
	vec2 displacement_pixels = normal_pixels * flow.x + vec2(-normal_pixels.y, normal_pixels.x) * flow.y;
	// The current and sampled pixel must both be outside every opening. Thus
	// refraction bends actors/background, never smears a neighbouring starfield.
	// Leave the actual aperture untouched rather than drawing a zero-displacement
	// SCREEN_TEXTURE sample over it. Shared recording viewports may have a
	// different backbuffer copy rectangle from the main window; that sample can
	// otherwise paint old background over the fracture's cosmic interior.
	if (touches_aperture(world_position)) { discard; }
	if (amount < 0.0001 || touches_aperture(world_position + displacement_world)) {
		displacement_pixels = vec2(0.0);
	}
	vec2 half_pixel = SCREEN_PIXEL_SIZE * 0.5;
	vec2 sample_uv = clamp(SCREEN_UV + displacement_pixels * SCREEN_PIXEL_SIZE, half_pixel, vec2(1.0) - half_pixel);
	COLOR = texture(screen_texture, sample_uv);
}
