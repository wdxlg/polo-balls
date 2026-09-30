extends ball

const ROCK_SCENE:PackedScene = preload("res://scenes/shooter/凑企鹅石头.tscn")
const ASSIMILATION_AUDIO:AudioStream = preload("res://audio/characters/meme/凑企鹅/你是凑企鹅.MP3")
const VICTORY_AUDIO:AudioStream = preload("res://audio/characters/meme/凑企鹅/灵感蘑.MP3")
const THROW_AUDIO:AudioStream = preload("res://audio/sfx/shooter/Knife_throw.ogg")
const FLY_KICK_AUDIO:AudioStream = preload("res://audio/characters/meme/凑企鹅/飞踢.mp3")
const FLY_KICK_ANIMATION:StringName = &"fly_kick"
const FLY_KICK_START_FRAME_NUMBER:int = 46
const PICKUP_AUDIO:Array[AudioStream] = [
	preload("res://audio/characters/meme/凑企鹅/咕咕嘎嘎1.MP3"),
	preload("res://audio/characters/meme/凑企鹅/咕咕嘎嘎2.MP3"),
	preload("res://audio/characters/meme/凑企鹅/咕咕嘎嘎3.MP3"),
	preload("res://audio/characters/meme/凑企鹅/咕咕嘎嘎4.MP3"),
	preload("res://audio/characters/meme/凑企鹅/咕咕嘎嘎5.MP3"),
]

enum PenguinAudio {
	THROW,
	PICKUP_1,
	PICKUP_2,
	PICKUP_3,
	PICKUP_4,
	PICKUP_5,
	ASSIMILATE,
	VICTORY,
	FLY_KICK,
}

@export_category("凑企鹅 - 石头")
# 正面扔中仍然是角色的高伤攻击；落地后的碰撞伤害另行配置。
@export_range(0.0,10.0,0.05) var rock_damage_multiplier:float = 4.7777778
@export_range(50.0,1200.0,10.0) var rock_speed:float = 320.0
@export_range(0.0,10.0,0.05) var grounded_rock_damage_multiplier:float = 1.0
@export_range(0.0,200.0,1.0) var rock_knockback_distance:float = 72.0
@export_range(0.0,200.0,1.0) var grounded_rock_knockback_distance:float = 0.0
@export_range(50.0,1600.0,10.0) var rock_knockback_speed:float = 520.0
@export_range(0.0,200.0,1.0) var rock_spawn_offset:float = 42.0
@export_range(0.0,1.0,0.01) var rock_throw_windup:float = 0.18
@export_range(0.0,1.0,0.01) var rock_throw_recovery:float = 0.24
@export var has_rock:bool = true

@export_category("凑企鹅 - 同化")
@export_range(0.01,0.95,0.01) var assimilate_health_ratio:float = 0.20
@export_range(0.0,1.0,0.01) var assimilate_after_voice_delay:float = 0.05
@export_range(0.02,1.0,0.01) var assimilate_scan_interval:float = 0.10

@export_category("凑企鹅 - 胜利")
@export_range(0.05,1.0,0.05) var victory_scan_interval:float = 0.20

@export_category("凑企鹅 - 飞踢")
@export_range(1.0,30.0,0.1) var fly_kick_cooldown:float = 8.5
@export_range(80.0,600.0,5.0) var fly_kick_acquire_range:float = 280.0
@export_range(100.0,1200.0,10.0) var fly_kick_speed:float = 650.0
@export_range(50.0,500.0,5.0) var fly_kick_max_distance:float = 230.0
@export_range(0.0,10.0,0.05) var fly_kick_damage_multiplier:float = 3.2222222
@export_range(20.0,300.0,5.0) var fly_kick_knockback_distance:float = 165.0
@export_range(100.0,1200.0,10.0) var fly_kick_knockback_speed:float = 700.0
@export_range(0.0,10.0,0.05) var fly_kick_wall_damage_multiplier:float = 1.5555556
@export_range(0.0,2.0,0.05) var fly_kick_wall_stun:float = 0.65
@export_range(0.0,1.0,0.01) var fly_kick_recovery:float = 0.26

var _assimilating:bool = false
var _victory_dancing:bool = false
var _assimilate_target_ids:Array[int] = []
var _assimilate_scan_elapsed:float = 0.0
var _victory_scan_elapsed:float = 0.0
var _has_seen_enemy:bool = false
var _pickup_voice_index:int = 0
var _owned_audio_players:Array[AudioStreamPlayer] = []
var _victory_audio_player:AudioStreamPlayer = null

var _fly_kick_sequence_active:bool = false
var _fly_kick_active:bool = false
var _fly_kick_direction:Vector2 = Vector2.RIGHT
var _fly_kick_target_id:int = 0
var _fly_kick_dash_frame_index:int = 0
var _fly_kick_travelled:float = 0.0
var _fly_kick_afterimage_elapsed:float = 0.0
var _fly_kick_serial:int = 0
var _fly_kick_hit_ids:Dictionary = {}

@onready var held_rock:Sprite2D = $Graphics/HeldRock
@onready var assimilation_animation:AnimatedSprite2D = $Graphics/AssimilationAnimation
@onready var fly_kick_animation:AnimatedSprite2D = $Graphics/FlyKickAnimation
@onready var fly_kick_area:Area2D = $FlyKickArea
@onready var fly_kick_shape:CollisionShape2D = $FlyKickArea/CollisionShape2D


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Skill = true
	Skill_Cooling = fly_kick_cooldown
	Health_Restore = 0
	super._ready()
	add_to_group("CouPenguinCharacter")
	_sync_assimilation_size_to_normal()
	_sync_fly_kick_size_to_normal()
	_fly_kick_dash_frame_index = _resolve_fly_kick_dash_frame_index()
	_set_has_rock_visual(has_rock)
	_set_assimilation_visual(false)
	_set_fly_kick_visual(false)
	if fly_kick_animation != null and not fly_kick_animation.frame_changed.is_connected(_on_fly_kick_animation_frame_changed):
		fly_kick_animation.frame_changed.connect(_on_fly_kick_animation_frame_changed)
	_setup_fly_kick_area()
	Can_Attack = has_rock


func _exit_tree() -> void:
	_stop_all_penguin_audio_local()
	_cleanup_owned_rocks()
	_release_all_assimilation_claims()
	_finish_fly_kick_immediate()


func Die() -> void:
	# 企鹅死亡进入 Die 的这一刻就停，不等节点稍后 queue_free。
	_stop_all_penguin_audio_sync()
	_cleanup_owned_rocks()
	_release_all_assimilation_claims()
	_finish_fly_kick_immediate()
	super.Die()


func stop_penguin_audio_for_conversion() -> void:
	# 被另一只凑企鹅同化时，在删除旧角色之前先停止旧角色持有的所有声音和唯一石头。
	_stop_all_penguin_audio_sync()
	_cleanup_owned_rocks()


func tick_physics(state:State,delta:float) -> void:
	if _fly_kick_sequence_active and is_multiplayer_authority():
		_tick_fly_kick_sequence(state,delta)
		return

	if is_multiplayer_authority() and health > 0:
		_assimilate_scan_elapsed += delta
		_victory_scan_elapsed += delta

		if not _victory_dancing and _victory_scan_elapsed >= victory_scan_interval:
			_victory_scan_elapsed = 0.0
			_update_enemy_memory_and_victory()

		if not _victory_dancing and not _assimilating and _assimilate_scan_elapsed >= assimilate_scan_interval:
			_assimilate_scan_elapsed = 0.0
			var targets:Array[ball] = _find_assimilation_targets()
			if not targets.is_empty():
				_begin_assimilation_group(targets)

	if _assimilating or _victory_dancing:
		if assimilation_animation != null and image is Sprite2D:
			assimilation_animation.flip_h = (image as Sprite2D).flip_h
		# 同化/胜利舞蹈时停止主动移动与攻击，但仍正常受击和被击退。
		super.tick_physics(State.Stand,delta)
		return

	super.tick_physics(state,delta)


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if _assimilating or _victory_dancing or not has_rock:
		Attacking = false
		Can_Attack = has_rock and not _assimilating and not _victory_dancing
		return

	var target:ball = _nearest_enemy_character()
	if target == null and not has_player_control_aim():
		Attacking = false
		return

	Attacking = true
	var aim:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(target) - global_position)
	if aim.length_squared() <= 0.000001:
		aim = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	aim = aim.normalized()

	await get_tree().create_timer(maxf(rock_throw_windup,0.01)).timeout
	if not is_instance_valid(self) or health <= 0 or _assimilating or _victory_dancing or not has_rock:
		if is_instance_valid(self):
			Attacking = false
		return

	_throw_rock(aim,target)
	await get_tree().create_timer(maxf(rock_throw_recovery,0.01)).timeout
	if is_instance_valid(self):
		Attacking = false


func _throw_rock(aim:Vector2,_target:ball) -> void:
	if not has_rock:
		return
	has_rock = false
	Can_Attack = false
	_set_has_rock_visual(false)
	_sync_has_rock_visual(false)

	var rock:Node2D = ROCK_SCENE.instantiate() as Node2D
	if rock == null:
		# 场景加载失败时不要永久吃掉唯一石头。
		has_rock = true
		Can_Attack = true
		_set_has_rock_visual(true)
		return

	rock.set("Master",self)
	rock.set("Master_name",str(name))
	rock.set("Team",Team)
	rock.set("travel_speed",rock_speed)
	rock.set("impact_damage",attack_damage(rock_damage_multiplier))
	rock.set("ground_contact_damage",attack_damage(grounded_rock_damage_multiplier))
	rock.set("knockback_distance",rock_knockback_distance)
	rock.set("ground_knockback_distance",grounded_rock_knockback_distance)
	rock.set("knockback_speed",rock_knockback_speed)
	rock.set("direction",aim)
	rock.global_position = global_position + aim * rock_spawn_offset
	rock.global_rotation = 0.0
	rock.name = Game.return_random_name(rock)
	get_tree().current_scene.add_child(rock,true)

	# 完全复用小刀猎投刀音源；播放器归凑企鹅自己持有，死亡/同化时可立即停止。
	_play_penguin_audio(PenguinAudio.THROW,false,true)


func pickup_penguin_rock(rock:Variant) -> void:
	if not is_multiplayer_authority() or _assimilating or _victory_dancing or has_rock:
		return
	if not is_instance_valid(rock):
		return
	if "Master" in rock and rock.get("Master") != self:
		return
	has_rock = true
	Can_Attack = true
	_set_has_rock_visual(true)
	_sync_has_rock_visual(true)
	_play_next_pickup_voice()
	if rock is Node:
		(rock as Node).queue_free()


func _cleanup_owned_rocks() -> void:
	if get_tree() == null:
		return
	for node:Node in get_tree().get_nodes_in_group("CouPenguinRock"):
		if node == null or not is_instance_valid(node):
			continue
		if node.get("Master") == self:
			node.queue_free()


func _play_next_pickup_voice() -> void:
	_pickup_voice_index = (_pickup_voice_index % PICKUP_AUDIO.size()) + 1
	_play_penguin_audio(PenguinAudio.PICKUP_1 + _pickup_voice_index - 1,false,false)


func _nearest_enemy_character() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_attackable_enemy(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	return nearest


func _find_assimilation_targets() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_enemy_character(candidate):
			continue
		if candidate.Max_health <= 0:
			continue
		var ratio:float = float(candidate.health) / float(candidate.Max_health)
		if ratio >= assimilate_health_ratio:
			continue
		if candidate.has_meta("cou_penguin_assimilating"):
			continue
		result.append(candidate)
	return result


func _is_attackable_enemy(candidate:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,candidate): return false # 皓宸复制品及其产物不把己方选为目标
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return false
	if not candidate.is_combat_targetable():
		return false
	if not Team.is_empty() and not candidate.Team.is_empty() and candidate.Team == Team:
		return false
	return true


func _is_enemy_character(candidate:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,candidate): return false # 皓宸复制品及其产物不把己方选为目标
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return false
	if candidate.Type != Ball_Type.Ball or candidate.health <= 0:
		return false
	if candidate.state_machine != null and candidate.state_machine.current_state == State.Die:
		return false
	# 只要双方 Team 相同，就永远是队友；空 Team 会在同化前被升级为凑企鹅专属队伍。
	if not Team.is_empty() and not candidate.Team.is_empty() and candidate.Team == Team:
		return false
	return true


func _begin_assimilation_group(targets:Array[ball]) -> void:
	if _assimilating or _victory_dancing or _fly_kick_active or targets.is_empty():
		return
	var ally_team:String = _ensure_real_team_identity()
	_assimilating = true
	_assimilate_target_ids.clear()
	for target:ball in targets:
		if target == null or not is_instance_valid(target) or not _is_enemy_character(target):
			continue
		if target.Max_health <= 0:
			continue
		var ratio:float = float(target.health) / maxf(float(target.Max_health),1.0)
		if ratio >= assimilate_health_ratio or target.has_meta("cou_penguin_assimilating"):
			continue
		target.set_meta("cou_penguin_assimilating",get_instance_id())
		_assimilate_target_ids.append(target.get_instance_id())
	if _assimilate_target_ids.is_empty():
		_assimilating = false
		return

	Can_Attack = false
	Attacking = false
	Using_Skill = false
	_set_assimilation_visual(true)
	_sync_assimilation_visual(true)

	# V45：一次锁定这一刻所有低于阈值的敌人；“你是凑企鹅”只播放一次，
	# 声音结束后整批同时转化，而不是逐个排队等待下一轮扫描。
	_play_penguin_audio(PenguinAudio.ASSIMILATE,false,false)
	_run_assimilation_group_after_voice(_assimilate_target_ids.duplicate(),ally_team)


func _run_assimilation_group_after_voice(target_ids:Array[int],ally_team:String) -> void:
	var voice_length:float = 3.918
	if ASSIMILATION_AUDIO != null:
		voice_length = maxf(ASSIMILATION_AUDIO.get_length(),0.05)
	await get_tree().create_timer(voice_length + maxf(assimilate_after_voice_delay,0.0)).timeout
	if not is_instance_valid(self) or health <= 0:
		return
	var converted_count:int = 0
	for target_id:int in target_ids:
		var target:ball = _resolve_live_ball(target_id)
		if target == null:
			continue
		# 声音期间若被治疗到阈值以上，则不强行转换，释放占用标记。
		var ratio:float = float(target.health) / maxf(float(target.Max_health),1.0)
		if ratio >= assimilate_health_ratio or not _is_enemy_character(target):
			if target.has_meta("cou_penguin_assimilating"):
				target.remove_meta("cou_penguin_assimilating")
			continue
		if _assimilate_target(target,ally_team):
			converted_count += 1
	# 转换完成后按用户要求固定播放“咕咕嘎嘎1”，整批只播一次避免多人同时爆音。
	if converted_count > 0:
		_play_penguin_audio(PenguinAudio.PICKUP_1,false,false)
	_finish_assimilation()


func _assimilate_target(target:ball,ally_team:String) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	var health_ratio:float = clampf(float(target.health) / maxf(float(target.Max_health),1.0),0.0,1.0)
	var spawn_position:Vector2 = target.global_position
	var spawn_rotation:float = target.global_rotation
	var spawn_direction:Vector2 = target.direction
	var inherited_setup_id:int = int(target.get_meta("battle_setup_id",-1))

	var packed:Resource = ResourceLoader.load("res://scenes/characters/meme/凑企鹅.tscn")
	if not packed is PackedScene:
		return false
	var new_penguin:ball = (packed as PackedScene).instantiate() as ball
	if new_penguin == null:
		return false

	# 同化是转队，不计为击杀。队伍在 add_child 前就写入，保证 MultiplayerSpawner
	# 的 spawn 属性第一帧就是正确队伍；入树后再写一次，避免任何 Ready 初始化覆盖。
	new_penguin.Team = ally_team
	new_penguin.global_position = spawn_position
	new_penguin.global_rotation = spawn_rotation
	new_penguin.direction = spawn_direction
	if inherited_setup_id >= 0:
		new_penguin.set_meta("battle_setup_id",inherited_setup_id)
	new_penguin.set_meta("victory_side_key","team:" + ally_team)
	new_penguin.name = Game.return_random_name(new_penguin)
	get_tree().current_scene.add_child(new_penguin,true)
	new_penguin.Team = ally_team

	# 保留“百分比”但不把从满血改到目标百分比显示成一大坨伤害数字。
	if new_penguin.health_bar != null:
		new_penguin.health_bar.suppress_floating_text = true
	new_penguin.health = maxi(int(round(float(new_penguin.Max_health) * health_ratio)),1)
	if new_penguin.health_bar != null:
		new_penguin.health_bar.suppress_floating_text = false

	if is_instance_valid(target):
		if target.has_meta("cou_penguin_assimilating"):
			target.remove_meta("cou_penguin_assimilating")
		if target.has_method("stop_penguin_audio_for_conversion"):
			target.call("stop_penguin_audio_for_conversion")
		Game.free_node(target)

	# 目标 queue_free 会到帧末才真正离场；下一帧再检查是否已经全场同队。
	call_deferred("_update_enemy_memory_and_victory")
	return true


func _release_all_assimilation_claims() -> void:
	for target_id:int in _assimilate_target_ids:
		var target:ball = _resolve_live_ball(target_id)
		if target != null and target.has_meta("cou_penguin_assimilating"):
			target.remove_meta("cou_penguin_assimilating")
	_assimilate_target_ids.clear()


func _finish_assimilation() -> void:
	_release_all_assimilation_claims()
	_assimilating = false
	if not _victory_dancing:
		_set_assimilation_visual(false)
		_sync_assimilation_visual(false)
	Can_Attack = has_rock and not _victory_dancing


func _ensure_real_team_identity() -> String:
	var current_team:String = str(Team).strip_edges()
	if current_team.is_empty() or current_team == "Ball":
		# 无队伍模式也必须把被同化者变成真正队友，而不是两个“空 Team”继续互殴。
		current_team = "__cou_penguin_team_" + str(name)
		Team = current_team
		if multiplayer.has_multiplayer_peer():
			_remote_force_team.rpc(current_team)
	return current_team


@rpc("authority","call_remote","reliable")
func _remote_force_team(team_name:String) -> void:
	Team = team_name


func _update_enemy_memory_and_victory() -> void:
	if not is_multiplayer_authority() or health <= 0 or _victory_dancing:
		return
	var ally_team:String = _ensure_real_team_identity()
	var alive_characters:int = 0
	var has_enemy:bool = false
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var candidate:ball = node as ball
		if candidate.Type != Ball_Type.Ball or candidate.health <= 0:
			continue
		alive_characters += 1
		if candidate != self and candidate.Team != ally_team:
			has_enemy = true

	if has_enemy:
		_has_seen_enemy = true
		return
	if _has_seen_enemy and alive_characters > 0:
		_trigger_team_victory_dance()


func _trigger_team_victory_dance() -> void:
	if _victory_dancing:
		return
	var my_team:String = str(Team)
	var dancers:Array[Node] = []
	for node:Node in get_tree().get_nodes_in_group("CouPenguinCharacter"):
		if not node is ball or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var other:ball = node as ball
		if other.health <= 0 or str(other.Team) != my_team:
			continue
		dancers.append(node)

	if dancers.is_empty():
		return
	# 第一只检测到完全胜利的企鹅立即把同队所有凑企鹅都切进舞蹈，
	# 包括刚刚同化出来、还没来得及“见过敌人”的新企鹅。
	for dancer:Node in dancers:
		dancer.call("_enter_victory_dance_local")
	# 灵感蘑从完全胜利开始持续循环，直到持有播放器的凑企鹅死亡/被删除/换场。
	_play_penguin_audio(PenguinAudio.VICTORY,true,false)


func _enter_victory_dance_local() -> void:
	if _victory_dancing:
		return
	_victory_dancing = true
	_assimilating = false
	Can_Attack = false
	Attacking = false
	_set_assimilation_visual(true)
	_sync_victory_dance(true)


# ============================================================
# V46 飞踢技能动画
# - 用户序列按文件名结尾数字升序播放：000,002,...,052。
# - 000~044 只是准备动画，角色保持正常移动速度；不会提前开启伤害区。
# - 切到 frame_046 的物理帧才真正开始冲刺，同时播放“啊”音效。
# - 046 之后继续沿用真实 Area2D 命中、中等伤害、击退、撞墙追加伤害与眩晕。
# ============================================================
func Skill() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		Using_Skill = false
		return
	if _assimilating or _victory_dancing or _fly_kick_sequence_active or is_damage_output_disabled():
		Using_Skill = false
		return
	var target:ball = _nearest_enemy_character()
	if not has_player_control_aim() and (target == null or global_position.distance_to(target.global_position) > fly_kick_acquire_range):
		Using_Skill = false
		return

	Using_Skill = true
	Attacking = false
	Can_Attack = false
	_fly_kick_sequence_active = true
	_fly_kick_active = false
	_fly_kick_target_id = target.get_instance_id() if target != null else 0
	_fly_kick_travelled = 0.0
	_fly_kick_afterimage_elapsed = 0.0
	_fly_kick_hit_ids.clear()
	_fly_kick_serial += 1
	var aim:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(target) - global_position)
	if aim.length_squared() <= 0.000001:
		aim = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_fly_kick_direction = aim.normalized()
	if fly_kick_area != null:
		fly_kick_area.monitoring = false
		fly_kick_area.set_meta("threat_debug_damage",0.0)
	_sync_fly_kick_visual(true)


func _tick_fly_kick_sequence(state:State,delta:float) -> void:
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		_finish_fly_kick_immediate()
		return
	if not is_combat_runtime_active():
		velocity = Vector2.ZERO
		return

	if _fly_kick_active:
		_tick_fly_kick(delta)
		return

	# 046 之前保持普通移动。这里仍处在 Skill 状态，但 ball 的 Skill 状态本来就按 Speed 移动，
	# 所以不额外减速、不提前冲刺，也不提前播放飞踢音效。
	super.tick_physics(state,delta)
	_update_fly_kick_animation_flip()

	if fly_kick_animation == null or fly_kick_animation.sprite_frames == null:
		_begin_fly_kick_dash()
		return
	if fly_kick_animation.frame >= _fly_kick_dash_frame_index:
		_begin_fly_kick_dash()


func _on_fly_kick_animation_frame_changed() -> void:
	if not is_multiplayer_authority() or not _fly_kick_sequence_active or _fly_kick_active:
		return
	if fly_kick_animation == null:
		return
	if fly_kick_animation.frame >= _fly_kick_dash_frame_index:
		_begin_fly_kick_dash()


func _begin_fly_kick_dash() -> void:
	if _fly_kick_active or not _fly_kick_sequence_active:
		return
	var target:ball = _resolve_live_ball(_fly_kick_target_id)
	if not has_player_control_aim() and (target == null or not _is_attackable_enemy(target)):
		target = _nearest_enemy_character()
	var aim:Vector2 = Vector2.ZERO
	if has_player_control_aim():
		aim = player_control_aim_direction(_fly_kick_direction)
	elif target != null:
		aim = combat_target_position(target) - global_position
	if aim.length_squared() <= 0.000001:
		aim = direction if direction.length_squared() > 0.000001 else _fly_kick_direction
	if aim.length_squared() <= 0.000001:
		aim = Vector2.RIGHT
	_fly_kick_direction = aim.normalized()
	direction = _fly_kick_direction
	_fly_kick_active = true
	_fly_kick_travelled = 0.0
	_fly_kick_afterimage_elapsed = 0.0
	if fly_kick_area != null:
		fly_kick_area.monitoring = true
		fly_kick_area.set_meta("threat_debug_damage",attack_damage(fly_kick_damage_multiplier))
	_update_fly_kick_animation_flip()
	# 用户指定：不是技能起手播放，而是 frame_046 真正进入飞踢的这一刻播放。
	_play_penguin_audio(PenguinAudio.FLY_KICK,false,false)


func _setup_fly_kick_area() -> void:
	if fly_kick_area == null:
		return
	fly_kick_area.collision_layer = 0
	fly_kick_area.collision_mask = 2
	fly_kick_area.monitoring = false
	fly_kick_area.monitorable = false
	fly_kick_area.set_meta("threat_debug_damage",0.0)


# 功能：用飞踢真实 CircleShape2D 沿本帧运动连续扫过敌人真实 Hurtbox，避免高速位移和物理身体接触导致漏判。
func _find_swept_fly_kick_target(motion:Vector2,delta:float) -> ball:
	if fly_kick_shape == null or not is_instance_valid(fly_kick_shape) or fly_kick_shape.shape == null:
		return null
	if motion.length_squared() <= 0.000001:
		return null

	var kick_shape:Shape2D = fly_kick_shape.shape
	var kick_transform:Transform2D = fly_kick_shape.global_transform
	var best_target:ball = null
	var best_progress:float = INF
	var motion_length_sq:float = motion.length_squared()

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_attackable_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		if _fly_kick_hit_ids.has(target_id):
			continue
		if target.self_hurtbox == null or not is_instance_valid(target.self_hurtbox):
			continue

		var target_shape:CollisionShape2D = target.self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if target_shape == null or target_shape.disabled or target_shape.shape == null:
			continue

		# 目标本帧也可能在移动；连续形状检测不依赖 Area2D overlap 下一物理帧才更新。
		var target_motion:Vector2 = target.velocity * maxf(delta,0.0)
		if not kick_shape.collide_with_motion(
			kick_transform,
			motion,
			target_shape.shape,
			target_shape.global_transform,
			target_motion
		):
			continue

		# 多个敌人同时在飞踢路径上时，优先结算沿冲刺方向最近的那个。
		var progress:float = clampf(
			(target.global_position - global_position).dot(motion) / motion_length_sq,
			0.0,
			1.0
		)
		if progress < best_progress:
			best_progress = progress
			best_target = target

	return best_target


func _tick_fly_kick(delta:float) -> void:
	if not is_multiplayer_authority() or health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		_finish_fly_kick_immediate()
		return
	if not is_combat_runtime_active():
		velocity = Vector2.ZERO
		return

	var before:Vector2 = global_position
	velocity = _fly_kick_direction * maxf(fly_kick_speed,1.0)
	var requested_motion:Vector2 = velocity * maxf(delta,0.0)

	# 第一层：移动前用真实飞踢形状做连续扫掠，高速一帧跨过 Hurtbox 也能被记录。
	var swept_target:ball = _find_swept_fly_kick_target(requested_motion,delta)

	# 第二层：冲刺改用 move_and_collide；实体身体真正撞到敌人就立即结算，不再自动沿敌人表面滑过去。
	var body_collision:KinematicCollision2D = move_and_collide(requested_motion)
	if body_collision != null:
		var collider:Variant = body_collision.get_collider()

		if collider is ball:
			var contacted_ball:ball = collider as ball
			if _is_attackable_enemy(contacted_ball):
				var contacted_id:int = contacted_ball.get_instance_id()
				if not _fly_kick_hit_ids.has(contacted_id):
					_fly_kick_hit_ids[contacted_id] = true
					_apply_fly_kick_hit(contacted_ball) # 根身体已经踢到敌人时直接算命中，不要求 Hurtbox 再往里重叠。
				_finish_fly_kick_with_recovery()
				return

			# 非敌方 ball 仍允许沿表面绕开一次，保持原来的移动容错。
			var ally_remainder:Vector2 = body_collision.get_remainder().slide(body_collision.get_normal())
			if ally_remainder.length_squared() > 0.000001:
				move_and_collide(ally_remainder)
		else:
			# 墙体/地图实体直接结束飞踢，不会把墙后的连续扫掠目标判成命中。
			_finish_fly_kick_with_recovery()
			return

	var moved:float = before.distance_to(global_position)
	_fly_kick_travelled += moved
	Repel = Vector2.ZERO

	_fly_kick_afterimage_elapsed += delta
	if _fly_kick_afterimage_elapsed >= 0.055:
		_fly_kick_afterimage_elapsed = 0.0
		AfterImage()

	# 第三层：没有实体障碍时，如果真实 Shape2D 扫掠经过敌人 Hurtbox，就按这一帧的运动轨迹结算。
	if body_collision == null and swept_target != null and is_instance_valid(swept_target):
		var swept_id:int = swept_target.get_instance_id()
		if not _fly_kick_hit_ids.has(swept_id):
			_fly_kick_hit_ids[swept_id] = true
			_apply_fly_kick_hit(swept_target)
			_finish_fly_kick_with_recovery()
			return

	# 第四层兜底：保留原 Area2D overlap，处理已经处在飞踢圆内部的 Hurtbox。
	for area:Area2D in fly_kick_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var candidate_node:Node = area.get_parent()
		if not candidate_node is ball:
			candidate_node = area.owner
		if not candidate_node is ball:
			continue
		var target:ball = candidate_node as ball
		if not _is_attackable_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		if _fly_kick_hit_ids.has(target_id):
			continue
		_fly_kick_hit_ids[target_id] = true
		_apply_fly_kick_hit(target)
		_finish_fly_kick_with_recovery()
		return

	if _fly_kick_travelled >= maxf(fly_kick_max_distance,10.0):
		_finish_fly_kick_with_recovery()


# V88：飞踢/撞墙两条路径本来就有专门的宽覆盖爆射线。
# 公共 receive_positional_damage() 现在也会自动补受击线，因此明确声明由本角色自己接管，
# 避免同一次飞踢叠两组效果。
func handles_positional_hit_feedback() -> bool:
	return true


func _apply_fly_kick_hit(target:ball) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	var outgoing:float = attack_damage(fly_kick_damage_multiplier)
	var hit_point:Vector2 = target.global_position
	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	target.receive_positional_damage(outgoing,hit_point,false,self)
	var health_loss:float = maxf(before_health - float(target.health),0.0)
	var block_loss:float = maxf(before_block - float(target.block),0.0)
	if health_loss > 0.0 or block_loss > 0.0:
		var seed:int = Game.battle_rng_seed_or("scripts/characters/meme/凑企鹅.gd:seed",int(Time.get_ticks_usec()) ^ target.get_instance_id() ^ get_instance_id())
		target.notify_hit_burst_feedback(hit_point,outgoing,health_loss,block_loss,72.0,seed,_fly_kick_direction)
	_play_fly_kick_collision_sfx(outgoing)

	var effect:Node = target.apply_knockback(
		_fly_kick_direction,
		fly_kick_knockback_distance,
		fly_kick_knockback_speed,
		0.0,
		0.0,
		{
			"source":self,
			"lock_control":true,
			"stun_only_on_collision":false,
			"collision_damage":0.0,
			"max_wall_bounces":0,
			"stop_on_character":true,
			"smooth_motion":true,
		}
	)
	_watch_fly_kick_wall_impact(target.get_instance_id(),effect,_fly_kick_serial)


func _watch_fly_kick_wall_impact(target_id:int,effect:Node,serial:int) -> void:
	var elapsed:float = 0.0
	while elapsed < 1.6:
		await get_tree().physics_frame
		if not is_instance_valid(self) or health <= 0 or serial != _fly_kick_serial:
			return
		var target:ball = _resolve_live_ball(target_id)
		if target == null:
			return
		for collision_index:int in range(target.get_slide_collision_count()):
			var collision:KinematicCollision2D = target.get_slide_collision(collision_index)
			if collision == null:
				continue
			var collider:Variant = collision.get_collider()
			if collider == null or collider is ball:
				continue
			var impact_position:Vector2 = collision.get_position()
			var wall_outgoing:float = attack_damage(fly_kick_wall_damage_multiplier)
			var before_health:float = float(target.health)
			var before_block:float = float(target.block)
			target.receive_positional_damage(wall_outgoing,impact_position,false,self)
			var health_loss:float = maxf(before_health - float(target.health),0.0)
			var block_loss:float = maxf(before_block - float(target.block),0.0)
			if health_loss > 0.0 or block_loss > 0.0:
				var seed:int = Game.battle_rng_seed_or("scripts/characters/meme/凑企鹅.gd:seed",int(Time.get_ticks_usec()) ^ target_id ^ serial)
				target.notify_hit_burst_feedback(impact_position,wall_outgoing,health_loss,block_loss,64.0,seed,_fly_kick_direction)
			target.apply_stun(fly_kick_wall_stun)
			_play_fly_kick_collision_sfx(wall_outgoing)
			return
		if effect == null or not is_instance_valid(effect) or (effect.has_method("is_active_effect") and not bool(effect.call("is_active_effect"))):
			return
		elapsed += get_physics_process_delta_time()


func _play_fly_kick_collision_sfx(raw_damage:float) -> void:
	var params:Dictionary = {"volume":clampf(raw_damage - 50.0,-16.0,0.0),"pitch":randf_range(0.96,1.05)}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)


func _finish_fly_kick_with_recovery() -> void:
	if not _fly_kick_sequence_active and not _fly_kick_active:
		return
	_fly_kick_active = false
	_fly_kick_sequence_active = false
	velocity = Vector2.ZERO
	if fly_kick_area != null:
		fly_kick_area.monitoring = false
		fly_kick_area.set_meta("threat_debug_damage",0.0)
	_sync_fly_kick_visual(false)
	_recover_from_fly_kick(_fly_kick_serial)


func _recover_from_fly_kick(serial:int) -> void:
	await get_tree().create_timer(maxf(fly_kick_recovery,0.01)).timeout
	if not is_instance_valid(self) or serial != _fly_kick_serial:
		return
	Using_Skill = false
	Can_Attack = has_rock and not _assimilating and not _victory_dancing


func _finish_fly_kick_immediate() -> void:
	var had_sequence:bool = _fly_kick_sequence_active or _fly_kick_active
	_fly_kick_active = false
	_fly_kick_sequence_active = false
	_fly_kick_target_id = 0
	velocity = Vector2.ZERO
	Using_Skill = false
	if fly_kick_area != null and is_instance_valid(fly_kick_area):
		fly_kick_area.monitoring = false
		fly_kick_area.set_meta("threat_debug_damage",0.0)
	if had_sequence:
		_sync_fly_kick_visual(false)
	else:
		_set_fly_kick_visual(false)


func _sync_fly_kick_visual(active:bool) -> void:
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_set_fly_kick_visual.rpc(active)
	else:
		_set_fly_kick_visual(active)


@rpc("authority","call_local","reliable")
func _remote_set_fly_kick_visual(active:bool) -> void:
	_set_fly_kick_visual(active)


func _set_fly_kick_visual(active:bool) -> void:
	_fly_kick_sequence_active = active
	_sync_fly_kick_size_to_normal()
	if image != null and is_instance_valid(image):
		image.visible = not active and not _assimilating and not _victory_dancing
	if held_rock != null and is_instance_valid(held_rock):
		held_rock.visible = has_rock and not active and not _assimilating and not _victory_dancing
	if fly_kick_animation == null or not is_instance_valid(fly_kick_animation):
		return
	fly_kick_animation.visible = active
	if active:
		_update_fly_kick_animation_flip()
		fly_kick_animation.stop()
		fly_kick_animation.frame = 0
		fly_kick_animation.play(FLY_KICK_ANIMATION)
	else:
		fly_kick_animation.stop()
		fly_kick_animation.frame = 0


func _update_fly_kick_animation_flip() -> void:
	if fly_kick_animation == null or not is_instance_valid(fly_kick_animation):
		return
	if image != null and is_instance_valid(image) and image is Sprite2D:
		fly_kick_animation.flip_h = (image as Sprite2D).flip_h
	elif absf(_fly_kick_direction.x) > 0.001:
		fly_kick_animation.flip_h = _fly_kick_direction.x > 0.0


func _resolve_fly_kick_dash_frame_index() -> int:
	if fly_kick_animation == null or fly_kick_animation.sprite_frames == null:
		return 0
	var frames:SpriteFrames = fly_kick_animation.sprite_frames
	if not frames.has_animation(FLY_KICK_ANIMATION):
		return 0
	var fallback:int = maxi(frames.get_frame_count(FLY_KICK_ANIMATION) - 1,0)
	for index:int in range(frames.get_frame_count(FLY_KICK_ANIMATION)):
		var texture:Texture2D = frames.get_frame_texture(FLY_KICK_ANIMATION,index)
		if texture == null:
			continue
		var file_stem:String = texture.resource_path.get_file().get_basename()
		if not file_stem.begins_with("frame_"):
			continue
		var number_text:String = file_stem.substr(6)
		if not number_text.is_valid_int():
			continue
		var frame_number:int = number_text.to_int()
		if frame_number == FLY_KICK_START_FRAME_NUMBER:
			return index
		if frame_number > FLY_KICK_START_FRAME_NUMBER:
			fallback = mini(fallback,index)
	return fallback


func _play_penguin_audio(kind:int,loop_audio:bool = false,randomize:bool = false) -> void:
	if multiplayer.has_multiplayer_peer():
		_remote_play_penguin_audio.rpc(kind,loop_audio,randomize)
	else:
		_play_penguin_audio_local(kind,loop_audio,randomize)


@rpc("authority","call_local","reliable")
func _remote_play_penguin_audio(kind:int,loop_audio:bool,randomize:bool) -> void:
	_play_penguin_audio_local(kind,loop_audio,randomize)


func _play_penguin_audio_local(kind:int,loop_audio:bool,randomize:bool) -> void:
	if health <= 0 or is_queued_for_deletion():
		return
	var stream:AudioStream = null
	match kind:
		PenguinAudio.THROW:
			stream = THROW_AUDIO
		PenguinAudio.PICKUP_1:
			stream = PICKUP_AUDIO[0]
		PenguinAudio.PICKUP_2:
			stream = PICKUP_AUDIO[1]
		PenguinAudio.PICKUP_3:
			stream = PICKUP_AUDIO[2]
		PenguinAudio.PICKUP_4:
			stream = PICKUP_AUDIO[3]
		PenguinAudio.PICKUP_5:
			stream = PICKUP_AUDIO[4]
		PenguinAudio.ASSIMILATE:
			stream = ASSIMILATION_AUDIO
		PenguinAudio.VICTORY:
			stream = VICTORY_AUDIO
		PenguinAudio.FLY_KICK:
			stream = FLY_KICK_AUDIO
	if stream == null:
		return

	# 胜利音乐用 MP3 自己的 loop 属性循环；Godot 对循环流不会发 finished，
	# 所以它会一直挂在角色下面，直到角色删除时由 _stop_all_penguin_audio_local 停掉。
	var playback_stream:AudioStream = stream
	if loop_audio and stream is AudioStreamMP3:
		var duplicated:AudioStreamMP3 = (stream.duplicate() as AudioStreamMP3)
		if duplicated != null:
			duplicated.loop = true
			playback_stream = duplicated

	if kind == PenguinAudio.VICTORY and _victory_audio_player != null and is_instance_valid(_victory_audio_player):
		if not _victory_audio_player.playing:
			_victory_audio_player.play()
		return

	var player:AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = playback_stream
	player.name = "CouPenguinOwnedAudio"
	if kind == PenguinAudio.THROW:
		# 与 Audios/Sfx/KnifeThrow1 的原项目模板参数一致。
		player.volume_db = -10.0
		player.pitch_scale = 1.2
	elif kind == PenguinAudio.FLY_KICK:
		player.volume_db = -2.0
	if randomize:
		player.pitch_scale *= randf_range(0.94,1.06)
	add_child(player)
	_owned_audio_players.append(player)
	if kind == PenguinAudio.VICTORY:
		_victory_audio_player = player
	if not loop_audio:
		player.finished.connect(func() -> void:
			_owned_audio_players.erase(player)
			if _victory_audio_player == player:
				_victory_audio_player = null
			if is_instance_valid(player):
				player.queue_free()
		)
	player.play()


func _stop_all_penguin_audio_sync() -> void:
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_stop_penguin_audio.rpc()
	else:
		_stop_all_penguin_audio_local()


@rpc("authority","call_local","reliable")
func _remote_stop_penguin_audio() -> void:
	_stop_all_penguin_audio_local()


func _stop_all_penguin_audio_local() -> void:
	for player:AudioStreamPlayer in _owned_audio_players.duplicate():
		if player != null and is_instance_valid(player):
			player.stop()
			player.queue_free()
	_owned_audio_players.clear()
	_victory_audio_player = null


func _resolve_live_ball(id:int) -> ball:
	if id <= 0 or not is_instance_id_valid(id):
		return null
	var obj:Object = instance_from_id(id)
	if not is_instance_valid(obj) or not (obj is ball):
		return null
	var result:ball = obj as ball
	if result.health <= 0 or result.is_queued_for_deletion():
		return null
	return result


func _sync_assimilation_size_to_normal() -> void:
	if assimilation_animation == null or image == null or not (image is Sprite2D):
		return
	var normal_sprite:Sprite2D = image as Sprite2D
	if normal_sprite.texture == null or assimilation_animation.sprite_frames == null:
		return

	# CharacterAutoFit 会先把普通图缩到统一人物高度。动画不再使用写死的独立倍率，
	# 而是读取普通图最终显示高度，再按动画帧原始高度算同样的屏幕高度。
	var target_height:float = float(normal_sprite.texture.get_height()) * absf(normal_sprite.scale.y)
	var source_height:float = 0.0
	var frames:SpriteFrames = assimilation_animation.sprite_frames
	if frames.has_animation(&"assimilate"):
		for index:int in range(frames.get_frame_count(&"assimilate")):
			var texture:Texture2D = frames.get_frame_texture(&"assimilate",index)
			if texture != null:
				source_height = maxf(source_height,float(texture.get_height()))
	if source_height <= 0.0 or target_height <= 0.0:
		return
	var fit_scale:float = target_height / source_height
	assimilation_animation.scale = Vector2(fit_scale,fit_scale)
	assimilation_animation.position = normal_sprite.position
	assimilation_animation.centered = true
	assimilation_animation.offset = Vector2.ZERO


func _sync_fly_kick_size_to_normal() -> void:
	if fly_kick_animation == null or image == null or not (image is Sprite2D):
		return
	var normal_sprite:Sprite2D = image as Sprite2D
	if normal_sprite.texture == null or fly_kick_animation.sprite_frames == null:
		return
	var target_height:float = float(normal_sprite.texture.get_height()) * absf(normal_sprite.scale.y)
	var source_height:float = 0.0
	var frames:SpriteFrames = fly_kick_animation.sprite_frames
	if frames.has_animation(FLY_KICK_ANIMATION):
		for index:int in range(frames.get_frame_count(FLY_KICK_ANIMATION)):
			var texture:Texture2D = frames.get_frame_texture(FLY_KICK_ANIMATION,index)
			if texture != null:
				source_height = maxf(source_height,float(texture.get_height()))
	if source_height <= 0.0 or target_height <= 0.0:
		return
	var fit_scale:float = target_height / source_height
	fly_kick_animation.scale = Vector2(fit_scale,fit_scale)
	fly_kick_animation.position = normal_sprite.position
	fly_kick_animation.centered = true
	fly_kick_animation.offset = Vector2.ZERO


func _set_has_rock_visual(value:bool) -> void:
	if held_rock != null:
		held_rock.visible = value and not _assimilating and not _victory_dancing and not _fly_kick_sequence_active


func _set_assimilation_visual(active:bool) -> void:
	_sync_assimilation_size_to_normal()
	if image != null and is_instance_valid(image):
		image.visible = not active and not _fly_kick_sequence_active
	_set_has_rock_visual(has_rock)
	if assimilation_animation == null:
		return
	assimilation_animation.visible = active
	if active:
		assimilation_animation.play(&"assimilate")
	else:
		assimilation_animation.stop()
		assimilation_animation.frame = 0


func _sync_has_rock_visual(value:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_remote_set_has_rock_visual.rpc(value)


func _sync_assimilation_visual(active:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_remote_set_assimilation_visual.rpc(active)


func _sync_victory_dance(active:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_remote_set_victory_dance.rpc(active)


@rpc("authority","call_remote","reliable")
func _remote_set_has_rock_visual(value:bool) -> void:
	has_rock = value
	_set_has_rock_visual(value)


@rpc("authority","call_remote","reliable")
func _remote_set_assimilation_visual(active:bool) -> void:
	_assimilating = active
	_set_assimilation_visual(active)


@rpc("authority","call_remote","reliable")
func _remote_set_victory_dance(active:bool) -> void:
	_victory_dancing = active
	if active:
		_assimilating = false
	_set_assimilation_visual(active)
