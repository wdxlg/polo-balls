extends Node2D
const CONTAINER=preload("res://scripts/effects/我的世界/mc_explosion.gd")
const SPIKE_COLOR=Color("#e06f25") # sampled orange from the native guardian spike texture
var owner_ref:WeakRef
var age:float=0.0
var reach:float=31.0
var start_radius:float=12.0
var angle_offset:float=0.0
static func spawn(actor:Node2D,point:Vector2,radius:float) -> Node2D:
	var effect:Node2D=load("res://scripts/characters/我的世界/new5/guardian_spike_fx.gd").new()
	effect.owner_ref=weakref(actor)
	effect.position=point
	effect.reach=radius
	effect.start_radius=actor.U.radius(actor)*0.85
	effect.angle_offset=actor.gaze.angle()
	CONTAINER.runtime_container(actor).add_child(effect)
	return effect
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	z_as_relative=false
	z_index=86
	add_to_group("BattleTransient")
	add_to_group("MCGuardianSpikeFX")
	queue_redraw()
func _process(delta:float) -> void:
	var actor:Node=owner_ref.get_ref() if owner_ref!=null else null
	if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.health<=0 or actor._death_visual_done:
		hide()
		queue_free()
		return
	if get_tree().paused or Game.now_stop_state or not actor.is_combat_runtime_active(): return
	age+=delta
	if age>=0.30:
		queue_free()
		return
	queue_redraw()
func _draw() -> void:
	var t:float=clampf(age/0.30,0.0,1.0)
	var distance:float=lerpf(start_radius,reach,1.0-pow(1.0-t,3.0))
	var alpha:float=1.0-smoothstep(0.5,1.0,t)
	var length:float=lerpf(13.0,8.0,t)
	var width:float=4.5
	for i:int in range(8):
		var angle:float=angle_offset+float(i)*TAU/8.0
		draw_set_transform(Vector2.RIGHT.rotated(angle)*distance,angle)
		draw_rect(Rect2(-length*0.5,-width*0.5,length,width),Color(SPIKE_COLOR,alpha))
		draw_rect(Rect2(-length*0.5,width*0.10,length,width*0.40),Color(SPIKE_COLOR.darkened(0.23),alpha))
	draw_set_transform(Vector2.ZERO)
