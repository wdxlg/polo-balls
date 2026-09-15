extends "res://scripts/effects/传说之下/Sans滚动骨头.gd"

# 终幕独有的完整双头骨。静止弧线通过 travel_speed=0 实现，绝不移动骨列冒充重力。
var remaining_life:float = 10.0
func configure_final(actor:ball,root:Vector2,inward:Vector2,move:Vector2,speed:float,length:float,life:float) -> void:
	configure(actor,root,inward,move,100000.0,maxf(speed,20.0),length,0.65,5.0,1.0)
	travel_speed = maxf(speed,0.0)
	remaining_life = life
	var tail:=Sprite2D.new()
	tail.texture = SANS_ATLAS
	tail.region_enabled = true
	tail.region_rect = BONE_HEAD_REGION
	tail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tail.scale = Vector2.ONE * visual_scale
	tail.rotation = PI
	tail.position = Vector2(-BONE_HEAD_LATERAL_OFFSET * visual_scale,-5.0 * visual_scale)
	add_child(tail)

func _physics_process(delta:float) -> void:
	if Game.now_stop_state:
		return
	remaining_life -= delta
	if remaining_life <= 0.0:
		queue_free()
		return
	super._physics_process(delta)
