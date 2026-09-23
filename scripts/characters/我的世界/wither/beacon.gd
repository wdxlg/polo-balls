extends "res://scripts/characters/我的世界/new5/base.gd"
## A summoned, targetable vanilla beacon: gravity, horizontal drive and a vertical beam.
const BEACON_TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_block/beacon_block.png")
const HEART_TEXTURE = preload("res://Images/characters/我的世界/wither/nether_star.png")
const VANILLA_SOUND = preload("res://scripts/characters/我的世界/wither/audio.gd")
const BEAM_VISUAL = preload("res://scripts/characters/我的世界/wither/beacon_beam.gd")
const PROFILE = preload("res://scripts/characters/我的世界/wither/beacon_profile.gd")
const GRAVITY:float = 1200.0
const TERMINAL_SPEED:float = 1100.0
const EPSILON:float = 0.0000001
const BUFFS:Array[String] = ["speed","haste","strength","resistance","regeneration"]
var _activated:bool = false
var _beam_visual:Node2D
var _body:CollisionShape2D
var _damage_shape:=RectangleShape2D.new()
var _pulse_index:int = 0
var damage_ticks:int = 0
var landed:bool = false
var fall_speed:float = 0.0
var beam_timer:float = 10.0
var warning_left:float = 0.0
var firing_left:float = 0.0
var tick_left:float = 0.0
var beam_end:Vector2
var beam_direction:Vector2 = Vector2.UP
var beams_fired:int = 0
var last_buff:String = ""
func _ready() -> void:
	Has_Collision_Damage=false
	Can_Attack=false
	Can_Skill=false
	Health_Restore=0
	super._ready()
	if image is Sprite2D:
		image.texture=BEACON_TEXTURE
		image.visible=false
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_body=get_node("CollisionShape2D")
	if is_instance_valid(Master) and Master is PhysicsBody2D: add_collision_exception_with(Master)
	_beam_visual=BEAM_VISUAL.new()
	_beam_visual.name="VanillaBeaconBeam"
	_beam_visual.top_level=true # Animation, damage and threat all use world units.
	add_child(_beam_visual)
	add_to_group("AI_Hazard")
	add_to_group("WitherBeacon")
func get_preview_texture() -> Texture2D: return BEACON_TEXTURE
func voice_role() -> String: return ""
func move(_speed:float,_delta:float) -> void: pass
func stand(_delta:float): Repel=Vector2.ZERO
func movement_multiplier() -> float: return PROFILE.speed_factor(warning_left,firing_left)
func body_width() -> float:
	return _body.shape.get_rect().size.x*absf(_body.global_scale.x)
func beam_width() -> float: return PROFILE.width(body_width(),warning_left,firing_left)
func beam_opacity() -> float: return PROFILE.opacity(warning_left,firing_left)
func step_mob(delta:float) -> void:
	var master:ball=Master as ball if is_instance_valid(Master) and Master is ball else null
	if master==null or master.health<=0: queue_free(); return
	if health<=0 or _death_sound_done: return
	var target:ball=U.nearest(self)
	var remaining:float=maxf(delta,0.0)
	# Split at physics steps AND phase/pulse boundaries. Even a slow frame samples
	# a moving ray at each scheduled hit, not fifteen hits at its final location.
	while remaining>EPSILON:
		if _activated and warning_left<=EPSILON and firing_left<=EPSILON and beam_timer<=EPSILON and is_instance_valid(target):
			warning_left=PROFILE.WARNING
			continue
		var dt:float=minf(remaining,1.0/120.0)
		var phase:int=0
		if _activated:
			if warning_left>EPSILON:
				phase=1
				dt=minf(dt,warning_left)
			elif firing_left>EPSILON:
				phase=2
				dt=minf(dt,minf(firing_left,maxf(tick_left,EPSILON)))
			elif beam_timer>EPSILON: dt=minf(dt,beam_timer)
		var horizontal:float=0.0
		if _activated and is_instance_valid(target) and not dizziness:
			var speed:float=maxf(Speed,0.0)*movement_multiplier()
			horizontal=clampf((target.global_position.x-global_position.x)/dt,-speed,speed)
		_gravity_step(dt,horizontal)
		beam_direction=Vector2.UP
		beam_end=_clipped_beam()
		remaining-=dt
		if not _activated: continue
		match phase:
			1:
				warning_left=maxf(warning_left-dt,0.0)
				if warning_left<=EPSILON:
					warning_left=0.0
					firing_left=PROFILE.FIRING
					# Midpoint samples: 0.05, 0.15 ... 1.45 = 15 pulses/36 base damage.
					tick_left=PROFILE.INTERVAL*0.5
					_pulse_index=0
					_emit_sound("beacon_power")
			2:
				firing_left=maxf(firing_left-dt,0.0)
				tick_left-=dt
				if tick_left<=EPSILON and _pulse_index<PROFILE.PULSES:
					_damage_tick(master)
					_pulse_index+=1
					damage_ticks+=1
					tick_left+=PROFILE.INTERVAL
				if firing_left<=EPSILON:
					firing_left=0.0
					_emit_sound("beacon_deactivate")
					beams_fired+=1
					last_buff=BUFFS[rng.randi_range(0,BUFFS.size()-1)]
					master.call("apply_beacon_buff",last_buff)
					beam_timer=10.0
			_:
				beam_timer=maxf(beam_timer-dt,0.0)

func beam_rect() -> Rect2:
	var origin:Vector2=beam_origin()
	return Rect2(Vector2(origin.x-beam_width()*0.5,beam_end.y),Vector2(beam_width(),maxf(origin.y-beam_end.y,0.0)))
func _damage_tick(master:ball) -> void:
	var rect:Rect2=beam_rect()
	if not rect.has_area(): return
	_damage_shape.size=rect.size
	var transform:Transform2D=Transform2D(0.0,rect.get_center())
	for node:Node in SubmissionCharacterTools.targeting_candidates(master):
		if not node is ball or not master.call("mc_enemy",node): continue
		var enemy:ball=node as ball
		if enemy.self_hurtbox==null: continue
		var hit:bool=false
		# Exact current hurtbox shapes, including scene scale, not a guessed circle.
		for shape:Node in enemy.self_hurtbox.get_children():
			if shape is CollisionShape2D and not shape.disabled and shape.shape!=null:
				if _damage_shape.collide(transform,shape.shape,shape.global_transform): hit=true; break
		if hit:
			var point:Vector2=enemy.global_position.clamp(rect.position,rect.end)
			master.call("impact",enemy,PROFILE.pulse_damage(_pulse_index),point)

func _gravity_step(dt:float,horizontal:float) -> void:
	var motion_x:float=horizontal+Repel.x
	velocity.x=motion_x
	if absf(motion_x)>0.00001:
		var side:KinematicCollision2D=move_and_collide(Vector2(motion_x*dt,0.0),false,0.001,false)
		if side!=null: velocity.x=0.0
	fall_speed=minf(fall_speed+GRAVITY*dt,TERMINAL_SPEED)
	velocity.y=fall_speed
	var down:KinematicCollision2D=move_and_collide(Vector2(0.0,fall_speed*dt),false,0.001,false)
	landed=down!=null and down.get_normal().y < -0.5
	if down!=null:
		fall_speed=0.0
		velocity.y=0.0
	if landed and not _activated:
		_activated=true
		if image is Sprite2D: image.visible=true
		_emit_sound("beacon_activate")
func beam_origin() -> Vector2:
	var half_height:float=_body.shape.get_rect().size.y*absf(_body.global_scale.y)*0.5 if is_instance_valid(_body) else 33.0
	return global_position+Vector2(0,-half_height)
func _clipped_beam() -> Vector2:
	var origin:Vector2=beam_origin()
	var source:ball=Master as ball if is_instance_valid(Master) and Master is ball else null
	var top:float=origin.y-4096.0
	if source!=null:
		var arena:Rect2=source.call("mc_arena_rect")
		if arena.has_area(): top=minf(arena.position.y,origin.y-1.0)
	var end:Vector2=Vector2(origin.x,top)
	var excludes:Array[RID]=[get_rid()]
	if source!=null: excludes.append(source.get_rid())
	var query:=PhysicsRayQueryParameters2D.create(origin,end,1,excludes)
	var hit:Dictionary=get_world_2d().direct_space_state.intersect_ray(query)
	return Vector2(hit.position) if not hit.is_empty() else end
func get_ai_hazard_info(_receiver:ball=null) -> Dictionary:
	if firing_left<=0 and warning_left<=0 or health<=0: return {}
	var master:ball=Master as ball if is_instance_valid(Master) and Master is ball else null
	if master==null: return {}
	var rect:Rect2=beam_rect()
	if not rect.has_area(): return {}
	return {"shape":"rect","position":rect.get_center(),"half_extents":rect.size*0.5,"rotation":0.0,"start":beam_origin(),"end":beam_end,"radius":beam_width()*0.5,"damage":0.0 if warning_left>0 else PROFILE.pulse_damage(_pulse_index),"danger_in":maxf(warning_left,0.0),"danger_duration":maxf(firing_left,0.1),"source":master,"kind":"wither_beacon_beam"}
func get_debug_detection_regions() -> Array[Dictionary]:
	if warning_left<=0 or health<=0: return []
	var rect:Rect2=beam_rect()
	return [{"shape":"rect","position":rect.get_center(),"half_extents":rect.size*0.5,"rotation":0.0}]
func Die() -> void:
	warning_left=0.0
	firing_left=0.0
	if is_instance_valid(_beam_visual): _beam_visual.hide()
	if is_instance_valid(Master) and Master.has_method("apply_beacon_buff"): Master.call("apply_beacon_buff","")
	super.Die()
func visual_mob() -> void:
	if image is Sprite2D:
		var strength:float=PROFILE.shake(warning_left)
		# Cosmetic only: neither the physics body nor the upward ray shakes/rotates.
		image.position=Vector2(sin(_view_clock*103.0),sin(_view_clock*137.0))*4.5*strength
		image.rotation=sin(_view_clock*91.0)*0.025*strength
func _emit_sound(event:String) -> void:
	VANILLA_SOUND.play(self,event,global_position)
	if multiplayer.has_multiplayer_peer(): _remote_sound.rpc(event,global_position)
@rpc("authority","call_remote","reliable")
func _remote_sound(event:String,point:Vector2) -> void: VANILLA_SOUND.play(self,event,point)
func visual_state() -> Dictionary:
	return {"time":clock,"activated":_activated,"landed":landed,"warning":warning_left,"firing":firing_left,"beam_end":beam_end}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_activated=bool(data.get("activated",_activated))
	landed=bool(data.get("landed",landed))
	warning_left=float(data.get("warning",0.0))
	firing_left=float(data.get("firing",0.0))
	beam_end=data.get("beam_end",beam_end)
	if image is Sprite2D: image.visible=_activated
func client_visual_step(delta:float) -> void:
	# Interpolate the supplied phase locally instead of visibly stepping at RPC rate.
	if not is_combat_runtime_active(): return
	if warning_left>0:
		var over:float=maxf(delta-warning_left,0.0)
		warning_left=maxf(warning_left-delta,0.0)
		if warning_left==0: firing_left=maxf(PROFILE.FIRING-over,0.0)
	elif firing_left>0: firing_left=maxf(firing_left-delta,0.0)
func _draw() -> void:
	if not _activated: draw_texture_rect(HEART_TEXTURE,Rect2(-16,-16,32,32),false)
func _process(delta:float) -> void:
	super._process(delta)
	if is_instance_valid(_beam_visual):
		_beam_visual.global_transform=Transform2D(0.0,beam_origin())
		_beam_visual.call("update_beam",maxf(beam_origin().y-beam_end.y,0.0),_view_clock,beam_width(),beam_opacity(),warning_left>0 and health>0,firing_left>0 and health>0)
	queue_redraw()
