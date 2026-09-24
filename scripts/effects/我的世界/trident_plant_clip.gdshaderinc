// Shared by the body, native glint, and the procedural electric strokes.
// MODEL_MATRIX includes the actual Sprite/canvas scale and rotation; do not
// reconstruct geometry from UV (polylines do not have meaningful item UVs).
uniform float plant_clip = 0.0;
uniform float plant_clip_y = 0.0;
varying vec2 trident_world_position;
void vertex() {
	trident_world_position = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy;
}
bool trident_buried_pixel() {
	return plant_clip > 0.5 && trident_world_position.y > plant_clip_y;
}
