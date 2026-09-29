extends "res://scripts/characters/我的世界/new5/base.gd"
const PARTS={"rod":preload("res://Images/characters/我的世界/new5/fishing_rod.png"),"cast":preload("res://Images/characters/我的世界/new5/fishing_rod_cast.png"),"sword":preload("res://Images/characters/我的世界/new5/iron_sword.png"),"hook":preload("res://Images/characters/我的世界/new5/fishhook.png")}
@export var cast_range:float=225.0
@export var break_distance:float=270.0
@export var sword_range:float=47.0
@export var sword_damage_multiplier:float=2.25
@export var pull_distance:float=100.0
@export var ground_wait:float=0.85
@export var return_speed:float=360.0
var facing:Vector2=Vector2.RIGHT
var hook_mode:int=0 # 0 idle, 1 ballistic cast, 2 attached, 3 resting, 4 retrieving
var hook_point:Vector2
var hook_velocity:Vector2
var hooked:ball
var _cast_left:float=0.6
var _cast_travel:float=0.0
var _attached_time:float=0.0
var _sword_left:float=0.0
var sword_pose:float=0.0
var _sword_facing:Vector2=Vector2.RIGHT
var _sword_origin:Vector2=Vector2.ZERO
var _sword_trails:Array[Dictionary]=[]
var _trail_wait:float=0.0
var _sword_hits:Dictionary={}
const SWORD_DURATION:float=0.26
const SWORD_COOLDOWN:float=0.85
var _reel_slash_started:bool=false
var _pull_slash_target:ball
var _pull_slash_wait:float=0.0
var _pull_slash_active:bool=false
var _retreat_left:float=0.0
var _cast_origin:Vector2
var _cast_target:Vector2
var _flight_time:float=0.0
var _flight_duration:float=0.5
var _arc_height:float=42.0
var _rest_left:float=0.0
var _return_left:float=0.0
var _return_hits:Dictionary={}
var rope:Line2D
var bobber:Sprite2D
var sword:Sprite2D
func _ready() -> void:
	super._ready()
	# Minecraft renders its fishing line as black geometry, not a rope texture.
	rope=U.line(self,"FishingLine",1.0,Color.BLACK)
	rope.antialiased=false
	bobber=Sprite2D.new()
	bobber.texture=PARTS.hook
	bobber.top_level=true
	bobber.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	bobber.scale=Vector2(2,2)
	add_child(bobber)
	sword=Sprite2D.new()
	sword.texture=PARTS.sword
	sword.top_level=true
	sword.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sword.scale=Vector2(1.25,1.25)
	sword.offset=Vector2(6.5,-6.5) # Hilt pivot, not sprite-center rotation.
	add_child(sword)
func break_line() -> void:
	hook_mode=0
	hooked=null
	_return_hits.clear()
	_cast_left=maxf(_cast_left,1.25)
func cast_at(point:Vector2) -> void:
	play_sound("entity.fishing_bobber.throw",-4.0)
	hook_mode=1
	hooked=null
	_return_hits.clear()
	facing=(point-global_position).normalized()
	_cast_origin=global_position+facing*16
	_cast_target=global_position+(point-global_position).limit_length(cast_range)
	hook_point=_cast_origin
	_flight_time=0.0
	_flight_duration=clampf(_cast_origin.distance_to(_cast_target)/400.0,0.28,0.65)
	_arc_height=clampf(_cast_origin.distance_to(_cast_target)*0.25,18.0,56.0)
	_cast_travel=0
func cast_point(t:float) -> Vector2:
	return _cast_origin.lerp(_cast_target,t)+Vector2.UP*(4.0*_arc_height*t*(1.0-t))
func pull_hook() -> void:
	if hook_mode==0 or hook_mode==4: return
	play_sound("entity.fishing_bobber.retrieve",-3.0)
	hook_mode=4
	_reel_slash_started=false
	_return_left=2.5
	_return_hits.clear()
	if is_instance_valid(hooked) and U.enemy(self,hooked) and U.line_clear(self,hook_point,global_position):
		_return_hit(hooked)
	hooked=null
func _hook_damage(target:ball,multiplier:float) -> bool:
	# Scoped suppression: keep normal damage/block/reporting, replace only hurt voice.
	var prior:bool=bool(target.get_meta("mc_hook_hurt_only",false))
	var old_hurt:AudioStream=target.Unique_Hurt_Audio
	target.set_meta("mc_hook_hurt_only",true)
	target.Unique_Hurt_Audio=null
	var accepted:bool=U.damage(self,target,attack_damage(multiplier),hook_point)
	if is_instance_valid(target):
		target.Unique_Hurt_Audio=old_hurt
		if prior: target.set_meta("mc_hook_hurt_only",true)
		else: target.remove_meta("mc_hook_hurt_only")
	# Settled victim emits one MC hit; keep hurt-voice suppression scoped above.
	return accepted
func _return_hit(target:ball) -> void:
	var id:int=target.get_instance_id()
	if _return_hits.has(id): return
	_return_hits[id]=true
	if not _hook_damage(target,0.5): return
	U.slow(self,target,0.12,0.65,"钓竿猛拉")
	var offset:Vector2=global_position-target.global_position
	# Existing collision-aware knockback handles walls and control immunity.
	target.apply_knockback(offset.normalized(),maxf(offset.length()-36.0,0.0),420,0,0,{"source":self})
	if not _reel_slash_started and U.enemy(self,target):
		_reel_slash_started=true
		_pull_slash_target=target
		step_pull_slash(0.0) # Trigger from retrieval itself, never from a proximity gate.
func _segment_target(a:Vector2,b:Vector2) -> ball:
	var result:ball
	var best:float=INF
	for other:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,other) or U.segment_distance(other.global_position,a,b)>U.radius(other)+3: continue
		var distance:float=a.distance_squared_to(other.global_position)
		if distance<best:
			best=distance
			result=other
	return result
func controlled_attack_action() -> void:
	# Existing sword slash. Reel-in follow-up remains part of the hook action.
	if not is_player_controlled() or not is_multiplayer_authority() or not can_act(): return
	try_start_sword(player_control_aim_direction(facing),false)
func controlled_skill_action() -> void:
	# The same button casts an idle hook or retrieves an already committed cast.
	if not is_player_controlled() or not is_multiplayer_authority() or not can_act(): return
	if hook_mode>0 and hook_mode<4:
		pull_hook()
	elif hook_mode==0 and _cast_left<=0.0 and _retreat_left<=0.0 and not _pull_slash_active:
		cast_at(player_control_aim_world_position(global_position+facing*cast_range))
func step_mob(delta:float) -> void:
	_cast_left-=delta
	_sword_left-=delta
	_retreat_left=maxf(0.0,_retreat_left-delta)
	if not can_act():
		cancel_pull_slash()
		sword_pose=0.0
		_sword_hits.clear()
		break_line()
		return
	advance_sword(delta)
	step_pull_slash(delta)
	if is_player_controlled(): facing=player_control_aim_direction(facing)
	var nearest:ball=null if is_player_controlled() else U.nearest(self)
	if nearest!=null:
		if not _pull_slash_active: facing=(nearest.global_position-global_position).normalized()
		if global_position.distance_to(nearest.global_position)<=sword_range+U.radius(nearest) and _sword_left<=0 and sword_pose<=0.0 and not _pull_slash_active and not is_instance_valid(_pull_slash_target) and _retreat_left<=0.0:
			try_start_sword(facing,false)
	if hook_mode==0:
		if nearest!=null and not _pull_slash_active and not is_instance_valid(_pull_slash_target) and _retreat_left<=0.0 and _cast_left<=0 and global_position.distance_to(nearest.global_position)<=cast_range and global_position.distance_to(nearest.global_position)>sword_range: cast_at(nearest.global_position)
		return
	if hook_mode==1:
		# Substeps trace the actual parabola, including long physics frames.
		var steps:int=maxi(1,ceili(delta/0.012))
		for i:int in range(steps):
			_flight_time=minf(_flight_time+delta/steps,_flight_duration)
			var next:Vector2=cast_point(_flight_time/_flight_duration)
			var obstruction:Dictionary=U.trace(self,hook_point,next)
			var stop:Vector2=obstruction.get("position",next)
			var target:ball=_segment_target(hook_point,stop)
			if target!=null and U.line_clear(self,hook_point,target.global_position) and _hook_damage(target,1.0):
				U.slow(self,target,0.60,1.0,"钓钩减速")
				hooked=target
				hook_mode=2
				_attached_time=0
				hook_point=target.global_position
				return
			hook_velocity=(stop-hook_point)/maxf(delta/steps,0.0001)
			hook_point=stop
			if not obstruction.is_empty():
				hook_point+=Vector2(obstruction.get("normal",Vector2.ZERO))*2.0
			if not obstruction.is_empty() or _flight_time>=_flight_duration:
				hook_mode=3
				_rest_left=ground_wait
				return
	elif hook_mode==2:
		if not is_instance_valid(hooked) or not U.enemy(self,hooked): pull_hook(); return
		hook_point=hooked.global_position
		_attached_time+=delta
		if global_position.distance_to(hook_point)>break_distance or _attached_time>=0.65: pull_hook()
	elif hook_mode==3:
		var touched:ball=_segment_target(hook_point,hook_point)
		if touched!=null and U.line_clear(self,hook_point,touched.global_position):
			hooked=touched
			hook_mode=2
			_attached_time=0.0
			hook_point=touched.global_position
			U.slow(self,touched,0.60,1.0,"钓钩减速")
			return # Resting pickup attaches without impact damage or hurt sound.
		_rest_left-=delta
		if _rest_left<=0: pull_hook()
	elif hook_mode==4:
		_return_left-=delta
		var next:Vector2=hook_point.move_toward(global_position,return_speed*delta)
		var obstruction:Dictionary=U.trace(self,hook_point,next)
		var stop:Vector2=obstruction.get("position",next)
		for other:Node in get_tree().get_nodes_in_group("Ball"):
			if not U.enemy(self,other) or U.segment_distance(other.global_position,hook_point,stop)>U.radius(other)+3: continue
			if U.line_clear(self,hook_point,other.global_position) and U.line_clear(self,global_position,other.global_position): _return_hit(other)
		hook_point=stop
		if not obstruction.is_empty() or hook_point.distance_to(global_position)<8 or _return_left<=0:
			break_line()
			_cast_left=1.4
func visual_mob() -> void:
	image.texture=PARTS.cast if hook_mode>0 else PARTS.rod
	face_horizontal(facing,false)
	if not is_instance_valid(rope): return
	rope.visible=hook_mode>0 and health>0 and is_combat_runtime_active()
	var start:Vector2=rod_line_origin()
	var points:=PackedVector2Array()
	for i:int in range(17):
		var t:float=float(i)/16.0
		var sag:float=minf(start.distance_to(hook_point)*0.10,16.0) if hook_mode!=4 else 2.0
		points.append(start.lerp(hook_point,t)+Vector2.DOWN*(4.0*t*(1.0-t)*sag))
	rope.points=points
	bobber.visible=rope.visible
	bobber.global_position=hook_point
	sword.visible=sword_pose>0 and health>0 and is_combat_runtime_active()
	sword.global_position=sword_hilt()
	sword.global_rotation=sword_angle(sword_pose)
func Die() -> void:
	clear_sword_trails()
	cancel_pull_slash()
	break_line()
	super.Die()
func visual_state() -> Dictionary: return {"time":clock,"facing":facing,"mode":hook_mode,"point":hook_point,"sword":sword_pose,"sword_facing":_sword_facing,"sword_origin":_sword_origin,"pull_slash":_pull_slash_active,"retreat":_retreat_left}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	facing=data.get("facing",facing)
	hook_mode=data.get("mode",0)
	hook_point=data.get("point",global_position)
	sword_pose=data.get("sword",0.0)
	_sword_facing=data.get("sword_facing",facing)
	_sword_origin=data.get("sword_origin",global_position)
	_pull_slash_active=bool(data.get("pull_slash",false))
	_retreat_left=float(data.get("retreat",0.0))

func rod_line_origin() -> Vector2:
	# Character flipping can be shader-based; Sprite2D.flip_h is not authoritative.
	return image.to_global(Vector2(-6 if is_character_visual_flipped_h() else 6,-6))
func sword_hilt() -> Vector2:
	return _sword_origin+_sword_facing*14.0
func sword_angle(pose:float) -> float:
	return _sword_facing.angle()+PI/4.0+(0.13-pose)*9.0
func sword_segment(pose:float) -> PackedVector2Array:
	var angle:float=sword_angle(pose)
	var hilt:Vector2=sword_hilt()
	# The blade follows the native texture's bottom-left to top-right diagonal.
	return PackedVector2Array([hilt+Vector2(2,-2).rotated(angle)*1.25,hilt+Vector2(13,-13).rotated(angle)*1.25])
func advance_sword(delta:float) -> void:
	if sword_pose<=0.0: return
	var previous:float=sword_pose
	sword_pose=maxf(0.0,sword_pose-maxf(delta,0.0))
	var steps:int=maxi(1,ceili((previous-sword_pose)*9.0/0.06))
	for i:int in range(steps+1):
		var sample_pose:float=lerpf(previous,sword_pose,float(i)/steps)
		var segment:PackedVector2Array=sword_segment(sample_pose)
		var obstruction:Dictionary=U.trace(self,sword_hilt(),segment[1])
		var tip:Vector2=obstruction.get("position",segment[1])
		for other:Node in get_tree().get_nodes_in_group("Ball"):
			if not U.enemy(self,other) or _sword_hits.has(other.get_instance_id()): continue
			if U.segment_distance(other.global_position,segment[0],tip)>U.radius(other)+1.5: continue
			if not U.line_clear(self,sword_hilt(),other.global_position): continue
			_sword_hits[other.get_instance_id()]=true
			if U.damage(self,other,attack_damage(sword_damage_multiplier),sword_hilt()):
				# Generic hit/crit was already emitted by the damage sink.
				other.apply_knockback((other.global_position-_sword_origin).normalized(),28,250,0,0,{"source":self})
	if _pull_slash_active and sword_pose<=0.0: finish_pull_slash()
func client_visual_step(delta:float) -> void:
	if is_combat_runtime_active(): sword_pose=maxf(0.0,sword_pose-delta)

func step_pull_slash(_delta:float) -> void:
	if not is_instance_valid(_pull_slash_target) or not U.enemy(self,_pull_slash_target):
		_pull_slash_target=null
		return
	var offset:Vector2=_pull_slash_target.global_position-global_position
	var heading:Vector2=offset.normalized() if offset.length_squared()>0.001 else facing
	_pull_slash_target=null
	# Retrieval and retreat still happen during cooldown, but cannot insert,
	# restart, or queue another sword swing.
	direction=-heading
	_retreat_left=0.45
	_cast_left=maxf(_cast_left,_retreat_left)
	try_start_sword(heading,true)
func try_start_sword(heading:Vector2,from_reel:bool) -> bool:
	if not can_act() or _sword_left>0.0 or sword_pose>0.0 or _pull_slash_active: return false
	_sword_facing=heading.normalized() if heading.length_squared()>0.001 else facing
	_sword_origin=global_position
	facing=_sword_facing
	_pull_slash_active=from_reel
	sword_pose=SWORD_DURATION
	_sword_left=SWORD_COOLDOWN
	_sword_hits.clear()
	play_sound("entity.player.attack.sweep",-4.0)
	return true
func finish_pull_slash() -> void:
	_pull_slash_active=false
	# Do not overwrite a wall bounce or a newer movement direction on completion.
	_cast_left=maxf(_cast_left,_retreat_left)
	_sword_left=maxf(_sword_left,_retreat_left)
func cancel_pull_slash() -> void:
	_pull_slash_target=null
	_pull_slash_wait=0.0
	_pull_slash_active=false
	_retreat_left=0.0
func _process(delta:float) -> void:
	super._process(delta)
	if health<=0:
		clear_sword_trails()
		return
	if not is_combat_runtime_active(): return
	for i:int in range(_sword_trails.size()-1,-1,-1):
		var trail:Dictionary=_sword_trails[i]
		trail.age+=delta
		if not is_instance_valid(trail.sprite) or trail.age>=0.12:
			if is_instance_valid(trail.sprite): trail.sprite.queue_free()
			_sword_trails.remove_at(i)
		else: trail.sprite.modulate.a=0.38*pow(1.0-trail.age/0.12,1.3)
	_trail_wait-=delta
	if sword_pose<=0 or _trail_wait>0 or not is_instance_valid(sword): return
	_trail_wait=0.025
	var snapshot:=Sprite2D.new()
	snapshot.texture=PARTS.sword
	snapshot.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	snapshot.offset=sword.offset
	snapshot.top_level=true
	snapshot.z_as_relative=false
	snapshot.z_index=sword.z_index-1
	snapshot.modulate=Color(0.78,0.88,1.0,0.38)
	add_child(snapshot)
	snapshot.global_transform=sword.global_transform
	_sword_trails.append({"sprite":snapshot,"age":0.0})
func clear_sword_trails() -> void:
	for trail:Dictionary in _sword_trails:
		if is_instance_valid(trail.sprite):
			trail.sprite.hide()
			trail.sprite.queue_free()
	_sword_trails.clear()
