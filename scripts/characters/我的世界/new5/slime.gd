extends "res://scripts/characters/我的世界/new5/base.gd"
const JUMP_FX=preload("res://scripts/characters/我的世界/new5/slime_jump_fx.gd")
var _ground_offset:float=0.0
var _render_elapsed:float=0.0
var _render_rest:float=0.2
var _render_air:bool=false
const FRAMES=preload("res://Images/characters/我的世界/new5/slime.tres")
@export_range(0,2,1) var slime_stage:int=0
@export var jump_damage:float=8.0
@export var landing_damage:float=20.0
@export var death_knockback_distance:float=28.0
@export var landing_slow_ratio:float=0.62
@export var landing_slow_duration:float=0.8
var airborne:bool=false
var jump_elapsed:float=0.0
var jump_duration:float=0.64
var jump_distance:float=56.0
var jump_height:float=22.0
var rest_duration:float=0.42
var rest_left:float=0.2
var jump_direction:Vector2=Vector2.RIGHT
var _split:bool=false
var _death_pulse_done:bool=false
var _death_fx_rendered:bool=false
var jump_min_distance:float=4.0
var jump_max_distance:float=110.0
var _jump_remaining:float=0.0
var _jump_fx_nodes:Array[Node]=[]
@export var slime_family:String=""
@export var continuation_victory_key:String="":
	set(value):
		continuation_victory_key=value
		bind_split_identity()
@export var continuation_presentation_key:String="":
	set(value):
		continuation_presentation_key=value
		bind_split_identity()
@export var continuation_setup_id:int=-1:
	set(value):
		continuation_setup_id=value
		set_meta("battle_continuation_setup_id",value)
var _motion_phase:float=0.0
var _jump_lift:float=0.0
var _bar_base:Vector2
var _prepared_children:Array[Node2D]=[]
var _pending_character_direction:Vector2=Vector2.ZERO
var _last_turn_character_id:int=0
var _body_scale:Vector2
var _image_base:Vector2
const STAGE_FACTOR:Array[float]=[1.0,0.68,0.43]
func _ready() -> void:
	# Split slimes navigate independently; their jump/impact is the existing
	# locomotion and landing effect, not a second invented attack button.
	if slime_stage>0: manual_controllable_subentity=true
	if slime_family.is_empty(): slime_family=str(get_instance_id())
	motion_blur_enabled=false
	AfterImage_Speed=-1.0
	_configure_stage()
	rest_left=rest_duration
	_render_rest=rest_left
	bind_split_identity()
	super._ready()
	_body_scale=image.scale
	_image_base=image.position
	if is_instance_valid(health_bar):
		_bar_base=health_bar.position
		# Split children live under creatures/, so the shared character-only path skipped them.
		health_bar.get_script().call("prepare_minecraft_number_label",health_bar.label)
	_cache_ground_offset()
func _configure_stage() -> void:
	slime_stage=clampi(slime_stage,0,2)
	Max_health=[420,165,55][slime_stage]
	jump_damage=[16.0,9.0,4.0][slime_stage]
	landing_damage=[44.0,22.0,9.0][slime_stage]
	death_knockback_distance=[28.0,19.0,12.0][slime_stage]
	jump_duration=[0.64,0.45,0.30][slime_stage]
	rest_duration=[0.52,0.42,0.34][slime_stage]
	jump_min_distance=[4.0,3.0,2.0][slime_stage]
	jump_max_distance=[110.0,76.0,48.0][slime_stage]
	jump_distance=[56.0,36.0,22.0][slime_stage]
	jump_height=[30.0,21.0,14.0][slime_stage]
	var factor:float=STAGE_FACTOR[slime_stage]
	var sprite:Sprite2D=get_node("Graphics/Image")
	sprite.scale=Vector2.ONE*1.25*factor
	for path:String in ["CollisionShape2D","hitbox/CollisionShape2D","hurtbox/CollisionShape2D"]:
		var shape:CollisionShape2D=get_node(path)
		shape.scale=Vector2.ONE*factor
func step_mob(delta:float) -> void:
	if health<=0 or _death_visual_done: return
	if bool(get_meta("battle_death_bridge_active",false)): set_meta("battle_death_bridge_active",false)
	if airborne:
		# Character systems may change direction outside our own collision callback.
		if direction.length_squared()>0.001 and not direction.is_equal_approx(jump_direction):
			_pending_character_direction=direction.normalized()
			direction=jump_direction
		jump_elapsed=minf(jump_elapsed+delta,jump_duration)
	else:
		if not can_act(): return
		rest_left=maxf(0.0,rest_left-delta)
		if rest_left<=0 and not dizziness:
			jump_direction=player_control_direction if is_player_controlled() else direction
			if jump_direction.length_squared()<0.01: return
			jump_direction=jump_direction.normalized()
			plan_jump(jump_direction)
			airborne=true
			jump_elapsed=0
			emit_jump_fx(false)
			play_sound(voice_event("jump"),-6.0)
			if can_act(): _pulse(false)
func plan_jump(heading:Vector2) -> void:
	# Lock this jump at takeoff: no mid-air homing or overshooting nearby victims.
	jump_direction=heading.normalized()
	var desired:float=[56.0,36.0,22.0][slime_stage]
	var nearest_along:float=INF
	var own_radius:float=U.radius(self)
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not slime_enemy(target): continue
		var body:Vector2=U.point(target,global_position) # tall bodies: their nearest part
		var offset:Vector2=body-global_position
		var along:float=offset.dot(jump_direction)
		var lateral:float=absf(offset.cross(jump_direction))
		if along<0.0 or along>jump_max_distance*3.0 or lateral>U.radius(target)+own_radius*0.7: continue
		if along>=nearest_along or not U.line_clear(self,global_position,body): continue
		nearest_along=along
		desired=along-own_radius-U.radius(target)-2.0
	jump_distance=clampf(desired,jump_min_distance,jump_max_distance)
	# Keep the travel budget at walls: physical contact must be able to reflect it.
	var ratio:float=clampf(jump_distance/jump_max_distance,0.0,1.0)
	var speed_ratio:float=clampf(Speed/maxf(float(default_properties.get("Speed",90.0)),0.001),0.5,1.6)
	jump_duration=lerpf([0.38,0.30,0.24][slime_stage],[0.76,0.58,0.44][slime_stage],sqrt(ratio))/speed_ratio
	jump_height=lerpf([12.0,9.0,6.0][slime_stage],[40.0,28.0,19.0][slime_stage],sqrt(ratio))
	_jump_remaining=jump_distance
	_motion_phase=0.0
	_jump_lift=0.0
	_pending_character_direction=Vector2.ZERO
	_last_turn_character_id=0
func stand(delta:float) -> void:
	# A motion lock selects Stand, but step_mob still advances the airborne clock.
	# Consume this frame's arc here too: never bank flight motion for the first
	# Move frame after knockback/stun. Repel stays additive at the current position.
	if airborne and active():
		move(0.0,delta)
	else:
		super.stand(delta)
func move(_speed:float,_delta:float) -> void:
	# Travel budget remains bounded across bounces, including with speed buffs.
	var t:float=clampf(jump_elapsed/jump_duration,0.0,1.0)
	var portion:float=(3.0*t*t-2.0*t*t*t)-(3.0*_motion_phase*_motion_phase-2.0*_motion_phase*_motion_phase*_motion_phase)
	var distance:float=minf(_jump_remaining,jump_distance*maxf(portion,0.0)) if airborne else 0.0
	_jump_remaining=maxf(0.0,_jump_remaining-distance)
	# Suppressed voluntary travel expires with its frame, rather than replaying
	# against the knockback on recovery. Ballistic rise/fall continues smoothly.
	if dizziness: distance=0.0
	var height:float=4.0*t*(1.0-t)*jump_height if airborne else 0.0
	var lift_motion:Vector2=Vector2.UP*(height-_jump_lift)
	_jump_lift=height
	_motion_phase=t
	# The entire CharacterBody2D follows the arc; move_and_slide sweeps all shapes.
	velocity=(jump_direction*distance+lift_motion)/maxf(_delta,0.00001)+Repel
	_last_requested_velocity=velocity
	if velocity.length_squared()>0.001:
		move_and_slide()
		# Process all contacts so a character cannot hide a wall hit in the same tick.
		for collision_index:int in range(get_slide_collision_count()):
			when_collide(_speed,get_slide_collision(collision_index))
	Repel=Vector2.ZERO
	if airborne and jump_elapsed>=jump_duration:
		airborne=false
		apply_landing_direction()
		_jump_lift=0.0
		jump_elapsed=0.0
		rest_left=rest_duration
		emit_jump_fx(true)
		play_sound(voice_event("squish"),-5.0)
		if can_act(): _pulse(true)
func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	if not airborne:
		super.when_collide(speed,collision)
		return
	var normal:Vector2=collision.get_normal().normalized()
	var collider:Object=collision.get_collider()
	# Keep shared collision sound/feedback, but separate its direction mutation.
	super.when_collide(speed,collision)
	if collider is ball:
		# A sustained slide against the same actor is one contact, not a new turn
		# every tick as the circle normal rotates around its body.
		if collider.get_instance_id()!=_last_turn_character_id and jump_direction.dot(normal)<-0.0001:
			_last_turn_character_id=collider.get_instance_id()
			_pending_character_direction=jump_direction.bounce(normal).normalized()
		direction=jump_direction
	else:
		if jump_direction.dot(normal)<-0.0001:
			jump_direction=jump_direction.bounce(normal).normalized()
		# A later wall contact must not let the deferred heading point back into it.
		if _pending_character_direction.dot(normal)<-0.0001:
			_pending_character_direction=_pending_character_direction.bounce(normal).normalized()
		direction=jump_direction
func apply_landing_direction() -> void:
	if _pending_character_direction.length_squared()>0.001:
		direction=_pending_character_direction.normalized()
		jump_direction=direction
	_pending_character_direction=Vector2.ZERO
func split_preparation_state() -> Dictionary:
	# World-owned cache dies with the match; no script-static resource lifetime.
	var tree:SceneTree=get_tree()
	var world:Node=tree.current_scene if tree!=null else null
	if not is_instance_valid(world): return {"frame":-1,"total":0,"shadow":{}}
	if not world.has_meta("mc_slime_preparation"):
		world.set_meta("mc_slime_preparation",{"frame":-1,"total":0,"shadow":{}})
	return world.get_meta("mc_slime_preparation")
func _character_ground_shadow_body_metrics() -> Dictionary:
	# All three stages share one immutable texture; scan it only once per match.
	var shared:Dictionary=split_preparation_state()
	var metrics:Dictionary=shared.shadow
	var origin:Vector2=to_local(image.to_global(Vector2.ZERO))
	var unit_x:float=origin.distance_to(to_local(image.to_global(Vector2.RIGHT)))
	if metrics.is_empty():
		var sampled:Dictionary=super._character_ground_shadow_body_metrics()
		if sampled.is_empty() or unit_x<=0.00001: return sampled
		metrics={"width":float(sampled.body_width)/unit_x,"foot":image.to_local(to_global(sampled.foot_point))}
		shared.shadow=metrics
	return {"body_width":float(metrics.width)*unit_x,"foot_point":to_local(image.to_global(metrics.foot))}
func slime_enemy(target:Variant) -> bool:
	if not U.enemy(self,target): return false
	return not (target.get_script()==get_script() and target.slime_family==slime_family)
func pulse_radius(landing:bool) -> float:
	return ([32.0,21.5,14.5] if landing else [18.0,12.0,7.5])[slime_stage]
func pulse_contains(target:ball,landing:bool) -> bool:
	return _pulse_contains_from(target,landing,global_position)
func _pulse_contains_from(target:ball,landing:bool,center:Vector2) -> bool:
	var distance:float=center.distance_to(U.point(target,center))
	var in_circle:bool=distance<=pulse_radius(landing)+U.radius(target)
	var touching_at_takeoff:bool=not landing and distance<=U.radius(self)+U.radius(target)+0.5
	return in_circle or touching_at_takeoff
func get_debug_attack_regions() -> Array[Dictionary]:
	if health<=0: return []
	var regions:Array[Dictionary]=[
		{"shape":"circle","position":global_position,"radius":pulse_radius(false),"damage":jump_damage,"kind":"slime_takeoff"},
		{"shape":"circle","position":global_position,"radius":pulse_radius(true),"damage":landing_damage,"kind":"slime_landing"}
	]
	if not airborne:
		regions.append({"shape":"circle","position":global_position,"radius":U.radius(self)+0.5,"damage":jump_damage,"kind":"slime_takeoff_contact"})
	elif ground_point().distance_squared_to(global_position)>1.0:
		# An airborne death bursts on the projected ground, not at body height.
		regions.append({"shape":"circle","position":ground_point(),"radius":pulse_radius(true),"damage":landing_damage,"kind":"slime_death"})
	return regions
func _pulse(landing:bool,death:bool=false) -> void:
	var hit:bool=false
	var center:Vector2=ground_point() if death else global_position
	var hit_point:Vector2=center
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not slime_enemy(target) or not _pulse_contains_from(target,landing,center): continue
		if not U.line_clear(self,center,U.point(target,center)): continue
		if not U.damage(self,target,attack_damage((landing_damage if landing else jump_damage)/maxf(float(default_properties.get("Damage",Damage)),0.01)),center): continue
		if not hit: hit_point=U.point(target,center)
		hit=true
		if death:
			var outward:Vector2=ball.body_point(target,center)-center
			if outward.length_squared()<0.0001: outward=Vector2.RIGHT
			target.apply_knockback(outward.normalized(),death_knockback_distance,160.0,0,0,{"source":self,"lock_control":false})
		elif landing: U.slow(self,target,landing_slow_ratio,landing_slow_duration,"史莱姆落地")
		else: target.apply_knockback((ball.body_point(target,global_position)-global_position).normalized(),[9.0,6.0,3.0][slime_stage],110.0,0,0,{"source":self,"lock_control":false})
	# Each victim now reports its own final HP damage through ball.
func _process(delta:float) -> void:
	prepare_split_child()
	if health<=0 or _death_visual_done:
		clear_jump_fx()
	if health>0 and is_combat_runtime_active():
		if _render_air!=airborne:
			_render_air=airborne
			_render_elapsed=jump_elapsed
			_render_rest=rest_left
		elif airborne:
			_render_elapsed=minf(_render_elapsed+delta,jump_duration)
		else:
			_render_rest=maxf(_render_rest-delta,0.0)
	super._process(delta)
func _ease_shape(a:float,b:float,t:float) -> float:
	return lerpf(a,b,smoothstep(0.0,1.0,clampf(t,0.0,1.0)))
func body_stretch(in_air:bool,phase:float) -> float:
	if in_air:
		# Vertical speed is the derivative of the ballistic height curve.
		var vertical_speed:float=absf(4.0*jump_height*(1.0-2.0*phase)/jump_duration)
		var horizontal_speed:float=6.0*phase*(1.0-phase)*jump_distance/jump_duration
		var speed:float=Vector2(horizontal_speed,vertical_speed).length()
		var reference_speed:float=[230.0,210.0,190.0][slime_stage]
		var stretched:float=1.0+0.62*clampf(speed/reference_speed,0.0,1.0)
		# Rapid, continuous release from the fully compressed preload.
		return _ease_shape(0.55,stretched,phase/0.14)
	# Impact/recovery first, then a long unmistakable preload and brief hold.
	var impact:float=body_stretch(true,1.0)
	if phase<0.16: return _ease_shape(impact,0.64,phase/0.16)
	if phase<0.34: return _ease_shape(0.64,1.08,(phase-0.16)/0.18)
	if phase<0.45: return _ease_shape(1.08,1.0,(phase-0.34)/0.11)
	if phase<0.90: return _ease_shape(1.0,0.55,(phase-0.45)/0.45)
	return 0.55
func visual_mob() -> void:
	if health<=0 or _death_visual_done: return
	face_horizontal(jump_direction if airborne else (player_control_direction if is_player_controlled() else direction))
	if _body_scale==Vector2.ZERO: return
	frame(FRAMES)
	var t:float=clampf(_render_elapsed/jump_duration,0,1) if airborne else 0.0
	var phase:float=t if airborne else clampf(1.0-_render_rest/rest_duration,0.0,1.0)
	var stretch:float=body_stretch(airborne,phase)
	# Rough volume preservation; deform around feet instead of sprite centre.
	image.scale=_body_scale*Vector2(1.0/sqrt(stretch),stretch)
	var foot_local:float=_ground_offset
	image.position=_image_base+Vector2(0,foot_local*(1.0-stretch))
	# The health bar inherits the real root displacement, with the body's squash offset.
	if is_instance_valid(health_bar): health_bar.position=_bar_base+Vector2(0,foot_local*(1.0-stretch))
	if is_instance_valid(_character_ground_shadow):
		var lift_ratio:float=clampf(_jump_lift/maxf(jump_height,0.001),0.0,1.0)
		_character_ground_shadow.global_position=ground_point()
		_character_ground_shadow.scale=Vector2.ONE*lerpf(1.0,0.55,lift_ratio)
		_character_ground_shadow.modulate.a=lerpf(1.0,0.40,lift_ratio)
func client_visual_step(delta:float) -> void:
	if not is_combat_runtime_active(): return
	if airborne: jump_elapsed=minf(jump_elapsed+delta,jump_duration)
	else: rest_left=maxf(rest_left-delta,0.0)
func split_scene() -> PackedScene:
	# Reuse the world's resource-only warmer; a script-static PackedScene here
	# would form a reference cycle because child scenes use this same script.
	var child_name:String="史莱姆_中" if slime_stage==0 else "史莱姆_小"
	var world:Node=get_tree().current_scene
	var warmer:Node=world.get("_mc_prewarmer") if world!=null and world.has_method("register_battle_unit") else null
	if is_instance_valid(warmer) and warmer.scenes.has(child_name): return warmer.scenes[child_name]
	return load("res://scenes/creatures/我的世界/"+child_name+".tscn")
func prepare_split_child() -> void:
	# Off-tree preparation: no _ready, collisions, groups, timers, RPC or combat.
	# Global budget: at most one prototype per rendered frame, 64 held in total.
	if not is_multiplayer_authority() or health<=0 or _split or slime_stage>=2: return
	var shared:Dictionary=split_preparation_state()
	if _prepared_children.size()>=2 or int(shared.total)>=64: return
	var frame_id:int=Engine.get_process_frames()
	if int(shared.frame)==frame_id: return
	shared.frame=frame_id
	var child:Node2D=split_scene().instantiate()
	child.get_node("Health_Bar").get_script().call("prepare_minecraft_number_label",child.get_node("Health_Bar/TextureRect/Label"))
	_prepared_children.append(child)
	shared.total=int(shared.total)+1
func take_split_child() -> Node2D:
	if not _prepared_children.is_empty():
		var shared:Dictionary=split_preparation_state()
		shared.total=maxi(0,int(shared.total)-1)
		return _prepared_children.pop_back()
	# Immediate deaths still split correctly; never delay damage/death for a pool.
	return split_scene().instantiate()
func discard_prepared_children() -> void:
	for child:Node2D in _prepared_children:
		if is_instance_valid(child): child.free()
	var shared:Dictionary=split_preparation_state()
	shared.total=maxi(0,int(shared.total)-_prepared_children.size())
	_prepared_children.clear()
func bind_split_identity() -> void:
	if continuation_victory_key.is_empty(): return
	set_meta("battle_continuation_victory_side_key",continuation_victory_key)
	set_meta("victory_side_key",continuation_victory_key)
	set_meta("battle_continuation_presentation_side_key",continuation_presentation_key)
	set_meta("battle_continuation_display_name","史莱姆")
func split_identity() -> Dictionary:
	if not continuation_victory_key.is_empty():
		return {"victory":continuation_victory_key,"presentation":continuation_presentation_key,"setup":continuation_setup_id}
	var world:Node=get_tree().current_scene
	var setup:int=int(get_meta("battle_setup_id",-1))
	var victory:String="team:"+Team if not Team.is_empty() else "solo_setup:"+str(setup) if setup>=0 else "solo_instance:"+str(get_instance_id())
	var presentation:String="team:"+Team if not Team.is_empty() else "solo:"+str(get_instance_id())
	if world!=null and world.has_method("_victory_side_key_for_character"): victory=world._victory_side_key_for_character(self)
	if world!=null and world.has_method("return_ball_side_key"): presentation=world.return_ball_side_key(self)
	return {"victory":victory,"presentation":presentation,"setup":setup}
func arm_split_bridge() -> void:
	if not is_multiplayer_authority() or _split or slime_stage>=2: return
	var identity:Dictionary=split_identity()
	set_meta("battle_death_bridge_victory_side_key",identity.victory)
	set_meta("battle_death_bridge_presentation_side_key",identity.presentation)
	set_meta("battle_death_bridge_display_name","史莱姆")
	set_meta("battle_death_bridge_active",true)
func on_actual_health_damage_received(amount:float,before:float) -> void:
	# Arm synchronously in the health setter, before the next World victory poll.
	if is_inside_tree() and health<=0:
		arm_split_bridge()
		_trigger_death_pulse()
	super.on_actual_health_damage_received(amount,before)
func _trigger_death_pulse() -> void:
	if _death_pulse_done or not is_multiplayer_authority() or not is_inside_tree(): return
	_death_pulse_done=true
	var point:Vector2=ground_point()
	var visual_seed:int=_voice_rng.randi()
	if multiplayer.has_multiplayer_peer(): _jump_fx.rpc(point,true,slime_stage,visual_seed,true)
	_jump_fx(point,true,slime_stage,visual_seed,true)
	# The landing hit already uses current Damage and target defenses; death
	# adds a push instead of the ordinary landing slow. Resolve before splitting.
	_pulse(true,true)
func inherit_split_identity(child:Node2D) -> void:
	var identity:Dictionary=split_identity()
	child.Team=Team
	child.Master=self
	child.Master_name=str(get_path())
	child.slime_family=slime_family
	child.continuation_victory_key=identity.victory
	child.continuation_presentation_key=identity.presentation
	child.continuation_setup_id=identity.setup
	child.set_multiplayer_authority(get_multiplayer_authority())
	# Write identity before ready/registration/spawn replication. Never copy the
	# root battle_setup_id: descendants are not new roster entries to respawn.
	var world:Node=get_tree().current_scene
	var side:String=str(get_meta("rotation_side",""))
	if not side.is_empty() and int(identity.setup)>=0 and world.has_method("_on_rotation_character_tree_exiting"):
		child.set_meta("rotation_side",side)
		child.tree_exiting.connect(Callable(world,"_on_rotation_character_tree_exiting").bind(child,side,int(identity.setup)),CONNECT_ONE_SHOT)
func Die() -> void:
	arm_split_bridge()
	_trigger_death_pulse()
	clear_jump_fx()
	airborne=false
	if not _split and is_multiplayer_authority():
		_split=true
		if slime_stage<2:
			for sign_value:float in [-1.0,1.0]:
				var child:Node2D=take_split_child()
				inherit_split_identity(child)
				child.direction=direction.rotated(sign_value*0.7).normalized()
				if child.direction==Vector2.ZERO: child.direction=Vector2(sign_value,0)
				var world:Node=get_tree().current_scene
				child.position=world.to_local(global_position) if world is Node2D else global_position
				child.name=Game.return_random_name(child)
				get_tree().current_scene.add_child(child,true)
				child.add_to_group("BattleTransient")
				# Separate through collision-aware movement, never spawn inside a wall.
				child.move_and_collide(Vector2(sign_value*10.0,0))
	# Both registered descendants now represent this side; no death-frame gap.
	set_meta("battle_death_bridge_active",false)
	super.Die()
func visual_state() -> Dictionary: return {"time":clock,"stage":slime_stage,"air":airborne,"elapsed":jump_elapsed,"rest":rest_left,"jump_direction":jump_direction,"duration":jump_duration,"distance":jump_distance,"height":jump_height,"lift":_jump_lift,"family":slime_family}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	var stage:int=int(data.get("stage",slime_stage))
	if stage!=slime_stage:
		slime_stage=stage
		_configure_stage()
		_body_scale=image.scale
		_cache_ground_offset()
	airborne=bool(data.get("air",false))
	jump_elapsed=float(data.get("elapsed",0))
	rest_left=float(data.get("rest",rest_left))
	jump_direction=data.get("jump_direction",jump_direction)
	jump_duration=float(data.get("duration",jump_duration))
	jump_distance=float(data.get("distance",jump_distance))
	jump_height=float(data.get("height",jump_height))
	_jump_lift=float(data.get("lift",_jump_lift))
	slime_family=str(data.get("family",slime_family))
	if absf(_render_elapsed-jump_elapsed)>0.12: _render_elapsed=jump_elapsed
	if absf(_render_rest-rest_left)>0.12: _render_rest=rest_left

func voice_role() -> String: return "slime"
func voice_event(kind:String) -> String:
	return "entity.slime."+kind+("_small" if slime_stage==2 and kind in ["jump","squish","hurt","death"] else "")

func _cache_ground_offset() -> void:
	var texture:Texture2D=FRAMES.get_frame_texture(&"idle",0)
	# Renderer foot=180 is the ground-plane centre. Alpha bounds end=202 is
	# the FRONT of the projected cube, not the centre of its footprint.
	_ground_offset=(180.0-texture.get_height()*0.5)*_body_scale.y
func ground_point() -> Vector2:
	# Stable resting feet, independent of the airborne sprite's vertical offset.
	return get_node("Graphics").to_global(_image_base+Vector2(0,_ground_offset))+Vector2.DOWN*_jump_lift
func emit_jump_fx(is_landing:bool) -> void:
	if not is_multiplayer_authority() or health<=0 or _death_visual_done: return
	var point:Vector2=ground_point()
	var visual_seed:int=_voice_rng.randi()
	if multiplayer.has_multiplayer_peer(): _jump_fx.rpc(point,is_landing,slime_stage,visual_seed)
	_jump_fx(point,is_landing,slime_stage,visual_seed)
@rpc("authority","call_remote","reliable")
func _jump_fx(point:Vector2,is_landing:bool,stage:int,visual_seed:int,death_burst:bool=false) -> void:
	if death_burst:
		if _death_fx_rendered: return
		_death_fx_rendered=true
	elif health<=0 or _death_visual_done or _split: return
	var safe_stage:int=clampi(stage,0,2)
	# Preserve Array[Node] and never pass freed instances to a typed callback.
	for index:int in range(_jump_fx_nodes.size()-1,-1,-1):
		if not is_instance_valid(_jump_fx_nodes[index]) or _jump_fx_nodes[index].is_queued_for_deletion():
			_jump_fx_nodes.remove_at(index)
	var effect:Node=JUMP_FX.spawn(self,point,is_landing,STAGE_FACTOR[safe_stage],pulse_radius(is_landing),visual_seed,death_burst)

	if is_instance_valid(effect) and not death_burst: _jump_fx_nodes.append(effect)
func clear_jump_fx() -> void:
	for effect:Node in _jump_fx_nodes:
		if is_instance_valid(effect):
			effect.hide()
			effect.queue_free()
	_jump_fx_nodes.clear()
func _exit_tree() -> void:
	discard_prepared_children()
	clear_jump_fx()
	super._exit_tree()
