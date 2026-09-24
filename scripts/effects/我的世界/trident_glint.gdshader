shader_type canvas_item;
render_mode unshaded, blend_add;
// Original Minecraft enchanted-item texture, two drifting diagonal passes.
// A supplied clock (not TIME) freezes correctly during gameplay pause.
uniform sampler2D native_glint : repeat_enable, filter_nearest;
uniform float glint_time = 0.0;
uniform float world_texel = 1.0;
#include "res://scripts/effects/我的世界/trident_plant_clip.gdshaderinc"
void fragment() {
	if (trident_buried_pixel()) discard;
	float mask = texture(TEXTURE, UV).a;
	vec2 p = (UV / TEXTURE_PIXEL_SIZE) * world_texel * 0.045;
	vec2 a = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
	vec2 b = vec2(p.x * 0.6 + p.y * 0.8, -p.x * 0.8 + p.y * 0.6);
	float first = texture(native_glint, a + vec2(glint_time * 0.12, -glint_time * 0.07)).r;
	float second = texture(native_glint, b + vec2(-glint_time * 0.09, glint_time * 0.11)).r;
	float shine = clamp((first + second * 0.7) * 1.6, 0.0, 0.85);
	COLOR = vec4(vec3(0.66, 0.24, 1.0) * shine, mask * 0.8);
}
