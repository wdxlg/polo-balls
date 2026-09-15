extends RefCounted
## Immutable state for one synchronous sampling batch, never cached across frames.
## Coordinate math and Color operations intentionally match ball._sample_current_visual_pixel.
var valid:bool = false
var source_image:Image
var rect:Rect2
var source_position:Vector2 = Vector2.ZERO
var source_size:Vector2 = Vector2.ZERO
var flip_h:bool = false
var flip_v:bool = false
var modulation:Color = Color.WHITE
var tint:Color = Color.WHITE
var mix_amount:float = 0.0
var width:int = 0
var height:int = 0

func sample(local_point:Vector2) -> Color:
	if not valid or not rect.has_point(local_point):
		return Color.TRANSPARENT
	var uv:Vector2 = (local_point - rect.position) / rect.size
	if flip_h:
		uv.x = 1.0 - uv.x
	if flip_v:
		uv.y = 1.0 - uv.y
	uv.x = clampf(uv.x,0.0,0.999999)
	uv.y = clampf(uv.y,0.0,0.999999)
	var pixel_position:Vector2 = source_position + uv * source_size
	var px:int = clampi(int(floor(pixel_position.x)),0,width - 1)
	var py:int = clampi(int(floor(pixel_position.y)),0,height - 1)
	var sampled:Color = source_image.get_pixel(px,py)
	if sampled.a <= 0.0:
		return Color.TRANSPARENT
	sampled = Color(
		lerpf(sampled.r,tint.r,mix_amount),
		lerpf(sampled.g,tint.g,mix_amount),
		lerpf(sampled.b,tint.b,mix_amount),
		sampled.a
	)
	sampled *= modulation
	return sampled
