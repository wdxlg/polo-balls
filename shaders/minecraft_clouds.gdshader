shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/summit_battle_focus.gdshaderinc"

// Native footprint parallel to the 2D battlefield, no oblique perspective.
// Approved flat-view adaptation; this is not a full Minecraft sky renderer.
uniform sampler2D cloud_mask : filter_nearest, repeat_enable;
uniform float cell_size = 32.0;
uniform float plane_depth : hint_range(1.0, 1.0) = 1.0;
// Ratios above 1 move clouds farther than the projected camera pan.
uniform float parallax : hint_range(0.0, 2.0) = 1.25;
uniform float travel = 0.0;
uniform vec2 height_shift = vec2(0.0, 10.6666667);
uniform float cloud_alpha : hint_range(0.0, 1.0) = 1.0;
varying vec2 world_point;
varying vec2 view_center_world;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	// Per-view camera, not a main-window uniform: recording/overview may have
	// different centers and zoom. NDC origin is the center of this viewport.
	vec4 center = inverse(CANVAS_MATRIX) * inverse(SCREEN_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0);
	view_center_world = center.xy / center.w;
}

bool occupied(vec2 cell) {
	vec2 size = vec2(textureSize(cloud_mask, 0));
	return textureLod(cloud_mask, (cell + vec2(0.5)) / size, 0.0).a > 0.5;
}

void fragment() {
	// Uncompressed horizontal footprint: square cells, no taper, no shear.
	// A straight lower edge provides thickness without tilting the cloud plane.
	vec2 plane_cell = vec2(cell_size, cell_size * plane_depth);
	vec2 sky_point = world_point - view_center_world * (1.0 - parallax);
	vec2 origin = (sky_point + vec2(travel, 0.0)) / plane_cell;
	vec2 ray = -height_shift / plane_cell;
	vec2 cell = floor(origin);
	vec2 step_dir = sign(ray);
	vec2 stride = vec2(1.0) / max(abs(ray), vec2(0.00001));
	vec2 boundary = cell + step(vec2(0.0), ray);
	vec2 next_hit = abs(boundary - origin) * stride;
	if (abs(ray.x) < 0.00001) { next_hit.x = 1e20; }
	if (abs(ray.y) < 0.00001) { next_hit.y = 1e20; }
	bool hit = occupied(cell);
	float face_light = 1.0;
	for (int i = 0; i < 3; i++) {
		if (hit) { break; }
		if (min(next_hit.x, next_hit.y) > 1.0) { break; }
		if (next_hit.x < next_hit.y) {
			cell.x += step_dir.x;
			next_hit.x += stride.x;
			face_light = 0.75;
		} else {
			cell.y += step_dir.y;
			next_hit.y += stride.y;
			face_light = 0.70;
		}
		hit = occupied(cell);
	}
	COLOR = hit ? vec4(summit_focus_grade(vec3(face_light), world_point, 3.0), cloud_alpha) : vec4(0.0);
}
