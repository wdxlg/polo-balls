shader_type canvas_item;
render_mode unshaded, blend_mix;

// Godot 2D port of Avaritia 1.12.2 cosmic.frag (Morpheus1101/Avaritia,
// d8cca83114cf831883b9a4c7734dd2d03ea6f485). Same 16 spherical layers,
// 10 native animated symbols, layer colours, density and 20 Hz animation.
// Only the camera ray and item mask are replaced by a 2D rift aperture.
// Source paths, hashes and atlas layout: av_cosmic_atlas.sources.json.
uniform sampler2D cosmic_atlas : filter_nearest, repeat_disable;
uniform vec2 cosmic_origin = vec2(0.0);
uniform float cosmic_time = 0.0;
uniform bool linear_output = false;
uniform float closure : hint_range(0.0, 1.0) = 1.0;
uniform float opening_progress : hint_range(0.0, 1.0) = 1.0;
uniform float opening_feather = 0.05;
varying float growth_coordinate;
// 穿障轨迹保持直线：各段出生时间 = 真实路程 / 箭速，不受帧分批或顶点色精度影响。
uniform bool sample_life_enabled = false;
uniform float sample_time = 0.0;
uniform float sample_open_ramp = 0.03;
uniform float sample_hold_time = 0.12;
uniform float sample_close_time = 0.16;
uniform vec2 sample_direction = vec2(1.0, 0.0);
uniform float sample_speed = 620.0;
// Only the portion outside the world map's visual mask is replayed at z91.
// Inside the map the aperture is behind characters, preserving their bodies.
uniform bool outside_only = false;
uniform int outside_count = 0;
uniform vec4 outside_rects[32];
// Sampled from av_bow_idle.png: #14534f, #83dbd6, silver/white bow limbs.
uniform vec4 bow_deep : source_color = vec4(0.078431, 0.325490, 0.309804, 1.0);
uniform vec4 bow_teal : source_color = vec4(0.513725, 0.858824, 0.839216, 1.0);
uniform vec4 bow_silver : source_color = vec4(0.784314, 0.784314, 0.784314, 1.0);

const float HALO_SCALE = 1.45;
varying float across_rift;
varying float half_width;
varying vec2 cosmic_plane;
varying vec2 aperture_world;
uniform float union_time = -1.0;
#include "res://shaders/heavenfall_union.gdshaderinc"

void vertex() {
	growth_coordinate = COLOR.g;
	float born = smoothstep(0.0, max(opening_feather, 0.0001), opening_progress - growth_coordinate);
	float aperture = closure * born;
	if (sample_life_enabled) {
		vec2 center = (MODEL_MATRIX * vec4(VERTEX - UV, 0.0, 1.0)).xy;
		float opened = max(dot(center - cosmic_origin, sample_direction), 0.0) / max(sample_speed, 1.0);
		float local_age = sample_time - opened;
		float ramp = max(sample_open_ramp, 0.0001);
		float seal_start = ramp + max(sample_hold_time, 0.0);
		// smoothstep 缓动：张开与收口两端减速，消除线性速率的速度突变。
		float grown = smoothstep(0.0, ramp, local_age);
		float shutting = 1.0 - smoothstep(seal_start, seal_start + max(sample_close_time, 0.0001), local_age);
		aperture *= min(grown, shutting);
	}
	across_rift = (COLOR.r * 2.0 - 1.0) * HALO_SCALE;
	half_width = length(UV) / HALO_SCALE * aperture;
	// UV contains a signed normal offset, not an image UV. Zero-width tips
	// stay at the exact path endpoint at every stage of closing.
	VERTEX -= UV * (1.0 - aperture);
	aperture_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	// All rifts look into one stationary universe, even across separate impacts.
	cosmic_plane = aperture_world / 180.0;
	COLOR = vec4(1.0);
}

#include "res://shaders/heavenfall_cosmic_common.gdshaderinc"

void fragment() {
	if (opening_progress <= 0.0 || growth_coordinate >= opening_progress) { discard; }
	if (outside_only) {
		vec2 p = aperture_world;
		bool outside = false;
		for (int i = 0; i < 32; i++) {
			if (i >= outside_count) { break; }
			vec4 r = outside_rects[i];
			if (p.x >= r.x && p.y >= r.y && p.x <= r.z && p.y <= r.w) {
				outside = true;
				break;
			}
		}
		if (!outside) { discard; }
	}
	if (half_width <= 0.0001) {
		discard;
	}
	float distance_from_center = abs(across_rift) * half_width;
	float aa = max(fwidth(distance_from_center) * 0.65, 0.12);
	float rim_width = min(0.85, half_width * 0.28);
	float inner_radius = max(half_width - rim_width, 0.0001);
	// Both masks go to zero INSIDE their boundary. Stars never contribute
	// to the rim or halo, including the last pixel of a narrowing tail.
	float interior = 1.0 - smoothstep(max(inner_radius - aa, 0.0), inner_radius, distance_from_center);
	float body = 1.0 - smoothstep(max(half_width - aa, 0.0), half_width, distance_from_center);
	float halo = pow(clamp((HALO_SCALE - abs(across_rift)) / (HALO_SCALE - 1.0), 0.0, 1.0), 2.0) * 0.13;
	vec2 joined = union_coverage(aperture_world, aa);
	interior = max(interior, joined.x);
	body = max(body, joined.y);
	vec3 rim = mix(bow_teal.rgb, bow_silver.rgb, 0.20);
	vec3 rgb = mix(bow_deep.rgb, rim, body);
	if (interior > 0.0) {
		rgb = mix(rgb, cosmic_colour_at(cosmic_plane, union_time >= 0.0 ? union_time : cosmic_time), interior);
	}
	// Alpha is coverage only: closing cannot fade or dim the universe.
	COLOR = vec4(rgb, max(body, halo));
}
