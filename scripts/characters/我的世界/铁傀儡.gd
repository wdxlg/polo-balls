extends "res://scripts/characters/我的世界/iron_golem/pair_base.gd"
const AIRBORNE:Script = preload("res://scripts/characters/我的世界/iron_golem/airborne.gd")
const PHYSICAL_AIRBORNE:Script = preload("res://scripts/effects/physical_airborne_effect.gd")
const GOLEM_FRAMES:Array[SpriteFrames] = [
	preload("res://Images/characters/我的世界/iron_golem/golem_0.tres"),
	preload("res://Images/characters/我的世界/iron_golem/golem_1.tres"),
	preload("res://Images/characters/我的世界/iron_golem/golem_2.tres"),
	preload("res://Images/characters/我的世界/iron_golem/golem_3.tres")]
const PREVIEW:Texture2D = preload("res://Images/characters/我的世界/iron_golem/golem_0_preview.png")
@export var windup_duration:float = 1.2
@export var minimum_charge:float = 0.12
@export var maximum_charge_damage:float = 2.0
@export var maximum_charge_launch:float = 2.2
@export var swing_duration:float = 0.48
@export var attack_interval:float = 1.7
@export var melee_reach:float = 43.0
@export var launch_distance:float = 55.0
@export var launch_speed:float = 260.0
@export var stun_duration:float = 0.65
@export var rage_damage_multiplier:float = 1.5
@export var rage_speed_multiplier:float = 1.35
@export var rage_interval_multiplier:float = 0.65
var companion:Node2D
var companion_spawned:bool = false
var enraged:bool = false
var _attack_wait:float = 0.5
var _phase:int = 0
var _phase_time:float = 0.0
# Attack-facing is authoritative; rejected direction changes are never buffered.
@export var attack_facing_flipped_h:bool = false
var _charge_target:WeakRef
var _charge_elapsed:float = 0.0
var _released_charge:float = 0.0
var _last_charge_offset:Vector2 = Vector2.ZERO
var _charge_sample_valid:bool = false
const SWING_FRAMES:int = 24
const IMPACT_TIME:float = 0.09
const MAX_ARM_SCALE:float = 2.1
var _swing_hit:bool = false
var _companion_death_notified:bool = false

func _ready() -> void:
	mc_audio_role = "iron_golem"
	pair_frames = GOLEM_FRAMES[0]
	super._ready()
	add_to_group("MinecraftIronGolem")
	update_pair_visual()
	ensure_companion.call_deferred()

func get_preview_texture() -> Texture2D: return PREVIEW
func crack_stage() -> int: return crack_stage_for_health(health)
func crack_stage_for_health(value:float) -> int:
	var ratio:float = value/maxf(Max_health,1.0)
	return 3 if ratio < 0.25 else 2 if ratio < 0.5 else 1 if ratio < 0.75 else 0
func repair_target_health() -> int:
	var stage:int = crack_stage()
	return int(ceil(float(Max_health)*[0.0,0.75,0.5,0.25][stage])) if stage>0 else health

func ensure_companion() -> void:
	if companion_spawned or not is_multiplayer_authority() or health<=0 or not is_combat_runtime_active(): return
	var scene:Node = get_tree().current_scene
	if scene == null: return
	var point:Vector2 = global_position
	for offset:Vector2 in [Vector2(30,12),Vector2(-30,12),Vector2(0,35),Vector2(0,-35)]:
		if mc_position_clear(global_position+offset,9.0):
			point = global_position+offset
			break
	var unit:ball = load("res://scenes/creatures/铁傀儡村民.tscn").instantiate()
	unit.Master = self
	unit.Master_name = str(get_path())
	unit.Team = Team
	unit.name = str(name)+"_Villager"
	unit.position = scene.to_local(point) if scene is Node2D else point
	unit.set_multiplayer_authority(get_multiplayer_authority())
	var victory_key:String = "team:"+Team if not Team.is_empty() else "solo_setup:"+str(get_meta("battle_setup_id")) if has_meta("battle_setup_id") else "solo_instance:"+str(get_instance_id())
	var presentation_key:String = "team:"+Team if not Team.is_empty() else "solo:"+str(get_instance_id())
	if scene.has_method("_victory_side_key_for_character"): victory_key = scene.call("_victory_side_key_for_character",self)
	if scene.has_method("return_ball_side_key"): presentation_key = scene.call("return_ball_side_key",self)
	unit.continuation_victory_key = victory_key
	unit.continuation_presentation_key = presentation_key
	unit.set_meta("battle_continuation_victory_side_key",victory_key)
	unit.set_meta("victory_side_key",victory_key)
	unit.set_meta("battle_continuation_presentation_side_key",presentation_key)
	unit.set_meta("battle_continuation_display_name","铁傀儡")
	companion = unit
	companion_spawned = true
	scene.add_child(unit,true)
	unit.add_to_group("BattleTransient")
	# World MultiplayerSpawner replicates the PackedScene; do not duplicate it with an RPC.

func tick_physics(state:State,delta:float) -> void:
	# Movement/collisions remain active, but attack phases reject their turn requests.
	pair_frames = GOLEM_FRAMES[clampi(visual_stage,0,3)]
	super.tick_physics(state,delta)
	if is_multiplayer_authority() and health>0 and is_combat_runtime_active():
		ensure_companion()
		if companion_spawned and is_instance_valid(companion) and companion.health<=0: on_companion_killed()
		visual_stage = crack_stage()
		visual_rage = enraged
		if dizziness or is_damage_output_disabled() or not Can_Attack:
			cancel_swing()
		else:
			step_attack(delta)
	pair_frames = GOLEM_FRAMES[clampi(visual_stage,0,3)]
	update_pair_visual()

func is_direction_change_locked() -> bool:
	if not is_node_ready() or health<=0: return false
	return _phase in [1,2] if is_multiplayer_authority() else visual_clip in ["charge","swing"]

func set_character_visual_flip_h(flipped:bool) -> void:
	# Reapply the same pose when shaders/textures refresh, never a pending flip.
	super.set_character_visual_flip_h(attack_facing_flipped_h if is_direction_change_locked() else flipped)

func set_player_control_direction(input_direction:Vector2) -> void:
	# Releasing movement may stop the player, but new turns during attack are dropped.
	if is_direction_change_locked() and not input_direction.is_zero_approx(): return
	super.set_player_control_direction(input_direction)

func update_pair_visual() -> void:
	# Replicas receive the locked facing with their existing charge/swing pose data.
	if is_direction_change_locked(): super.set_character_visual_flip_h(attack_facing_flipped_h)
	super.update_pair_visual()

func current_attack_heading() -> Vector2:
	var sign_x:float = -1.0 if dir_left else 1.0
	if is_character_visual_flipped_h(): sign_x = -sign_x
	# Includes root/Graphics/Image rotation and negative-scale transforms.
	return (image.global_transform.x * sign_x).normalized()

func charge_fraction(elapsed:float) -> float:
	return clampf((elapsed-minimum_charge)/maxf(windup_duration-minimum_charge,0.01),0.0,1.0)

func arm_scale_at(clock:float) -> float:
	# Exact same sampled curve as bake_pair.py; no oversized invisible reach.
	var frame:int = clampi(int(clock*float(SWING_FRAMES)/swing_duration),0,SWING_FRAMES-1)
	var f:float = float(frame)/float(SWING_FRAMES-1)
	if f<=0.18: return lerpf(1.0,MAX_ARM_SCALE,f/0.18)
	if f<=0.36: return MAX_ARM_SCALE
	return lerpf(MAX_ARM_SCALE,1.0,(f-0.36)/0.64)

func current_arm_scale() -> float:
	return arm_scale_at(visual_clock) if visual_clip=="swing" else 1.0

func target_in_front(target:ball,heading:Vector2,arm_size:float = 1.0) -> bool:
	if not mc_enemy(target): return false
	var offset:Vector2 = target.global_position-global_position
	if offset.dot(heading)<=0.001 or offset.length()>melee_reach*arm_size+12.0: return false
	return overlaps_target(target,global_position+heading*20.0*arm_size,22.0*arm_size) and mc_line_clear(global_position,target.global_position)

func nearest_front_enemy() -> ball:
	var nearest:ball = null
	var best:float = melee_reach*melee_reach
	var heading:Vector2 = current_attack_heading()
	for node:Node in SubmissionCharacterTools.targeting_candidates(self):
		var target:ball = node as ball
		if not mc_enemy(target) or not target.is_combat_lockable(): continue
		var distance:float = global_position.distance_squared_to(target.global_position)
		if distance<=best and target_in_front(target,heading):
			best = distance
			nearest = target
	return nearest

func cancel_swing() -> void:
	_phase = 0
	_phase_time = 0.0
	_charge_elapsed = 0.0
	_released_charge = 0.0
	_charge_target = null
	_charge_sample_valid = false
	set_pair_clip("idle")

func should_release_charge(target:Variant,delta:float) -> bool:
	if _charge_elapsed>=windup_duration: return true
	if not mc_enemy(target): return true
	var offset:Vector2 = target.global_position-global_position
	var relative_velocity:Vector2 = target.velocity-velocity
	if _charge_sample_valid and delta>0.00001:
		relative_velocity = (offset-_last_charge_offset)/delta
	_last_charge_offset = offset
	_charge_sample_valid = true
	var heading:Vector2 = current_attack_heading()
	var predicted:Vector2 = offset+relative_velocity*IMPACT_TIME
	# Wall/body collision cannot turn this attack. Only actual target escape,
	# range, occlusion or full charge may release it; no deferred bounce trigger.
	return offset.dot(heading)<=0.0 or not mc_line_clear(global_position,target.global_position) or offset.length()>=melee_reach-4.0 or predicted.length()>=melee_reach-4.0 or predicted.dot(heading)<=2.0


func release_swing() -> void:
	if _phase==0: attack_facing_flipped_h = is_character_visual_flipped_h()
	_released_charge = charge_fraction(_charge_elapsed)
	_phase = 2
	_phase_time = 0.0
	set_pair_clip("swing")
	visual_clock = 0.0
	mc_play("attack",-2.0)

func step_attack(delta:float) -> void:
	if not mc_live() or dizziness or not Can_Attack: return
	_attack_wait = maxf(_attack_wait-delta,0.0)
	if _phase == 0:
		if _attack_wait<=0.0 and not is_player_controlled():
			var target:ball = nearest_front_enemy()
			if target != null: begin_swing(target)
		if _phase==0: set_pair_clip("walk" if not direction.is_zero_approx() else "idle")
	else:
		_phase_time += delta
		if _phase == 1:
			_charge_elapsed = minf(_phase_time,windup_duration)
			visual_clock = 0.38*clampf(_charge_elapsed/windup_duration,0.0,1.0)
			var target:Variant = _charge_target.get_ref() if _charge_target!=null else null
			var release:bool = should_release_charge(target,delta)
			if _charge_elapsed>=minimum_charge and release: release_swing()
		elif _phase == 2:
			visual_clock = minf(_phase_time,swing_duration)
			if not _swing_hit and _phase_time>=IMPACT_TIME:
				_swing_hit = true
				# Resolve at the actual impact pose, even if a long tick skipped past it.
				var clock:float = visual_clock
				visual_clock = IMPACT_TIME
				resolve_upswing()
				visual_clock = clock
			if _phase_time>=swing_duration:
				_phase = 0
				set_pair_clip("idle")

func begin_swing(target:ball) -> bool:
	if not mc_live() or dizziness or not Can_Attack or _phase!=0 or _attack_wait>0.0 or not mc_enemy(target): return false
	if global_position.distance_to(target.global_position)>melee_reach or not target_in_front(target,current_attack_heading()): return false
	attack_facing_flipped_h = is_character_visual_flipped_h()
	_phase = 1
	_phase_time = 0.0
	_charge_elapsed = 0.0
	_released_charge = 0.0
	_swing_hit = false
	_charge_target = weakref(target)
	_last_charge_offset = target.global_position-global_position
	_charge_sample_valid = false
	_attack_wait = attack_interval*(rage_interval_multiplier if enraged else 1.0)
	set_pair_clip("charge")
	notify_ai_noise("attack")
	return true

func resolve_upswing() -> int:
	if not mc_live() or dizziness or not Can_Attack: return 0
	var count:int = 0
	var heading:Vector2 = current_attack_heading()
	var size:float = current_arm_scale()
	var damage_scale:float = lerpf(1.0,maximum_charge_damage,_released_charge)*(rage_damage_multiplier if enraged else 1.0)
	var height:float = launch_distance*lerpf(1.0,maximum_charge_launch,_released_charge)
	var speed:float = launch_speed*lerpf(1.0,1.5,_released_charge)
	for node:Node in SubmissionCharacterTools.targeting_candidates(self):
		var target:ball = node as ball
		if not target_in_front(target,heading,size): continue
		var offset:Vector2 = target.global_position-global_position
		set_meta("blood_attack_velocity",Vector2.UP*speed)
		if mc_damage_with_impact(target,attack_damage(damage_scale),target.global_position):
			count += 1
			var launch:Vector2 = (Vector2.UP+offset.normalized()*0.22).normalized()
			launch_target(target,height,speed,launch)
	return count

func launch_target(target:ball,height:float,up_speed:float,ground_direction:Vector2) -> Node:
	if not mc_live() or not mc_enemy(target) or not target.can_receive_control_from(self): return null
	var power:float = attack_damage(rage_damage_multiplier if enraged else 1.0)/48.0
	if multiplayer.has_multiplayer_peer(): _start_airborne.rpc(target.get_path(),height,up_speed,stun_duration,power,ground_direction)
	var effect:Node = _start_airborne(target.get_path(),height,up_speed,stun_duration,power,ground_direction)
	return effect

@rpc("authority","call_remote","reliable")
func _start_airborne(target_path:NodePath,height:float,up_speed:float,stun:float,power:float,ground_direction:Vector2 = Vector2.ZERO) -> Node:
	var target:ball = get_node_or_null(target_path) as ball
	if target==null or target.health<=0 or not target.can_receive_control_from(self): return null
	var exclusions:Array[int] = [get_instance_id()]
	if is_instance_valid(companion): exclusions.append(companion.get_instance_id())
	if is_instance_valid(Master): exclusions.append(Master.get_instance_id())
	return PHYSICAL_AIRBORNE.launch(target,self,height,up_speed,stun,ground_direction.x*up_speed*0.25,{
		"effect_script":AIRBORNE,
		"name":"KnockbackEffect_GolemAirborne",
		"properties":{"owner_team":Team,"owner_id":get_instance_id(),"damage_power":maxf(power,0.0),"excluded_ids":exclusions}
	})

func move(speed:float,delta:float) -> void:
	if not is_combat_runtime_active() or health<=0: return
	var ratio:float = 0.30 if _phase==1 else 0.55 if _phase==2 else 1.0
	super.move(speed*ratio*(rage_speed_multiplier if enraged else 1.0),delta)

func Attack() -> void:
	Attacking = false
	var target:ball = nearest_front_enemy()
	if target!=null: begin_swing(target)

func on_companion_killed() -> void:
	if not is_multiplayer_authority() or health<=0 or enraged: return
	enraged = true
	visual_rage = true
	update_pair_visual()
	mc_play("attack",-1.0)

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if not is_inside_tree(): return
	visual_stage = crack_stage()
	pair_frames = GOLEM_FRAMES[visual_stage]
	if amount>0.0 and visual_stage>crack_stage_for_health(before) and health>0: mc_play("damage",-4.0)
	update_pair_visual()
	if health<=0: notify_golem_death()

func notify_golem_death() -> void:
	if _companion_death_notified: return
	_companion_death_notified = true
	if is_instance_valid(companion) and companion.health>0: companion.on_golem_killed()
func Die() -> void:
	cancel_swing()
	notify_golem_death()
	super.Die()
