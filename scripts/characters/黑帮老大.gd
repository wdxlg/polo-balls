extends ball

const MINION_SCENE:PackedScene = preload("res://scenes/creatures/投稿随从.tscn")
const MINION_SCRIPT = preload("res://scripts/creatures/投稿随从.gd")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const BOSS_NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮老大_普通状态.png")
const BOSS_CALL_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮老大_喊人状态.png")
const BOSS_MONEY_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮老大_扔钱状态.png")
const BOSS_SHOOT_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮老大_开枪状态.png")
const BOSS_BULLET_SCENE:PackedScene = preload("res://scenes/shooter/子弹.tscn")
const MONEY_THROW_SCRIPT = preload("res://scripts/effects/黑帮老大_扔钱.gd")
const GANG_THROW_MONEY_SFX:AudioStream = preload("res://audio/characters/黑帮老大/扔钱.mp3")
const GANG_BUYOUT_SFX:AudioStream = preload("res://audio/characters/黑帮老大/收购.mp3")
const GANG_WHISTLE_SFX_1:AudioStream = preload("res://audio/characters/黑帮老大/吹哨1.mp3")
const GANG_WHISTLE_SFX_2:AudioStream = preload("res://audio/characters/黑帮老大/吹哨2.mp3")
const GANG_WHISTLE_SFX_3:AudioStream = preload("res://audio/characters/黑帮老大/吹哨3.mp3")

const GANG_SFX_THROW_MONEY:int = 0
const GANG_SFX_BUYOUT:int = 1
const GANG_SFX_WHISTLE_1:int = 2
const GANG_SFX_WHISTLE_2:int = 3
const GANG_SFX_WHISTLE_3:int = 4

@export_category("黑帮老大 - 手枪")
@export_range(0.0,10.0,0.05) var ranged_damage_multiplier:float = 2.0
@export_range(1.0,10.0,0.1) var ranged_attack_interval:float = 3.8
@export_range(100.0,1000.0,10.0) var ranged_attack_range:float = 520.0
@export_range(100.0,1200.0,10.0) var ranged_bullet_speed:float = 430.0
@export_range(0.1,2.0,0.05) var shoot_pose_duration:float = 0.55

@export_category("黑帮老大 - 小弟")
@export_range(1,8,1) var initial_minion_count:int = 2
@export_range(1,12,1) var max_minions:int = 4
@export_range(1.0,30.0,0.5) var summon_interval:float = 10.0
@export_range(0.1,2.0,0.05) var call_pose_duration:float = 0.75

@export_category("黑帮老大 - 扔钱")
@export_range(1.0,30.0,0.5) var money_interval:float = 6.0
@export_range(0.2,2.0,0.05) var money_flight_time:float = 0.70
@export_range(10.0,180.0,5.0) var money_arc_height:float = 72.0
@export_range(0.1,2.0,0.05) var money_pose_duration:float = 0.70

# 召唤物会自行死亡/跑路，必须只保存 WeakRef。
var _owned:Array[WeakRef] = []
var _pose_token:int = 0
var _attack_elapsed:float = 0.0
var _attack_busy:bool = false
var _summon_elapsed:float = 0.0
var _money_elapsed:float = 0.0
var _initial_spawn_done:bool = false

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	super._ready()
	if self_hitbox != null:
		self_hitbox.monitoring = false
	call_deferred("_spawn_initial_group")

func _spawn_initial_group() -> void:
	if _initial_spawn_done or not is_instance_valid(self) or health <= 0:
		return
	if not is_multiplayer_authority():
		return
	_initial_spawn_done = true
	var count:int = mini(initial_minion_count,max_minions)
	if count <= 0:
		return
	_show_pose(BOSS_CALL_TEXTURE,call_pose_duration)
	_spawn_group(MINION_SCRIPT.Kind.GANG_NORMAL,count)

func _process(delta:float) -> void:
	_prune_owned()
	if not is_multiplayer_authority() or health <= 0:
		return

	# 每 10 秒检查一次是否能补 1 名普通小弟，总人数最多 4。
	_summon_elapsed += delta
	if not is_player_controlled() and _summon_elapsed >= summon_interval:
		_summon_elapsed = fmod(_summon_elapsed,maxf(summon_interval,0.01))
		if _gang_minion_count() < max_minions:
			_show_pose(BOSS_CALL_TEXTURE,call_pose_duration)
			_spawn_group(MINION_SCRIPT.Kind.GANG_NORMAL,1)

	# 每隔一段时间尝试给一个普通小弟扔钱；没有普通小弟时本轮什么都不做。
	_money_elapsed += delta
	if not is_player_controlled() and _money_elapsed >= money_interval:
		_money_elapsed = fmod(_money_elapsed,maxf(money_interval,0.01))
		var ordinary:ball = _pick_money_target()
		if ordinary != null:
			_throw_money_to(ordinary)

	_attack_elapsed += delta
	if not is_player_controlled() and not _attack_busy and _attack_elapsed >= ranged_attack_interval:
		var target:ball = TOOLS.nearest_enemy(self,ranged_attack_range)
		if target != null and is_instance_valid(target):
			_attack_elapsed = 0.0
			_begin_ranged_attack(target)


func controlled_attack_action() -> void:
	# 左键：鼠标瞄准开枪，沿用原射击间隔与起手动画。
	if not _can_use_manual_gang_action() or _attack_busy or _attack_elapsed < ranged_attack_interval or not has_player_control_aim():
		return
	_attack_elapsed = 0.0
	_attack_busy = true
	_show_pose(BOSS_SHOOT_TEXTURE,shoot_pose_duration)
	_fire_after_manual_windup(player_control_aim_world_position())


func controlled_skill_action() -> void:
	# 右键：呼叫一名普通小弟；开局固定的小弟仍属出生初始化。
	if not _can_use_manual_gang_action() or _summon_elapsed < summon_interval or _gang_minion_count() >= max_minions:
		return
	_summon_elapsed = 0.0
	_show_pose(BOSS_CALL_TEXTURE,call_pose_duration)
	_spawn_group(MINION_SCRIPT.Kind.GANG_NORMAL,1)


func player_control_extra_actions() -> Array[StringName]:
	return [&"controlled_money_action"]


func controlled_money_action() -> void:
	# 中键：给现有普通小弟扔钱升级，不在无小弟时消耗冷却。
	if not _can_use_manual_gang_action() or _money_elapsed < money_interval:
		return
	var ordinary:Array[ball] = _ordinary_minions()
	if ordinary.is_empty():
		return
	var chosen:ball = ordinary[0]
	var aim:Vector2 = player_control_aim_world_position(global_position)
	for minion:ball in ordinary:
		if minion.global_position.distance_squared_to(aim) < chosen.global_position.distance_squared_to(aim):
			chosen = minion
	_money_elapsed = 0.0
	_throw_money_to(chosen)


func _can_use_manual_gang_action() -> bool:
	return is_player_controlled() and is_multiplayer_authority() and health > 0 and is_combat_runtime_active()

func _set_boss_texture(texture:Texture2D) -> void:
	if not image is Sprite2D or texture == null:
		return
	(image as Sprite2D).texture = texture
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		fitter.call_deferred("apply_visual_fit_only")

func _show_pose(texture:Texture2D,duration:float) -> void:
	_pose_token += 1
	var token:int = _pose_token
	_set_boss_texture(texture)
	_restore_pose_after(token,maxf(duration,0.05))

func _restore_pose_after(token:int,duration:float) -> void:
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(self) or health <= 0:
		return
	if token != _pose_token:
		return
	_set_boss_texture(BOSS_NORMAL_TEXTURE)

func _spawn_group(kind_value:int,count:int) -> void:
	var available:int = maxi(max_minions - _gang_minion_count(),0)
	var actual_count:int = mini(count,available)
	if actual_count <= 0:
		return
	_play_random_summon_whistle()
	for i:int in range(actual_count):
		_spawn_one(kind_value,i,actual_count)

func _spawn_one(kind_value:int,index:int,count:int) -> void:
	var minion:ball = MINION_SCENE.instantiate() as ball
	if minion == null:
		return
	minion.Master = self
	minion.Master_name = name
	minion.Team = Team
	minion.inherit_master_attack_power = true
	minion.Target_Enemy = Target_Enemy
	minion.set("kind",kind_value)
	minion.name = Game.return_random_name(minion)
	var angle:float = TAU * float(index) / maxf(float(count),1.0) + randf_range(-0.25,0.25)
	var point:Vector2 = TOOLS.safe_spawn_position(self,global_position + Vector2.from_angle(angle) * randf_range(40.0,72.0),22.0)
	get_tree().current_scene.add_child(minion,true)
	minion.global_position = point
	_owned.append(weakref(minion))

func _owned_balls() -> Array[ball]:
	var alive:Array[ball] = []
	var kept:Array[WeakRef] = []
	for ref:WeakRef in _owned:
		if ref == null:
			continue
		var raw:Variant = ref.get_ref()
		if raw is ball:
			var minion:ball = raw as ball
			if is_instance_valid(minion) and not minion.is_queued_for_deletion():
				alive.append(minion)
				kept.append(ref)
	_owned = kept
	return alive

func _gang_minion_count() -> int:
	var count:int = 0
	for minion:ball in _owned_balls():
		if minion.health <= 0:
			continue
		var k:int = int(minion.get("kind"))
		if k == MINION_SCRIPT.Kind.GANG_NORMAL or k == MINION_SCRIPT.Kind.GANG_GUN:
			count += 1
	return count

func _ordinary_minions() -> Array[ball]:
	var result:Array[ball] = []
	for minion:ball in _owned_balls():
		if minion.health <= 0 or int(minion.get("kind")) != MINION_SCRIPT.Kind.GANG_NORMAL:
			continue
		if minion.has_method("is_gang_normal_available_for_money") and not bool(minion.call("is_gang_normal_available_for_money")):
			continue
		result.append(minion)
	return result

func _pick_money_target() -> ball:
	var ordinary:Array[ball] = _ordinary_minions()
	if ordinary.is_empty():
		return null
	# 优先给离老大最近的普通小弟，钱的抛物线更容易看清。
	var best:ball = ordinary[0]
	var best_d:float = global_position.distance_squared_to(best.global_position)
	for i:int in range(1,ordinary.size()):
		var candidate:ball = ordinary[i]
		var d:float = global_position.distance_squared_to(candidate.global_position)
		if d < best_d:
			best = candidate
			best_d = d
	return best

func _throw_money_to(minion:ball) -> void:
	if minion == null or not is_instance_valid(minion):
		return
	if minion.has_method("set_money_pending"):
		minion.call("set_money_pending",true)
	_show_pose(BOSS_MONEY_TEXTURE,money_pose_duration)
	var world:Node = get_tree().current_scene
	if world == null:
		if minion.has_method("set_money_pending"):
			minion.call("set_money_pending",false)
		return
	var money:Node2D = MONEY_THROW_SCRIPT.new() as Node2D
	if money == null:
		return
	world.add_child(money)
	money.call("setup",self,minion,global_position,money_flight_time,money_arc_height)
	_play_gang_sfx_everywhere(GANG_SFX_THROW_MONEY,global_position,1.5,1.0)

func _on_gang_money_arrived(minion:ball) -> void:
	if minion == null or not is_instance_valid(minion) or minion.health <= 0:
		return
	if minion.has_method("can_receive_gang_money") and not bool(minion.call("can_receive_gang_money")):
		if minion.has_method("set_money_pending"):
			minion.call("set_money_pending",false)
		return
	if int(minion.get("kind")) != MINION_SCRIPT.Kind.GANG_NORMAL:
		if minion.has_method("set_money_pending"):
			minion.call("set_money_pending",false)
		return
	minion.call("upgrade_to",MINION_SCRIPT.Kind.GANG_GUN)
	minion.health = minion.Max_health
	_play_gang_sfx_everywhere(GANG_SFX_BUYOUT,minion.global_position,-1.0,1.0)
	if minion.has_method("set_money_pending"):
		minion.call("set_money_pending",false)

func _flee_all_normal_minions() -> void:
	for minion:ball in _owned_balls():
		if minion.health <= 0 or int(minion.get("kind")) != MINION_SCRIPT.Kind.GANG_NORMAL:
			continue
		if minion.has_method("begin_gang_flee"):
			minion.call("begin_gang_flee")

func _prune_owned() -> void:
	_owned_balls()

func _begin_ranged_attack(target:ball) -> void:
	if _attack_busy or target == null or not is_instance_valid(target):
		return
	_attack_busy = true
	_show_pose(BOSS_SHOOT_TEXTURE,shoot_pose_duration)
	_fire_after_short_windup(weakref(target))

func _fire_after_short_windup(target_ref:WeakRef) -> void:
	await get_tree().create_timer(0.10).timeout
	if not is_instance_valid(self) or health <= 0:
		return
	var raw:Variant = target_ref.get_ref() if target_ref != null else null
	if raw is ball:
		var target:ball = raw as ball
		if is_instance_valid(target) and target.health > 0 and TOOLS.is_enemy(self,target):
			_fire_bullet(target)
	await get_tree().create_timer(maxf(shoot_pose_duration - 0.10,0.05)).timeout
	if is_instance_valid(self):
		_attack_busy = false

func _fire_after_manual_windup(aim:Vector2) -> void:
	await get_tree().create_timer(0.10).timeout
	if is_instance_valid(self) and _can_use_manual_gang_action():
		_fire_bullet_toward(aim)
	await get_tree().create_timer(maxf(shoot_pose_duration - 0.10,0.05)).timeout
	if is_instance_valid(self):
		_attack_busy = false

func _fire_bullet(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	_fire_bullet_toward(combat_target_position(target))

func _fire_bullet_toward(aim:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var projectile:ball = BOSS_BULLET_SCENE.instantiate() as ball
	if projectile == null:
		return
	var dir:Vector2 = aim - global_position
	if dir.length_squared() <= 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	projectile.set_collision_layer_value(2,false)
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Damage = maxi(int(round(attack_damage(ranged_damage_multiplier))),0)
	projectile.Speed = ranged_bullet_speed
	projectile.global_position = global_position + dir * 24.0
	projectile.global_rotation = projectile.Default_Rotation + dir.angle()
	projectile.direction = dir
	projectile.name = Game.return_random_name(projectile)
	world.add_child(projectile,true)
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("G18单发",{},true,true)
	else:
		Audios.play_sfx("G18单发",{},true,true)

func _play_random_summon_whistle() -> void:
	var pick:int = randi_range(GANG_SFX_WHISTLE_1,GANG_SFX_WHISTLE_3)
	_play_gang_sfx_everywhere(pick,global_position,-3.0,randf_range(0.98,1.02))


func _play_gang_sfx_everywhere(kind_value:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_gang_sfx.rpc(kind_value,position_value,volume_db,pitch)
	else:
		_rpc_play_gang_sfx(kind_value,position_value,volume_db,pitch)


@rpc("authority","call_local","unreliable")
func _rpc_play_gang_sfx(kind_value:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	var stream:AudioStream = null
	match kind_value:
		GANG_SFX_THROW_MONEY:
			stream = GANG_THROW_MONEY_SFX
		GANG_SFX_BUYOUT:
			stream = GANG_BUYOUT_SFX
		GANG_SFX_WHISTLE_1:
			stream = GANG_WHISTLE_SFX_1
		GANG_SFX_WHISTLE_2:
			stream = GANG_WHISTLE_SFX_2
		GANG_SFX_WHISTLE_3:
			stream = GANG_WHISTLE_SFX_3
		_:
			return
	_play_gang_stream(stream,position_value,volume_db,pitch)


func _play_gang_stream(stream:AudioStream,position_value:Vector2,volume_db:float,pitch:float) -> void:
	if stream == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = 1500.0
	player.attenuation = 0.45
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func Die() -> void:
	# 老大死亡：只有普通小弟跑路。已经拿枪的小弟永不跑路，也不跟着老大死亡。
	_flee_all_normal_minions()
	_owned.clear()
	super()
	queue_free()
