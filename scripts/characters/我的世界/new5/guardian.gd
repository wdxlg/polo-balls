extends "res://scripts/characters/我的世界/new5/base.gd"
const FRAMES=preload("res://Images/characters/我的世界/new5/guardian_extended.tres")
const RETRACTED_FRAMES=preload("res://Images/characters/我的世界/new5/guardian_retracted.tres")
const HALF_FRAMES=preload("res://Images/characters/我的世界/new5/guardian_half.tres")
enum SpikePhase { RETRACTED, CHARGING, EXTENDED, RETRACTING }
var spike_phase:SpikePhase=SpikePhase.RETRACTED
@export var spike_hold_time:float=1.10
@export var spike_retract_time:float=0.20
@export var spike_contact_damage:float=2.0
@export var spike_contact_interval:float=0.35
var _contact_clock:float=0.0
var _contact_hits:Dictionary={}
var _beam_flow:float=0.0
var _laser_delay_left:float=0.0
var _laser_delay_total:float=0.0
var _spike_delay_left:float=0.0
var _spike_delay_total:float=0.0
@export var beam_flow_start_speed:float=18.0
@export var beam_flow_end_speed:float=140.0
@export var laser_range:float=270.0
# Legacy scene property; angular gating is disabled for 360-degree targeting.
@export var sector_degrees:float=15.0
@export var laser_tick:float=2.0
@export var laser_damage:float=90.0
@export var crossing_damage:float=4.0
@export var spike_radius:float=31.0
@export var spike_damage:float=18.0
@export var spike_charge_time:float=0.30
@export var spike_cooldown:float=0.80
const SPIKE_FX=preload("res://scripts/characters/我的世界/new5/guardian_spike_fx.gd")
const GLOW_SHADER=preload("res://scripts/characters/我的世界/new5/guardian_glow.gdshader")
var spike_charging:bool=false
var _spike_charge:float=0.0
var _spike_burst_age:float=1.0
var _body_base_scale:Vector2
var _spike_effects:Array[Node]=[]
var beam_glow:Line2D
var facing:Vector2=Vector2.LEFT
var gaze:Vector2=Vector2.LEFT
var locked:ball
var _tick_left:float=0.0
var _spike_left:float=0.0
var _laser_player:AudioStreamPlayer2D
const PREVIEW=preload("res://Images/characters/我的世界/new5/guardian_preview.png")
const BEAM_TEXTURE=preload("res://Images/characters/我的世界/new5/guardian_beam.png")
const BEAM_SHADER=preload("res://scripts/characters/我的世界/new5/guardian_beam.gdshader")
@export var beam_width:float=14.0
@export var beam_repeat_length:float=24.0
@export var beam_start_width:float=2.5
@export var beam_hit_width:float=1.0
@export_range(0.5,0.98,0.01) var beam_thicken_fraction:float=0.88
var beam:Line2D
var beam_active:bool=false
var beam_end:Vector2
var _manual_beam_held:bool=false
var _manual_spike_requested:bool=false
func _ready() -> void:
	super._ready()
	_body_base_scale=image.scale
	beam_glow=U.line(self,"GuardianBeamGlow",beam_width*2.5,Color.WHITE)
	beam_glow.z_index=84
	beam_glow.texture=BEAM_TEXTURE
	beam_glow.texture_mode=Line2D.LINE_TEXTURE_STRETCH
	var glow_material:=ShaderMaterial.new()
	glow_material.shader=GLOW_SHADER
	beam_glow.material=glow_material
	beam_glow.visible=false
	beam=U.line(self,"GuardianBeam",beam_width,Color.WHITE)
	beam.texture=BEAM_TEXTURE
	beam.texture_mode=Line2D.LINE_TEXTURE_STRETCH
	beam.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	beam.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var material:=ShaderMaterial.new()
	material.shader=BEAM_SHADER
	material.set_shader_parameter("native_beam",BEAM_TEXTURE)
	beam.material=material
static func cardinal(offset:Vector2) -> Vector2:
	if absf(offset.x)>=absf(offset.y): return Vector2(signf(offset.x),0)
	return Vector2(0,signf(offset.y))
func in_sector(offset:Vector2) -> bool:
	# Legacy method name retained; acquisition and lock retention are now 360 degrees.
	return offset.length_squared()>0.001 and offset.length_squared()<=laser_range*laser_range
func controlled_attack_action() -> void:
	if is_player_controlled() and is_multiplayer_authority() and can_act(): _manual_beam_held=true
func controlled_skill_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not can_act() or _spike_left>0.0: return
	if not spike_targets().is_empty(): _manual_spike_requested=true
func player_control_action_released(index:int) -> void:
	if index==0: _manual_beam_held=false
func player_control_action_cancelled(index:int) -> void:
	if index==0: _manual_beam_held=false
	elif index==1: _manual_spike_requested=false
func set_player_control_peer(peer_id:int) -> void:
	if peer_id != player_control_peer_id:
		_manual_beam_held=false
		_manual_spike_requested=false
	super.set_player_control_peer(peer_id)
func _manual_beam_target() -> ball:
	if not has_player_control_aim(): return null
	var point:Vector2=player_control_aim_world_position()
	var best:float=INF
	var chosen:ball
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball) or not U.enemy(self,raw) or not raw.is_combat_lockable(): continue
		var target:ball=raw as ball
		var offset:Vector2=ball.body_point(target,global_position)-global_position
		if not in_sector(offset) or not U.line_clear(self,global_position,ball.body_point(target,global_position)): continue
		var tolerance:float=U.radius(target)+16.0
		var squared:float=point.distance_squared_to(ball.body_point(target,point))
		if squared<=tolerance*tolerance and squared<best:
			best=squared
			chosen=target
	return chosen
func step_mob(delta:float) -> void:
	_spike_left-=delta
	_spike_burst_age+=delta
	_contact_clock+=delta
	advance_spike_phase()
	if not can_act():
		spike_charging=false
		_spike_charge=0.0
		if spike_phase==SpikePhase.CHARGING: spike_phase=SpikePhase.RETRACTED
		break_lock()
		return
	if is_player_controlled() and _manual_beam_held:
		var aimed:ball=_manual_beam_target()
		if aimed!=locked:
			break_lock()
			if aimed!=null:
				locked=aimed
				_tick_left=laser_tick
				start_charge_sound()
	elif is_player_controlled() and not beam_active:
		break_lock()
	# A closer enemy cannot steal a valid charge already in progress.
	if is_instance_valid(locked):
		var offset:Vector2=ball.body_point(locked,global_position)-global_position
		if not U.enemy(self,locked) or not locked.is_combat_lockable() or not in_sector(offset) or not U.line_clear(self,global_position,ball.body_point(locked,global_position)): break_lock()
	if not is_instance_valid(locked) and not is_player_controlled():
		locked=null
		var best:float=INF
		for candidate:Node in get_tree().get_nodes_in_group("Ball"):
			if not U.enemy(self,candidate) or not candidate.is_combat_lockable(): continue
			var offset:Vector2=ball.body_point(candidate,global_position)-global_position
			if offset.length_squared()<best and in_sector(offset) and U.line_clear(self,global_position,ball.body_point(candidate,global_position)):
				locked=candidate
				best=offset.length_squared()
		if locked!=null:
			_tick_left=laser_tick
			_laser_delay_total=0.0
			_laser_delay_left=0.0
			start_charge_sound()
	if is_instance_valid(locked):
		var offset:Vector2=ball.body_point(locked,global_position)-global_position
		facing=offset.normalized()
		gaze=offset.normalized()
		beam_active=true
		beam_end=locked.global_position
	else: break_lock()
	if beam_active:
		_tick_left-=consume_attack_delay(delta,true)
		if _tick_left<=0:
			_tick_left+=laser_tick
			_laser_delay_total=0.0
			_laser_hit()
			if is_instance_valid(locked) and U.enemy(self,locked) and (not is_player_controlled() or _manual_beam_held): start_charge_sound()
			else: break_lock()
	step_spikes(delta)
func spike_targets() -> Array[ball]:
	var targets:Array[ball]=[]
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if U.enemy(self,target) and global_position.distance_to(ball.body_point(target,global_position))<=spike_radius+U.radius(target) and U.line_clear(self,global_position,ball.body_point(target,global_position)):
			targets.append(target)
	return targets
func step_spikes(delta:float) -> void:
	if spike_phase==SpikePhase.EXTENDED:
		scan_spike_contacts()
		return
	if spike_phase==SpikePhase.RETRACTING or _spike_left>0: return
	# An already charging spike finishes; only new attacks require a manual click.
	if is_player_controlled() and not spike_charging and not _manual_spike_requested: return
	var targets:Array[ball]=spike_targets()
	if targets.is_empty():
		_manual_spike_requested=false
		spike_phase=SpikePhase.RETRACTED
		spike_charging=false
		_spike_charge=0.0
		return
	if not spike_charging:
		spike_phase=SpikePhase.CHARGING
		spike_charging=true
		_spike_charge=0.0
		_spike_delay_left=0.0
		_spike_delay_total=0.0
		return
	_spike_charge+=consume_attack_delay(delta,false)
	if _spike_charge<spike_charge_time: return
	spike_charging=false
	_spike_charge=0.0
	_spike_left=0.0
	_spike_burst_age=0.0
	spike_phase=SpikePhase.EXTENDED
	_manual_spike_requested=false
	_contact_hits.clear()
	for target:ball in targets:
		if damage_with_sound(target,attack_damage(spike_damage/maxf(float(default_properties.get("Damage",Damage)),0.01))):
			_contact_hits[target.get_instance_id()]=_contact_clock
			target.apply_knockback((ball.body_point(target,global_position)-global_position).normalized(),22,190,0,0,{"source":self})
	if multiplayer.has_multiplayer_peer(): _spike_burst.rpc(global_position)
	_spike_burst(global_position)
@rpc("authority","call_remote","reliable")
func _spike_burst(point:Vector2) -> void:
	if health<=0 or _death_visual_done: return
	spike_phase=SpikePhase.EXTENDED
	spike_charging=false
	_spike_burst_age=0.0
	for i:int in range(_spike_effects.size()-1,-1,-1):
		if not is_instance_valid(_spike_effects[i]) or _spike_effects[i].is_queued_for_deletion(): _spike_effects.remove_at(i)
	_spike_effects.append(SPIKE_FX.spawn(self,point,spike_radius))
	_guardian_sound("entity.puffer_fish.sting",point,-4.0)
func advance_spike_phase() -> void:
	if spike_phase not in [SpikePhase.EXTENDED,SpikePhase.RETRACTING]: return
	if spike_phase==SpikePhase.EXTENDED and _spike_burst_age>=spike_hold_time and is_multiplayer_authority():
		emit_guardian_sound("entity.puffer_fish.blow_out",global_position,-5.0)
	if _spike_burst_age>=spike_hold_time+spike_retract_time:
		spike_phase=SpikePhase.RETRACTED
		_spike_left=spike_cooldown
		_contact_hits.clear()
	elif _spike_burst_age>=spike_hold_time:
		spike_phase=SpikePhase.RETRACTING
func spike_extension() -> float:
	if spike_phase==SpikePhase.EXTENDED: return 1.0
	if spike_phase==SpikePhase.RETRACTING:
		return 1.0-smoothstep(0.0,1.0,(_spike_burst_age-spike_hold_time)/maxf(spike_retract_time,0.001))
	return 0.0
func spike_frames() -> SpriteFrames:
	var extension:float=spike_extension()
	if extension<0.25: return RETRACTED_FRAMES
	if extension<0.75: return HALF_FRAMES
	return FRAMES
func scan_spike_contacts() -> void:
	# Query the actual body shape, not the much larger burst radius. This covers
	# stationary guardians contacted by another moving character as well.
	var shape:CollisionShape2D=get_node("CollisionShape2D")
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=shape.shape
	query.transform=shape.global_transform
	query.collision_mask=collision_mask
	query.exclude=[get_rid()]
	query.margin=1.0
	query.collide_with_areas=false
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,32):
		try_spike_contact(hit.get("collider"))
func try_spike_contact(target:Variant) -> bool:
	if spike_phase!=SpikePhase.EXTENDED or not can_act() or not U.enemy(self,target): return false
	if global_position.distance_to(ball.body_point(target,global_position))>U.radius(self)+U.radius(target)+1.1: return false
	var id:int=target.get_instance_id()
	if _contact_clock-float(_contact_hits.get(id,-1000.0))<spike_contact_interval: return false
	if not U.line_clear(self,global_position,ball.body_point(target,global_position)): return false
	_contact_hits[id]=_contact_clock
	if not damage_with_sound(target,attack_damage(spike_contact_damage/maxf(float(default_properties.get("Damage",Damage)),0.01))): return false
	target.apply_knockback((ball.body_point(target,global_position)-global_position).normalized(),4.0,70.0,0,0,{"source":self,"lock_control":false})
	return true
func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	super.when_collide(speed,collision)
	try_spike_contact(collision.get_collider())
func beam_flow_speed(progress:float) -> float:
	return lerpf(beam_flow_start_speed,beam_flow_end_speed,clampf(progress,0.0,1.0)*clampf(progress,0.0,1.0))
func spike_body_scale() -> float:
	if spike_charging: return lerpf(1.0,0.84,smoothstep(0.0,1.0,_spike_charge/maxf(spike_charge_time,0.001)))
	var t:float=_spike_burst_age
	if t<0.075: return lerpf(0.84,1.24,smoothstep(0.0,0.075,t))
	if t<0.20: return lerpf(1.24,0.97,smoothstep(0.075,0.20,t))
	if t<0.32: return lerpf(0.97,1.0,smoothstep(0.20,0.32,t))
	return 1.0
func clear_spike_effects() -> void:
	for effect:Node in _spike_effects:
		if is_instance_valid(effect):
			effect.hide()
			effect.queue_free()
	_spike_effects.clear()
func beam_charge_color(progress:float) -> Color:
	var energy:float=progress*progress
	var native:Color=Color((64+191*energy)/255.0,(32+191*energy)/255.0,(128-64*energy)/255.0)
	return Color.from_hsv(native.h,lerpf(0.35,0.95,progress),lerpf(0.55,1.0,progress))
func break_lock() -> void:
	_laser_delay_left=0.0
	_laser_delay_total=0.0
	if beam_active or is_instance_valid(_laser_player):
		if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _beam_sfx.rpc(false)
		_beam_sfx(false)
	locked=null
	beam_active=false
	_beam_flow=0.0
	if is_instance_valid(beam): beam.hide()
	if is_instance_valid(beam_glow): beam_glow.hide()
	_tick_left=laser_tick
func _laser_hit() -> void:
	if not is_instance_valid(locked) or not U.enemy(self,locked):
		break_lock()
		return
	damage_with_sound(locked,attack_damage(laser_damage/maxf(float(default_properties.get("Damage",Damage)),0.01)),true)
	var ray:Vector2=(beam_end-global_position).normalized()
	for other:Node in get_tree().get_nodes_in_group("Ball"):
		if other==locked or not U.enemy(self,other): continue
		var projection:float=(ball.body_point(other,global_position)-global_position).dot(ray)
		if projection<=0 or projection>global_position.distance_to(beam_end): continue
		if U.segment_distance(ball.body_point_seg(other,global_position,beam_end),global_position,beam_end)>U.radius(other)+3: continue
		if damage_with_sound(other,attack_damage(crossing_damage/maxf(float(default_properties.get("Damage",Damage)),0.01))):
			var side:Vector2=ray.orthogonal()
			if side.dot(ball.body_point(other,global_position)-global_position)<0: side=-side
			other.apply_knockback(side,24,180,0,0,{"source":self})
func visual_mob() -> void:
	if is_instance_valid(_laser_player):
		_laser_player.global_position=global_position
		_laser_player.stream_paused=not is_combat_runtime_active() or _laser_delay_left>0.0
	frame(spike_frames(),StringName("v%02d"%_view_index))
	set_character_visual_flip_h(false)
	image.rotation=0.0
	image.offset=Vector2.ZERO
	if _body_base_scale!=Vector2.ZERO: image.scale=_body_base_scale*spike_body_scale()
	if is_instance_valid(beam):
		beam.visible=beam_active and health>0 and is_combat_runtime_active()
		beam.global_transform=Transform2D.IDENTITY
		beam.points=PackedVector2Array([image.to_global(EYE_OFFSETS[_view_index]),beam_end])
		beam.width=charge_width()
		var progress:float=clampf(1.0-_tick_left/maxf(laser_tick,0.001),0,1)
		beam.default_color=beam_charge_color(progress)
		beam_glow.visible=beam.visible
		beam_glow.global_transform=Transform2D.IDENTITY
		beam_glow.points=beam.points
		beam_glow.width=beam.width*lerpf(1.5,2.8,progress)
		beam_glow.default_color=beam.default_color
		beam_glow.material.set_shader_parameter("glow_strength",progress*progress*0.65)
		beam.material.set_shader_parameter("emission_strength",progress*progress*0.65)
		beam.material.set_shader_parameter("along_scale",beam.points[0].distance_to(beam_end)/maxf(beam_repeat_length,1.0))
		beam.material.set_shader_parameter("scroll",_beam_flow)
func visual_state() -> Dictionary: return {"time":clock,"facing":facing,"gaze":gaze,"beam":beam_active,"end":beam_end,"tick_left":_tick_left,"spike_charging":spike_charging,"spike_charge":_spike_charge,"spike_burst_age":_spike_burst_age,"spike_phase":spike_phase,"beam_flow":_beam_flow,"laser_delay":_laser_delay_left,"spike_delay":_spike_delay_left}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_laser_delay_left=float(data.get("laser_delay",0.0))
	_spike_delay_left=float(data.get("spike_delay",0.0))
	facing=data.get("facing",Vector2.LEFT)
	gaze=data.get("gaze",facing)
	beam_active=data.get("beam",false)
	beam_end=data.get("end",global_position)
	_tick_left=float(data.get("tick_left",laser_tick))
	spike_charging=bool(data.get("spike_charging",false))
	_spike_charge=float(data.get("spike_charge",0.0))
	_spike_burst_age=float(data.get("spike_burst_age",1.0))
	spike_phase=int(data.get("spike_phase",0)) as SpikePhase
	var flow_error:float=fposmod(float(data.get("beam_flow",_beam_flow))-_beam_flow+0.5,1.0)-0.5
	_beam_flow=fposmod(_beam_flow+flow_error*0.2,1.0)
func Die() -> void:
	spike_phase=SpikePhase.RETRACTED
	_contact_hits.clear()
	clear_spike_effects()
	spike_charging=false
	break_lock()
	super.Die()

func voice_role() -> String: return "guardian"
func get_preview_texture() -> Texture2D: return FRAMES.get_frame_texture(&"v32",0)

@rpc("authority","call_remote","reliable")
func _beam_sfx(start:bool) -> void:
	if is_instance_valid(_laser_player):
		_laser_player.stop()
		_laser_player.remove_from_group("MCNativeSFX")
		_laser_player.queue_free()
	_laser_player=AUDIO.play(self,"entity.guardian.attack",global_position,1.0,false,true,true) if start else null
func _exit_tree() -> void:
	clear_spike_effects()
	_beam_sfx(false)
	super._exit_tree()

@export var turn_response:float=12.0
var _look_angle:float=PI
var _view_index:int=32
const EYE_OFFSETS:Array[Vector2]=[Vector2(15.50000,1.90211),Vector2(14.76625,3.35836),Vector2(13.02878,4.49677),Vector2(11.05538,5.25930),Vector2(9.26319,5.74243),Vector2(7.75000,6.05017),Vector2(6.50151,6.25015),Vector2(5.45355,6.38562),Vector2(4.58347,6.47767),Vector2(3.80226,6.54553),Vector2(3.14320,6.59236),Vector2(2.53155,6.62756),Vector2(1.96950,6.65305),Vector2(1.45868,6.67062),Vector2(0.94625,6.68294),Vector2(0.45983,6.68977),Vector2(0.00000,6.69188),Vector2(-0.45983,6.68977),Vector2(-0.94625,6.68294),Vector2(-1.45868,6.67062),Vector2(-1.96950,6.65305),Vector2(-2.53155,6.62756),Vector2(-3.14320,6.59236),Vector2(-3.80226,6.54553),Vector2(-4.58347,6.47767),Vector2(-5.45355,6.38562),Vector2(-6.50151,6.25015),Vector2(-7.75000,6.05017),Vector2(-9.26319,5.74243),Vector2(-11.05538,5.25930),Vector2(-13.02878,4.49677),Vector2(-14.76625,3.35836),Vector2(-15.50000,1.90211),Vector2(-14.76625,0.44587),Vector2(-13.02878,-0.69254),Vector2(-11.05538,-1.45508),Vector2(-9.26319,-1.93820),Vector2(-7.75000,-2.24594),Vector2(-6.50151,-2.44593),Vector2(-5.45355,-2.58139),Vector2(-4.58347,-2.67344),Vector2(-3.80226,-2.74130),Vector2(-3.14320,-2.78813),Vector2(-2.53155,-2.82333),Vector2(-1.96950,-2.84883),Vector2(-1.45868,-2.86639),Vector2(-0.94625,-2.87872),Vector2(-0.45983,-2.88554),Vector2(0.00000,-2.88765),Vector2(0.45983,-2.88554),Vector2(0.94625,-2.87872),Vector2(1.45868,-2.86639),Vector2(1.96950,-2.84883),Vector2(2.53155,-2.82333),Vector2(3.14320,-2.78813),Vector2(3.80226,-2.74130),Vector2(4.58347,-2.67344),Vector2(5.45355,-2.58139),Vector2(6.50151,-2.44593),Vector2(7.75000,-2.24594),Vector2(9.26319,-1.93820),Vector2(11.05538,-1.45508),Vector2(13.02878,-0.69254),Vector2(14.76625,0.44587)]
func _process(delta:float) -> void:
	if health>0 and is_combat_runtime_active():
		advance_facing(delta)
		if beam_active:
			var progress:float=clampf(1.0-_tick_left/maxf(laser_tick,0.001),0.0,1.0)
			# Integrate speed, rather than multiplying elapsed time by a changing
			# speed: native texture bands always travel smoothly eye -> target.
			_beam_flow=fposmod(_beam_flow+delta*beam_flow_speed(progress)/maxf(beam_repeat_length,1.0),1.0)
	super._process(delta)
func advance_facing(delta:float) -> void:
	var desired:Vector2=gaze if gaze.length_squared()>0.001 else facing
	if desired.length_squared()>0.001:
		_look_angle=lerp_angle(_look_angle,desired.angle(),1-exp(-maxf(delta,0.0)*turn_response))
	_view_index=posmod(roundi(_look_angle/TAU*64),64)

func charge_width() -> float:
	var progress:float=clampf(1.0-_tick_left/maxf(laser_tick,0.001),0,1)
	if progress<beam_thicken_fraction:
		return lerpf(beam_start_width,beam_width,progress/beam_thicken_fraction)
	return lerpf(beam_width,beam_hit_width,(progress-beam_thicken_fraction)/(1.0-beam_thicken_fraction))
func client_visual_step(delta:float) -> void:
	if is_combat_runtime_active():
		_spike_burst_age+=delta
		advance_spike_phase()
		if spike_charging: _spike_charge=minf(_spike_charge+consume_attack_delay(delta,false),spike_charge_time)
	if beam_active and is_combat_runtime_active(): _tick_left=maxf(0,_tick_left-consume_attack_delay(delta,true))

func start_charge_sound() -> void:
	if multiplayer.has_multiplayer_peer(): _beam_sfx.rpc(true)
	_beam_sfx(true)
static func impact_volume(actual_damage:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual_damage)
func damage_with_sound(target:ball,amount:float,critical:bool=false) -> bool:
	if not is_instance_valid(target): return false
	var before:float=maxf(target.health,0.0)
	var point:Vector2=ball.body_point(target,global_position)
	var accepted:bool=U.damage(self,target,amount,global_position)
	var remaining:float=maxf(target.health,0.0) if is_instance_valid(target) else 0.0
	var actual:float=maxf(before-remaining,0.0)
	if accepted and actual>0.0:
		pass # The victim selected hurt/crit from actual HP loss, not the laser flag.
	return accepted
func emit_guardian_sound(event:String,point:Vector2,volume:float,priority:bool=false) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.has_multiplayer_peer(): _guardian_sound.rpc(event,point,volume,priority)
	_guardian_sound(event,point,volume,priority)
@rpc("authority","call_remote","reliable")
func _guardian_sound(event:String,point:Vector2,volume:float,priority:bool=false) -> AudioStreamPlayer2D:
	# Different events and different guardians must not suppress each other.
	return AUDIO.play(self,event,point,volume,false,priority,true)

# Movement control remains locked by the normal knockback controller. Only its
# temporary motion lock is exempted from cancelling the guardian's charge.
func can_act() -> bool:
	if not active() or not Can_Attack or is_damage_output_disabled(): return false
	if not dizziness: return true
	var locks:int=int(get_meta("generic_motion_lock_count",0))
	if locks<=0 or bool(get_meta("generic_motion_lock_baseline",false)): return false
	var motion_locks:int=0
	for child:Node in get_children():
		if child.get_script()==KNOCKBACK_EFFECT_SCRIPT and child._lock_acquired:
			if child._stage==1: return false # Explicit stun is still a real interruption.
			motion_locks+=1
	return motion_locks==locks
func apply_knockback(knockback_direction:Vector2,knockback_distance:float,knockback_speed:float=700.0,wall_bounce_strength:float=0.0,stun_duration:float=0.0,options:Dictionary={}) -> Node:
	var effect:Node=super.apply_knockback(knockback_direction,knockback_distance,knockback_speed,wall_bounce_strength,stun_duration,options)
	if is_instance_valid(effect) and knockback_distance>0.0 and knockback_speed>0.0:
		add_attack_delay(knockback_attack_delay(knockback_distance),knockback_attack_delay(knockback_distance)/8.0)
	return effect
static func knockback_attack_delay(distance:float) -> float:
	return clampf(0.28+maxf(distance,0.0)*0.012,0.28,1.76)
static func hurt_attack_delay(amount:float) -> float:
	return clampf(0.064+maxf(amount,0.0)*0.0024,0.064,0.24)
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if amount>0.0: add_attack_delay(hurt_attack_delay(amount),hurt_attack_delay(amount)/8.0)
func add_attack_delay(seconds:float,spike_seconds:float=-1.0) -> void:
	if not active(): return
	# Stronger laser suppression, but preserve the original spike reaction timing.
	# Per-charge budgets prevent rapid small hits from locking attacks forever.
	if beam_active and is_instance_valid(locked):
		var extra:float=minf(maxf(seconds,0.0),maxf(3.6-_laser_delay_total,0.0))
		_laser_delay_left+=extra
		_laser_delay_total+=extra
	if spike_charging:
		var extra:float=minf(maxf(spike_seconds if spike_seconds>=0.0 else seconds,0.0),maxf(0.12-_spike_delay_total,0.0))
		_spike_delay_left+=extra
		_spike_delay_total+=extra
func consume_attack_delay(delta:float,laser:bool) -> float:
	var paused_time:float=minf(delta,_laser_delay_left if laser else _spike_delay_left)
	if laser: _laser_delay_left-=paused_time
	else: _spike_delay_left-=paused_time
	return delta-paused_time
