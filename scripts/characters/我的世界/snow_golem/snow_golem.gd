extends "res://scripts/characters/我的世界/new5/base.gd"
const FIELD = preload("res://scripts/characters/我的世界/snow_golem/snow_field.gd")
const RULES = preload("res://scripts/characters/我的世界/snow_golem/rules.gd")
const SNOW_AUDIO = preload("res://scripts/characters/我的世界/snow_golem/audio.gd")
const SHOT:PackedScene = preload("res://scenes/shooter/我的世界/雪球.tscn")
const PUMPKIN:Array[Texture2D] = [preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_00.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_01.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_02.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_03.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_04.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_05.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_06.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_07.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_08.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_09.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_10.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_11.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_12.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_13.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_14.png"),preload("res://Images/characters/我的世界/snow_golem/faces/pumpkin_15.png")]
const BARE:Array[Texture2D] = [preload("res://Images/characters/我的世界/snow_golem/faces/bare_00.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_01.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_02.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_03.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_04.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_05.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_06.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_07.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_08.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_09.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_10.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_11.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_12.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_13.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_14.png"),preload("res://Images/characters/我的世界/snow_golem/faces/bare_15.png")]
const HEAD_FRAMES:Array[Texture2D] = [preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_00.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_01.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_02.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_03.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_04.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_05.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_06.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_07.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_08.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_09.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_10.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_11.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_12.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_13.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_14.png"),preload("res://Images/characters/我的世界/snow_golem/heads/pumpkin_15.png")]
const HEAD_CENTERS:Array[Vector2] = [Vector2(0.0,-29.5),Vector2(0.0,-30.0),Vector2(0.0,-30.0),Vector2(0.0,-29.5),Vector2(0.0,-29.5),Vector2(0.0,-29.5),Vector2(0.0,-30.0),Vector2(0.0,-30.0),Vector2(0.0,-29.5),Vector2(0.0,-30.0),Vector2(0.0,-30.0),Vector2(0.0,-29.5),Vector2(0.0,-29.5),Vector2(0.0,-29.5),Vector2(0.0,-30.0),Vector2(0.0,-30.0)]
const DIRECTION_COUNT:int = 16
const BLOCK_FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
@export var attack_range:float = 260.0
@export var snowball_speed:float = 260.0
@export var shot_cold:float = 22.0
@export var snow_cold:float = 8.0
@export var freeze_duration:float = 1.4
@export var snow_tick_interval:float = 0.5
@export var snow_damage_multiplier:float = 0.33333334
@export var snowball_knockback:float = 8.0
@export_range(0.0,1.0,0.05) var aim_hold_duration:float = 0.25
@export_category("雪傀儡 / 雪球连射")
@export_range(0.0,1.0,0.01) var burst_probability:float = 0.10
@export_range(1,64,1) var burst_shots:int = 20
@export var burst_interval_min:float = 0.05
@export var burst_interval_max:float = 0.10
@export var burst_spread_degrees:float = 15.0
var family:String = ""
var has_pumpkin:bool = true
var head_break_count:int = 0
var force_next_burst:bool = false
var attacks_started:int = 0
var bursts_started:int = 0
var _burst_remaining:int = 0
var _burst_wait:float = 0.0
var _burst_point:Vector2 = Vector2.ZERO
var _burst_target:WeakRef
var _burst_manual:bool = false
@export_category("雪傀儡 / 移动与动作声音")
# 按基础速度行走时的脚步间隔；实际间隔随当前移速缩放（越快越密、越慢越稀，可与上一声重叠）。
@export var footstep_base_interval:float = 0.32
# 撞墙脚步的最短间隔（贴墙推挤时不会每帧响）。
@export var footstep_min_interval:float = 0.28
@export var footstep_volume_db:float = -3.0
@export var shoot_volume_db:float = 0.0
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
var _footstep_cadence = FOOTSTEP.new()
var _footstep_wait:float = 0.0
var _wall_step_due:bool = false
var _wall_contact_this_step:bool = false
var _walking_right:bool = false
var _step_audio:Dictionary = {}
var _step_voices:Array[Dictionary] = [] # 所有还在响的脚步（脚步可以重叠）
var _shoot_audio:Dictionary = {} # Latest launch remains available to action observers.
var _shoot_voices:Array[Dictionary] = [] # One transient for every actual projectile.
var _break_audio:Dictionary = {}
var _sound_serial:int = 0
var _last_sound_serial:int = 0
var _last_break_fx_serial:int = 0
var _state_version:int = 0
var shots_fired:int = 0
var _field:Node2D
var _shot_left:float = 0.0
var _last_cell:Vector2i
var _last_point:Vector2
var _trail_started:bool = false
var _trail_grid_revision:int = -1
var _aim:Vector2 = Vector2.LEFT
var _aim_hold_left:float = 0.0
var _visual_heading:Vector2 = Vector2.LEFT
var _aim_pose:int = 1
var _shot_serial:int = 0

func _ready() -> void:
	# Full native heading views own orientation; the shared mover must not mirror
	# a pre-oriented frame again (including its independent shader flip).
	dir_left = false
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Dead_Audio = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	cold_effect_ratio = 0.0 # Snow Golem retains cold damage/status immunity.
	motion_blur_enabled = false
	motion_stretch_enabled = false
	AfterImage_Speed = 0.0
	super._ready()
	image.z_as_relative = true
	image.z_index = 0
	add_to_group("MCSnowGolem")
	if family.is_empty(): family = str(name)
	set_meta("mc_snow_family",family)
	_field = FIELD.ensure(self)
	_shot_left = maxf(Attack_Cooling,0.1)
	_last_point = global_position
	wall_contact_impact.connect(_on_snow_wall_contact)
	call_deferred("_initialize_identity")
	visual_mob()

func _request_initial_state() -> void:
	# Pumpkin removal and a guaranteed next attack are persistent state, not an
	# expendable animation sample. Use reliable initial delivery for late actors.
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority(): _request_snow_state.rpc_id(get_multiplayer_authority())

@rpc("any_peer","call_remote","reliable")
func _request_snow_state() -> void:
	if is_multiplayer_authority(): _receive_snow_state.rpc_id(multiplayer.get_remote_sender_id(),network_visual_state())

@rpc("authority","call_remote","reliable")
func _receive_snow_state(data:Dictionary) -> void:
	accept_visual(data)
	visual_mob()

func _sync_snow_state() -> void:
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _receive_snow_state.rpc(network_visual_state())

func _initialize_identity() -> void:
	if not is_multiplayer_authority(): return
	if has_meta("battle_continuation_victory_side_key"): return
	var world:Node = get_tree().current_scene
	var victory:String = "team:"+Team if not Team.is_empty() else "solo_instance:"+str(get_instance_id())
	var presentation:String = "team:"+Team if not Team.is_empty() else "solo:"+str(get_instance_id())
	if world.has_method("_victory_side_key_for_character"):
		victory = world.call("_victory_side_key_for_character",self)
		presentation = world.call("return_ball_side_key",self)
	set_meta("battle_continuation_victory_side_key",victory)
	set_meta("battle_continuation_presentation_side_key",presentation)
	set_meta("victory_side_key",victory)

func step_mob(delta:float) -> void:
	if not active() or delta<=0.0: return
	_shot_left = maxf(0.0,_shot_left-delta)
	_aim_hold_left = maxf(0.0,_aim_hold_left-delta)
	if dizziness or is_damage_output_disabled():
		_cancel_burst()
		_last_point = global_position
		_last_cell = _field.snow_cell_at(global_position) if is_instance_valid(_field) else FIELD.cell_at(global_position)
		return
	lay_trail()
	if not Can_Attack:
		_cancel_burst()
		return
	if _burst_remaining>0:
		_burst_wait -= delta
		# At most the remaining bounded volley: large frames catch up without
		# rerolling chance, recursive volleys, or an unbounded timer loop.
		while _burst_remaining>0 and _burst_wait<=0.0:
			if not _emit_snowball(_burst_aim_point(),true):
				_cancel_burst()
				break
			_burst_remaining -= 1
			if _burst_remaining>0: _burst_wait += _random_burst_interval()
		if _burst_remaining==0: _sync_snow_state()
		return
	# An already-started volley may finish under manual control; AI may not
	# start a new attack for the player. LMB still uses this exact same roll.
	if is_player_controlled() or _shot_left>0.0: return
	var target:ball = nearest_snow_enemy()
	if is_instance_valid(target): fire_at(ball.body_point(target,global_position),target)

func _cancel_burst() -> void:
	var changed:bool = _burst_remaining>0
	_burst_remaining = 0
	_burst_wait = 0.0
	_burst_target = null
	if changed:
		_state_version += 1
		_sync_snow_state()
	# A half-health guarantee armed DURING a volley belongs to the next attack.

func _random_burst_interval() -> float:
	var minimum:float = maxf(burst_interval_min,0.01)
	return rng.randf_range(minimum,maxf(burst_interval_max,minimum))

func _burst_aim_point() -> Vector2:
	if _burst_manual:
		if has_player_control_aim(): _burst_point = player_control_aim_world_position()
	elif _burst_target!=null:
		var target:Variant = _burst_target.get_ref()
		if is_instance_valid(target) and RULES.enemy(self,target) and target.is_combat_lockable(): _burst_point = ball.body_point(target,global_position)
	# Losing a target does not invent a summon or reroll the attack. Finish the
	# committed volley toward its last position; actual bullets still hit walls.
	return _burst_point

func nearest_snow_enemy() -> ball:
	var result:ball
	var best:float = attack_range*attack_range
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not RULES.enemy(self,node) or not node.is_combat_lockable(): continue
		var distance:float = global_position.distance_squared_to(ball.body_point(node,global_position))
		if distance <= best and U.line_clear(self,global_position,ball.body_point(node,global_position)):
			best = distance
			result = node as ball
	return result

func lay_trail() -> void:
	if not active() or dizziness or is_damage_output_disabled(): return
	if not is_instance_valid(_field): _field = FIELD.ensure(self)
	_field.refresh_grid()
	if _trail_grid_revision!=_field.grid_revision:
		_trail_grid_revision = _field.grid_revision
		_trail_started = false
	var point:Vector2 = global_position
	if not _trail_started:
		_trail_started = true
		_last_cell = _field.snow_cell_at(point)
		_last_point = point
		_field.deposit(self,_last_cell,false)
		return
	var distance:float = _last_point.distance_to(point)
	# Never paint a teleport line or refresh the same occupied cell every frame.
	if distance > FIELD.LEGACY_ENV_CELL*8.0: _last_point = point
	var span:float = maxf(minf(_field.grid_size.x,_field.grid_size.y)*0.3,0.1)
	var steps:int = clampi(int(ceil(_last_point.distance_to(point)/span)),1,128)
	for index:int in range(1,steps+1):
		var cell:Vector2i = _field.snow_cell_at(_last_point.lerp(point,float(index)/float(steps)))
		if cell == _last_cell: continue
		_last_cell = cell
		_field.deposit(self,cell,false)
	_last_point = point

func fire_at(point:Vector2,target:ball = null) -> bool:
	if not can_act() or _burst_remaining>0 or _shot_left>0.0 or not point.is_finite() or global_position.distance_to(point)>attack_range: return false
	if not U.line_clear(self,global_position,point): return false
	var burst:bool = force_next_burst or rng.randf()<clampf(burst_probability,0.0,1.0)
	_burst_point = point
	_burst_manual = is_player_controlled()
	_burst_target = weakref(target) if is_instance_valid(target) else null
	if not _emit_snowball(point,burst): return false
	attacks_started += 1
	_shot_left = maxf(Attack_Cooling,0.1)
	if burst:
		bursts_started += 1
		force_next_burst = false # Only a real first emission consumes the guarantee.
		_burst_remaining = clampi(burst_shots,1,64)-1
		_burst_wait = _random_burst_interval() if _burst_remaining>0 else 0.0
	_sync_snow_state()
	return true

func _battle_parent() -> Node:
	return _field.get_parent() if is_instance_valid(_field) else get_parent()

func _emit_snowball(point:Vector2,spread:bool) -> bool:
	if not can_act() or not is_instance_valid(_battle_parent()): return false
	var aim:Vector2 = global_position.direction_to(point)
	if aim.is_zero_approx(): aim = direction.normalized()
	if aim.is_zero_approx(): aim = Vector2.RIGHT
	_aim = aim
	_aim_hold_left = maxf(aim_hold_duration,0.0)
	visual_mob()
	var heading:Vector2 = aim.rotated(deg_to_rad(rng.randf_range(-absf(burst_spread_degrees),absf(burst_spread_degrees)))) if spread else aim
	_shot_serial += 1
	shots_fired += 1
	_state_version += 1
	var shot_name:String = str(name)+"_Snowball_"+str(_shot_serial)
	var damage:float = attack_damage() # Every projectile samples the current attack.
	_spawn_snowball(shot_name,global_position,heading,damage)
	if multiplayer.has_multiplayer_peer(): _spawn_snowball.rpc(shot_name,global_position,heading,damage)
	_request_action_sound("entity.snow_golem.shoot","shot",shoot_volume_db)
	return true

@rpc("authority","call_remote","reliable")
func _spawn_snowball(shot_name:String,point:Vector2,heading:Vector2,damage:float) -> void:
	var world:Node = _battle_parent()
	if world.has_node(NodePath(shot_name)): return
	var shot:ball = SHOT.instantiate()
	shot.name = shot_name
	shot.Master = self
	shot.Master_name = str(name)
	shot.Team = Team
	shot.set_meta("mc_snow_family",family)
	shot.Damage = int(round(damage))
	shot.Speed = snowball_speed
	shot.cold_gain = shot_cold
	shot.freeze_duration = freeze_duration
	shot.snow_knockback = snowball_knockback
	shot.direction = heading
	shot.position = world.to_local(point) if world is Node2D else point
	shot.set_multiplayer_authority(get_multiplayer_authority())
	world.add_child(shot,true)

func Attack() -> void:
	Attacking = false
	if has_player_control_aim(): fire_at(player_control_aim_world_position())
	elif not is_player_controlled():
		var target:ball = nearest_snow_enemy()
		if is_instance_valid(target): fire_at(ball.body_point(target,global_position),target)
func player_control_action(action_index:int) -> void:
	if action_index == 0 and is_player_controlled() and is_multiplayer_authority(): Attack()

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if not is_multiplayer_authority() or not has_pumpkin or amount<=0.0: return
	if float(health)>float(Max_health)*0.5: return
	var pose:int = direction_pose(_visual_heading)
	var point:Vector2 = image.to_global(image.offset+HEAD_CENTERS[pose])
	var scale_value:float = maxf(absf(image.global_scale.x),absf(image.global_scale.y))
	has_pumpkin = false
	head_break_count += 1
	_state_version += 1
	force_next_burst = true
	var seed_value:int = Game.derive_battle_random_seed("snow_pumpkin_break:"+str(name),head_break_count) if Game.is_battle_random_active() else int(get_instance_id())
	_show_pumpkin_break(head_break_count,point,pose,scale_value,seed_value)
	if multiplayer.has_multiplayer_peer():
		_show_pumpkin_break.rpc(head_break_count,point,pose,scale_value,seed_value)
		_receive_snow_state.rpc(network_visual_state())
	visual_mob()

@rpc("authority","call_remote","reliable")
func _show_pumpkin_break(serial:int,point:Vector2,pose:int,scale_value:float,seed_value:int) -> void:
	if serial<=_last_break_fx_serial: return
	_last_break_fx_serial = serial
	has_pumpkin = false
	head_break_count = maxi(head_break_count,serial)
	visual_mob()
	var effect:Node2D = BLOCK_FRAGMENTS.spawn_texture(self,HEAD_FRAMES[clampi(pose,0,DIRECTION_COUNT-1)],point,scale_value,{"effect_parent":_battle_parent(),"seed":seed_value,"max_pieces":16,"scatter_radius":20.0,"arc_height_min":7.0,"arc_height_max":17.0,"flight_min":0.30,"flight_max":0.55,"ground_hold":0.10,"fade_time":0.25})
	if is_instance_valid(effect):
		effect.set_meta("snow_pumpkin_break",serial)
		effect.set_meta("snow_pumpkin_source",str(name))
	var variants:Array = SNOW_AUDIO.action_records("block.wood.break")
	if not variants.is_empty(): _break_audio = SNOW_AUDIO.queue_action(self,"block.wood.break",posmod(seed_value,variants.size()),point,SNOW_AUDIO.PHASE_GAIN_DB,"pumpkin_break")

func get_preview_texture() -> Texture2D: return PUMPKIN[3]
func voice_role() -> String: return "snow_golem"
@rpc("authority","call_remote","reliable")
func _receive_sound(event:String,point:Vector2,volume_db:float) -> AudioStreamPlayer2D:
	return SNOW_AUDIO.play(self,event,point,volume_db)

func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health<=0:
		_cancel_burst()
		_stop_movement_and_launch_audio()
	super.tick_physics(state,delta)

func set_character_visual_flip_h(_flipped:bool) -> void:
	# All 16 images are already oriented; forbid both shader and ordinary mirroring.
	super.set_character_visual_flip_h(false)
	if image is Sprite2D: image.flip_h = false

static func direction_pose(heading:Vector2) -> int:
	return posmod(int(round(heading.angle()*float(DIRECTION_COUNT)/TAU)),DIRECTION_COUNT)

func _movement_facing_hint() -> Vector2:
	# The shared mover uses player_control_direction, not the stored AI direction.
	return player_control_direction if is_player_controlled() else direction

func move(speed:float,delta:float) -> void:
	_wall_contact_this_step = false
	var start:Vector2 = global_position
	super.move(speed,delta)
	_step_movement_audio(start,delta)
	visual_mob()

func stand(delta:float) -> void:
	_wall_contact_this_step = false
	var start:Vector2 = global_position
	super.stand(delta)
	_step_movement_audio(start,delta)
	visual_mob()

func _on_snow_wall_contact(normal_speed:float,_point:Vector2) -> void:
	if active() and normal_speed>1.0:
		_wall_step_due = true
		_wall_contact_this_step = true

func _step_movement_audio(start:Vector2,delta:float) -> void:
	if not active() or dizziness or delta<=0.0: return
	_footstep_wait = maxf(_footstep_wait-delta,0.0)
	var moved:float = start.distance_to(global_position)
	# Read the actual completed shared physics step, never an idle speed value.
	if moved<0.01 and not _wall_contact_this_step:
		_wall_step_due = false # Never replay a stale collision while stationary.
		_footstep_cadence.tick(0.0,delta,1.0,1.0)
		return
	# 行走脚步：按当前实际移速计步（footstep_cadence.gd），不等上一声播完。
	var walk_due:bool = _footstep_cadence.tick(moved,delta,FOOTSTEP.base_speed(self),footstep_base_interval)
	var wall_due:bool = _wall_step_due and _footstep_wait<=0.0
	if not walk_due and not wall_due: return
	var reason:String = "wall" if wall_due else "walk"
	if _request_action_sound("block.snow.step",reason,0.0 if wall_due else footstep_volume_db):
		_footstep_wait = maxf(footstep_min_interval,0.0)
		_wall_step_due = false

func _request_action_sound(event:String,reason:String,gain:float) -> bool:
	if not active(): return false
	var records:Array = SNOW_AUDIO.action_records(event)
	if records.is_empty(): return false
	var variant:int = _voice_rng.randi_range(0,records.size()-1) # Cosmetic RNG, not volley chance/spread.
	_sound_serial += 1
	_receive_action_sound(_sound_serial,event,variant,global_position,gain,reason)
	var accepted:Dictionary = _step_audio if event=="block.snow.step" else _shoot_audio
	if accepted.is_empty(): return false
	if multiplayer.has_multiplayer_peer(): _receive_action_sound.rpc(_sound_serial,event,variant,global_position,gain,reason)
	return true

@rpc("authority","call_remote","reliable")
func _receive_action_sound(serial:int,event:String,variant:int,point:Vector2,gain:float,reason:String) -> void:
	if serial<=_last_sound_serial or event not in ["block.snow.step","entity.snow_golem.shoot"]: return
	_last_sound_serial = serial
	if health<=0 or is_queued_for_deletion(): return
	# 脚步与每发投射物的发射声都允许重叠（脚步节奏由移速决定）。
	# Per-projectile launch events may overlap, even in a late reliable batch.
	var ticket:Dictionary = SNOW_AUDIO.queue_action(self,event,variant,point,gain,reason)
	if event=="block.snow.step":
		_step_audio = ticket
		_prune_step_voices()
		if not ticket.is_empty(): _step_voices.append(ticket)
	else:
		_shoot_audio = ticket
		_prune_shoot_voices()
		if not ticket.is_empty(): _shoot_voices.append(ticket)

func _prune_step_voices() -> void:
	for i:int in range(_step_voices.size()-1,-1,-1):
		if not SNOW_AUDIO.action_busy(_step_voices[i]): _step_voices.remove_at(i)

func _prune_shoot_voices() -> void:
	for i:int in range(_shoot_voices.size()-1,-1,-1):
		if not SNOW_AUDIO.action_busy(_shoot_voices[i]): _shoot_voices.remove_at(i)

func _process(delta:float) -> void:
	super._process(delta)
	if health<=0: _stop_movement_and_launch_audio()
	_prune_shoot_voices()
	_prune_step_voices()
	var paused:bool = not is_combat_runtime_active()
	var tickets:Array = [_step_audio,_break_audio]
	tickets.append_array(_shoot_voices)
	tickets.append_array(_step_voices)
	for ticket:Dictionary in tickets:
		var player:AudioStreamPlayer2D = SNOW_AUDIO.action_player(ticket)
		if is_instance_valid(player): player.stream_paused = paused

func _stop_movement_and_launch_audio() -> void:
	SNOW_AUDIO.stop_action(_step_audio)
	for ticket:Dictionary in _step_voices: SNOW_AUDIO.stop_action(ticket)
	_step_voices.clear()
	SNOW_AUDIO.stop_action(_shoot_audio)
	for ticket:Dictionary in _shoot_voices: SNOW_AUDIO.stop_action(ticket)
	_shoot_voices.clear()

func _exit_tree() -> void:
	_stop_movement_and_launch_audio()
	super._exit_tree()

func visual_mob() -> void:
	if not is_instance_valid(image): return
	if is_multiplayer_authority() and not dizziness:
		var walking:Vector2 = _movement_facing_hint()
		if absf(walking.x)>0.01: _walking_right = walking.x>0.0
		# Readable front-quarter walking views. Only an actual shot/volley uses
		# the full target heading; vertical travel keeps the last horizontal side.
		var hint:Vector2 = _aim if _aim_hold_left>0.0 or _burst_remaining>0 else Vector2(1 if _walking_right else -1,1)
		if hint.length_squared()>0.000001: _visual_heading = hint.normalized()
	_aim_pose = direction_pose(_visual_heading)
	image.texture = PUMPKIN[_aim_pose] if has_pumpkin else BARE[_aim_pose]
	image.rotation = 0.0
	_face_right = _visual_heading.x>=0.0
	set_character_visual_flip_h(false)

func visual_state() -> Dictionary:
	return {"time":clock,"revision":_state_version,"pumpkin":has_pumpkin,"break_count":head_break_count,"force_burst":force_next_burst,"burst_remaining":_burst_remaining,"burst_wait":_burst_wait,"shots":shots_fired,"family":family,"aim":_aim,"pose":_aim_pose,"shot_left":_shot_left,"aim_hold":_aim_hold_left,"facing":_visual_heading,"walk_right":_walking_right}
func accept_visual(data:Dictionary) -> void:
	var revision:int = int(data.get("revision",_state_version))
	if revision<_state_version: return # A delayed animation sample cannot undo a reliable gameplay phase.
	_state_version = revision
	super.accept_visual(data)
	var incoming_break:int = int(data.get("break_count",head_break_count))
	if incoming_break>=head_break_count: force_next_burst = bool(data.get("force_burst",force_next_burst))
	head_break_count = maxi(head_break_count,incoming_break)
	has_pumpkin = has_pumpkin and bool(data.get("pumpkin",has_pumpkin)) # Old visual packets cannot regrow a broken head.
	_burst_remaining = int(data.get("burst_remaining",0))
	_burst_wait = float(data.get("burst_wait",0.0))
	shots_fired = int(data.get("shots",shots_fired))
	family = str(data.get("family",family))
	set_meta("mc_snow_family",family)
	_aim = data.get("aim",_aim)
	_aim_pose = int(data.get("pose",1))
	_shot_left = float(data.get("shot_left",0.0))
	_aim_hold_left = float(data.get("aim_hold",0.0))
	_visual_heading = data.get("facing",_visual_heading)
	_walking_right = bool(data.get("walk_right",_walking_right))

func get_debug_detection_regions() -> Array:
	if health<=0 or not Can_Attack or dizziness or is_damage_output_disabled(): return []
	return [{"shape":"circle","position":global_position,"radius":attack_range,"kind":"snowball_targeting"}]
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_SNOW_GOLEM")

@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	DEATH_FX.death_pose(self,image,false) # The selected native heading is already baked.
