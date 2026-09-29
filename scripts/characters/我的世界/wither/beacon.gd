extends "res://scripts/characters/我的世界/new5/base.gd"
## A summoned, targetable vanilla beacon: gravity, horizontal drive and a vertical beam.
const BEACON_TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_block/beacon_block.png")
const HEART_TEXTURE = preload("res://Images/characters/我的世界/wither/nether_star.png")
const VANILLA_SOUND = preload("res://scripts/characters/我的世界/wither/audio.gd")
const BEAM_VISUAL = preload("res://scripts/characters/我的世界/wither/beacon_beam.gd")
const EMITTER=preload("res://scripts/characters/我的世界/wither/beacon_emitter.gd")
const GLOW=preload("res://scripts/characters/我的世界/wither/beacon_glow.gd")
const RING_VISUAL = preload("res://scripts/characters/我的世界/wither/beacon_ring.gd")
const PROFILE = preload("res://scripts/characters/我的世界/wither/beacon_profile.gd")
const SUMMON_FX = preload("res://scripts/characters/我的世界/wither/beacon_summon_fx.gd")
const GRAVITY:float = 1200.0
const TERMINAL_SPEED:float = 1100.0
const EPSILON:float = 0.0000001
# This Wither beacon samples four level-I primaries: never grant Jump Boost.
# Regeneration is a secondary/full-pyramid effect, not part of this pool.
const BUFFS:Array[String] = ["speed","haste","resistance","strength"]
var _activated:bool = false
var _beam_visual:Node2D
var _core_glow:Node2D
var _ring_back:Node2D
var _ring_front:Node2D
var _body:CollisionShape2D
var _damage_shape:=RectangleShape2D.new()
var _pulse_index:int = 0
var damage_ticks:int = 0
const REBOUND_DURATION:float = 0.35
var _rebound_left:float = 0.0
var _rebound_heading:float = 0.0
var horizontal_bounces:int = 0
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
var _summon_fx:Node2D
var _summon_origin:Vector2
var _summon_target:Vector2
var _summon_flight:float = 0.80
var _summon_elapsed:float = 0.0
var _summon_landed_at:float = -1.0
var _summon_morph_at:float = -1.0
var _summon_initialized:bool = false
var _beacon_hum:AudioStreamPlayer2D
func _ready() -> void:
	manual_controllable_subentity=true
	Has_Collision_Damage=false
	Can_Attack=false
	Can_Skill=false
	Health_Restore=0
	super._ready()
	if image is Sprite2D:
		image.texture=BEACON_TEXTURE
		image.visible=false
	if is_instance_valid(health_bar):
		health_bar.visible=false
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_body=get_node("CollisionShape2D")
	if is_instance_valid(Master) and Master is PhysicsBody2D: add_collision_exception_with(Master)
	_summon_origin=Master.global_position if is_instance_valid(Master) else global_position
	_summon_target=_summon_origin
	_summon_fx=SUMMON_FX.new()
	_summon_fx.name="NetherStarSummon"
	add_child(_summon_fx)
	_summon_fx.call("setup",image,body_width())
	_beacon_hum=AudioStreamPlayer2D.new()
	_beacon_hum.name="BeaconBeamHum"
	var hum_stream:AudioStreamOggVorbis=VANILLA_SOUND.STREAMS["beacon_ambient"].duplicate() as AudioStreamOggVorbis
	hum_stream.loop=true
	_beacon_hum.stream=hum_stream
	_beacon_hum.volume_db=-4.0
	_beacon_hum.max_distance=1800.0
	add_child(_beacon_hum)
	call_deferred("_initialize_summon")
	_ring_back=RING_VISUAL.new()
	_ring_back.name="BeaconTopRingBack"
	_ring_back.top_level=true
	_ring_back.show_behind_parent=true
	add_child(_ring_back)
	_beam_visual=BEAM_VISUAL.new()
	_beam_visual.name="VanillaBeaconBeam"
	_beam_visual.top_level=true # Animation, damage and threat all use world units.
	add_child(_beam_visual)
	_core_glow=GLOW.new()
	_core_glow.name="BeaconCoreEmission"
	_core_glow.on_core=true
	_core_glow.top_level=true
	add_child(_core_glow)
	_ring_front=RING_VISUAL.new()
	_ring_front.name="BeaconTopRingFront"
	_ring_front.top_level=true
	_ring_front.front_half=true
	add_child(_ring_front)
	add_to_group("AI_Hazard")
	add_to_group("WitherBeacon")
func _initialize_summon() -> void:
	if _summon_initialized: return
	_summon_origin=Master.global_position if is_instance_valid(Master) else global_position
	_summon_target=_first_support_below(_summon_origin)
	_summon_flight=SUMMON_FX.flight_duration(_summon_origin.distance_to(_summon_target))
	_summon_initialized=true
func _first_support_below(from:Vector2) -> Vector2:
	# The same first physical floor that catches the falling body, including
	# intervening platforms; never teleport the character through a wall.
	var half_height:float=_body.shape.get_rect().size.y*absf(_body.global_scale.y)*0.5
	var arena:Rect2=Master.call("mc_arena_rect") if is_instance_valid(Master) else Rect2()
	var bottom:float=maxf(from.y+64.0,arena.end.y+64.0) if arena.has_area() else from.y+4096.0
	var exclude:Array[RID]=[get_rid()]
	if Master is PhysicsBody2D: exclude.append((Master as PhysicsBody2D).get_rid())
	var ray:=PhysicsRayQueryParameters2D.create(from,Vector2(from.x,bottom),1,exclude)
	var hit:Dictionary=get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and Vector2(hit.normal).y < -0.5:
		return Vector2(from.x,float(hit.position.y)-half_height-0.01)
	return Vector2(from.x,(arena.end.y if arena.has_area() else from.y+150.0)-half_height)
func _advance_summon(dt:float) -> void:
	_summon_elapsed+=dt
	if _summon_morph_at>=0.0: return
	if not landed:
		if _summon_landed_at>=0.0: _summon_landed_at=-1.0
		return
	if _summon_landed_at<0.0: _summon_landed_at=_summon_elapsed
	if _summon_elapsed <= _summon_flight:
		_summon_target=global_position
	if _summon_elapsed >= maxf(_summon_flight,_summon_landed_at)+SUMMON_FX.SHAKE_DURATION:
		_summon_target=global_position
		_summon_morph_at=_summon_elapsed
		if multiplayer.has_multiplayer_peer(): _remote_summon_morph.rpc(_summon_morph_at,_summon_target)
		if image is Sprite2D: image.visible=true
		if is_instance_valid(health_bar): health_bar.visible=true
		_emit_sound("beacon_morph")
func _start_beacon_hum() -> void:
	if is_instance_valid(_beacon_hum) and not _beacon_hum.playing: _beacon_hum.play()
func _stop_beacon_hum() -> void:
	if is_instance_valid(_beacon_hum) and _beacon_hum.playing: _beacon_hum.stop()
func get_preview_texture() -> Texture2D: return BEACON_TEXTURE
func voice_role() -> String: return ""
func move(_speed:float,_delta:float) -> void: pass
func stand(_delta:float): Repel=Vector2.ZERO
func movement_multiplier() -> float: return PROFILE.speed_factor(warning_left,firing_left)
func body_width() -> float:
	return _body.shape.get_rect().size.x*absf(_body.global_scale.x)
func emitter_width() -> float: return EMITTER.core_width(body_width())
func beam_width() -> float: return PROFILE.width(emitter_width(),warning_left,firing_left)
func beam_opacity() -> float: return PROFILE.opacity(warning_left,firing_left)
func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not active() or _summon_morph_at<0.0 or not has_player_control_aim(): return
	if warning_left>EPSILON or firing_left>EPSILON or beam_timer>EPSILON: return
	var point:Vector2=player_control_aim_world_position()
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball) or not U.enemy(self,raw): continue
		if ball.body_point(raw,point).distance_to(point)<=U.radius(raw)+6.0:
			warning_left=PROFILE.WARNING # Existing vertical beam, now intentionally fired.
			return
func step_mob(delta:float) -> void:
	if not active(): return
	var master:ball=Master as ball if is_instance_valid(Master) and Master is ball else null
	if master==null or master.health<=0: queue_free(); return
	if health<=0 or _death_sound_done: return
	if not _summon_initialized: _initialize_summon()
	var target:ball=null if is_player_controlled() else U.nearest(self)
	var remaining:float=maxf(delta,0.0)
	# Split at physics steps AND phase/pulse boundaries. Even a slow frame samples
	# a moving ray at each scheduled hit, not all accumulated hits at its final location.
	while remaining>EPSILON:
		if _summon_morph_at>=0.0 and warning_left<=EPSILON and firing_left<=EPSILON and beam_timer<=EPSILON and is_instance_valid(target) and not is_player_controlled():
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
		_rebound_left=maxf(_rebound_left-dt,0.0)
		var horizontal:float=0.0
		if _summon_morph_at>=0.0 and not dizziness and bool(Game.Game_Settings.get("Ball_Can_Move",true)):
			var speed:float=maxf(Speed,0.0)*movement_multiplier()
			if _rebound_left>0:
				horizontal=_rebound_heading*speed
			elif is_player_controlled(): horizontal=player_control_direction.x*speed
			elif is_instance_valid(target):
				horizontal=clampf((target.global_position.x-global_position.x)/dt,-speed,speed)
		_gravity_step(dt,horizontal)
		_advance_summon(dt)
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
					# Midpoint samples: 0.05, 0.15 ... 4.95 = 50 pulses/300 base damage.
					tick_left=PROFILE.INTERVAL*0.5
					_pulse_index=0
					# Grant the one effect when the beam actually fires, not five seconds
					# later when it fades. The warning itself grants nothing.
					last_buff=BUFFS[rng.randi_range(0,BUFFS.size()-1)]
					master.call("apply_beacon_buff",last_buff)
					_emit_sound("beacon_activate")
					_emit_sound("beacon_power")
					_start_beacon_hum()
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
					_stop_beacon_hum()
					_emit_sound("beacon_deactivate")
					beams_fired+=1
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
	for node:Variant in SubmissionCharacterTools.targeting_candidates(master):
		if not is_instance_valid(node): continue
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
		# Crowd mode normally drops the body mask; keep gameplay side rebounds.
		# Restore the mask immediately, without changing gravity/support behavior.
		var old_mask:int=collision_mask
		collision_mask=old_mask|2
		var side:KinematicCollision2D=move_and_collide(Vector2(motion_x*dt,0.0),false,0.001,false)
		collision_mask=old_mask
		if side!=null:
			velocity.x=0.0
			var normal_x:float=side.get_normal().x
			if absf(normal_x)>0.5 and motion_x*normal_x<0.0:
				_rebound_heading=signf(normal_x)
				_rebound_left=REBOUND_DURATION
				horizontal_bounces+=1
				direction=Vector2(_rebound_heading,0.0)
				velocity.x=absf(motion_x)*_rebound_heading
				_last_requested_velocity=Vector2(motion_x,0.0)
				when_collide(absf(motion_x),side)
	# Keep physical gravity/landing. While held, vertical WASD can lift or
	# descend the activated beacon; letting go returns to the original gravity.
	if is_player_controlled() and _activated and not dizziness and bool(Game.Game_Settings.get("Ball_Can_Move",true)) and absf(player_control_direction.y)>0.01:
		fall_speed=player_control_direction.y*maxf(Speed,0.0)*movement_multiplier()
	else: fall_speed=minf(fall_speed+GRAVITY*dt,TERMINAL_SPEED)
	velocity.y=fall_speed
	var down:KinematicCollision2D=move_and_collide(Vector2(0.0,fall_speed*dt),false,0.001,false)
	landed=down!=null and down.get_normal().y < -0.5
	if down!=null:
		fall_speed=0.0
		velocity.y=0.0
	if landed and not _activated:
		_activated=true
func beam_origin() -> Vector2:
	return global_position+EMITTER.beam_tip(body_width())
func ring_origin() -> Vector2:
	# The launch ring stays on the glass TOP plane; only the emitter moves inside.
	return global_position+EMITTER.glass_center(body_width())
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
	var active_beam:bool=firing_left>EPSILON
	_stop_beacon_hum()
	if active_beam and is_multiplayer_authority(): _emit_sound("beacon_deactivate")
	warning_left=0.0
	firing_left=0.0
	if is_instance_valid(_summon_fx): _summon_fx.call("render",_summon_elapsed,_summon_origin,_summon_target,_summon_flight,-1.0,false)
	if is_instance_valid(_beam_visual): _beam_visual.hide()
	if is_instance_valid(_core_glow): _core_glow.hide()
	if is_instance_valid(_ring_back): _ring_back.hide()
	if is_instance_valid(_ring_front): _ring_front.hide()
	if is_instance_valid(Master) and Master.has_method("apply_beacon_buff"): Master.call("apply_beacon_buff","")
	super.Die()
func visual_mob() -> void:
	if is_instance_valid(_summon_fx):
		var morph_age:float=_summon_elapsed-_summon_morph_at if _summon_morph_at>=0.0 else -1.0
		_summon_fx.call("render",_summon_elapsed,_summon_origin,_summon_target,_summon_flight,morph_age,health>0 and not _death_sound_done)
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
	return {"time":clock,"activated":_activated,"landed":landed,"warning":warning_left,"firing":firing_left,"beam_end":beam_end,
		"summon_origin":_summon_origin,"summon_target":_summon_target,"summon_flight":_summon_flight,
		"summon_elapsed":_summon_elapsed,"summon_morph_at":_summon_morph_at}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_summon_origin=data.get("summon_origin",_summon_origin)
	_summon_target=data.get("summon_target",_summon_target)
	_summon_flight=float(data.get("summon_flight",_summon_flight))
	_summon_elapsed=float(data.get("summon_elapsed",_summon_elapsed))
	_summon_morph_at=float(data.get("summon_morph_at",_summon_morph_at))
	_summon_initialized=true
	_activated=bool(data.get("activated",_activated))
	landed=bool(data.get("landed",landed))
	warning_left=float(data.get("warning",0.0))
	firing_left=float(data.get("firing",0.0))
	beam_end=data.get("beam_end",beam_end)
	if image is Sprite2D: image.visible=_summon_morph_at>=0.0
	if is_instance_valid(health_bar): health_bar.visible=_summon_morph_at>=0.0
@rpc("authority","call_remote","reliable")
func _remote_summon_morph(at:float,at_position:Vector2) -> void:
	_summon_elapsed=maxf(_summon_elapsed,at)
	_summon_target=at_position
	_summon_morph_at=at
	_summon_initialized=true
	if is_instance_valid(health_bar): health_bar.visible=true
	_emit_sound("beacon_morph")
func client_visual_step(delta:float) -> void:
	# Interpolate the supplied phase locally instead of visibly stepping at RPC rate.
	if not is_combat_runtime_active(): return
	if health>0: _summon_elapsed+=maxf(delta,0.0)
	if warning_left>0:
		var over:float=maxf(delta-warning_left,0.0)
		warning_left=maxf(warning_left-delta,0.0)
		if warning_left==0: firing_left=maxf(PROFILE.FIRING-over,0.0)
	elif firing_left>0: firing_left=maxf(firing_left-delta,0.0)
func _process(delta:float) -> void:
	super._process(delta)
	if is_instance_valid(_beacon_hum):
		if firing_left>EPSILON and health>0 and not _death_sound_done:
			if is_combat_runtime_active(): _start_beacon_hum()
		else: _stop_beacon_hum()
		# Set pause *after* play: AudioStreamPlayer2D.play() clears stream_paused.
		var suspended:bool=not is_combat_runtime_active()
		_beacon_hum.stream_paused=suspended
		# The headless/null audio driver ignores stream_paused; keep pause silent
		# on all audio backends without restarting the ambient loop on unpause.
		_beacon_hum.volume_db=-80.0 if suspended else -4.0
	if is_instance_valid(_beam_visual):
		_beam_visual.global_transform=Transform2D(0.0,beam_origin())
		_beam_visual.call("update_beam",maxf(beam_origin().y-beam_end.y,0.0),_view_clock,beam_width(),beam_opacity(),warning_left>0 and health>0,firing_left>0 and health>0,emitter_width())
	if is_instance_valid(_core_glow):
		_core_glow.global_transform=Transform2D(0.0,global_position)
		_core_glow.update_glow(emitter_width(),0.0,beam_opacity() if health>0 and not _death_sound_done else 0.0,body_width())
	var ring_age:float=PROFILE.FIRING-firing_left if firing_left>0 and warning_left<=0 else -1.0
	for ring:Node2D in [_ring_back,_ring_front]:
		if is_instance_valid(ring):
			ring.global_transform=Transform2D(0.0,ring_origin())
			ring.call("update_ring",ring_age,body_width(),health>0 and not _death_sound_done)
	queue_redraw()
func _exit_tree() -> void:
	if firing_left>EPSILON and is_multiplayer_authority() and get_tree().current_scene!=null:
		_emit_sound("beacon_deactivate")
	_stop_beacon_hum()
	super._exit_tree()
