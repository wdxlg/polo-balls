shader_type canvas_item;
#include "res://scripts/effects/我的世界/trident_plant_clip.gdshaderinc"
uniform float refill_flash : hint_range(0.0,1.0) = 0.0;
void fragment() {
	if (trident_buried_pixel()) discard;
	// Keep native item alpha/modulation and the refill ghost unchanged.
	COLOR.rgb = mix(COLOR.rgb,vec3(1.0),refill_flash);
}
