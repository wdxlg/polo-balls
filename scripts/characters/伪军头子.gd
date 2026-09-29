extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const SOLDIER_SCENE:PackedScene = preload("res://scenes/creatures/伪军.tscn")
const MONEY_SUMMON_SFX:AudioStream = preload("res://audio/characters/黑帮老大/收购.mp3")
const SOLDIER_HARD_CAP:int = 3

@export_category("伪军头子 - 动员")
@export_range(0,3,1) var reinforcement_cap:int = 3
@export_range(0.2,10.0,0.1) var spawn_rate_hz:float = 2.0
@export_range(0.0,5.0,0.1) var initial_recruit_delay:float = 0.6
@export_range(10.0,100.0,5.0) var health_step:float = 50.0
@export_range(16.0,120.0,2.0) var spawn_forward_distance:float = 42.0
@export_range(8.0,80.0,2.0) var spawn_side_spacing:float = 24.0

@export_category("伪军头子 - 钞票")
@export_range(1,3,1) var money_max:int = 3
@export_range(0.0,3.0,0.25) var initial_money:float = 2.0
@export_range(0.5,30.0,0.25) var money_recharge_seconds:float = 6.0
@export_range(-24.0,12.0,0.5) var summon_sfx_volume_db:float = -2.0

@onready var money_ui:Node = $MoneyUI

var money_value:float = 2.0
var _spawn_cooldown_left:float = 0.0
var _money_sync_left:float = 0.0
var _next_health_threshold:float = 0.0
var _surrender_started:bool = false
# V133：碰撞/受击回调里不能立刻把带 Area2D 的伪军 add_child 到物理世界。
# 先预留兵力名额，再 deferred 真正入树，防止同一帧多次请求突破 3 人硬上限。
var _pending_reinforcement_spawns:int = 0

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	super._ready()
	add_to_group("FakeArmyBoss")
	reinforcement_cap = clampi(reinforcement_cap,0,SOLDIER_HARD_CAP)
	_next_health_threshold = maxf(float(Max_health) - health_step,0.0)
	money_value = clampf(initial_money,0.0,float(maxi(money_max,1)))
	_spawn_cooldown_left = maxf(initial_recruit_delay,0.0)
	_update_money_ui()

func is_fake_army_boss() -> bool:
	return true

func _physics_process(delta:float) -> void:
	if health <= 0 or _surrender_started:
		return
	if not is_combat_runtime_active():
		_spawn_cooldown_left = maxf(initial_recruit_delay,0.0)
		return

	# 钞票是连续资源：没攒满时从当前那一张底部向上缓慢恢复。
	if is_multiplayer_authority():
		if money_value < float(maxi(money_max,1)):
			money_value = minf(float(maxi(money_max,1)),money_value + delta / maxf(money_recharge_seconds,0.01))
		_money_sync_left = maxf(_money_sync_left - delta,0.0)
		if _money_sync_left <= 0.0:
			_sync_money_to_remotes()
	_update_money_ui()

	if not is_multiplayer_authority():
		return
	_spawn_cooldown_left = maxf(_spawn_cooldown_left - delta,0.0)
	if not is_player_controlled():
		_try_recruit_soldier()


func controlled_attack_action() -> void:
	# 左键：消耗一张钞票动员一名伪军；掉血触发的增援属于被动，保持不变。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or _surrender_started or not is_combat_runtime_active():
		return
	_try_recruit_soldier()


func _try_recruit_soldier() -> void:
	if _count_my_soldiers_reserved() < _effective_reinforcement_cap() and money_value >= 1.0 and _spawn_cooldown_left <= 0.0:
		if _spend_money_and_spawn(0):
			_spawn_cooldown_left = 1.0 / maxf(spawn_rate_hz,0.01)

func on_actual_health_damage_received(_actual_health_damage:float,_health_before:float) -> void:
	if not is_multiplayer_authority() or _surrender_started:
		return
	while _next_health_threshold > 0.0 and float(health) <= _next_health_threshold:
		# 原机制“掉50血立即来2兵”保留，但总兵力硬上限固定为 3。
		_grant_money(2.0)
		_spend_money_and_spawn(-1)
		_spend_money_and_spawn(1)
		_next_health_threshold -= maxf(health_step,1.0)

func _grant_money(amount:float) -> void:
	money_value = clampf(money_value + maxf(amount,0.0),0.0,float(maxi(money_max,1)))
	_update_money_ui()
	_sync_money_to_remotes(true)

func _spend_money_and_spawn(side_index:int) -> bool:
	if money_value < 1.0:
		return false
	if not _spawn_one(side_index):
		return false
	money_value = maxf(money_value - 1.0,0.0)
	_update_money_ui()
	_sync_money_to_remotes(true)
	_play_summon_money_sfx_everywhere(global_position)
	return true

func _update_money_ui() -> void:
	if money_ui != null and is_instance_valid(money_ui) and money_ui.has_method("set_money"):
		money_ui.call("set_money",money_value,maxi(money_max,1))


func _sync_money_to_remotes(force:bool = false) -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return
	if not force and _money_sync_left > 0.0:
		return
	_money_sync_left = 0.12
	_rpc_sync_money_value.rpc(money_value)

@rpc("authority","call_remote","unreliable")
func _rpc_sync_money_value(value:float) -> void:
	money_value = clampf(value,0.0,float(maxi(money_max,1)))
	_update_money_ui()


func _effective_reinforcement_cap() -> int:
	return clampi(reinforcement_cap,0,SOLDIER_HARD_CAP)

func _count_my_soldiers() -> int:
	var count:int = 0
	for node:Node in get_tree().get_nodes_in_group("FakeArmySoldier"):
		if not node is ball:
			continue
		var soldier:ball = node as ball
		if soldier.health <= 0:
			continue
		if soldier.get("owner_head") == self:
			count += 1
	return count


func _count_my_soldiers_reserved() -> int:
	return _count_my_soldiers() + maxi(_pending_reinforcement_spawns,0)


func _spawn_one(side_index:int) -> bool:
	if _count_my_soldiers_reserved() >= _effective_reinforcement_cap():
		return false
	if not is_inside_tree() or SOLDIER_SCENE == null or get_tree().current_scene == null:
		return false

	# 可能从 Hurtbox/Hitbox 的 area_entered / area_shape_entered 伤害链调用到这里。
	# 此时 PhysicsServer2D 正在 flush queries，直接 add_child() 会让新伪军的 Area2D
	# 在查询回调内部进入监测状态。这里只预留名额，真正入树放到 deferred 阶段。
	_pending_reinforcement_spawns += 1
	call_deferred("_spawn_one_deferred",side_index)
	return true


func _spawn_one_deferred(side_index:int) -> void:
	_pending_reinforcement_spawns = maxi(_pending_reinforcement_spawns - 1,0)
	# 头子已经死亡/开始撤退时，取消物理回调里排队的迟到增援，避免死后又凭空刷出一名伪军。
	if _surrender_started or health <= 0:
		return
	if not is_inside_tree() or SOLDIER_SCENE == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	if _count_my_soldiers() >= _effective_reinforcement_cap():
		# 名额在 deferred 前被其它来源占用时，把本次已经扣掉的 1 张钞票退回。
		_grant_money(1.0)
		return

	var soldier:ball = SOLDIER_SCENE.instantiate() as ball
	if soldier == null:
		_grant_money(1.0)
		return
	var facing:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var side:Vector2 = Vector2(-facing.y,facing.x)
	var desired:Vector2 = global_position + facing * spawn_forward_distance + side * float(side_index) * spawn_side_spacing
	soldier.Master = self
	soldier.Master_name = str(get_path())
	soldier.Team = Team
	soldier.inherit_master_attack_power = true
	soldier.master_attack_damage_multiplier = 1.0
	soldier.direction = facing
	soldier.set("owner_head",self)
	soldier.name = Game.return_random_name(soldier)
	world.add_child(soldier,true)
	soldier.global_position = TOOLS.safe_spawn_position(self,desired,18.0)

func _play_summon_money_sfx_everywhere(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_summon_money_sfx.rpc(position_value)
	else:
		_rpc_play_summon_money_sfx(position_value)

@rpc("authority","call_local","unreliable")
func _rpc_play_summon_money_sfx(position_value:Vector2) -> void:
	if MONEY_SUMMON_SFX == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = MONEY_SUMMON_SFX
	player.volume_db = summon_sfx_volume_db
	player.max_distance = 1500.0
	player.attenuation = 0.45
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free)
	player.play()

func Die() -> void:
	if _surrender_started:
		return
	_surrender_started = true
	# V137：头子死亡时，小弟不再 health=0 瞬间消失。
	# 优先调用新的跑路入口：停止攻击、复用黑帮老大“跑路了兄弟”音效、朝最近地图边界逃走。
	for node:Node in get_tree().get_nodes_in_group("FakeArmySoldier"):
		if node == null or not is_instance_valid(node) or node.get("owner_head") != self:
			continue
		if node.has_method("begin_fake_army_flee_from_head_death"):
			node.call("begin_fake_army_flee_from_head_death")
		elif node.has_method("force_surrender"):
			# 兼容旧伪军脚本；V137 的 force_surrender() 本身也会转到跑路逻辑。
			node.call("force_surrender")
	super()
