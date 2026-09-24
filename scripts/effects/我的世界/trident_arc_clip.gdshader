shader_type canvas_item;
render_mode unshaded;
#include "res://scripts/effects/我的世界/trident_plant_clip.gdshaderinc"
void fragment() {
	if (trident_buried_pixel()) discard;
}
