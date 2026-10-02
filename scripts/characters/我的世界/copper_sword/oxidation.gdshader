shader_type canvas_item;
// Native sword alpha/bevel + unmodified vanilla copper-block oxidation textures.
// Oxidizing a sword is this character's custom mechanic, not a vanilla item variant.
instance uniform float rust_level : hint_range(0.0, 1.0) = 0.0;
instance uniform float sprite_flip_h : hint_range(0.0, 1.0) = 0.0;
instance uniform float power : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 hit_white_color : source_color = vec4(1.0);
instance uniform float defualt_color_mix : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 default_color : source_color = vec4(1.0);
instance uniform float snow_cold : hint_range(0.0, 1.0) = 0.0;
instance uniform vec2 snow_freeze_offset = vec2(0.0);
uniform sampler2D copper_clean : source_color, filter_nearest, repeat_disable;
uniform sampler2D copper_exposed : source_color, filter_nearest, repeat_disable;
uniform sampler2D copper_weathered : source_color, filter_nearest, repeat_disable;
uniform sampler2D copper_oxidized : source_color, filter_nearest, repeat_disable;
varying vec4 sprite_modulate;
#include "res://shaders/mc_enchant_glint.gdshaderinc"
void vertex() {
	VERTEX += snow_freeze_offset;
	sprite_modulate = COLOR;
}
void fragment() {
	vec2 uv = UV;
	if (sprite_flip_h > 0.5) uv.x = 1.0 - uv.x;
	vec4 original = texture(TEXTURE, uv);
	vec3 pigment = original.rgb;
	// Separate red copper pixels from the native yellow/brown wooden grip.
	bool metal = original.r - original.g > (original.g - original.b) * 1.3;
	if (metal && original.a > 0.0) {
		float shade = clamp(original.r / max(texture(copper_clean, uv).r, 0.001), 0.15, 1.7);
		vec3 exposed = texture(copper_exposed, uv).rgb * shade;
		vec3 weathered = texture(copper_weathered, uv).rgb * shade;
		vec3 oxidized = texture(copper_oxidized, uv).rgb * shade;
		float stage = clamp(rust_level, 0.0, 1.0) * 3.0;
		pigment = mix(pigment, exposed, clamp(stage, 0.0, 1.0));
		pigment = mix(pigment, weathered, clamp(stage - 1.0, 0.0, 1.0));
		pigment = mix(pigment, oxidized, clamp(stage - 2.0, 0.0, 1.0));
	}
	vec4 result = vec4(pigment, original.a) * sprite_modulate;
	result.rgb = mix(result.rgb, default_color.rgb, defualt_color_mix);
	result.rgb = mix(result.rgb, vec3(0.94, 0.98, 1.0), clamp(snow_cold, 0.0, 1.0) * 0.88);
	result.rgb = mix(result.rgb, hit_white_color.rgb, power);
	result.rgb += mc_enchant_glint_rgb(uv, TEXTURE_PIXEL_SIZE);
	COLOR = result;
}
