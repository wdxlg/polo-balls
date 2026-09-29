extends Node2D
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")
var source_ref:WeakRef
var damage:float=0.0
var max_radius:float=55.0
var duration:float=0.35
var knockback:float=45.0
var authoritative:bool=true
var age:float=0.0
var hit_ids:Dictionary={}
# Damage stays inside the initial ring; expansion is strictly cosmetic.
var initial_radius:float=30.0
var damage_window:float=0.10
var radius:float=30.0
var sound_played:bool=false
func _ready() -> void:
	z_as_relative=false
	z_index=103
	add_to_group("BattleTransient")
	add_to_group("AllayRecallWave")
func _physics_process(delta:float) -> void:
	var source:Variant=source_ref.get_ref() if source_ref!=null else null
	if not is_instance_valid(source) or source.health<=0:
		queue_free()
		return
	if not source.is_combat_runtime_active(): return
	var previous_age:float=age
	var peak_dealt:float=0.0
	age+=maxf(delta,0.0)
	radius=lerpf(initial_radius,max_radius,clampf(age/maxf(duration,0.01),0.0,1.0))
	if authoritative and source.is_multiplayer_authority() and previous_age<damage_window and not source.is_damage_output_disabled():
		for target:Node in get_tree().get_nodes_in_group("Ball"):
			if not U.enemy(source,target) or target.is_queued_for_deletion(): continue
			if not source.Team.is_empty() and target.Team==source.Team: continue
			var id:int=target.get_instance_id()
			if hit_ids.has(id): continue
			var offset:Vector2=ball.body_point(target,global_position)-global_position
			var body_radius:float=U.radius(target)
			if offset.length()-body_radius>initial_radius: continue
			if not U.line_clear(self,global_position,ball.body_point(target,global_position)): continue
			hit_ids[id]=true
			var before:float=target.health
			var amount:float=source.effective_outgoing_damage(damage)
			if amount>0.0 and target.receive_positional_damage(amount,global_position,false,source):
				peak_dealt=maxf(peak_dealt,maxf(before-target.health,0.0))
				target.apply_knockback(offset.normalized() if offset.length_squared()>0.001 else Vector2.RIGHT,knockback,240.0,0.0,0.0,{"source":source,"stop_on_character":true})
	if peak_dealt>0.0 and not sound_played:
		sound_played=true
		# Per-victim actual feedback already emitted; never replace it with an AOE maximum.
	queue_redraw()
	if age>=duration: queue_free()
func _draw() -> void:
	var t:float=clampf(age/maxf(duration,0.01),0.0,1.0)
	var alpha:float=pow(1.0-t,0.7)
	# Hollow pixel ring: pale blue band, blue inner/outer borders; transparent center.
	var pixel:float=4.0
	var inner_radius:float=maxf(radius-12.0,0.0)
	var cells:int=int(ceil(radius/pixel))
	for y:int in range(-cells,cells):
		for x:int in range(-cells,cells):
			var point:Vector2=Vector2(x+0.5,y+0.5)*pixel
			if point.length()>radius or point.length()<inner_radius: continue
			var border:bool=false
			for axis:Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				var neighbor_distance:float=(point+axis*pixel).length()
				if neighbor_distance>radius or neighbor_distance<inner_radius: border=true
			var color:Color=Color(0.2,0.6,1.0,alpha) if border else Color(0.65,0.87,1.0,alpha*0.85)
			draw_rect(Rect2(Vector2(x,y)*pixel,Vector2.ONE*pixel),color)
