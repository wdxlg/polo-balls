extends "res://scripts/characters/我的世界/new5/base.gd"
## Left/right at rest; continuous, accelerating, full-angle alternating cuts in combat.
const SWORD:Texture2D = preload("res://Images/characters/我的世界/copper_sword/copper_sword.png")
const LIGHTNING = preload("res://scripts/effects/我的世界/trident_lightning.gd")
const MC_ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const CHARGE_VISUAL = preload("res://scripts/characters/我的世界/copper_sword/charge_visual.gd")
const SWING_TRAIL = preload("res://scripts/characters/我的世界/copper_sword/swing_trail.gd")
const NATIVE_FEEDBACK = preload("res://scripts/effects/我的世界/mc16_native_feedback.gd")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const WEAPON_SIZE = preload("res://scripts/characters/我的世界/weapon_visual_size.gd")

@export_category("铜剑 / 交替挥剑")
@export_range(0.20,1.50,0.01) var base_swing_duration:float = 0.44
@export_range(0.03,0.30,0.01) var initial_raise_duration:float = 0.07
@export_range(0.04,0.30,0.01) var return_duration:float = 0.12
@export_range(0.01,0.50,0.01) var speed_per_hit:float = 0.16
@export_range(1.0,5.0,0.1) var maximum_attack_speed:float = 3.0
@export_range(0.4,5.0,0.05) var combo_reset_delay:float = 1.25
@export_category("铜剑 / 攻击移动与残影")
@export_range(0.50,1.0,0.01) var attack_move_speed_ratio:float = 0.85
## Radians per second of the actual blade, not character movement or combo count.
@export_range(6.0,40.0,0.5) var trail_min_angular_speed:float = 16.0
@export_range(0.06,0.35,0.01) var trail_lifetime:float = 0.14
@export_category("铜剑 / 生锈与引雷")
@export_range(2.0,90.0,0.5) var rust_duration:float = 12.0
@export_range(0.5,30.0,0.5) var charged_duration:float = 5.0
@export_range(0.1,1.5,0.01) var lightning_warning:float = 0.68
@export_range(0.05,0.8,0.01) var hit_lightning_warning:float = 0.15
@export_range(12.0,180.0,1.0) var lightning_radius:float = 62.0
@export_range(0.1,5.0,0.1) var lightning_damage_ratio:float = 2.0
@export_range(0.1,3.0,0.05) var hit_lightning_damage_ratio:float = 0.75
@export_range(0.05,3.0,0.05) var lightning_stun:float = 0.65
@export_range(0.05,2.0,0.05) var hit_lightning_stun:float = 0.30

var native_feedback:Node
var charge_visual:Node2D
var swing_trail:Node2D
var rust:float = 0.0
var charged_left:float = 0.0
var combo_hits:int = 0
var cleanse_count:int = 0
var lightning_count:int = 0
var _combo_left:float = 0.0
var _swing_active:bool = false
var _swing_elapsed:float = 0.0
var _swing_duration:float = 0.44
var _swing_down:bool = true
var _next_swing_down:bool = true
var _swing_connected:bool = false
var _swing_hits:Dictionary = {}
var _last_phase:float = 0.0
var _last_pose:Transform2D
var _rest_position:Vector2
var _rest_scale:Vector2 = Vector2.ONE
var _swing_aim_from:float = 0.0
var _swing_aim_to:float = 0.0
var _windup_left:float = 0.0
var _windup_total:float = 0.0
var _raise_from:Transform2D = Transform2D.IDENTITY
var _holding_pose:bool = false
var _returning:bool = false
var _return_elapsed:float = 0.0
var _return_from:Transform2D = Transform2D.IDENTITY
var _manual_attack_held:bool = false
var _movement_face_right:bool = true
var _cleanse_pending:bool = false
var _cleanse_effect:Node2D
var _copper_audio:Array[WeakRef] = []
var _weapon_shapes:Dictionary = {}
var _grip_colliders:Array[CollisionShape2D] = []
## Native 16x16 item texture: the grip/pommel, not the blade or crossguard.
const GRIP_PIXEL_CENTER:Vector2 = Vector2(-4.5,4.5)
const HIT_BEGIN:float = 0.32
const HIT_END:float = 1.0
const SWING_HALF_ARC:float = 1.45
const SWING_EASE_POWER:float = 2.4

func _ready() -> void:
	dir_left = false
	Has_Collision_Damage = false
	Attack_Cooling = base_swing_duration
	# No generic ball sounds mixed into this vanilla-item character.
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	Unique_Hurt_Audio = AUDIO.EVENTS["entity.player.hurt"][0].stream
	Unique_Death_Audio = AUDIO.EVENTS["entity.item.break"][0].stream
	WEAPON_SIZE.fit_to_wooden_sword(image,1.0)
	_rest_scale = image.scale
	_rest_position = image.position
	super._ready()
	_rest_position = image.position
	_rest_scale = image.scale
	image.z_as_relative = false
	image.z_index = 3
	for path:NodePath in [NodePath("CollisionShape2D"),NodePath("hitbox/CollisionShape2D"),NodePath("hurtbox/CollisionShape2D")]:
		_grip_colliders.append(get_node(path) as CollisionShape2D)
	_face_right = not is_character_visual_flipped_h()
	_movement_face_right = _face_right
	native_feedback = NATIVE_FEEDBACK.attach(self,"copper_sword")
	charge_visual = CHARGE_VISUAL.new()
	charge_visual.name = "CopperTridentChargeVisual"
	charge_visual.unit = self
	add_child(charge_visual)
	swing_trail = SWING_TRAIL.new()
	swing_trail.name = "CopperSwordSwingTrail"
	swing_trail.unit = self
	add_child(swing_trail)
	add_to_group("MinecraftCopperSword")
	_ensure_weapon_shapes()
	visual_mob()

func get_preview_texture() -> Texture2D: return SWORD
func mc_live() -> bool: return active() and not is_damage_output_disabled()
func mc_enemy(target:Variant) -> bool:
	if not U.enemy(self,target) or target.health<=0 or target.is_queued_for_deletion(): return false
	if target.Type not in [Ball_Type.Ball,Ball_Type.Creature]: return false
	if target==Master or target.Master==self: return false
	if is_instance_valid(Master) and target.Master==Master: return false
	return true
func attack_speed() -> float:
	return clampf(1.0+float(combo_hits)*speed_per_hit,1.0,maximum_attack_speed)
func _cooling_scale() -> float:
	return maxf(Attack_Cooling,0.05)/maxf(base_swing_duration,0.05)
func current_swing_duration() -> float:
	return maxf(base_swing_duration*_cooling_scale()/attack_speed(),0.055)
func reset_combo() -> void:
	combo_hits = 0
	_combo_left = 0.0

func attack_movement_scale() -> float:
	return clampf(attack_move_speed_ratio,0.0,1.0) if can_act() and (_swing_active or _holding_pose) else 1.0

func move(speed:float,delta:float):
	# Scale only this call's voluntary locomotion. Never overwrite Speed/buff state;
	# the shared move() still owns knockback, crowd separation and transport.
	super.move(speed*attack_movement_scale(),delta)

func _has_attack_pose() -> bool:
	return _swing_active or _holding_pose or _returning

func _update_movement_facing() -> void:
	if not is_multiplayer_authority(): return
	var travel:Vector2 = player_control_direction if is_player_controlled() else velocity if velocity.length_squared()>1.0 else direction
	if absf(travel.x)>0.01: _movement_face_right = travel.x>0.0
	# Keep the same texture parity throughout a chain. Aim is a full angle, not a flip.
	if not _has_attack_pose(): _face_right = _movement_face_right

func _facing_toward(target:ball,fallback:bool) -> bool:
	var dx:float = target.global_position.x-global_position.x
	return dx>0.0 if absf(dx)>0.5 else fallback

func _aim_angle(target:ball = null) -> float:
	var aim:Vector2 = Vector2.RIGHT if _face_right else Vector2.LEFT
	if is_instance_valid(target): aim = ball.body_point(target,global_position)-global_position
	elif has_player_control_aim(): aim = player_control_aim_direction(aim)
	if aim.length_squared()<0.0001: aim = Vector2.RIGHT if _face_right else Vector2.LEFT
	return graphics.global_transform.basis_xform_inv(aim).angle()

func attack_axis() -> Vector2:
	return graphics.global_transform.basis_xform(Vector2.RIGHT.rotated(_swing_aim_to)).normalized()

func step_mob(delta:float) -> void:
	if not active(): return
	var dt:float = maxf(delta,0.0)
	_update_movement_facing()
	charged_left = maxf(charged_left-dt,0.0)
	_advance_rust(dt)
	_combo_left = maxf(_combo_left-dt,0.0)
	if combo_hits>0 and _combo_left<=0.0: reset_combo()
	if not can_act():
		cancel_swing()
		reset_combo()
		_advance_return(dt)
		return
	# Consume the remaining frame time across the stroke boundary. No recovery timer,
	# idle frame, or trip back to the neutral pose is inserted between opposite cuts.
	var remaining:float = dt
	for _guard:int in range(32):
		if not _swing_active:
			var wants_attack:bool = not is_player_controlled() or _manual_attack_held
			var target:ball = _select_swing_target() if wants_attack else null
			if wants_attack and (target!=null or is_player_controlled()): begin_swing(target)
			if not _swing_active:
				if _holding_pose: cancel_swing()
				_advance_return(remaining)
				return
		if remaining<=0.000001: return
		var used:float = minf(remaining,_windup_left+maxf(_swing_duration-_swing_elapsed,0.0))
		advance_swing(used)
		remaining = maxf(remaining-used,0.0)
		if _swing_active: return

func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and is_instance_valid(swing_trail): swing_trail.advance(delta)
	super.tick_physics(state,delta)
	if not active(): return
	_update_movement_facing()
	# Include translation performed by ball.move() in this same physics tick.
	if _swing_active and _windup_left<=0.0 and can_act(): _sample_swing(_last_phase)
	visual_mob()

func begin_swing(target:ball = null) -> bool:
	if not can_act() or _swing_active: return false
	_update_movement_facing()
	if not mc_enemy(target) or not target.is_combat_lockable(): target = _select_swing_target()
	var continuing:bool = _holding_pose
	var previous_aim:float = _swing_aim_to
	var previous_pose:Transform2D = _current_local_pose()
	if not _has_attack_pose():
		if target!=null: _face_right = _facing_toward(target,_face_right)
		elif has_player_control_aim():
			var hint:Vector2 = player_control_aim_direction()
			if absf(hint.x)>0.01: _face_right = hint.x>0.0
	_swing_aim_to = _aim_angle(target)
	_swing_aim_from = previous_aim if continuing else _swing_aim_to
	_swing_down = _next_swing_down
	_next_swing_down = not _next_swing_down
	# Attack speed changes the time spent actually swinging, not a delay between hits.
	_swing_duration = current_swing_duration()
	_swing_elapsed = 0.0
	_windup_total = 0.0 if continuing else minf(initial_raise_duration,_swing_duration*0.24)
	_windup_left = _windup_total
	_raise_from = previous_pose
	_holding_pose = false
	_returning = false
	_last_phase = 0.0
	_swing_hits.clear()
	_swing_connected = false
	_swing_active = true
	Attacking = true
	_last_pose = weapon_transform(0.0)
	visual_mob()
	_sync_copper_visual()
	return true

func advance_swing(delta:float) -> void:
	if not active() or not _swing_active: return
	if not can_act():
		cancel_swing()
		reset_combo()
		return
	var dt:float = maxf(delta,0.0)
	if _windup_left>0.0:
		var raising:float = minf(dt,_windup_left)
		_windup_left = maxf(_windup_left-raising,0.0)
		dt -= raising
		if _windup_left>0.000001:
			visual_mob()
			return
		_windup_left = 0.0
	var previous:float = _last_phase
	_swing_elapsed = minf(_swing_duration,_swing_elapsed+dt)
	var phase:float = clampf(_swing_elapsed/maxf(_swing_duration,0.001),0.0,1.0)
	if previous<HIT_BEGIN and phase>=HIT_BEGIN:
		_emit_copper_sound("entity.player.attack.sweep",global_position,-5.0)
	_sample_swing(phase)
	if is_instance_valid(swing_trail): swing_trail.record_segment(previous,phase)
	if phase>=1.0:
		if _swing_connected:
			combo_hits = mini(combo_hits+1,999)
			_combo_left = combo_reset_delay
		else: reset_combo()
		_swing_active = false
		_holding_pose = true
		Attacking = false
		# Preserve the endpoint for the reverse stroke. Stopping is a separate return.
		_sync_copper_visual()
	visual_mob()

func cancel_swing() -> void:
	_manual_attack_held = false
	if not _swing_active and not _holding_pose: return
	_return_from = _current_local_pose()
	_swing_active = false
	_holding_pose = false
	_windup_left = 0.0
	Attacking = false
	_returning = true
	_return_elapsed = 0.0
	visual_mob()
	_sync_copper_visual()

func _advance_return(delta:float) -> void:
	if not _returning: return
	_return_elapsed = minf(return_duration,_return_elapsed+maxf(delta,0.0))
	if _return_elapsed>=return_duration:
		_returning = false
		if is_multiplayer_authority(): _update_movement_facing()
		else: _face_right = _movement_face_right
	visual_mob()

func _rest_pose() -> Transform2D:
	return Transform2D(0.0,_rest_scale,0.0,_rest_position)

func _current_local_pose() -> Transform2D:
	if _returning:
		var t:float = clampf(_return_elapsed/maxf(return_duration,0.001),0.0,1.0)
		return _return_from.interpolate_with(_rest_pose(),1.0-pow(1.0-t,3.0))
	if _swing_active:
		if _windup_left>0.0:
			var raised:float = 1.0-_windup_left/maxf(_windup_total,0.001)
			return _raise_from.interpolate_with(_weapon_local_pose(0.0),smoothstep(0.0,1.0,raised))
		return _weapon_local_pose(clampf(_swing_elapsed/maxf(_swing_duration,0.001),0.0,1.0))
	if _holding_pose: return _weapon_local_pose(1.0)
	return _rest_pose()

func weapon_angle(phase:float) -> float:
	var p:float = clampf(phase,0.0,1.0)
	# Ease-IN only: slow start, fast finish. No ease-out/neutral-pose segment.
	var sweep:float = lerpf(-SWING_HALF_ARC,SWING_HALF_ARC,pow(p,SWING_EASE_POWER))
	if not _swing_down: sweep = -sweep
	if not _face_right: sweep = -sweep
	# A new target can be anywhere around us. Retarget smoothly in the slow part,
	# keeping phase0 EXACTLY at the previous endpoint, even across the +/-PI seam.
	var aim:float = lerp_angle(_swing_aim_from,_swing_aim_to,smoothstep(0.0,HIT_BEGIN,p))
	var native_axis:float = -PI*0.25 if _face_right else -PI*0.75
	return aim-native_axis+sweep

func _weapon_local_pose(phase:float) -> Transform2D:
	var angle:float = weapon_angle(phase)
	var grip:Vector2 = Vector2(-5.5 if _face_right else 5.5,5.5)*_rest_scale
	var position_local:Vector2 = _rest_position+grip-grip.rotated(angle)
	return Transform2D(angle,_rest_scale,0.0,position_local)

func weapon_transform(phase:float) -> Transform2D:
	return graphics.global_transform*_weapon_local_pose(phase)

func _ensure_weapon_shapes() -> void:
	if not _weapon_shapes.is_empty(): return
	# Share geometry within this battle, not in a static script cache that keeps
	# the character's textures/materials alive after the World is disposed.
	var world:Node = get_tree().current_scene
	if world!=null and world.has_meta("mc_copper_weapon_shapes"):
		_weapon_shapes = world.get_meta("mc_copper_weapon_shapes")
		return
	var pixels:Image = SWORD.get_image()
	var points := PackedVector2Array()
	for y:int in range(pixels.get_height()):
		for x:int in range(pixels.get_width()):
			if pixels.get_pixel(x,y).a<=0.1: continue
			for corner:Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				points.append(Vector2(x,y)+corner-SWORD.get_size()*0.5)
	var hull:PackedVector2Array = Geometry2D.convex_hull(points)
	if hull.size()>1 and hull[0]==hull[-1]: hull.remove_at(hull.size()-1)
	var right_shape := ConvexPolygonShape2D.new()
	right_shape.points = hull
	_weapon_shapes[true] = right_shape
	for i:int in range(hull.size()): hull[i].x = -hull[i].x
	hull.reverse()
	var left_shape := ConvexPolygonShape2D.new()
	left_shape.points = hull
	_weapon_shapes[false] = left_shape
	if world!=null: world.set_meta("mc_copper_weapon_shapes",_weapon_shapes)

func _has_swing_target() -> bool:
	return _select_swing_target()!=null

func _select_swing_target() -> ball:
	# Probe the same aimed sweep and mirrored native polygon that actually do damage.
	var reach:float = SWORD.get_size().length()*image.global_scale.length()+8.0
	var saved_down:bool = _swing_down
	var saved_facing:bool = _face_right
	var saved_from:float = _swing_aim_from
	var saved_to:float = _swing_aim_to
	var keep_parity:bool = _has_attack_pose()
	_swing_down = _next_swing_down
	var closest:float = INF
	var result:ball
	for raw:Node in SubmissionCharacterTools.targeting_candidates(self):
		if not mc_enemy(raw) or not raw.is_combat_lockable(): continue
		var candidate:ball = raw as ball
		var distance:float = global_position.distance_squared_to(ball.body_point(candidate,global_position))
		if distance>=closest or distance>pow(reach+U.radius(candidate),2.0): continue
		if not U.line_clear(self,global_position,ball.body_point(candidate,global_position)): continue
		_face_right = saved_facing if keep_parity else _facing_toward(candidate,saved_facing)
		_swing_aim_to = _aim_angle(candidate)
		_swing_aim_from = saved_to if _holding_pose else _swing_aim_to
		# Uniform angular samples, not uniform time in the slow-start easing curve.
		for i:int in range(17):
			var progress:float = lerpf(pow(HIT_BEGIN,SWING_EASE_POWER),1.0,float(i)/16.0)
			var phase:float = pow(progress,1.0/SWING_EASE_POWER)
			if candidate in _contacts_at(weapon_transform(phase)):
				result = candidate
				closest = distance
				break
	_face_right = saved_facing
	_swing_down = saved_down
	_swing_aim_from = saved_from
	_swing_aim_to = saved_to
	return result

func _contacts_at(pose:Transform2D) -> Array[ball]:
	_ensure_weapon_shapes()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _weapon_shapes[_face_right]
	query.transform = pose
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result:Array[ball] = []
	for contact:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,128):
		var collider:Node = contact.collider
		var raw:Node = collider
		while is_instance_valid(raw) and not raw is ball: raw = raw.get_parent()
		if not raw is ball or collider!=raw.self_hurtbox or not mc_enemy(raw): continue
		if not U.line_clear(self,global_position,ball.body_point(raw,global_position)): continue
		if raw not in result: result.append(raw as ball)
	return result

func _sample_swing(next_phase:float) -> void:
	if not _swing_active or _windup_left>0.0 or not can_act(): return
	var pose:Transform2D = weapon_transform(next_phase)
	var travel:float = _last_pose.origin.distance_to(pose.origin)
	var turn:float = absf(angle_difference(_last_pose.get_rotation(),pose.get_rotation()))
	var phase_travel:float = absf(next_phase-_last_phase)*2.0*SWING_HALF_ARC*SWING_EASE_POWER
	var count:int = clampi(int(ceil(maxf(maxf(travel/1.5,turn/0.035),phase_travel/0.035))),1,384)
	var root_shift:Vector2 = _last_pose.origin-weapon_transform(_last_phase).origin
	for i:int in range(count+1):
		var fraction:float = float(i)/float(count)
		var phase:float = lerpf(_last_phase,next_phase,fraction)
		if phase<HIT_BEGIN or phase>HIT_END: continue
		var sample:Transform2D = weapon_transform(phase)
		sample.origin += root_shift*(1.0-fraction)
		for target:ball in _contacts_at(sample):
			var id:int = target.get_instance_id()
			if _swing_hits.has(id): continue
			_swing_hits[id] = true
			var point:Vector2 = ball.body_point(target,global_position)
			if _damage_with_feedback(target,attack_damage(),point):
				_swing_connected = true
				_combo_left = combo_reset_delay
				if charged_left>0.0 and Can_Skill: _summon_lightning(point,false)
	_last_phase = next_phase
	_last_pose = pose

func _damage_with_feedback(target:ball,amount:float,point:Vector2) -> bool:
	if not mc_live() or not mc_enemy(target) or amount<=0.0: return false
	var before:float = maxf(target.health,0.0)
	var accepted:bool = U.damage(self,target,amount,point)
	var remaining:float = maxf(target.health,0.0) if is_instance_valid(target) else 0.0
	var actual:float = maxf(before-remaining,0.0)
	if not accepted or actual<=0.0: return false
	_emit_copper_sound(HIT_GAIN.damage_event(actual),point,HIT_GAIN.damage_gain(actual))
	return true

func _advance_rust(delta:float) -> void:
	if not active(): return
	if _cleanse_pending and (not is_instance_valid(_cleanse_effect) or _cleanse_effect.is_queued_for_deletion()): _cleanse_pending = false
	if not Can_Skill or is_damage_output_disabled(): return
	if _cleanse_pending: return
	rust = minf(1.0,rust+maxf(delta,0.0)/maxf(rust_duration,0.01))
	if rust>=1.0:
		_cleanse_pending = true
		_summon_lightning(global_position,true)

func _summon_lightning(point:Vector2,cleansing:bool) -> void:
	if not mc_live() or not Can_Skill: return
	lightning_count += 1
	var seed_value:int = rng.randi_range(1,2147483646)
	_show_copper_lightning(point,seed_value,cleansing)
	if multiplayer.has_multiplayer_peer(): _show_copper_lightning.rpc(point,seed_value,cleansing)

@rpc("authority","call_remote","reliable")
func _show_copper_lightning(point:Vector2,seed_value:int,cleansing:bool) -> void:
	if health<=0: return
	var callback:Callable = _on_lightning_impact.bind(cleansing) if is_multiplayer_authority() else Callable()
	var effect:Node2D = MC_ABILITIES.lightning(self,point,seed_value,lightning_radius,lightning_warning if cleansing else hit_lightning_warning,{
		"script":LIGHTNING,"name":"CopperCleanseLightning" if cleansing else "CopperHitLightning",
		"fields":{"caster":self,"fixed_impact":not cleansing},"on_impact":callback
	})
	if effect == null: return
	effect.set_meta("copper_cleanse",cleansing)
	if cleansing: _cleanse_effect = effect

func _self_foot_world_position() -> Vector2: return global_position

func _on_lightning_impact(point:Vector2,cleansing:bool) -> void:
	if not active(): return
	if cleansing:
		if not _cleanse_pending: return
		_cleanse_pending = false
		if not Can_Skill or is_damage_output_disabled(): return
		cleanse_negative_effects() # Only the completed natural rust-cycle bolt, never hit lightning.
		rust = 0.0
		charged_left = maxf(charged_duration,0.0)
		cleanse_count += 1
		native_feedback.request("block.enchantment_table.use",point,-7.0,0.0)
		_sync_copper_visual()
	if not mc_live() or not Can_Skill: return
	var ratio:float = lightning_damage_ratio if cleansing else hit_lightning_damage_ratio
	var stun_time:float = lightning_stun if cleansing else hit_lightning_stun
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not GEOMETRY.enemy(self,raw): continue
		if point.distance_to(ball.body_point(raw,point))>lightning_radius+GEOMETRY.radius(raw): continue
		# Deliberately does not use the melee callback: lightning cannot proc itself.
		if _damage_with_feedback(raw,attack_damage()*ratio,point) and is_instance_valid(raw) and raw.health>0:
			raw.apply_stun(stun_time)
	visual_mob()

func player_control_action_ids() -> Array[StringName]:
	# Oxidation/lightning reaction is passive; Skill() only clears the state flag.
	return [&"controlled_attack_action"]
func player_control_action(action_index:int) -> void:
	# Do not let mouse/target aim overwrite locomotion. The held input connects cuts.
	if not is_player_controlled() or not is_multiplayer_authority(): return
	if action_index==0:
		_manual_attack_held = true
		begin_swing()
func player_control_action_released(action_index:int) -> void:
	if action_index!=0 or not is_multiplayer_authority(): return
	_manual_attack_held = false
	# A tap still completes its one slash; release only prevents the next slash.
	if not _swing_active and _holding_pose: cancel_swing()
func player_control_action_cancelled(action_index:int) -> void:
	if action_index!=0 or not is_multiplayer_authority(): return
	_manual_attack_held = false
	cancel_swing()
	reset_combo()
func set_player_control_peer(peer_id:int) -> void:
	var previous:int = player_control_peer_id
	super.set_player_control_peer(peer_id)
	if previous!=player_control_peer_id: _manual_attack_held = false
func controlled_attack_action() -> void: begin_swing()
func Attack() -> void: begin_swing()
func Skill() -> void: Using_Skill = false # Oxidation is passive, not a manual cleanse.

func _emit_copper_sound(event:String,point:Vector2,volume_db:float) -> void:
	if not is_multiplayer_authority(): return
	_play_copper_sound(event,point,volume_db)
	if multiplayer.has_multiplayer_peer(): _play_copper_sound.rpc(event,point,volume_db)
@rpc("authority","call_remote","reliable")
func _play_copper_sound(event:String,point:Vector2,volume_db:float) -> void:
	var player:AudioStreamPlayer2D = AUDIO.play(self,event,point,volume_db,false,true,true,true)
	if is_instance_valid(player):
		player.set_meta("mc_damage_source",get_instance_id())
		_copper_audio.append(weakref(player))
func _process(delta:float) -> void:
	# Authority ages echoes on the physics clock, replicas on their visual clock.
	if not is_multiplayer_authority() and is_instance_valid(swing_trail): swing_trail.advance(delta)
	super._process(delta)
	for i:int in range(_copper_audio.size()-1,-1,-1):
		var player:Variant = _copper_audio[i].get_ref()
		if not is_instance_valid(player): _copper_audio.remove_at(i)
		else: player.stream_paused = not is_combat_runtime_active()

func visual_mob() -> void:
	# Also remove a previous version's persistent label without hiding HP or other buffs.
	side_status_remove_permanent("left","mc_copper_sword")
	if not is_instance_valid(image): return
	set_character_visual_flip_h(not _face_right)
	image.transform = _current_local_pose()
	_sync_grip_colliders()
	image.set_instance_shader_parameter("rust_level",rust)

func _sync_grip_colliders() -> void:
	if _grip_colliders.is_empty(): return
	# Sprite mirroring is done in the shader and does not change image.transform.
	# Explicitly mirror the handle point/axis before applying the animated pose.
	var facing:float = 1.0 if _face_right else -1.0
	var pose:Transform2D = image.global_transform
	var center:Vector2 = pose * Vector2(GRIP_PIXEL_CENTER.x*facing,GRIP_PIXEL_CENTER.y)
	var shaft:Vector2 = pose.basis_xform(Vector2(-facing,1.0))
	if shaft.length_squared()<0.000001: return
	var angle:float = shaft.angle()-PI*0.5 # Capsule's long axis is local Y.
	for collider:CollisionShape2D in _grip_colliders:
		collider.global_position = center
		collider.global_rotation = angle

func _sync_copper_visual() -> void:
	if multiplayer.has_multiplayer_peer(): _new5_visual.rpc(network_visual_state())
func visual_state() -> Dictionary:
	return {"time":clock,"rust":rust,"charged":charged_left,"combo":combo_hits,"active":_swing_active,"elapsed":_swing_elapsed,"duration":_swing_duration,"down":_swing_down,"pending":_cleanse_pending,
		"aim_from":_swing_aim_from,"aim_to":_swing_aim_to,"windup":_windup_left,"windup_total":_windup_total,"raise_from":_raise_from,"holding":_holding_pose,
		"returning":_returning,"return_elapsed":_return_elapsed,"return_from":_return_from,"return_duration":return_duration,"move_face":_movement_face_right,"trail_threshold":trail_min_angular_speed,"trail_lifetime":trail_lifetime}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	rust = clampf(float(data.get("rust",0.0)),0.0,1.0)
	charged_left = maxf(float(data.get("charged",0.0)),0.0)
	combo_hits = maxi(int(data.get("combo",0)),0)
	_swing_active = bool(data.get("active",false))
	_swing_duration = maxf(float(data.get("duration",base_swing_duration)),0.01)
	_swing_elapsed = clampf(float(data.get("elapsed",0.0)),0.0,_swing_duration)
	_swing_down = bool(data.get("down",true))
	_cleanse_pending = bool(data.get("pending",false))
	_swing_aim_from = float(data.get("aim_from",0.0))
	_swing_aim_to = float(data.get("aim_to",_swing_aim_from))
	_windup_total = maxf(float(data.get("windup_total",0.0)),0.0)
	_windup_left = clampf(float(data.get("windup",0.0)),0.0,_windup_total)
	_raise_from = data.get("raise_from",_rest_pose())
	_holding_pose = bool(data.get("holding",false))
	_returning = bool(data.get("returning",false))
	_return_elapsed = maxf(float(data.get("return_elapsed",0.0)),0.0)
	_return_from = data.get("return_from",_rest_pose())
	return_duration = maxf(float(data.get("return_duration",return_duration)),0.01)
	_movement_face_right = bool(data.get("move_face",_face_right))
	trail_min_angular_speed = maxf(float(data.get("trail_threshold",trail_min_angular_speed)),0.0)
	trail_lifetime = maxf(float(data.get("trail_lifetime",trail_lifetime)),0.01)
func client_visual_step(delta:float) -> void:
	if health<=0 or not is_combat_runtime_active(): return
	var dt:float = maxf(delta,0.0)
	if _swing_active:
		var previous:float = clampf(_swing_elapsed/_swing_duration,0.0,1.0)
		var raising:float = minf(dt,_windup_left)
		_windup_left = maxf(_windup_left-raising,0.0)
		_swing_elapsed = minf(_swing_elapsed+dt-raising,_swing_duration)
		if is_instance_valid(swing_trail): swing_trail.record_segment(previous,_swing_elapsed/_swing_duration)
		if _swing_elapsed>=_swing_duration:
			_swing_active = false
			_holding_pose = true
	_advance_return(dt)
	charged_left = maxf(charged_left-dt,0.0)

func get_debug_attack_regions() -> Array[Dictionary]:
	if not _swing_active or _windup_left>0.0 or health<=0 or _last_phase<HIT_BEGIN or _last_phase>HIT_END: return []
	var points := PackedVector2Array()
	var pose:Transform2D = weapon_transform(_last_phase)
	for point:Vector2 in _weapon_shapes[_face_right].points: points.append(pose*point)
	return [{"shape":"polygon","points":points,"damage":attack_damage(),"kind":"copper_sword_blade"}]
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_COPPER_SWORD")

@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	ITEM_DEATH.spawn(self)
func Die() -> void:
	if _death_sound_done: return
	if is_instance_valid(swing_trail): swing_trail.clear()
	cancel_swing()
	reset_combo()
	charged_left = 0.0
	_cleanse_pending = false
	for child:Node in get_children():
		if child.get_script()==LIGHTNING: child.queue_free()
	super.Die()
func _exit_tree() -> void:
	for ref:WeakRef in _copper_audio:
		var player:Variant = ref.get_ref()
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	super._exit_tree()
