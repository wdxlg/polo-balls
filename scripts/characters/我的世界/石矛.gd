extends "res://scripts/characters/我的世界/mc_item_base.gd"
## Four attached weapons, not autonomous summons/projectiles. Growth is never spent.
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const SOUNDS = preload("res://scripts/characters/我的世界/new5/audio.gd")
const TEXTURE:Texture2D = preload("res://Images/characters/我的世界/stone_spear/stone_spear_in_hand.png")
const ICON:Texture2D = preload("res://Images/characters/我的世界/stone_spear/stone_spear.png")
const STAB_SOUNDS:Array[AudioStream] = [preload("res://audio/characters/我的世界/stone_spear/attack1.ogg"),preload("res://audio/characters/我的世界/stone_spear/attack2.ogg"),preload("res://audio/characters/我的世界/stone_spear/attack3.ogg")]
# Exact Minecraft Java 1.21.11 item.spear events; provenance in the audio SOURCE.json.
const FORMATION_SFX:AudioStream = preload("res://audio/characters/我的世界/stone_spear/use.ogg")
const HIT_SOUNDS:Array[AudioStream] = [preload("res://audio/characters/我的世界/stone_spear/hit1.ogg"),preload("res://audio/characters/我的世界/stone_spear/hit2.ogg"),preload("res://audio/characters/我的世界/stone_spear/hit3.ogg")]
enum Formation {FOLLOW, ORBIT, STAB}
const SPEED_DAMAGE_FACTOR:float = 0.25
const COPY_TRAILS = preload("res://classes/sprite_snapshot_trail.gd")
const BLOCK_SFX:AudioStream = preload("res://audio/sfx/防御/BlockAtt.ogg")
const GUARD_FX = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
@export var movement_growth:float = 10.0
@export_range(90.0,3600.0,30.0) var body_turn_degrees_per_second:float = 3600.0
@export_range(1.0,180.0,1.0) var follow_cohesion_reference_speed:float = 45.0
@export_range(45.0,2000.0,5.0) var follow_merge_speed:float = 300.0
@export var formation_position_response:float = 10.0
@export var formation_angle_response:float = 8.0
@export_range(0.0,1.0) var copy_opacity:float = 0.78
@export var formation_interval:float = 5.0
@export var formation_transition:float = 0.35
@export var formation_spacing:float = 16.0
@export var stab_interval:float = 1.65
@export var stab_out_time:float = 0.16
@export var stab_return_time:float = 0.38
@export var stab_base_distance:float = 12.0
@export var orbit_base_rate:float = 0.65
@export var orbit_speed_factor:float = 0.018
@export var copy_trail_min_speed:float = 180.0
@export var copy_trail_interval:float = 0.035
@export var copy_trail_lifetime:float = 0.16
@export var tip_hit_interval:float = 0.55
var permanent_speed_bonus:float = 0.0
var formation:int = Formation.FOLLOW
var _base_speed:float = 170.0
var _facing:float = 0.0
var _orbit:float = 0.0
# A shared, simulated follower frame carries every formation; not a visual-only tween.
var _formation_center:Vector2 = Vector2.ZERO
var _formation_heading:float = 0.0
var _switch_wait:float = 5.0
var _transition_left:float = 0.0
var _stab_wait:float = 0.65
var _stab_time:float = -1.0
var _stab_distance:float = 0.0
var _stab_axes:PackedFloat32Array = PackedFloat32Array([0,0,0,0])
var _tip_guards:Array[hurtbox] = []
var _guard_hit_id:int = -1
var _guard_impact:Vector2 = Vector2.ZERO
var _guard_feedback_until:Dictionary = {}
var guard_feedback_count:int = 0
var last_guard_position:Vector2 = Vector2.ZERO
var _copy_trails:Node2D
var _copy_trail_elapsed:float = 0.0
var _copy_trail_last:Dictionary = {}
var _copy_trail_form:int = -1
var _copy_trail_body:Vector2 = Vector2.ZERO
var _copies:Array[Sprite2D] = []
var _centers:Array[Vector2] = []
var _angles:Array[float] = []
var _tip_speeds:Array[float] = [0,0,0,0,0]
var _hits:Array[Dictionary] = [{},{},{},{},{}]
var _stroke_hits:Array[Dictionary] = [{},{},{},{},{}]
var _clock:float = 0.0
var _real_speed:float = 0.0
var _last_motion:Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _sfx_rng := RandomNumberGenerator.new()
var _pose_state:PackedFloat32Array = PackedFloat32Array()
var _last_body_position:Vector2 = Vector2.ZERO
var _main_shift:float = 0.0
var last_sound_event:String = ""
var last_sound_gain:float = 0.0

func _ready() -> void:
	Has_Collision_Damage = false
	motion_blur_enabled = false
	motion_stretch_enabled = false
	AfterImage_Speed = -1.0
	super._ready()
	_base_speed = maxf(Speed,1.0)
	_switch_wait = formation_interval
	_rng.randomize()
	_sfx_rng.randomize()
	_facing = direction.angle() if not direction.is_zero_approx() else 0.0
	_formation_center = global_position
	_formation_heading = _facing
	self_hitbox.set_deferred("monitoring",false)
	self_hitbox.collision_mask = 0
	self_hitbox.collision_layer = 0
	add_to_group("MinecraftStoneSpear")
	for i:int in range(4):
		var sprite := Sprite2D.new()
		sprite.name = "StoneSpearCopy%d" % i
		sprite.texture = TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.modulate.a = copy_opacity
		add_child(sprite)
		_copies.append(sprite)
		var pose:Dictionary = formation_pose(i,0.0)
		_centers.append(global_position+pose.offset)
		_angles.append(pose.angle)
	_copy_trails = COPY_TRAILS.new()
	_copy_trails.name = "CopyTrails"
	add_child(_copy_trails)
	_reset_copy_trails()
	_create_tip_guards()
	_last_body_position = global_position
	_setup_replication()
	_store_pose()
	_apply_pose()

func _setup_replication() -> void:
	var sync:MultiplayerSynchronizer = get_node("MultiplayerSynchronizer")
	var config:SceneReplicationConfig = sync.replication_config.duplicate()
	for key:String in ["permanent_speed_bonus","formation","_facing","_orbit","_formation_center","_formation_heading","_switch_wait","_transition_left","_stab_wait","_stab_time","_stab_distance","_stab_axes","_main_shift","_pose_state","direction","_real_speed"]:
		var path := NodePath(".:"+key)
		if not config.has_property(path): config.add_property(path)
		config.property_set_spawn(path,true)
		config.property_set_replication_mode(path,SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config

func allows_character_motion_effects() -> bool: return true # Opt in only for the four explicit copy trails.
func get_preview_texture() -> Texture2D: return ICON
func _is_character_ground_shadow_owner() -> bool: return false
func get_projectile_embed_parent() -> Node2D: return image
func _on_hitbox_on_hit(_hurt:hurtbox) -> void: pass
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:int = State.Die if health<=0 else (State.Stand if dizziness or not is_combat_runtime_active() else State.Move)
	return -1 if next==state else next

func move(speed:float,delta:float) -> void:
	var before:Vector2 = global_position
	super.move(speed*(1.0+permanent_speed_bonus/_base_speed),delta)
	_last_motion = global_position-before

func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority(): return
	if health<=0:
		_cancel_stab()
		super.tick_physics(state,delta)
		return
	if not is_combat_runtime_active() or delta<=0.0: return
	# External placement/teleport is not a giant weapon sweep or a growth reward.
	var relocation:Vector2 = global_position-_last_body_position
	if relocation.length_squared()>0.0001:
		_reset_copy_trails()
		for i:int in range(_centers.size()): _centers[i] += relocation
		_formation_center += relocation
		_transition_left = maxf(_transition_left,0.1)
	var old_formation_center:Vector2 = _formation_center
	var old_formation_heading:float = _formation_heading
	var old_shift:float = _main_shift
	var old_center:Vector2 = global_position
	var old_facing:float = _facing
	var previous_centers:Array[Vector2] = _centers.duplicate()
	var previous_angles:Array[float] = _angles.duplicate()
	_last_motion = Vector2.ZERO
	super.tick_physics(state,delta)
	_last_body_position = global_position
	_clock += delta
	_real_speed = _last_motion.length()/delta
	var controlled:bool = is_player_controlled()
	var heading:Vector2 = player_control_direction if controlled else direction
	if not dizziness:
		if _last_motion.length_squared()>0.000001 and not heading.is_zero_approx():
			permanent_speed_bonus += maxf(movement_growth,0.0)*delta
		var aim:Vector2 = player_control_aim_direction(Vector2.from_angle(_facing)) if controlled else heading
		if not aim.is_zero_approx() and _stab_time<0.0: _facing = rotate_toward(_facing,aim.angle(),deg_to_rad(body_turn_degrees_per_second)*delta)
	if dizziness or not Can_Attack or is_damage_output_disabled():
		_cancel_stab()
		_main_shift = 0.0
		for i:int in range(_centers.size()): _centers[i] += global_position-old_center
		_formation_center += global_position-old_center
		_transition_left = maxf(_transition_left,0.1)
		_tip_speeds.fill(0.0)
		_apply_pose()
		_store_pose()
		return
	_advance_formation_frame(delta,global_position-old_center)
	_switch_wait = maxf(0.0,_switch_wait-delta)
	_stab_wait = maxf(0.0,_stab_wait-delta)
	if not controlled and _switch_wait<=0.0: choose_formation()
	var in_transition:bool = _transition_left>0.0
	_transition_left = maxf(_transition_left-delta,0.0)
	if formation==Formation.STAB and not controlled and not in_transition and _stab_time<0.0 and _stab_wait<=0.0: begin_stab()
	var old_stab_time:float = _stab_time
	if _stab_time>=0.0:
		_stab_time += delta
		if _stab_time>=stab_out_time+stab_return_time: _stab_time = -1.0
	var old_orbit:float = _orbit
	if formation==Formation.ORBIT: _orbit += orbit_rate(_real_speed)*delta
	for i:int in range(4):
		var pose:Dictionary = formation_pose(i,_real_speed)
		var target:Vector2 = _formation_center+pose.offset
		var fully_gathered:bool = formation==Formation.FOLLOW and follow_gather_progress(_real_speed)>=1.0
		if fully_gathered: target = global_position
		if in_transition:
			var weight:float = minf(1.0,delta/maxf(_transition_left+delta,delta))
			_centers[i] = _centers[i].lerp(target,weight)
			_angles[i] = lerp_angle(_angles[i],pose.angle,weight)
		elif formation==Formation.FOLLOW:
			# Outer copies lag more. Increasing speed reduces both lag and spacing.
			var response:float = follow_response(i,_real_speed)
			var outer_loss:float = 0.16 if i==1 or i==3 else 0.08
			var carried:float = 1.0 if fully_gathered else 1.0-outer_loss*pow(1.0-follow_cohesion(_real_speed),2.0)
			_centers[i] += (global_position-old_center)*carried
			_centers[i] = _centers[i].lerp(target,1.0-exp(-response*delta))
			# Finish sub-pixel convergence exactly; continue carrying full body motion.
			if fully_gathered and _centers[i].distance_squared_to(target)<=0.0001: _centers[i] = target
			_angles[i] = lerp_angle(_angles[i],pose.angle,1.0-exp(-response*delta))
		else:
			_centers[i] = target
			_angles[i] = pose.angle
	_main_shift = stroke_offset(_stab_time) if formation==Formation.STAB else 0.0
	_tip_speeds.fill(0.0)
	if not in_transition:
		var main_active:bool = formation!=Formation.STAB or (old_stab_time>=0.0 and old_stab_time<stab_out_time)
		if main_active:
			var main_end:Vector2 = global_position+Vector2.from_angle(_facing)*_main_shift
			var active_delta:float = delta
			if formation==Formation.STAB and old_stab_time+delta>stab_out_time:
				active_delta = stab_out_time-old_stab_time
				main_end = old_center.lerp(global_position,active_delta/delta)+Vector2.from_angle(_facing)*_stab_distance
			_sweep_tip(0,old_center+Vector2.from_angle(old_facing)*old_shift,main_end,old_facing,_facing,active_delta,old_center)
		for i:int in range(4):
			if formation==Formation.STAB:
				if old_stab_time<0.0 or old_stab_time>=stab_out_time: continue
				# Clamp the sweep at the outward peak, never include elastic return.
				var fraction:float = minf(1.0,(stab_out_time-old_stab_time)/delta)
				var tip_center:Vector2 = _centers[i]
				if fraction<1.0:
					var radial:Vector2 = Vector2.from_angle(_stab_axes[i])
					tip_center = old_formation_center.lerp(_formation_center,fraction)+radial*(scaled_spacing()+_stab_distance)
				_sweep_tip(i+1,previous_centers[i],tip_center,previous_angles[i],_angles[i],delta*fraction,old_center)
			elif formation==Formation.ORBIT:
				# Arc subdivision, so the rotation is not replaced by one interior chord.
				var frame_turn:float = angle_difference(old_formation_heading,_formation_heading)
				var steps:int = maxi(1,int(ceil(absf(_orbit-old_orbit+frame_turn)/0.12)))
				steps = mini(steps,128)
				var a_center:Vector2 = previous_centers[i]
				var a_angle:float = previous_angles[i]
				for step:int in range(1,steps+1):
					var f:float = float(step)/steps
					var theta:float = old_formation_heading+frame_turn*f+lerpf(old_orbit,_orbit,f)+float(i)*PI*0.5-PI*0.5
					var b_center:Vector2 = old_formation_center.lerp(_formation_center,f)+Vector2.from_angle(theta)*scaled_spacing()
					var b_angle:float = theta+PI*0.5
					_sweep_tip(i+1,a_center,b_center,a_angle,b_angle,delta/steps,old_center)
					a_center = b_center
					a_angle = b_angle
			else:
				_sweep_tip(i+1,previous_centers[i],_centers[i],previous_angles[i],_angles[i],delta,old_center)
	_apply_pose()
	_store_pose()
	_prune_hits()

func _advance_formation_frame(delta:float,body_motion:Vector2 = Vector2.ZERO) -> void:
	# The four attached weapons follow translation AND heading in all three stances.
	# Exponential response is frame-rate independent; fast movement tightens follow.
	# Carry normal translation so high speed cannot stretch the attachment indefinitely.
	# Heading/layout changes still travel along the smoothed follower frame.
	_formation_center += body_motion
	var tightness:float = follow_cohesion(_real_speed) if formation==Formation.FOLLOW else cohesion(_real_speed)
	var position_response:float = lerpf(formation_position_response,24.0,tightness)
	_formation_center = _formation_center.lerp(global_position,1.0-exp(-position_response*delta))
	if _stab_time<0.0:
		var angle_response:float = lerpf(formation_angle_response,16.0,tightness)
		_formation_heading = lerp_angle(_formation_heading,_facing,1.0-exp(-angle_response*delta))

func damage_at_speed(speed_value:float) -> float:
	return attack_damage(SPEED_DAMAGE_FACTOR*maxf(speed_value,0.0)/maxf(_base_speed*CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,1.0))
func cohesion(speed_value:float) -> float:
	return maxf(speed_value,0.0)/(maxf(speed_value,0.0)+180.0)
func follow_cohesion(speed_value:float) -> float:
	# Follow response remains fast; geometric gathering has a separate start speed.
	return maxf(speed_value,0.0)/(maxf(speed_value,0.0)+maxf(follow_cohesion_reference_speed,1.0))
func follow_gather_progress(speed_value:float) -> float:
	# Birth-speed movement must retain the fully open layout. Only the speed
	# gained above that baseline contributes to gathering; the endpoint stays 300.
	var start:float = _base_speed*CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	var span:float = maxf(follow_merge_speed-start,1.0)
	var progress:float = clampf(follow_cohesion(speed_value-start)/maxf(follow_cohesion(span),0.000001),0.0,1.0)
	return 1.0 if is_equal_approx(progress,1.0) else progress
func scaled_spacing() -> float: return formation_spacing*global_transform.x.length()/0.2
func tip_distance() -> float: return 75.0*global_transform.x.length()
func tip_radius() -> float: return 10.0*global_transform.x.length()
func orbit_rate(speed_value:float) -> float: return orbit_base_rate+maxf(speed_value,0.0)*orbit_speed_factor
func follow_response(index:int,speed_value:float) -> float:
	var outer:bool = index==1 or index==3
	return lerpf(6.0 if outer else 10.0,36.0,follow_cohesion(speed_value))
func stab_reach(speed_value:float) -> float: return (stab_base_distance+maxf(speed_value,0.0)*0.12)*global_transform.x.length()/0.2
func stroke_offset(time:float) -> float:
	if time<0.0: return 0.0
	if time<=stab_out_time: return _stab_distance*sin(clampf(time/stab_out_time,0.0,1.0)*PI*0.5)
	var u:float = clampf((time-stab_out_time)/maxf(stab_return_time,0.001),0.0,1.0)
	# Damped overshoot exists only in the non-damaging return phase.
	return _stab_distance*pow(1.0-u,2.0)*cos(u*PI*1.5)
func formation_pose(index:int,speed_value:float) -> Dictionary:
	var offset:Vector2
	var angle:float
	if formation==Formation.FOLLOW:
		var side:float = -1.0 if index<2 else 1.0
		var rank:float = 1.0+float(index%2)
		var gap:float = scaled_spacing()*(1.0-follow_gather_progress(speed_value))
		offset = Vector2(0,side*rank*gap).rotated(_formation_heading)
		angle = _formation_heading
	elif formation==Formation.ORBIT:
		var theta:float = _formation_heading+_orbit+float(index)*PI*0.5-PI*0.5
		offset = Vector2.from_angle(theta)*scaled_spacing()
		angle = theta+PI*0.5
	else:
		angle = _stab_axes[index] if _stab_time>=0.0 else _formation_heading+float(index)*PI*0.5-PI*0.5
		offset = Vector2.from_angle(angle)*(scaled_spacing()+stroke_offset(_stab_time))
	return {"offset":offset,"angle":angle}

func choose_formation() -> bool:
	if not _can_act() or not Can_Skill or _switch_wait>0.0 or _stab_time>=0.0: return false
	# Authority alone draws one of the OTHER two stances.
	return set_formation((formation+1+_rng.randi_range(0,1))%3)
func set_formation(next:int) -> bool:
	if not _can_act() or not Can_Skill or next<0 or next>2 or next==formation: return false
	formation = next
	_reset_copy_trails()
	_switch_wait = maxf(formation_interval,0.1)
	_transition_left = maxf(formation_transition,0.01)
	_cancel_stab()
	_stab_wait = 0.45
	_tip_speeds.fill(0.0)
	if formation==Formation.ORBIT: _orbit = 0.0
	_update_tip_guards()
	_store_pose()
	_emit_formation_audio()
	return true
func begin_stab() -> bool:
	if not _can_act() or formation!=Formation.STAB or _transition_left>0.0 or _stab_wait>0.0 or _stab_time>=0.0: return false
	# Lock the already-visible directions, not a newly rotated target formation.
	_formation_heading = _angles[0]+PI*0.5
	_stab_time = 0.0
	_stab_wait = maxf(stab_interval,stab_out_time+stab_return_time)
	_stab_distance = stab_reach(_real_speed)
	for i:int in range(4): _stab_axes[i] = _angles[i]
	for item:Dictionary in _stroke_hits: item.clear()
	_emit_audio(false,global_position,0.0)
	return true
func _cancel_stab() -> void:
	_stab_time = -1.0
	for item:Dictionary in _stroke_hits: item.clear()
func _can_act() -> bool:
	return is_multiplayer_authority() and health>0 and not is_queued_for_deletion() and is_combat_runtime_active() and not dizziness and Can_Attack and not is_damage_output_disabled()

# The same hurtbox -> hitbox rejection hooks as wooden spear. Only copy tips
# participate; exact current shapes avoid turning four tips into a full shield.
func _create_tip_guards() -> void:
	for i:int in range(4):
		var guard := hurtbox.new()
		guard.name = "OrbitTipGuard%d" % i
		guard.collision_layer = 0
		guard.collision_mask = 0
		guard.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		collision.shape = shape
		guard.add_child(collision)
		add_child(guard)
		_tip_guards.append(guard)

func _orbit_guard_active() -> bool:
	# Passive contact defense, like wood: stun/Can_Attack do not remove the tip.
	return formation==Formation.ORBIT and health>0 and not is_queued_for_deletion() and is_combat_runtime_active()

func _update_tip_guards() -> void:
	var active:bool = _orbit_guard_active() and is_multiplayer_authority()
	for i:int in range(_tip_guards.size()):
		_tip_guards[i].global_position = _centers[i]+Vector2.from_angle(_angles[i])*tip_distance()
		_tip_guards[i].global_rotation = _angles[i]
		_tip_guards[i].collision_layer = 2 if active else 0

func should_bypass_duplicate_hit_guard(_incoming:hitbox,contact:hurtbox) -> bool:
	return _orbit_guard_active() and _tip_guards.has(contact)

func can_receive_hit_contact(incoming:hitbox,contact:hurtbox) -> bool:
	_guard_hit_id = -1
	# A stale area_entered after switching/death must not consume a projectile.
	if not is_multiplayer_authority(): return false
	if not _orbit_guard_active(): return not _tip_guards.has(contact)
	if not is_instance_valid(incoming): return true
	for i:int in range(_tip_guards.size()):
		var guard:hurtbox = _tip_guards[i]
		var collision:CollisionShape2D = guard.get_child(0)
		var touches:bool = contact==guard
		# Query current geometry, not the previous physics frame's overlaps list.
		for child:Node in incoming.get_children():
			if child is CollisionShape2D and not child.disabled and child.shape!=null:
				if collision.shape.collide(collision.global_transform,child.shape,child.global_transform):
					touches = true
					break
		if touches:
			_guard_hit_id = incoming.get_instance_id()
			_guard_impact = guard.global_position
			return false
	return true

func can_receive_hit_from(incoming:hitbox) -> bool:
	return can_receive_hit_contact(incoming,null)

func _estimate_block_impact_position(incoming:hitbox) -> Vector2:
	if is_instance_valid(incoming) and incoming.get_instance_id()==_guard_hit_id: return _guard_impact
	return super._estimate_block_impact_position(incoming)

func on_incoming_hit_rejected(incoming:hitbox) -> void:
	if not is_multiplayer_authority() or not _orbit_guard_active() or not is_instance_valid(incoming): return
	var id:int = incoming.get_instance_id()
	if id!=_guard_hit_id: return
	var now:int = Time.get_ticks_msec()
	for key:Variant in _guard_feedback_until.keys():
		if int(_guard_feedback_until[key])<=now: _guard_feedback_until.erase(key)
	if _guard_feedback_until.has(id): return
	_guard_feedback_until[id] = now+120
	# Reuse public burst, projectile classification and authoritative disposal.
	super.on_incoming_hit_rejected(incoming)
	if multiplayer.has_multiplayer_peer(): _play_audio.rpc("stone_spear.block",0,_guard_impact,-1.0)
	else: _play_audio("stone_spear.block",0,_guard_impact,-1.0)

func _guard_ring_deferred(scene_ref:WeakRef,point:Vector2) -> void:
	var scene:Node = scene_ref.get_ref()
	if not is_instance_valid(scene) or scene.is_queued_for_deletion() or scene!=get_tree().current_scene: return
	GUARD_FX.expanding_ring(scene,point,3.2,{"name":"StoneSpearGuardRing","lifetime":0.13,"end_scale":2.15,"palette":[Color.WHITE],"z_index":520})

func _sweep_tip(index:int,start:Vector2,finish:Vector2,angle_a:float,angle_b:float,delta:float,anchor:Vector2) -> void:
	if not _can_act() or delta<=0.000001: return
	# 0.05s U-turns can cover 120 degrees in one 30Hz tick. Sweep the actual
	# rotating tip arc, never a single shortcut chord across the spear shaft.
	var turn:float = angle_difference(angle_a,angle_b)
	var steps:int = maxi(1,int(ceil(absf(turn)/0.12)))
	for step:int in range(steps):
		var from:float = float(step)/steps
		var to:float = float(step+1)/steps
		_sweep_tip_segment(index,start.lerp(finish,from),start.lerp(finish,to),angle_a+turn*from,angle_a+turn*to,delta/steps,anchor)

func _sweep_tip_segment(index:int,start:Vector2,finish:Vector2,angle_a:float,angle_b:float,delta:float,anchor:Vector2) -> void:
	if not _can_act() or delta<=0.000001: return
	var a:Vector2 = start+Vector2.from_angle(angle_a)*tip_distance()
	var b:Vector2 = finish+Vector2.from_angle(angle_b)*tip_distance()
	var speed_value:float = a.distance_to(b)/delta
	_tip_speeds[index] = speed_value
	if speed_value<=0.1: return
	var excluded:Dictionary = {}
	for id:Variant in _hits[index]:
		if float(_hits[index][id])>_clock: excluded[id] = true
	if formation==Formation.STAB: excluded.merge(_stroke_hits[index])
	for contact:Dictionary in SWEEP.contacts(self,a,b,tip_radius(),excluded,anchor):
		var target:ball = contact.target
		_hits[index][target.get_instance_id()] = _clock+tip_hit_interval
		if formation==Formation.STAB: _stroke_hits[index][target.get_instance_id()] = true
		var before:float = maxf(float(target.health),0.0)
		target.receive_classified_spatial_damage(damage_at_speed(speed_value),{"shape":"circle","point":contact.point,"radius":tip_radius(),"source":self,"carrier":"weapon_sweep"},&"ordinary")
		var actual:float = maxf(before-maxf(float(target.health),0.0),0.0) if is_instance_valid(target) else before
		if actual>0.0: _emit_audio(true,contact.point,actual)
func _prune_hits() -> void:
	for item:Dictionary in _hits:
		for id:Variant in item.keys():
			if float(item[id])<=_clock: item.erase(id)

func _apply_pose() -> void:
	if not is_instance_valid(image): return
	set_character_visual_flip_h(false)
	image.global_position = global_position+Vector2.from_angle(_facing)*_main_shift
	image.global_rotation = _facing+PI*0.75
	collision_shape_2d.global_rotation = _facing
	self_hurtbox.global_position = global_position+Vector2.from_angle(_facing)*_main_shift
	self_hurtbox.global_rotation = _facing
	for i:int in range(_copies.size()):
		_copies[i].global_position = _centers[i]
		_copies[i].global_rotation = _angles[i]+PI*0.75
		_copies[i].global_scale = Vector2.ONE*(global_transform.x.length()*3.535534)
		_copies[i].modulate.a = copy_opacity
		_copies[i].visible = health>0
	_update_tip_guards()
func _store_pose() -> void:
	if not is_multiplayer_authority(): return
	var values := PackedFloat32Array()
	for i:int in range(_centers.size()):
		var relative:Vector2 = _centers[i]-global_position
		values.append_array(PackedFloat32Array([relative.x,relative.y,_angles[i],_tip_speeds[i+1]]))
	values.append(_tip_speeds[0])
	_pose_state = values
func _reset_copy_trails() -> void:
	if is_instance_valid(_copy_trails): _copy_trails.clear()
	_copy_trail_elapsed = 0.0
	_copy_trail_last.clear()
	_copy_trail_form = formation
	_copy_trail_body = global_position

func _update_copy_trails(delta:float) -> void:
	if not is_instance_valid(_copy_trails): return
	if health<=0 or is_queued_for_deletion() or dizziness or not Can_Attack or is_damage_output_disabled() or not allows_character_motion_effects():
		_reset_copy_trails()
		return
	# Freeze both creation and fading during battle pause. No queued catch-up burst.
	if not is_combat_runtime_active() or delta<=0.0: return
	if formation!=_copy_trail_form or global_position.distance_to(_copy_trail_body)>maxf(64.0,_real_speed*delta*4.0):
		_reset_copy_trails()
	_copy_trail_body = global_position
	_copy_trails.advance(delta)
	var outward:bool = formation!=Formation.STAB or (_stab_time>=0.0 and _stab_time<stab_out_time)
	if _real_speed<copy_trail_min_speed or not outward or _transition_left>0.0:
		_copy_trail_elapsed = 0.0
		_copy_trail_last.clear()
		return
	_copy_trail_elapsed += delta
	var interval:float = maxf(copy_trail_interval,0.02)
	if _copy_trail_elapsed<interval: return
	_copy_trail_elapsed = fmod(_copy_trail_elapsed,interval)
	for i:int in range(_copies.size()):
		var pose:Transform2D = _copies[i].global_transform
		if _copy_trail_last.has(i):
			var previous:Transform2D = _copy_trail_last[i]
			if previous.origin.distance_to(pose.origin)<1.0 and absf(angle_difference(previous.get_rotation(),pose.get_rotation()))<0.04: continue
		if _copy_trails.capture(_copies[i],pose,copy_trail_lifetime,0.42,i):
			_copy_trail_last[i] = pose

func _process(delta:float) -> void:
	if is_multiplayer_authority():
		_update_tip_guards()
		_update_copy_trails(delta)
		return
	if _pose_state.size()!=17 or _copies.size()!=4: return
	for i:int in range(4):
		_centers[i] = global_position+Vector2(_pose_state[i*4],_pose_state[i*4+1])
		_angles[i] = _pose_state[i*4+2]
		_tip_speeds[i+1] = _pose_state[i*4+3]
	_tip_speeds[0] = _pose_state[16]
	_apply_pose()
	_update_copy_trails(delta)

func player_control_action_ids() -> Array[StringName]: return [&"controlled_stab",&"controlled_formation"]
func player_control_action_hold_repeat_allowed(index:int) -> bool: return index==0
func controlled_stab() -> void:
	if is_player_controlled(): begin_stab()
func controlled_formation() -> void:
	if is_player_controlled(): choose_formation()
func get_ai_attack_threats(_receiver:ball) -> Array:
	var result:Array = []
	if health<=0 or dizziness or not Can_Attack or is_damage_output_disabled() or _transition_left>0.0 or not is_combat_runtime_active(): return result
	if formation==Formation.STAB and (_stab_time<0.0 or _stab_time>=stab_out_time): return result
	for i:int in range(5):
		if _tip_speeds[i]<=0.1: continue
		var center:Vector2 = global_position+Vector2.from_angle(_facing)*_main_shift if i==0 else _centers[i-1]
		var angle:float = _facing if i==0 else _angles[i-1]
		result.append({"shape":"circle","position":center+Vector2.from_angle(angle)*tip_distance(),"radius":tip_radius(),"damage":damage_at_speed(_tip_speeds[i]),"danger_in":0.0,"danger_duration":0.03,"kind":"stone_spear_tip","source":self})
	return result
func get_debug_attack_regions() -> Array: return get_ai_attack_threats(null)
func get_debug_detection_regions() -> Array[Dictionary]: return []
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_STONE_SPEAR")

func _emit_formation_audio() -> void:
	# One exact item.spear.use per accepted switch; no audio/gameplay RNG draw.
	if multiplayer.has_multiplayer_peer(): _play_audio.rpc("minecraft:item.spear.use",0,global_position,0.0)
	else: _play_audio("minecraft:item.spear.use",0,global_position,0.0)
func _emit_audio(hit:bool,point:Vector2,actual:float) -> void:
	if hit and (is_nan(actual) or actual<=0.0): return
	var event:String = ("minecraft:item.spear.hit" if actual<50.0 else HIT_GAIN.damage_event(actual)) if hit else "minecraft:item.spear.attack"
	var count:int = (HIT_SOUNDS.size() if event=="minecraft:item.spear.hit" else SOUNDS.EVENTS[event].size()) if hit else STAB_SOUNDS.size()
	var variant:int = _sfx_rng.randi_range(0,count-1)
	if multiplayer.has_multiplayer_peer(): _play_audio.rpc(event,variant,point,HIT_GAIN.damage_gain(actual) if hit else 0.0)
	else: _play_audio(event,variant,point,HIT_GAIN.damage_gain(actual) if hit else 0.0)
@rpc("authority","call_local","reliable")
func _play_audio(event:String,variant:int,point:Vector2,gain:float) -> void:
	var stream:AudioStream
	match event:
		"minecraft:item.spear.use": stream = FORMATION_SFX
		"minecraft:item.spear.attack": stream = STAB_SOUNDS[posmod(variant,STAB_SOUNDS.size())]
		"minecraft:item.spear.hit": stream = HIT_SOUNDS[posmod(variant,HIT_SOUNDS.size())]
		"stone_spear.block": stream = BLOCK_SFX
		_: stream = SOUNDS.EVENTS[event][posmod(variant,SOUNDS.EVENTS[event].size())].stream
	last_sound_event = event
	last_sound_gain = gain
	if event=="stone_spear.block":
		guard_feedback_count += 1
		last_guard_position = point
		var scene:Node = get_tree().current_scene
		if is_instance_valid(scene): _guard_ring_deferred.call_deferred(weakref(scene),point)
	var combat_feedback:bool = event not in ["minecraft:item.spear.attack","minecraft:item.spear.use"]
	AUDIO.queue_stream(self,stream,point,{"volume_db":gain,"priority":combat_feedback,"keep_after_source":combat_feedback,"metadata":{"mc_sound_event":event}})
func Die() -> void:
	_reset_copy_trails()
	_cancel_stab()
	for sprite:Sprite2D in _copies: sprite.hide()
	for guard:hurtbox in _tip_guards: guard.set_deferred("collision_layer",0)
	_guard_feedback_until.clear()
	super.Die()
