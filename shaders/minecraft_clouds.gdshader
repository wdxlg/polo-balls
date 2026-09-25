shader_type canvas_item;
render_mode unshaded;

// Original Java clouds.png occupancy, not noise or hand-authored cloud silhouettes.
uniform sampler2D cloud_mask : filter_nearest, repeat_enable;
uniform float cell_size = 48.0; // Java fancy cloud cell 12 blocks, adapted at 4 world px/block.
uniform float travel = 0.0;
uniform vec2 height_shift = vec2(-8.0, -16.0); // Extruded slab: 4 blocks thick.
uniform float cloud_alpha : hint_range(0.0, 1.0) = 0.8;
varying vec2 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

bool occupied(vec2 cell) {
	vec2 size = vec2(textureSize(cloud_mask, 0));
	return textureLod(cloud_mask, (cell + vec2(0.5)) / size, 0.0).a > 0.5;
}

void fragment() {
	// Exact orthographic ray through a single-height voxel slab. At this height
	// a ray can cross at most two grid boundaries; no per-cloud nodes or 3D viewport.
	vec2 origin = (world_point + vec2(travel, 0.0) - height_shift) / cell_size;
	vec2 ray = height_shift / cell_size;
	vec2 cell = floor(origin);
	vec2 step_dir = sign(ray);
	vec2 stride = vec2(1.0) / max(abs(ray), vec2(0.00001));
	vec2 boundary = cell + step(vec2(0.0), ray);
	vec2 next_hit = abs(boundary - origin) * stride;
	bool hit = occupied(cell);
	float face_light = 1.0;
	for (int i = 0; i < 3; i++) {
		if (hit) { break; }
		if (min(next_hit.x, next_hit.y) > 1.0) { break; }
		if (next_hit.x < next_hit.y) {
			cell.x += step_dir.x;
			next_hit.x += stride.x;
			face_light = 0.9;
		} else {
			cell.y += step_dir.y;
			next_hit.y += stride.y;
			face_light = 0.8;
		}
		hit = occupied(cell);
	}
	COLOR = hit ? vec4(vec3(face_light), cloud_alpha) : vec4(0.0);
}
