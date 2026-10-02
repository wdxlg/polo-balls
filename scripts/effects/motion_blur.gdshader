shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 view_size = vec2(1080.0, 1920.0);
uniform int object_count = 0;
uniform vec4 objects[64];
uniform float radii[64];
uniform vec2 cam_x = vec2(1.0, 0.0);
uniform vec2 cam_y = vec2(0.0, 1.0);
uniform vec2 cam_o = vec2(0.0);
uniform float cam_threshold = 1e9;
uniform float shutter = 0.5;
uniform float ramp = 1.25;
uniform float max_blur = 192.0;

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(p - a - ab * t);
}

void fragment() {
	vec2 p = UV * view_size;
	vec2 units_per_pixel = vec2(abs(dFdx(p.x)), abs(dFdy(p.y)));
	vec2 uv_per_unit = SCREEN_PIXEL_SIZE / max(units_per_pixel, vec2(1e-6));
	vec2 blur = vec2(0.0);
	float best = -1.0;
	for (int i = 0; i < 64; i++) {
		if (i >= object_count) break;
		vec4 o = objects[i];
		if (segment_distance(p, o.xy - o.zw * 0.5, o.xy + o.zw * 0.5) <= radii[i]) {
			float l = length(o.zw);
			if (l > best) { best = l; blur = o.zw; }
		}
	}
	if (best < 0.0) {
		vec2 motion = p - (cam_x * p.x + cam_y * p.y + cam_o);
		blur = motion * shutter * smoothstep(cam_threshold, cam_threshold * ramp, length(motion));
	}
	float len = length(blur);
	if (len > max_blur) { blur *= max_blur / len; }
	vec2 blur_uv = blur * uv_per_unit;
	float pixels = length(blur_uv / SCREEN_PIXEL_SIZE);
	if (pixels < 0.75) {
		COLOR = vec4(textureLod(screen_tex, SCREEN_UV, 0.0).rgb, 1.0);
	} else {
		int samples = clamp(int(ceil(pixels)), 3, 32);
		vec3 sum = vec3(0.0);
		for (int k = 0; k < 32; k++) {
			if (k >= samples) break;
			float s = (float(k) + 0.5) / float(samples) - 0.5;
			sum += textureLod(screen_tex, SCREEN_UV - blur_uv * s, 0.0).rgb;
		}
		COLOR = vec4(sum / float(samples), 1.0);
	}
}
