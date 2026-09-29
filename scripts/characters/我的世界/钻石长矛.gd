extends "res://scripts/characters/我的世界/mc_item_base.gd"
## Independent from wooden spear: no inherited burst/guard/pass-through state.
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const GEOMETRY = preload("res://classes/map_tile_geometry.gd")
const ECHO = preload("res://scripts/characters/我的世界/diamond_spear/echo.gd")
const FEEDBACK = preload("res://scripts/characters/我的世界/diamond_spear/feedback.gd")
# Unmodified textures extracted from Mojang's verified Java 1.21.11 client JAR.
const TEXTURE:Texture2D = preload("res://Images/characters/我的世界/diamond_spear/diamond_spear_in_hand.png")
const INVENTORY_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/diamond_spear/diamond_spear.png")
# Native hand sprite points upper-left; rotate it without rewriting any pixels.
const NATIVE_ROTATION_OFFSET:float = PI * 0.75
const STAB_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/木矛/attack1.ogg"),
	preload("res://audio/characters/我的世界/木矛/attack2.ogg"),
	preload("res://audio/characters/我的世界/木矛/attack3.ogg"),
]
const SPEAR_HIT_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/木矛/hit1.ogg"),
	preload("res://audio/characters/我的世界/木矛/hit2.ogg"),
	preload("res://audio/characters/我的世界/木矛/hit3.ogg"),
]
const SWEEP_SOUNDS:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/近战/横扫/横扫01.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫02.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫03.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫04.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫05.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫06.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫07.ogg"),
]
const USE_SOUNDS:Array[AudioStream] = [preload("res://audio/characters/我的世界/木矛/use.ogg")]
enum Sfx {STAB, SWEEP, BLINK, HIT, ECHO, READY, WINDUP}
const SFX_NAMES:Array[String] = ["stab","sweep","blink","hit","echo","ready","windup"]
const MC_HIT_AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")

@export_category("钻石长矛 / 重型转向与速度")
@export_range(120.0,1800.0,10.0) var max_move_speed:float = 960.0
@export_range(0.0,4000.0,10.0) var acceleration:float = 180.0
@export_range(0.0,300.0,5.0) var hit_speed_boost:float = 60.0
@export_range(90.0,1440.0,10.0) var turn_degrees_per_second:float = 900.0
@export_range(0.0,2.0,0.05) var turn_speed_loss_per_radian:float = 0.18
@export_range(1.0,5.0,0.1) var speed_damage_max:float = 2.4
@export_category("钻石长矛 / 正面刺击与定点虚影")
@export_range(5.0,40.0,1.0) var thrust_half_angle:float = 25.0
@export_range(5.0,50.0,1.0) var thrust_tip_reach:float = 13.0
@export_range(0.2,0.8,0.01) var thrust_duration:float = 0.38
@export_range(0.0,30.0,0.5) var thrust_distance:float = 14.0
@export_range(0,6,1) var max_echoes:int = 4
@export_range(0.05,1.0,0.05) var echo_damage_ratio:float = 0.32
@export_range(14.0,120.0,1.0) var echo_thrust_distance:float = 42.0
@export_range(42.0,180.0,1.0) var echo_max_thrust_distance:float = 96.0
@export_range(0.02,0.10,0.005) var echo_spawn_interval:float = 0.04
@export_range(0.02,0.15,0.005) var echo_final_interval:float = 0.07
@export_category("钻石长矛 / 虚影满层与穿刺升级")
@export_range(250.0,1500.0,10.0) var echo_full_speed:float = 600.0
@export_range(300.0,1800.0,10.0) var echo_upgrade_speed:float = 800.0
@export_range(0.02,0.15,0.005) var echo_pierce_start_delay:float = 0.04
@export_range(0.06,0.25,0.005) var echo_pierce_duration:float = 0.10
@export_range(0.0,0.08,0.005) var thrust_lookahead_max_time:float = 0.05
@export_range(0.0,0.05,0.001) var impact_visual_hold:float = 0.032
@export_category("钻石长矛 / 半周旋扫")
@export_range(0.15,0.8,0.01) var sweep_duration:float = 0.20
@export_range(0.5,10.0,0.1) var sweep_cooldown:float = 3.2
@export_range(10.0,60.0,1.0) var sweep_radius:float = 30.0
@export_range(0.1,3.0,0.05) var sweep_damage_ratio:float = 0.85
@export_range(0.0,80.0,1.0) var sweep_knockback:float = 24.0
@export_category("钻石长矛 / 闪白瞬移")
@export_range(1.0,25.0,1.0) var blink_half_angle:float = 25.0
@export_range(40.0,300.0,5.0) var blink_range:float = 180.0
@export_range(20.0,100.0,1.0) var blink_min_range:float = 42.0
@export_range(0.04,0.3,0.01) var blink_windup:float = 0.04
@export_range(0.0,30.0,1.0) var blink_clearance:float = 12.0
@export_range(0.0,15.0,0.5) var blink_pullback:float = 3.0
@export_range(0.08,0.3,0.01) var blink_recover_duration:float = 0.14
@export_range(0.1,4.0,0.1) var blink_damage_ratio:float = 1.6

enum Action {IDLE, THRUST, SWEEP, BLINK_WINDUP, BLINK_RECOVER, PIERCE_RECOVER, PIERCE_CHARGE}
var _action:Action = Action.IDLE
var _elapsed:float = 0.0
var _facing:Vector2 = Vector2.RIGHT
var _sweep_move_pending:bool = false # Also covers the final sweep frame after its action ends.
var _base_speed:float = 240.0
var _momentum:float = 240.0
var _attack_wait:float = 0.20
var _sweep_wait:float = 0.40
var _blink_wait:float = 0.65
var _blink_ref:WeakRef
var _action_power:float = 1.0
var _action_hits:Dictionary = {}
var _sweep_start:float = 0.0
var _sweep_sign:float = 1.0
var _trail_step:int = -1
var _visual_shift:float = 0.0
var _pose_scale:float = 1.0
var _image_rest_scale:Vector2 = Vector2.ONE
var _hurtbox_rest_scale:Vector2 = Vector2.ONE
var _render_from_center:Vector2 = Vector2.ZERO
var _render_to_center:Vector2 = Vector2.ZERO
var _render_from_angle:float = 0.0
var _render_to_angle:float = 0.0
var _render_from_shift:float = 0.0
var _render_to_shift:float = 0.0
var _render_from_scale:float = 1.0
var _render_to_scale:float = 1.0
var _render_clock:float = 0.0
var _render_sweep:bool = false
var _last_tip:Vector2
var _blink_axis:Vector2 = Vector2.RIGHT
var _visual_nodes:Array[Node2D] = []
var _pending_echo_anchors:Array[Vector2] = []
# A volley owns immutable world coordinates, never a live target reference.
var _echo_target_position:Vector2 = Vector2.ZERO
var _echo_origin:Vector2 = Vector2.ZERO
var _echo_axis:Vector2 = Vector2.RIGHT
var _echo_volley_count:int = 0
var _echo_volley_piercing:bool = false
var _echo_requires_skill:bool = false
var _echo_skip_action_tick:bool = false
var _pierce_start:Vector2 = Vector2.ZERO
var _pierce_end:Vector2 = Vector2.ZERO
var _pierce_duration:float = 0.08
var _pierce_skill:bool = false
var _thrust_lookahead_delta:float = 0.0
var _feedback_nodes:Array[Node2D] = []
var _impact_hold_remaining:float = 0.0
var _impact_held_angle:float = 0.0
var _impact_held_shift:float = 0.0
var _impact_held_scale:float = 1.0
var total_pierce_thrusts:int = 0
var _echo_spawn_wait:float = 0.0
var _echo_volley_power:float = 0.0
var _pose_send_wait:float = 0.0
var _facing_initialized:bool = false
var last_blink_from:Vector2
var last_blink_to:Vector2
var total_blinks:int = 0
var total_sweeps:int = 0
var total_thrusts:int = 0
var _sfx_rng := RandomNumberGenerator.new()
var _last_sfx_variant:Dictionary = {}
var _speed_sound_armed:bool = true

func _ready() -> void:
	Has_Collision_Damage = false
	motion_blur_enabled = false
	motion_stretch_enabled = false
	AfterImage_Speed = -1.0
	Health_Restore = 0
	if image is Sprite2D: image.texture = TEXTURE
	super._ready()
	_sfx_rng.randomize()
	_image_rest_scale = image.scale
	_hurtbox_rest_scale = self_hurtbox.scale
	add_to_group("MinecraftDiamondSpear")
	_base_speed = maxf(Speed,1.0)
	_momentum = _base_speed
	self_hitbox.set_deferred("monitoring",false)
	self_hitbox.collision_mask = 0
	self_hitbox.collision_layer = 0
	# Private geometry: menu instances must never mutate each other's shapes.
	collision_shape_2d.shape = collision_shape_2d.shape.duplicate()
	(self_hurtbox.get_node("CollisionShape2D") as CollisionShape2D).shape = (self_hurtbox.get_node("CollisionShape2D") as CollisionShape2D).shape.duplicate()
	if direction.length_squared() > 0.001:
		_facing = direction.normalized()
	_apply_pose()

func get_preview_texture() -> Texture2D: return INVENTORY_TEXTURE
func _is_character_ground_shadow_owner() -> bool: return false
func get_projectile_embed_parent() -> Node2D: return image
func current_hit_damage_multiplier() -> float: return speed_multiplier()
func _on_hitbox_on_hit(_hurt:hurtbox) -> void: pass # No duplicate passive body damage.

func _live() -> bool:
	return is_multiplayer_authority() and health > 0 and not is_queued_for_deletion() and is_combat_runtime_active()

func _can_act() -> bool:
	return _live() and not dizziness and not is_damage_output_disabled() and _action == Action.IDLE

func _enemy(value:Variant) -> bool:
	return is_instance_valid(value) and value is ball and not value.is_queued_for_deletion() and TOOLS.is_enemy(self,value)

func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:int = State.Move
	if health <= 0: next = State.Die
	elif not is_combat_runtime_active() or dizziness: next = State.Stand
	return -1 if state == next else next

func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return
	if health <= 0:
		_cancel_action()
		super.tick_physics(state,delta)
		return
	if not is_combat_runtime_active(): return
	if not _facing_initialized:
		_facing_initialized = true
		if direction.length_squared() > 0.001:
			_facing = direction.normalized()
	if dizziness:
		_momentum = _base_speed
		Speed = _momentum
		_cancel_action()
	elif is_damage_output_disabled() or (_action in [Action.THRUST,Action.PIERCE_RECOVER] and not Can_Attack) or (_action in [Action.SWEEP,Action.BLINK_WINDUP,Action.BLINK_RECOVER] and not Can_Skill):
		_cancel_action()
	if not dizziness:
		_thrust_lookahead_delta = clampf(delta,0.0,thrust_lookahead_max_time)
		_attack_wait = maxf(_attack_wait-delta,0.0)
		_sweep_wait = maxf(_sweep_wait-delta,0.0)
		_blink_wait = maxf(_blink_wait-delta,0.0)
		if _action == Action.IDLE:
			if not is_player_controlled() and _can_act():
				if Can_Skill and _sweep_wait <= 0.0 and _side_target() != null:
					_begin_sweep(_side_target())
				elif Can_Attack and _attack_wait <= 0.0 and _front_target() != null:
					Attack()
				elif Can_Skill and _blink_wait <= 0.0:
					_try_blink_target()
		# Acceleration is locomotion, not an idle-only reward. Stabs and sweeps
		# keep building speed; do it before steering so real turn loss still applies.
		if state == State.Move: _accelerate_motion(delta)
		if _action == Action.IDLE:
			_update_steering(delta)
		else:
			_tick_action(delta)
	Speed = _momentum
	_update_speed_audio()
	super.tick_physics(state,delta)
	_apply_pose(false)
	# The visible tip's swept contact catches fast motion without body damage.
	if _action == Action.THRUST and _elapsed <= thrust_duration*0.70:
		var tip:Vector2 = _tip_position()
		damage_segment(_last_tip,tip,2.5,_action_power,_action_hits,0.0)
		_last_tip = tip
	_pose_send_wait -= delta
	if _pose_send_wait <= 0.0:
		_pose_send_wait = 0.05
		if multiplayer.has_multiplayer_peer(): _sync_pose.rpc(_facing,_visual_shift,_pose_scale)

func _movement_direction() -> Vector2:
	# Movement belongs to the common ball controller, never the aiming AI.
	var value:Vector2 = player_control_direction if is_player_controlled() else direction
	return value.normalized() if value.length_squared()>0.001 else Vector2.ZERO

func _accelerate_motion(delta:float) -> void:
	if not _live() or dizziness: return
	if _movement_direction()==Vector2.ZERO: return
	_momentum = minf(max_move_speed,_momentum+acceleration*maxf(delta,0.0))
	Speed = _momentum

func _update_steering(delta:float) -> void:
	var movement:Vector2 = _movement_direction()
	var desired:Vector2 = movement if movement!=Vector2.ZERO else _facing
	if has_player_control_aim(): desired = player_control_aim_direction(desired)
	steer_toward(desired,delta)

func steer_toward(desired:Vector2,delta:float) -> void:
	if desired.length_squared() <= 0.001: return
	var difference:float = _facing.angle_to(desired.normalized())
	var step:float = clampf(difference,-deg_to_rad(turn_degrees_per_second)*delta,deg_to_rad(turn_degrees_per_second)*delta)
	_facing = _facing.rotated(step).normalized()
	if absf(step) > 0.001:
		_momentum = maxf(_base_speed*0.80,_momentum*exp(-absf(step)*turn_speed_loss_per_radian))
	Speed = _momentum
	# Do not assign direction here: turning the weapon must not steer its travel.

func _commit_skill_direction() -> void:
	# A skill turning the spear turns its actual travel, not a lasting image-only offset.
	direction = _facing.normalized()

func move(_speed:float,delta:float) -> void:
	if not is_combat_runtime_active(): return
	# Flash windup and landing recovery no longer suspend ordinary locomotion.
	# Public movement/physics still owns walls and contacts. Only the sweep
	# temporarily owns player travel input; AI travel uses the committed direction.
	var saved_input:Vector2 = player_control_direction
	if _sweep_move_pending and is_player_controlled(): player_control_direction = direction
	super.move(_momentum,delta)
	player_control_direction = saved_input
	_sweep_move_pending = false
	set_character_visual_flip_h(false)

func speed_multiplier(value:float = -1.0) -> float:
	var actual:float = _momentum if value < 0.0 else value
	return lerpf(1.0,speed_damage_max,clampf((actual-_base_speed)/maxf(max_move_speed-_base_speed,1.0),0.0,1.0))

func echo_count(value:float = -1.0) -> int:
	var actual:float = _momentum if value < 0.0 else value
	if max_echoes <= 0 or actual < 150.0: return 0
	if actual < _base_speed: return 1
	var base_count:int = mini(2,max_echoes)
	var progress:float = clampf((actual-_base_speed)/maxf(echo_full_speed-_base_speed,1.0),0.0,1.0)
	return mini(max_echoes,base_count+int(floor(progress*float(max_echoes-base_count)+0.000001)))

func echoes_upgraded(value:float = -1.0) -> bool:
	var actual:float = _momentum if value < 0.0 else value
	return max_echoes>0 and actual>=maxf(echo_upgrade_speed,echo_full_speed+1.0)

func thrust_offset_at(time:float,duration:float,distance:float=-1.0) -> float:
	var u:float = clampf(time/maxf(duration,0.01),0.0,1.0)
	var reach:float = thrust_distance if distance<0.0 else distance
	# Fast forward stroke, zero velocity at extension, then a smooth damped return.
	if u < 0.22: return reach*smoothstep(0.0,1.0,u/0.22)
	var v:float = (u-0.22)/0.78
	return reach*cos(TAU*v)*pow(1.0-smoothstep(0.0,1.0,v),2.0)

func sweep_scale_at(progress:float) -> float:
	# Progress is the swept angle / 180 degrees: 1x -> 2x at 90 -> 1x.
	# Zero slope at the endpoints and peak, with no scale/pivot discontinuity.
	return 1.0+pow(sin(PI*clampf(progress,0.0,1.0)),2.0)

func _front_target() -> ball:
	var nearest:ball
	var best:float = INF
	var tip:Vector2 = _tip_position()
	var ahead:Vector2 = tip
	var movement:Vector2 = _movement_direction()
	# Use the same 0.6 locomotion multiplier as ball.move, not raw stat speed.
	# One upcoming physics step only; this starts an action, never deals predictive damage.
	if movement.dot(_facing)>0.5 and _thrust_lookahead_delta>0.0:
		var move_speed:float = _momentum*(CHARACTER_BASE_MOVE_SPEED_MULTIPLIER if Type==Ball_Type.Ball else 1.0)
		ahead += movement*move_speed*_thrust_lookahead_delta
		var obstacle:Dictionary = get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(tip,ahead,1,[get_rid()]))
		if not obstacle.is_empty(): ahead = obstacle.position
	for raw:Node in TOOLS.targeting_candidates(self):
		if not _enemy(raw) or not raw.is_combat_lockable(): continue
		var target_point:Vector2 = combat_target_position(raw)
		var offset:Vector2 = target_point-global_position
		if offset.length_squared()<0.001 or absf(_facing.angle_to(offset))>deg_to_rad(thrust_half_angle): continue
		var closest:Vector2 = Geometry2D.get_closest_point_to_segment(target_point,tip,ahead)
		var distance:float = closest.distance_to(target_point)
		var reach:float = 140.0 if echoes_upgraded() else thrust_tip_reach
		if distance>reach+_target_extent(raw,_facing): continue
		var sight:Dictionary = get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(tip,target_point,1,[get_rid()]))
		if not sight.is_empty(): continue
		var priority:float = tip.distance_squared_to(target_point)
		if priority<best:
			best = priority
			nearest = raw
	return nearest

func _side_target() -> ball:
	if _front_target() != null: return null
	var nearest:ball
	var best:float = INF
	for raw:Node in TOOLS.targeting_candidates(self):
		if not _enemy(raw) or not raw.is_combat_lockable(): continue
		var offset:Vector2 = combat_target_position(raw)-global_position
		var angle:float = absf(_facing.angle_to(offset))
		if angle<deg_to_rad(45.0) or angle>deg_to_rad(135.0): continue
		var distance:float = offset.length()
		if distance<=sweep_radius+_target_extent(raw,offset.normalized()) and distance<best:
			best = distance
			nearest = raw
	return nearest

func Attack() -> void:
	if not _can_act() or not Can_Attack or _attack_wait>0.0: return
	var target:ball = _front_target()
	if target == null: return
	_action_power = speed_multiplier()
	_attack_wait = maxf(Attack_Cooling,thrust_duration)
	total_thrusts += 1
	# The upgraded normal attack crosses first. It does not borrow/reset the blink skill cooldown.
	if echoes_upgraded():
		var plan:Dictionary = _pierce_plan(target,0.0)
		if not plan.is_empty():
			_perform_pierce(plan,false)
			_echo_skip_action_tick = true # Ignore this action's pre-birth physics delta.
			total_pierce_thrusts += 1
			return
	# A blocked crossing can still make a legal ordinary stab; never grant wall penetration.
	_action = Action.THRUST
	_elapsed = 0.0
	_action_hits.clear()
	_last_tip = _tip_position()
	_emit_audio(Sfx.STAB)
	_queue_echoes(global_position,combat_target_position(target),_facing,_action_power*echo_damage_ratio)
	_tick_echo_queue(0.0)

func _clear_echo_queue() -> void:
	_pending_echo_anchors.clear()
	_echo_target_position = Vector2.ZERO
	_echo_spawn_wait = 0.0
	_echo_volley_count = 0
	_echo_volley_piercing = false
	_echo_requires_skill = false
	_echo_skip_action_tick = false

func _queue_echoes(origin:Vector2,target_point:Vector2,axis:Vector2,power:float,piercing:bool=false,requires_skill:bool=false) -> void:
	_clear_echo_queue()
	_echo_origin = origin
	_echo_target_position = target_point
	_echo_axis = axis
	_echo_volley_power = power
	_echo_volley_piercing = piercing
	_echo_requires_skill = requires_skill
	_echo_volley_count = echo_count()
	_echo_spawn_wait = echo_pierce_start_delay if piercing else 0.0
	for i:int in range(_echo_volley_count):
		if piercing:
			var inline:float = -float(i)*3.0
			_pending_echo_anchors.append(origin+axis*inline)
		else:
			var lateral:float = (6.0+float(i/2)*4.0)*(1.0 if i%2==0 else -1.0)
			_pending_echo_anchors.append(origin+axis.orthogonal()*lateral+axis*(float(i%3)-1.0)*3.0)

func _tick_echo_queue(delta:float) -> void:
	if not is_combat_runtime_active(): return
	var allowed:bool = Can_Skill if _echo_requires_skill else Can_Attack
	if not _live() or dizziness or is_damage_output_disabled() or not allowed or _action not in [Action.THRUST,Action.BLINK_RECOVER,Action.PIERCE_RECOVER,Action.PIERCE_CHARGE]:
		_clear_echo_queue()
		return
	if _pending_echo_anchors.is_empty(): return
	_echo_spawn_wait -= maxf(delta,0.0)
	if _echo_spawn_wait>0.00001: return
	# Only one birth per update, even on a slow frame. No target lookup after the initial snapshot.
	var anchor:Vector2 = _pending_echo_anchors.pop_front()
	var offset:Vector2 = _echo_target_position-anchor
	var aim:Vector2 = offset.normalized() if offset.length_squared()>0.001 else _echo_axis
	var tip_reach:float = 72.0*global_transform.x.length()
	var stroke:float = clampf(offset.length()-tip_reach+8.0,echo_thrust_distance,maxf(echo_max_thrust_distance,echo_thrust_distance))
	var duration:float = thrust_duration+0.06
	if _echo_volley_piercing:
		stroke = minf(offset.length()+_half_length()+blink_clearance,blink_range+_half_length()+blink_clearance+12.0)
		if last_blink_to.is_finite() and _echo_origin.is_finite():
			stroke = maxf(stroke, _echo_origin.distance_to(last_blink_to))
		duration = echo_pierce_duration+0.12
	var accent:bool = _pending_echo_anchors.is_empty() and _echo_volley_count>=3
	_emit_echo(anchor,aim,duration,true,_echo_volley_power,1.0,stroke,_echo_volley_piercing,accent,_echo_requires_skill,_echo_origin)
	# Four echoes: 0 / .04 / .08 / .15, or .04 / .08 / .12 / .19 after a body crossing.
	_echo_spawn_wait = maxf(echo_final_interval,echo_spawn_interval) if _pending_echo_anchors.size()==1 and _echo_volley_count>=3 else echo_spawn_interval

func Skill() -> void:
	if not _can_act() or not Can_Skill: return
	var side:ball = _side_target()
	if side != null and _sweep_wait<=0.0: _begin_sweep(side)
	elif _blink_wait<=0.0: _try_blink_target()

func _begin_sweep(target:ball) -> bool:
	if not _can_act() or not Can_Skill or _sweep_wait>0.0 or not _enemy(target): return false
	_action = Action.SWEEP
	_elapsed = 0.0
	_action_hits.clear()
	_action_power = speed_multiplier()*sweep_damage_ratio
	_sweep_start = _facing.angle()
	_sweep_sign = 1.0 if _facing.cross(combat_target_position(target)-global_position)>=0.0 else -1.0
	_sweep_wait = sweep_cooldown
	_trail_step = -1
	total_sweeps += 1
	_emit_audio(1)
	return true

func _try_blink_target() -> bool:
	var candidates:Array = TOOLS.targeting_candidates(self)
	var options:Array[Dictionary] = []
	for raw:Node in candidates:
		if not _enemy(raw) or not raw.is_combat_lockable(): continue
		var offset:Vector2 = combat_target_position(raw)-global_position
		var distance:float = offset.length()
		if distance<blink_min_range or distance>blink_range: continue
		if absf(_facing.angle_to(offset))>deg_to_rad(minf(blink_half_angle,25.0)): continue
		var axis:Vector2 = offset/distance
		var end:Vector2 = combat_target_position(raw)+axis*(_target_extent(raw,axis)+_half_length()+blink_clearance)
		var score:int = 0
		for other:Node in candidates:
			if not _enemy(other) or not other.is_combat_lockable(): continue
			var point:Vector2 = combat_target_position(other)
			var contact:Vector2 = Geometry2D.get_closest_point_to_segment(point,global_position,end)
			if contact.distance_to(point)<=3.0+_target_extent(other,axis.orthogonal()): score += 1
		options.append({"target":raw,"score":score,"distance":distance})
	# Prefer a valid multi-enemy line; distance breaks ties. Still bounded by the original cone/range.
	options.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return a.score>b.score if a.score!=b.score else a.distance<b.distance)
	for option:Dictionary in options:
		if _begin_blink(option.target): return true
	return false

func _begin_blink(target:ball) -> bool:
	if not _can_act() or not Can_Skill or _blink_wait>0.0 or blink_plan(target).is_empty(): return false
	_blink_ref = weakref(target)
	_action = Action.BLINK_WINDUP
	_elapsed = 0.0
	_action_power = speed_multiplier()*blink_damage_ratio
	_flash_visual()
	_emit_audio(Sfx.WINDUP)
	if multiplayer.has_multiplayer_peer(): _flash_visual.rpc()
	return true

func _tick_action(delta:float) -> void:
	var first_update:bool = is_zero_approx(_elapsed)
	_elapsed += delta
	match _action:
		Action.THRUST:
			# Attack already spawned the first echo this tick. Do not charge a
			# pre-birth frame delta and produce a second one in that same update.
			if not first_update: _tick_echo_queue(delta)
			_visual_shift = thrust_offset_at(_elapsed,thrust_duration)
			if _elapsed>=thrust_duration: _finish_action()
		Action.SWEEP:
			var u:float = clampf(_elapsed/maxf(sweep_duration,0.01),0.0,1.0)
			var progress:float = smoothstep(0.0,1.0,u)
			var prior:float = smoothstep(0.0,1.0,clampf((_elapsed-delta)/maxf(sweep_duration,0.01),0.0,1.0))
			var angle:float = _sweep_start+_sweep_sign*PI*progress
			var steps:int = maxi(1,int(ceil(PI*absf(progress-prior)/deg_to_rad(10.0))))
			for i:int in range(1,steps+1):
				var sample_progress:float = lerpf(prior,progress,float(i)/steps)
				var axis:Vector2 = Vector2.RIGHT.rotated(_sweep_start+_sweep_sign*PI*sample_progress)
				var size_factor:float = sweep_scale_at(sample_progress)
				var reach:float = _half_length()*size_factor
				damage_segment(global_position-axis*reach,global_position+axis*reach,3.0*size_factor,_action_power,_action_hits,sweep_knockback)
			_facing = Vector2.RIGHT.rotated(angle)
			_pose_scale = sweep_scale_at(progress)
			_commit_skill_direction()
			_sweep_move_pending = true
			var trail:int = int(u*9.0)
			if trail!=_trail_step:
				_trail_step = trail
				_emit_echo(global_position,_facing,0.24,false,0.0,_pose_scale)
			if u>=1.0:
				_finish_action()
		Action.BLINK_WINDUP:
			if _elapsed>=blink_windup: _execute_blink()
		Action.PIERCE_CHARGE:
			if not first_update: _tick_echo_queue(delta)
			var u:float = clampf(_elapsed/maxf(_pierce_duration,0.01),0.0,1.0)
			var progress:float = smoothstep(0.0,1.0,u)
			var cur_pos:Vector2 = _pierce_start.lerp(_pierce_end,progress)
			global_position = cur_pos
			_apply_pose()
			_emit_echo(cur_pos,_blink_axis,0.18,false,0.0)
			damage_segment(_pierce_start,cur_pos,3.0,_action_power,_action_hits,0.0,Vector2.INF,true)
			if u>=1.0:
				global_position = _pierce_end
				_apply_pose()
				_action = Action.BLINK_RECOVER if _pierce_skill else Action.PIERCE_RECOVER
				_elapsed = 0.0
		Action.BLINK_RECOVER,Action.PIERCE_RECOVER:
			# The body keeps moving. Finish the delayed volley without turning its aim into homing.
			if _echo_skip_action_tick: _echo_skip_action_tick = false
			else: _tick_echo_queue(delta)
			_update_steering(delta)
			var u:float = clampf(_elapsed/maxf(blink_recover_duration,0.01),0.0,1.0)
			_visual_shift = -blink_pullback*sin(TAU*u)*pow(1.0-u,2.0)
			if u>=1.0 and _pending_echo_anchors.is_empty(): _finish_action()

func _execute_blink() -> void:
	var target:Variant = _blink_ref.get_ref() if _blink_ref!=null else null
	var plan:Dictionary = blink_plan(target)
	if plan.is_empty():
		_blink_wait = 0.20
		_finish_action()
		return
	_perform_pierce(plan,true)

func _perform_pierce(plan:Dictionary,skill:bool) -> void:
	var start:Vector2 = global_position
	var end:Vector2 = plan["end"]
	# Snapshot before damage callbacks can move, kill or free the target.
	var target_point:Vector2 = plan["target_position"]
	var upgraded:bool = echoes_upgraded()
	var echo_power:float = speed_multiplier()*echo_damage_ratio
	_blink_axis = plan["axis"]
	_facing = _blink_axis
	_commit_skill_direction()
	_action_hits.clear()
	_clear_echo_queue()
	_pierce_start = start
	_pierce_end = end
	_pierce_skill = skill
	_pierce_duration = clampf(start.distance_to(end)/1400.0,0.05,0.08)
	_elapsed = 0.0
	_visual_shift = 0.0
	last_blink_from = start
	last_blink_to = end
	if skill:
		_blink_wait = maxf(Skill_Cooling,0.2)
		total_blinks += 1
		global_position = end
		_apply_pose()
		_action = Action.BLINK_RECOVER
	else:
		_action = Action.PIERCE_CHARGE
	# A few silhouettes plus a sharp line, not seventeen overlapping full-size spears.
	for i:int in range(4):
		_emit_echo(start.lerp(end,float(i)/3.0),_blink_axis,0.18,false,0.0)
	_play_pierce_feedback(start,end)
	if multiplayer.has_multiplayer_peer(): _play_pierce_feedback.rpc(start,end)
	_emit_audio(Sfx.BLINK if skill else Sfx.STAB)
	damage_segment(start,end,3.0,_action_power,_action_hits,0.0,Vector2.INF,true)
	if upgraded and _live() and not dizziness and not is_damage_output_disabled():
		_queue_echoes(start,target_point,_blink_axis,echo_power,true,skill)

func blink_plan(target:Variant) -> Dictionary:
	return _pierce_plan(target,blink_min_range)

func _pierce_plan(target:Variant,minimum_range:float) -> Dictionary:
	if not _enemy(target) or not target.is_combat_lockable(): return {}
	var target_point:Vector2 = combat_target_position(target)
	var offset:Vector2 = target_point-global_position
	var distance:float = offset.length()
	if distance<=0.001 or distance<minimum_range or distance>blink_range: return {}
	if absf(_facing.angle_to(offset))>deg_to_rad(minf(blink_half_angle,25.0))+0.00001: return {}
	var axis:Vector2 = offset/distance
	var gap:float = _target_extent(target,axis)+_half_length()+blink_clearance+blink_pullback*1.4
	var end:Vector2 = target_point+axis*gap
	# No rear vacancy test and no character-body mask. Terrain/floor path safety remains mandatory.
	if not _path_clear(global_position,end,axis): return {}
	return {"end":end,"axis":axis,"target_position":target_point}

func _floor_regions() -> Array:
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("return_map_world_rect"):
		var groups:Variant = world.get("map_group")
		var key:Variant = world.get("now_choose_map")
		if groups is Dictionary and groups.has(key):
			var map_node:Node = groups[key]
			if map_node is TileMapLayer: return GEOMETRY.from_layer(map_node)["regions"]
			var rect:Rect2 = world.call("return_map_world_rect",map_node)
			return [rect] if rect.has_area() else []
	return []

func _on_floor(point:Vector2,axis:Vector2,regions:Array) -> bool:
	if regions.is_empty(): return true # Standalone test/training arenas without painted maps.
	var side:Vector2 = axis.orthogonal()*(_half_width()+3.0)
	var forward:Vector2 = axis*(_half_length()+3.0)
	for p:Vector2 in [point,point+forward+side,point+forward-side,point-forward+side,point-forward-side]:
		if not GEOMETRY.contains(regions,p): return false
	return true

func _query_shape(point:Vector2,axis:Vector2,mask:int) -> PhysicsShapeQueryParameters2D:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_half_length()*2.0+6.0,_half_width()*2.0+6.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(axis.angle(),point)
	query.collision_mask = mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return query

func _body_clear(point:Vector2,axis:Vector2,mask:int) -> bool:
	if not _on_floor(point,axis,_floor_regions()): return false
	return get_world_2d().direct_space_state.intersect_shape(_query_shape(point,axis,mask),1).is_empty()

func _path_clear(start:Vector2,end:Vector2,axis:Vector2) -> bool:
	var query:PhysicsShapeQueryParameters2D = _query_shape(start,axis,1)
	query.motion = end-start
	var space:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if not space.intersect_shape(_query_shape(start,axis,1),1).is_empty(): return false
	var cast:PackedFloat32Array = space.cast_motion(query)
	if cast.size()<2 or cast[0]<0.9999: return false
	var regions:Array = _floor_regions()
	var steps:int = maxi(1,int(ceil(start.distance_to(end)/4.0)))
	for i:int in range(steps+1):
		if not _on_floor(start.lerp(end,float(i)/steps),axis,regions): return false
	return true

func damage_segment(start:Vector2,end:Vector2,width:float,multiplier:float,hits:Dictionary,knockback:float,source_anchor:Vector2=Vector2.INF,accent:bool=false) -> void:
	if not _live() or dizziness or is_damage_output_disabled(): return
	for contact:Dictionary in preload("res://classes/weapon_tip_sweep.gd").contacts(self,start,end,width,hits,source_anchor):
		var raw:ball = contact.target
		var point:Vector2 = contact.point
		hits[raw.get_instance_id()] = true
		var health_before:float = maxf(float(raw.health),0.0)
		var sound_point:Vector2 = ball.body_point(raw,global_position)
		var accepted:bool = raw.receive_spatial_damage(attack_damage(multiplier),{"point":point,"source":self})
		var health_after:float = maxf(float(raw.health),0.0) if is_instance_valid(raw) else 0.0
		var actual:float = maxf(health_before-health_after,0.0)
		if accepted or actual>0.0:
			_momentum = minf(max_move_speed,_momentum+hit_speed_boost)
			Speed = _momentum
		if actual>0.0:
			_emit_audio(Sfx.HIT,sound_point,HIT_GAIN.damage_gain(actual),accent)
			if accent:
				var impact_axis:Vector2 = (end-start).normalized() if start.distance_squared_to(end)>0.001 else _facing
				_play_impact_feedback(point,impact_axis)
				if multiplayer.has_multiplayer_peer(): _play_impact_feedback.rpc(point,impact_axis)
			_play_damage_impact(sound_point,actual)
			if multiplayer.has_multiplayer_peer(): _play_damage_impact.rpc(sound_point,actual)
		if accepted and knockback>0.0 and is_instance_valid(raw) and raw.health>0:
			var push:Vector2 = (ball.body_point(raw,global_position)-global_position).normalized()
			raw.apply_knockback(push,knockback,380.0,0.0,0.0,{"source":self})

func _target_extent(target:ball,axis:Vector2) -> float:
	var extent:float = 2.0
	if target.self_hurtbox == null: return extent
	for child:Node in target.self_hurtbox.get_children():
		if child is CollisionShape2D and child.shape!=null and not child.disabled:
			var rect:Rect2 = child.shape.get_rect()
			for corner:Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
				extent = maxf(extent,absf((child.to_global(corner)-combat_target_position(target)).dot(axis)))
	return extent

func _half_length() -> float: return 80.0*global_transform.x.length()
func _half_width() -> float: return 15.0*global_transform.y.length()
func _tip_position() -> Vector2:
	# Damage must use the current simulation pose, never the interpolated image.
	return global_position+_facing*(_visual_shift+72.0*global_transform.x.length()*_pose_scale)

func _apply_pose(snap:bool=true) -> void:
	set_character_visual_flip_h(false)
	var angle:float = _facing.angle()-global_rotation
	var local_axis:Vector2 = Vector2.RIGHT.rotated(angle)
	var offset:Vector2 = local_axis*_visual_shift/maxf(global_transform.x.length(),0.001)
	self_hurtbox.rotation = angle
	self_hurtbox.scale = _hurtbox_rest_scale*_pose_scale
	self_hurtbox.position = offset
	collision_shape_2d.rotation = angle
	# One physics sample of interpolation, NOT a lagging exponential follower.
	# Interpolate translation too: a fast-moving pivot must not step at 60 Hz
	# while only its rotation looks smooth on a high-refresh display.
	if global_position.distance_to(_render_to_center)>64.0: snap = true
	_render_from_center = _render_to_center
	_render_from_angle = _render_to_angle
	_render_from_shift = _render_to_shift
	_render_from_scale = _render_to_scale
	_render_to_center = global_position
	_render_to_angle = _facing.angle()
	_render_to_shift = _visual_shift
	_render_to_scale = _pose_scale
	_render_sweep = _action==Action.SWEEP
	if snap:
		_render_from_center = _render_to_center
		_render_from_angle = _render_to_angle
		_render_from_shift = _render_to_shift
		_render_from_scale = _render_to_scale
	_render_clock = 0.0
	_render_pose(1.0)
	# All pose transforms share the moving body center. Weapon/hurt reach scales,
	# but the locomotion collider does not inflate into walls or push the pivot.

func _process(delta:float) -> void:
	if not is_node_ready() or health<=0 or not is_combat_runtime_active(): return
	# Spawners may position a node after _ready(), before its first physics tick.
	if global_position.distance_to(_render_to_center)>64.0: _apply_pose()
	_render_clock += delta
	_impact_hold_remaining = maxf(_impact_hold_remaining-delta,0.0)
	var fraction:float = Engine.get_physics_interpolation_fraction() if is_multiplayer_authority() else clampf(_render_clock/0.05,0.0,1.0)
	_render_pose(fraction)

func _render_pose(fraction:float) -> void:
	var alpha:float = clampf(fraction,0.0,1.0)
	var angle:float = lerp_angle(_render_from_angle,_render_to_angle,alpha)
	var center:Vector2 = _render_from_center.lerp(_render_to_center,alpha)
	var shift:float = lerpf(_render_from_shift,_render_to_shift,alpha)
	var size_factor:float = lerpf(_render_from_scale,_render_to_scale,alpha)
	if _render_sweep:
		# Re-evaluate the curve at the rendered angle, so an interpolated 90-degree
		# midpoint still reaches exactly 2x even between coarse physics samples.
		size_factor = sweep_scale_at(absf(wrapf(angle-_sweep_start,-PI,PI))/PI)
	# Local pose hold only: center keeps following locomotion; no simulation, collision or audio clock pause.
	if _impact_hold_remaining>0.0:
		angle = _impact_held_angle
		shift = _impact_held_shift
		size_factor = _impact_held_scale
	image.global_rotation = angle+NATIVE_ROTATION_OFFSET
	image.scale = _image_rest_scale*size_factor
	image.global_position = center+Vector2.RIGHT.rotated(angle)*shift

func _finish_action() -> void:
	_clear_echo_queue()
	_action = Action.IDLE
	_elapsed = 0.0
	_visual_shift = 0.0
	_pose_scale = 1.0
	_blink_ref = null
	Attacking = false
	Using_Skill = false

func _cancel_action() -> void:
	_impact_hold_remaining = 0.0
	_thrust_lookahead_delta = 0.0
	_sweep_move_pending = false
	_finish_action()
	_action_hits.clear()
	for i:int in range(_visual_nodes.size()-1,-1,-1):
		if not is_instance_valid(_visual_nodes[i]):
			_visual_nodes.remove_at(i)
			continue
		var node:Node2D = _visual_nodes[i]
		if node.attack_echo: node.queue_free()
	_apply_pose()

func _emit_echo(point:Vector2,axis:Vector2,duration:float,damaging:bool,power:float,size_factor:float=1.0,stroke:float=-1.0,piercing:bool=false,accent:bool=false,requires_skill:bool=false,origin:Vector2=Vector2.INF) -> void:
	if damaging:
		if not _body_clear(point,axis,1): return
		var source_point:Vector2 = global_position if not origin.is_finite() else origin
		var ray := PhysicsRayQueryParameters2D.create(source_point,point,1,[get_rid()])
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return
	var distance:float = echo_thrust_distance if stroke<0.0 else stroke
	_spawn_echo(point,axis,duration,damaging,power,size_factor,distance,piercing,accent,requires_skill)
	if damaging: _emit_audio(Sfx.ECHO,point,0.0,accent)
	if multiplayer.has_multiplayer_peer(): _spawn_echo.rpc(point,axis,duration,damaging,power,size_factor,distance,piercing,accent,requires_skill)

@rpc("authority","call_remote","reliable")
func _spawn_echo(point:Vector2,axis:Vector2,duration:float,damaging:bool,power:float,size_factor:float=1.0,stroke:float=-1.0,piercing:bool=false,accent:bool=false,requires_skill:bool=false) -> void:
	for i:int in range(_visual_nodes.size()-1,-1,-1):
		if not is_instance_valid(_visual_nodes[i]): _visual_nodes.remove_at(i)
	if _visual_nodes.size()>=48:
		var oldest:Node2D = _visual_nodes.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	var node:Node2D = ECHO.new()
	node.caster = self
	node.anchor = point
	node.axis = axis
	node.visual_scale = _image_rest_scale*(image.get_parent() as Node2D).global_scale*size_factor
	node.tip_distance = 72.0*global_transform.x.length()*size_factor
	node.stroke_duration = echo_pierce_duration if piercing else thrust_duration
	node.stroke_distance = echo_thrust_distance if stroke<0.0 else stroke
	node.lifetime = duration
	node.attack_echo = damaging
	node.piercing = piercing
	node.accent = accent
	node.requires_skill = requires_skill
	node.multiplier = power
	node.tint = Color(0.72,1.0,1.0,0.82) if accent else Color(0.40,0.95,1.0,0.62 if damaging else 0.28)
	add_child(node)
	_visual_nodes.append(node)

@rpc("authority","call_remote","unreliable_ordered")
func _sync_pose(facing:Vector2,shift:float,size_factor:float=1.0) -> void:
	_facing = facing
	_visual_shift = shift
	_pose_scale = size_factor
	_apply_pose(false)

@rpc("authority","call_remote","reliable")
func _flash_visual() -> void: hit_white_visual_only()

func _sfx_pool(kind:int) -> Array[AudioStream]:
	match kind:
		Sfx.STAB,Sfx.BLINK,Sfx.ECHO: return STAB_SOUNDS
		Sfx.SWEEP: return SWEEP_SOUNDS
		Sfx.HIT: return SPEAR_HIT_SOUNDS
		Sfx.READY,Sfx.WINDUP: return USE_SOUNDS
	return []

func _add_feedback(node:Node2D) -> void:
	for i:int in range(_feedback_nodes.size()-1,-1,-1):
		if not is_instance_valid(_feedback_nodes[i]): _feedback_nodes.remove_at(i)
	if _feedback_nodes.size()>=12:
		var oldest:Node2D = _feedback_nodes.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	node.caster = self
	add_child(node)
	_feedback_nodes.append(node)

@rpc("authority","call_remote","reliable")
func _play_pierce_feedback(start:Vector2,end:Vector2) -> void:
	if not is_inside_tree() or not is_combat_runtime_active(): return
	var node:Node2D = FEEDBACK.new()
	node.kind = 0
	node.origin = start
	node.endpoint = end
	node.lifetime = 0.15
	_add_feedback(node)

@rpc("authority","call_remote","reliable")
func _play_impact_feedback(point:Vector2,axis:Vector2) -> void:
	if not is_inside_tree() or not is_combat_runtime_active(): return
	var node:Node2D = FEEDBACK.new()
	node.kind = 1
	node.origin = point
	node.endpoint = point+axis
	node.lifetime = 0.16
	node.hold = impact_visual_hold
	_add_feedback(node)
	# Coalesce same-crossing impacts. Later echoes do not accumulate a global/time-scale freeze.
	if _impact_hold_remaining<=0.0:
		_impact_held_angle = image.global_rotation-NATIVE_ROTATION_OFFSET
		_impact_held_shift = _visual_shift
		_impact_held_scale = _pose_scale
	_impact_hold_remaining = maxf(_impact_hold_remaining,impact_visual_hold)

func _update_speed_audio() -> void:
	if not _live() or dizziness: return
	# Hysteresis: one cue when entering high speed, not a use sound every tick.
	var threshold:float = maxf(echo_upgrade_speed,echo_full_speed+1.0)
	if _momentum<=threshold*0.85: _speed_sound_armed = true
	if _speed_sound_armed and echoes_upgraded() and _movement_direction()!=Vector2.ZERO:
		_speed_sound_armed = false
		_emit_audio(Sfx.READY)

func _emit_audio(kind:int,point:Vector2=Vector2.INF,gain:float=0.0,accent:bool=false) -> void:
	if not _live() or dizziness: return
	var pool:Array[AudioStream] = _sfx_pool(kind)
	if pool.is_empty(): return
	var index:int = _sfx_rng.randi_range(0,pool.size()-1)
	var last:int = int(_last_sfx_variant.get(kind,-1))
	if pool.size()>1 and last>=0:
		index = _sfx_rng.randi_range(0,pool.size()-2)
		if index>=last: index += 1
	_last_sfx_variant[kind] = index
	var pitch:float = _sfx_rng.randf_range(0.965,0.98) if accent else _sfx_rng.randf_range(0.995,1.035)
	var origin:Vector2 = point if point.is_finite() else global_position
	_play_audio(kind,index,origin,pitch,gain)
	# The authority chooses the variant and pitch once for every listener.
	if multiplayer.has_multiplayer_peer(): _play_audio.rpc(kind,index,origin,pitch,gain)

@rpc("authority","call_remote","reliable")
func _play_audio(kind:int,index:int,point:Vector2,pitch:float,gain:float=0.0) -> void:
	if not is_inside_tree() or not is_combat_runtime_active(): return
	var pool:Array[AudioStream] = _sfx_pool(kind)
	if index<0 or index>=pool.size(): return
	var scene:Node = get_tree().current_scene
	if scene==null: return
	# Bounded weapon-only voices; do not steal the separate hurt/crit channels.
	var active:Array[Node] = get_tree().get_nodes_in_group("DiamondSpearSFX")
	if active.size()>=48:
		var oldest:AudioStreamPlayer2D = active[0] as AudioStreamPlayer2D
		oldest.stop()
		oldest.remove_from_group("DiamondSpearSFX")
		oldest.queue_free()
	var player := AudioStreamPlayer2D.new()
	player.stream = pool[index]
	player.volume_db = clampf(gain,0.0,6.0)
	player.pitch_scale = clampf(pitch,0.965,1.035)
	player.max_distance = 1450.0
	player.attenuation = 0.70
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
	scene.add_child(player)
	player.global_position = point
	player.add_to_group("DiamondSpearSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("diamond_spear_source",get_instance_id())
	player.set_meta("diamond_spear_sfx_event",SFX_NAMES[kind])
	player.set_meta("diamond_spear_sfx_variant",index)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()

@rpc("authority","call_remote","reliable")
func _play_damage_impact(point:Vector2,actual:float) -> void:
	var event:String = HIT_GAIN.damage_event(actual)
	if event.is_empty(): return
	# Separate hurt/crit feedback is retained alongside the native spear hit.
	# Both start at the default level and grow with actual HP damage.
	var player:AudioStreamPlayer2D = MC_HIT_AUDIO.play(self,event,point,HIT_GAIN.damage_gain(actual),false,true,true,true)
	if is_instance_valid(player): player.set_meta("mc_damage_source",get_instance_id())

func get_debug_detection_regions() -> Array[Dictionary]:
	return [{"center":_tip_position(),"radius":thrust_tip_reach,"color":Color(0.2,0.9,1.0,0.55)}]
