extends Node2D
## Compact native block props; one logical cell does not mean a 24px visual cube.
const PUMPKIN:Texture2D = preload("res://Images/characters/我的世界/snow_golem/pumpkin_block.png")
const SNOW:Texture2D = preload("res://Images/characters/我的世界/snow_golem/snow_block.png")
const HEAD_WIDTH:float = 13.0
# 16 native vertical units projected through the original 30°/12° camera.
const LAYER_RISE_RATIO:float = 0.70
var field:Node2D
func _ready() -> void:
	z_as_relative = true
	z_index = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func block_size(head:Dictionary) -> Vector2:
	var width:float = HEAD_WIDTH*float(head.get("visual_scale",1.0))
	return Vector2(width,width*float(PUMPKIN.get_height())/float(PUMPKIN.get_width()))

static func layer_rise(head:Dictionary) -> float:
	return block_size(head).x*LAYER_RISE_RATIO

func flight_pose(head:Dictionary) -> Dictionary:
	var size:Vector2 = block_size(head)
	var duration:float = maxf(float(head.duration),0.001)
	var t:float = clampf(float(head.elapsed)/duration,0.0,1.0)
	var expected_blocks:int = int(head.blocks)
	if not bool(head.landed) and is_instance_valid(field) and field.patches.has(head.cell):
		var landing_time:float = field._clock+maxf(duration-float(head.elapsed),0.0)
		if field._snow_present_at(field.patches[head.cell],landing_time): expected_blocks = 1
	# Interpolate cube centers, not a head-height offset plus another full cube.
	# If snow will be absorbed, arrive smoothly at the one-block stack height.
	var destination:Vector2 = head.point-Vector2(0,size.y*0.5+layer_rise(head)*expected_blocks)
	var point:Vector2 = head.start.lerp(destination,t)+Vector2(0,-sin(t*PI)*6.0*float(head.get("visual_scale",1.0)))
	return {"point":point,"angle":sin(t*PI)*0.14}

func _shadow(point:Vector2,width:float,alpha:float) -> void:
	draw_set_transform(point+Vector2(0,0.8),0.0,Vector2(1.0,0.3))
	draw_circle(Vector2.ZERO,width*0.46,Color(0,0,0,alpha))
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if not is_instance_valid(field): return
	for head:Dictionary in field.heads.values():
		var size:Vector2 = block_size(head)
		var mirror:Vector2 = Vector2(-1,1) if bool(head.get("face_right",false)) else Vector2.ONE
		var ground:Vector2 = head.point
		if not bool(head.landed):
			var pose:Dictionary = flight_pose(head)
			_shadow(ground,size.x,0.10)
			draw_set_transform(pose.point,float(pose.angle),mirror)
			draw_texture_rect(PUMPKIN,Rect2(-size*0.5,size),false)
			draw_set_transform(Vector2.ZERO)
			continue
		_shadow(ground,size.x,0.18)
		draw_set_transform(ground,0.0,mirror)
		var rise:float = layer_rise(head)
		var blocks:int = int(head.blocks)
		for level:int in range(blocks):
			draw_texture_rect(SNOW,Rect2(Vector2(-size.x*0.5,-size.y-rise*level),size),false)
		draw_texture_rect(PUMPKIN,Rect2(Vector2(-size.x*0.5,-size.y-rise*blocks),size),false)
		draw_set_transform(Vector2.ZERO)
