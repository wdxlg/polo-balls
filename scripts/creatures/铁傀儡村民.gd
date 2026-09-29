extends "res://scripts/characters/我的世界/iron_golem/pair_base.gd"
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")
const VILLAGER_FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/iron_golem/villager_0.tres")
const PREVIEW:Texture2D = preload("res://Images/characters/我的世界/iron_golem/villager_0_preview.png")
const INGOT_SCRIPT = preload("res://scripts/characters/我的世界/iron_golem/iron_ingot_projectile.gd")
@export var repair_interval:float = 4.5
@export var evade_distance:float = 50.0
@export var throw_interval:float = 2.4
@export var throw_range:float = 220.0
@export var iron_speed:float = 280.0
var orphaned:bool = false
var repair_wait:float = 0.0
var carrying_iron:bool = false
var _throw_wait:float = 0.9
var _throw_left:float = 0.0
var _throw_aim:Vector2
var _shot_serial:int = 0
var _villager_death_notified:bool = false
var _evade_wait:float = 0.0
var _evade_left:float = 0.0
var _evade_heading:Vector2 = Vector2.ZERO

func _ready() -> void:
	manual_controllable_subentity = true
	mc_audio_role = "villager"
	pair_frames = VILLAGER_FRAMES
	super._ready()
	Can_Attack = false
	add_to_group("MinecraftGolemVillager")
	update_pair_visual()

func get_preview_texture() -> Texture2D: return PREVIEW
func mc_ambient_event() -> String: return "ambient"
func golem_alive() -> bool:
	return not orphaned and is_instance_valid(Master) and Master.health>0 and not Master.is_queued_for_deletion()

func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health>0 and is_combat_runtime_active():
		if not orphaned and not golem_alive(): on_golem_killed()
		if not dizziness:
			repair_wait = maxf(repair_wait-delta,0.0)
			var target:ball = null if is_player_controlled() else mc_nearest(delta)
			if orphaned: step_orphan(target,delta)
			else: step_helper(target,delta)
		else:
			_throw_left = 0.0
			set_pair_clip("carry" if carrying_iron else "idle")
	super.tick_physics(state,delta)

func step_helper(target:ball,delta:float = 0.0) -> void:
	Can_Attack = false
	carrying_iron = Master.crack_stage()>0
	# No following, homing, formation tether, or repair-seeking direction override.
	if carrying_iron and not is_player_controlled(): try_repair()
	step_small_evade(target,delta)
	set_pair_clip(("carry_walk" if carrying_iron else "walk") if not direction.is_zero_approx() else ("carry" if carrying_iron else "idle"))

func step_small_evade(target:ball,delta:float) -> void:
	_evade_wait = maxf(_evade_wait-delta,0.0)
	_evade_left = maxf(_evade_left-delta,0.0)
	if is_player_controlled() or direction.is_zero_approx() or Speed<=0.0 or not bool(Game.Game_Settings.get("Ball_Can_Move",true)): return
	if _evade_wait<=0.0 and mc_enemy(target) and global_position.distance_to(target.global_position)<evade_distance:
		_evade_heading = target.global_position.direction_to(global_position)
		_evade_left = 0.12
		_evade_wait = 1.0
	if _evade_left>0.0:
		# A tiny temporary offset, not a new movement heading or continuous fleeing AI.
		Repel += _evade_heading*Speed*0.12

func touching_golem() -> bool:
	if not golem_alive() or collision_shape_2d==null or Master.collision_shape_2d==null: return false
	var shape:Shape2D = collision_shape_2d.shape.duplicate()
	if shape is RectangleShape2D:
		shape.size += Vector2.ONE*(4.0/maxf(absf(global_scale.x),0.01))
	return shape.collide(collision_shape_2d.global_transform,Master.collision_shape_2d.shape,Master.collision_shape_2d.global_transform)

func try_repair() -> int:
	if not mc_live() or dizziness or not golem_alive() or repair_wait>0.0: return 0
	if Master.crack_stage()==0: return 0
	if not touching_golem() or not mc_line_clear(global_position,Master.global_position): return 0
	var amount:int = Master.heal(Master.repair_target_health()-Master.health)
	if amount>0:
		repair_wait = repair_interval
		Master.visual_stage = Master.crack_stage()
		Master.pair_frames = Master.GOLEM_FRAMES[Master.visual_stage]
		Master.update_pair_visual()
		Master.mc_play("repair",-2.0)
		mc_play("yes",-8.0)
		carrying_iron = Master.crack_stage()>0
	return amount

func on_golem_killed() -> void:
	if not is_multiplayer_authority() or orphaned or health<=0: return
	orphaned = true
	Can_Attack = true
	carrying_iron = true
	_throw_wait = 0.8
	# Continuation metadata freezes the original team/solo identity before the master leaves.
	Master = null
	Master_name = ""

func step_orphan(target:ball,delta:float) -> void:
	_throw_wait = maxf(_throw_wait-delta,0.0)
	if is_damage_output_disabled() or not Can_Attack:
		_throw_left = 0.0
		set_pair_clip("carry")
		return
	if _throw_left>0.0:
		var before:float = _throw_left
		_throw_left = maxf(_throw_left-delta,0.0)
		if before>0.14 and _throw_left<=0.14: launch_iron(_throw_aim)
		if _throw_left<=0.0: set_pair_clip("carry")
		return
	if is_player_controlled():
		set_pair_clip("carry_walk" if not direction.is_zero_approx() else "carry")
		return
	if target == null:
		set_pair_clip("carry_walk" if not direction.is_zero_approx() else "carry")
		return
	var offset:Vector2 = target.global_position-global_position
	var distance:float = offset.length()
	set_pair_clip("carry_walk" if not direction.is_zero_approx() else "carry")
	if _throw_wait<=0.0 and distance<=throw_range and mc_line_clear(global_position,target.global_position):
		_throw_wait = throw_interval
		_throw_left = 0.36
		_throw_aim = offset.normalized()
		set_pair_clip("throw")

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not orphaned or not Can_Attack or dizziness or not mc_live(): return
	if _throw_wait>0.0 or _throw_left>0.0 or not has_player_control_aim(): return
	var point:Vector2 = player_control_aim_world_position()
	var chosen:ball = null
	var nearest:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw) or not raw.is_combat_lockable(): continue
		var distance:float = raw.global_position.distance_to(point)
		if distance<=U.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	if chosen==null or global_position.distance_to(chosen.global_position)>throw_range or not mc_line_clear(global_position,chosen.global_position): return
	_throw_wait=throw_interval
	_throw_left=0.36
	_throw_aim=global_position.direction_to(chosen.global_position)
	set_pair_clip("throw")
func controlled_skill_action() -> void:
	if is_player_controlled() and is_multiplayer_authority() and not orphaned and carrying_iron: try_repair()

func launch_iron(heading:Vector2) -> void:
	if not mc_live() or dizziness or not orphaned or not Can_Attack: return
	_shot_serial += 1
	var point:Vector2 = global_position+heading*12.0
	var shot_name:String = str(name)+"_Iron_"+str(_shot_serial)
	if multiplayer.has_multiplayer_peer(): _spawn_iron.rpc(point,heading,attack_damage(),shot_name)
	_spawn_iron(point,heading,attack_damage(),shot_name)
	var event:String = "entity.snowball.throw"
	if multiplayer.has_multiplayer_peer(): _pair_audio.rpc(event,point,-6.0)
	_pair_audio_local(event,point,-6.0)

func play_iron_impact(point:Vector2) -> void:
	var event:String = "block.anvil.hit"
	if multiplayer.has_multiplayer_peer(): _pair_audio.rpc(event,point,-12.0)
	_pair_audio_local(event,point,-12.0)

@rpc("authority","call_remote","reliable")
func _spawn_iron(point:Vector2,heading:Vector2,damage_value:float,shot_name:String) -> void:
	var scene:Node = get_tree().current_scene
	if scene == null or scene.get_node_or_null(NodePath(shot_name))!=null: return
	var shot:Node2D = INGOT_SCRIPT.new()
	shot.name = shot_name
	shot.source_ref = weakref(self)
	shot.heading = heading
	shot.damage = damage_value
	shot.speed = iron_speed
	shot.set_multiplayer_authority(get_multiplayer_authority())
	scene.add_child(shot)
	shot.global_position = point

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if health<=0: notify_villager_death()
func notify_villager_death() -> void:
	if _villager_death_notified: return
	_villager_death_notified = true
	if is_instance_valid(Master) and Master.health>0 and Master.has_method("on_companion_killed"): Master.on_companion_killed()
func Die() -> void:
	notify_villager_death()
	super.Die()
func Attack() -> void: Attacking = false
