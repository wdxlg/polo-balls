extends Node2D
## Expanding, one-contact annulus. Pixel rendering and exact hurt-shape queries
## reuse public helpers; policy alone is target-current-HP raw health damage.
const ARC = preload("res://scripts/effects/我的世界/pixel_arc.gd")
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
var source:ball
var max_radius:float = 320.0
var duration:float = 0.8
var age:float = 0.0
var radius:float = 0.0
var previous_radius:float = 0.0
var hit_ids:Dictionary = {}
const SIDES:int = 48
const HALF_WIDTH:float = 3.5
func _ready() -> void:
	top_level=true
	z_as_relative=false
	z_index=2
	add_to_group("BattleTransient")
	add_to_group("DingWakeWave")
func set_age(value:float,deal:bool) -> void:
	previous_radius=radius
	age=clampf(value,0.0,duration)
	radius=lerpf(0.0,max_radius,age/maxf(duration,0.01))
	if deal and is_instance_valid(source) and source.call("_can_act"): _hit_new_contacts()
	queue_redraw()
func _segments() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var middle:float=(previous_radius+radius)*0.5
	var width:float=HALF_WIDTH+absf(radius-previous_radius)*0.5
	for i:int in range(SIDES):
		result.append({"a":global_position+Vector2.from_angle(TAU*float(i)/SIDES)*middle,"b":global_position+Vector2.from_angle(TAU*float(i+1)/SIDES)*middle,"r":width})
	return result
func _hit_new_contacts() -> void:
	# A single coarse exact-shape query, then test the annular swept band only.
	var candidates:Array[Dictionary]=SWEEP.contacts(source,global_position,global_position,radius+HALF_WIDTH,hit_ids,global_position)
	if candidates.is_empty(): return
	var bands:Array[Dictionary]=_segments()
	for hit:Dictionary in candidates:
		var target:ball=hit.target
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		var touches:bool=false
		for band:Dictionary in bands:
			var shape:=CapsuleShape2D.new()
			shape.radius=band.r
			shape.height=Vector2(band.a).distance_to(band.b)+shape.radius*2.0
			var pose:=Transform2D((Vector2(band.b)-Vector2(band.a)).angle()-PI*0.5,(Vector2(band.a)+Vector2(band.b))*0.5)
			for child:Node in target.self_hurtbox.get_children():
				if child is CollisionShape2D and not child.disabled and child.shape!=null and shape.collide(pose,child.shape,child.global_transform): touches=true; break
			if touches: break
		if not touches: continue
		hit_ids[target.get_instance_id()]=true
		var amount:float=source.effective_outgoing_damage(maxf(float(target.health),0.0))
		if amount>0.0:
			target.receive_classified_spatial_damage(amount,{"shape":"circle","point":target.global_position,"origin":global_position,"radius":HALF_WIDTH,"source":source,"carrier":"area"},&"ordinary",true,true)
func threats(receiver:ball) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not is_instance_valid(source) or source.health<=0 or age>=duration or source.is_damage_output_disabled() or source.dizziness or not source.Can_Attack: return result
	if is_instance_valid(receiver):
		if hit_ids.has(receiver.get_instance_id()) or not SWEEP.TOOLS.is_enemy(source,receiver): return result
		if not SWEEP._clear(source.get_world_2d().direct_space_state,source,global_position,receiver.global_position): return result
	var amount:float=maxf(float(receiver.health),0.0) if is_instance_valid(receiver) else float(source.Max_health)
	for band:Dictionary in _segments():
		result.append({"shape":"segment","start":band.a,"end":band.b,"radius":band.r,"damage":amount,"danger_in":0.0,"danger_duration":0.03,"kind":"ding_wake_raw_health","source":source})
	return result
func _draw() -> void:
	ARC.draw_ring(self,Vector2.ZERO,radius,Color("d8f6ff"),pow(1.0-clampf(age/maxf(duration,0.01),0,1),0.35))
