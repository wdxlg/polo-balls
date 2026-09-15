extends ball

const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const DICE_VISUAL_SCRIPT = preload("res://scripts/effects/投稿/掷骰子视觉.gd")

const NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/投稿/掷骰子的人/人物_01_普通状态.png")
const THROW_TEXTURE:Texture2D = preload("res://Images/characters/投稿/掷骰子的人/人物_02_掷骰子状态.png")
const WAIT_TEXTURE:Texture2D = preload("res://Images/characters/投稿/掷骰子的人/人物_03_搓手等待状态.png")

const BASE_MAX_HEALTH:int = 400
const HEALTH_WARNING_LINE:float = 250.0
const PERIODIC_ROLL_INTERVAL:float = 10.0
const HALF_HEALTH_RATIO:float = 0.5
const SPECIAL_SEVEN_CHANCE:float = 0.001
const MAX_WEAPONS:int = 2
const ROLL_ANIMATION_TIME:float = 0.62
const REROLL_GAP:float = 0.16
const OPENING_ROLL_DELAY:float = 0.72
const MAX_CHAIN_ROLLS:int = 48
const EXPLOSION_RADIUS:float = 190.0
const EXPLOSION_DAMAGE:float = 50.0

# 当前项目所有可直接作为远程攻击来源的 shooter 场景都进入随机池。
# 运行时仍会 ResourceLoader.exists() 二次过滤，因此用户本次没上传的资源不会被伪造。
const RANGED_WEAPON_SCENES = [
	"res://scenes/shooter/不坏煎饼弹.tscn",
	"res://scenes/shooter/伪军子弹.tscn",
	"res://scenes/shooter/军火商_子弹.tscn",
	"res://scenes/shooter/凑企鹅石头.tscn",
	"res://scenes/shooter/子弹.tscn",
	"res://scenes/shooter/建筑工人_砖块.tscn",
	"res://scenes/shooter/战争女神_火焰剑气.tscn",
	"res://scenes/shooter/数学老师公式弹.tscn",
	"res://scenes/shooter/时光客时钟.tscn",
	"res://scenes/shooter/炸弹客炸弹.tscn",
	"res://scenes/shooter/猎人_霰弹.tscn",
	"res://scenes/shooter/磁铁_电球.tscn",
	"res://scenes/shooter/科学家弹丸.tscn",
	"res://scenes/shooter/菊花茶水滴.tscn",
	"res://scenes/shooter/蛇咬.tscn",
	"res://scenes/shooter/裁判红牌.tscn",
	"res://scenes/shooter/裁判蓝牌.tscn",
	"res://scenes/shooter/裁判黄牌.tscn",
	"res://scenes/shooter/酒瓶.tscn",
	"res://scenes/shooter/键盘文字.tscn",
	"res://scenes/shooter/领导处分文件.tscn",
	"res://scenes/shooter/领导小领导.tscn",
	"res://scenes/shooter/魔角猎人_黑弹.tscn",
	"res://scenes/shooter/bee.tscn",
	"res://scenes/shooter/clown/clown_projectile.tscn",
	"res://scenes/shooter/clown_projectile.tscn",
	"res://scenes/shooter/knife.tscn",
]

@export_category("掷骰子")
@export_range(0.25,2.0,0.01) var roll_animation_time:float = ROLL_ANIMATION_TIME
@export_range(50.0,360.0,5.0) var explosion_radius:float = EXPLOSION_RADIUS
@export_range(1.0,500.0,1.0) var explosion_damage:float = EXPLOSION_DAMAGE
@export_range(0.2,4.0,0.05) var weapon_range_multiplier:float = 1.0
@export_range(0.25,4.0,0.05) var weapon_cooldown_multiplier:float = 1.0

var _rng := RandomNumberGenerator.new()
var _opening_roll_pending:bool = false
var _opening_roll_delay_left:float = OPENING_ROLL_DELAY
var _periodic_roll_cooldown_left:float = PERIODIC_ROLL_INTERVAL
var _periodic_roll_started:bool = false
var _half_health_roll_armed:bool = true
var _pending_rolls:int = 0
var _rolling:bool = false
var _health_locked_by_roll:bool = false
var _suppress_roll_trigger_depth:int = 0
var _allow_zero_death:bool = false
var _roll_serial:int = 0
var _roll_loop_deferred:bool = false
var _dice_visual:Node2D = null

var _weapon_paths:Array[String] = []
var _weapon_cooldowns:Array[float] = []
var _weapon_names:Array[String] = []

func get_health_threshold_values() -> PackedFloat32Array:
	# 继续复用 Health_bar 已有的阈值提示线系统。
	# V98 最大生命改为 400；半血投骰在 200，但用户指定的提示线仍固定在 250。
	return PackedFloat32Array([minf(HEALTH_WARNING_LINE,float(Max_health))])

func _ready() -> void:
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/人物/掷骰子的人.gd:_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	_setup_dice_visual()
	_restore_inherited_runtime_state()
	_set_character_pose_local("normal")

	_opening_roll_pending = not bool(get_meta(&"dice_skip_opening_roll",false))
	_opening_roll_delay_left = OPENING_ROLL_DELAY
	# 自我复制仍沿用 V96 的“不立刻连锁开局骰”；它从出生起正常等待 10 秒。
	_periodic_roll_started = not _opening_roll_pending
	_periodic_roll_cooldown_left = PERIODIC_ROLL_INTERVAL

func _restore_inherited_runtime_state() -> void:
	if has_meta(&"dice_initial_health"):
		var inherited_health:int = clampi(int(get_meta(&"dice_initial_health",Max_health)),0,Max_health)
		_suppress_roll_trigger_depth += 1
		health = inherited_health
		_suppress_roll_trigger_depth -= 1
	if has_meta(&"dice_weapon_paths"):
		var payload:Variant = get_meta(&"dice_weapon_paths")
		if payload is Array:
			for raw_path:Variant in payload:
				var path:String = str(raw_path)
				if _weapon_paths.size() >= MAX_WEAPONS:
					break
				if ResourceLoader.exists(path):
					_append_weapon(path)

func _setup_dice_visual() -> void:
	var existing:Node2D = get_node_or_null("DiceRollVisual") as Node2D
	if existing != null:
		_dice_visual = existing
		return
	var visual := Node2D.new()
	visual.name = "DiceRollVisual"
	visual.set_script(DICE_VISUAL_SCRIPT)
	visual.position = Vector2(48.0,42.0)
	visual.visible = false
	add_child(visual)
	_dice_visual = visual

func _physics_process(delta:float) -> void:
	if not is_multiplayer_authority():
		return
	if not is_combat_runtime_active():
		return

	# 治疗/点数 6 回到半血线以上后，半血事件重新武装。
	var half_health:float = float(Max_health) * HALF_HEALTH_RATIO
	if float(health) > half_health + 0.5:
		_half_health_roll_armed = true

	# 正在投骰时不计 10 秒，也不重复触发定时骰。
	if _rolling:
		return

	# “出生后投一次”的延迟只按真实战斗物理时间减少；SceneTree 暂停时
	# 默认不会调用 _physics_process，因此暂停时间天然不计入。
	if _opening_roll_pending:
		_opening_roll_delay_left = maxf(_opening_roll_delay_left - delta,0.0)
		if _opening_roll_delay_left <= 0.0 and health > 0:
			_opening_roll_pending = false
			_queue_roll(1)
		return

	if health <= 0:
		return

	if _periodic_roll_started:
		_periodic_roll_cooldown_left = maxf(_periodic_roll_cooldown_left - delta,0.0)
		if _periodic_roll_cooldown_left <= 0.0:
			# 先占住本轮定时触发，避免 call_deferred 真正进入 _rolling 前重复排队。
			_periodic_roll_cooldown_left = PERIODIC_ROLL_INTERVAL
			_queue_roll(1)
			return

	_tick_granted_weapons(delta)

func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	if _suppress_roll_trigger_depth > 0 or actual_health_damage <= 0.0:
		return

	var half_health:float = float(Max_health) * HALF_HEALTH_RATIO
	if (
		_half_health_roll_armed
		and health_before > half_health
		and float(health) <= half_health
	):
		# 正在投骰时如果跨过 250，按用户规则直接跳过这一次半血骰，
		# 不在当前骰结束后补投。
		_half_health_roll_armed = false
		if not _rolling:
			_queue_roll(1)

	# 0HP 是独立保命事件。正常伤害路径在投骰期间会被锁住；
	# 因此这里不会和“正在投骰时跳过 250”互相冲突。
	if health <= 0 and not _allow_zero_death and _pending_rolls <= 0 and not _rolling:
		_queue_roll(1)

func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _health_locked_by_roll:
		return
	super.take_damage(damage,ignore_block)

func receive_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block:bool = false,
	source:Node = null
) -> bool:
	if _health_locked_by_roll:
		return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)

func receive_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block:bool = false,
	raw_health:bool = false
) -> bool:
	if _health_locked_by_roll:
		return false
	return super.receive_spatial_damage(damage,damage_space,ignore_block,raw_health)

func get_next_state(state:State) -> int:
	if health <= 0 and not _allow_zero_death:
		if _pending_rolls <= 0 and not _rolling:
			_queue_roll(1)
		_schedule_roll_loop()
		return -1
	return super.get_next_state(state)

func _queue_roll(count:int = 1) -> void:
	if not is_multiplayer_authority() or _allow_zero_death:
		return
	_pending_rolls += maxi(count,0)
	_schedule_roll_loop()

func _schedule_roll_loop() -> void:
	if _rolling or _roll_loop_deferred or _pending_rolls <= 0:
		return
	_roll_loop_deferred = true
	call_deferred("_begin_roll_loop")

func _begin_roll_loop() -> void:
	_roll_loop_deferred = false
	if _rolling or _pending_rolls <= 0 or not is_inside_tree() or not is_multiplayer_authority():
		return
	_run_roll_loop()

func _run_roll_loop() -> void:
	_rolling = true
	_health_locked_by_roll = true
	set_meta(&"dice_health_locked",true)
	_allow_zero_death = false
	_roll_serial += 1
	var serial:int = _roll_serial
	var chain_count:int = 0

	while _pending_rolls > 0 and chain_count < MAX_CHAIN_ROLLS:
		if not _roll_sequence_valid(serial):
			break
		_pending_rolls -= 1
		chain_count += 1
		var result:int = _roll_result()
		_broadcast_roll_visual(result)
		await get_tree().create_timer(maxf(roll_animation_time,0.08),false).timeout
		if not _roll_sequence_valid(serial):
			break

		var reroll:bool = await _apply_roll_result(result)
		if not _roll_sequence_valid(serial):
			break
		if reroll:
			_pending_rolls += 1

		# 只有 1/6 的主动重投能继续给 0HP 角色争取 6；其它结果结算完仍是 0 就正式死亡。
		if health <= 0 and not reroll:
			_pending_rolls = 0
			_allow_zero_death = true
			break
		if _pending_rolls > 0:
			await get_tree().create_timer(REROLL_GAP,false).timeout

	_health_locked_by_roll = false
	if has_meta(&"dice_health_locked"):
		remove_meta(&"dice_health_locked")
	_rolling = false
	_broadcast_hide_dice_visual()
	# 每一整段投骰流程结束后才开始新的 10 秒冷却。
	_periodic_roll_started = true
	_periodic_roll_cooldown_left = PERIODIC_ROLL_INTERVAL
	if health <= 0:
		_allow_zero_death = true
		_schedule_zero_health_resolution()
	elif _pending_rolls > 0:
		_schedule_roll_loop()

func _roll_sequence_valid(serial:int) -> bool:
	return (
		is_instance_valid(self)
		and is_inside_tree()
		and is_multiplayer_authority()
		and serial == _roll_serial
	)

func _roll_result() -> int:
	if _rng.randf() < SPECIAL_SEVEN_CHANCE:
		return 7
	return _rng.randi_range(1,6)

func _apply_roll_result(result:int) -> bool:
	match result:
		1:
			_spawn_explosion_everywhere()
			_apply_internal_self_damage(explosion_damage)
			return true
		2:
			_apply_internal_self_damage(25.0)
			return false
		3:
			_clone_nearest_enemy_as_ally()
			return false
		4:
			_grant_random_ranged_weapon()
			return false
		5:
			_clone_self_with_weapons()
			return false
		6:
			_restore_to_full()
			return true
		7:
			_broadcast_seven_jackpot()
			await get_tree().create_timer(0.12,false).timeout
			_instant_kill_all_enemies()
			return false
	return false

func _apply_internal_self_damage(amount:float) -> void:
	if amount <= 0.0:
		return
	var before:float = float(health)
	_suppress_roll_trigger_depth += 1
	health -= int(round(amount))
	_suppress_roll_trigger_depth -= 1
	var actual:float = maxf(before - float(health),0.0)
	if actual > 0.0 and Game.has_method("report_combat_damage"):
		Game.report_combat_damage(self,self,actual,before)

func _restore_to_full() -> void:
	_allow_zero_death = false
	_suppress_roll_trigger_depth += 1
	Max_health = BASE_MAX_HEALTH
	health = BASE_MAX_HEALTH
	_suppress_roll_trigger_depth -= 1

func _spawn_explosion_everywhere() -> void:
	_broadcast_explosion_visual(global_position,maxf(explosion_radius,20.0))
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if target == self or target.health <= 0:
			continue
		if target.Type == Ball_Type.Shooter or target.Type == Ball_Type.Shooter_with_Health:
			continue
		if global_position.distance_squared_to(target.global_position) > explosion_radius * explosion_radius:
			continue
		target.receive_spatial_damage(
			explosion_damage,
			{"point":target.global_position,"source":self},
			true,
			true
		)

func _clone_nearest_enemy_as_ally() -> void:
	var enemy:ball = SUBMISSION_TOOLS.nearest_enemy(self)
	if enemy == null or not is_instance_valid(enemy):
		return
	var path:String = str(enemy.scene_file_path)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var packed:PackedScene = load(path) as PackedScene
	if packed == null:
		return
	var instance:Node = packed.instantiate()
	if not instance is ball:
		instance.queue_free()
		return
	var clone:ball = instance as ball
	var original_current_health:int = maxi(int(enemy.health),1)
	_apply_enemy_clone_stats(clone,enemy,original_current_health,false)
	clone.Master = self
	clone.Master_name = str(name)
	clone.Team = Team
	clone.set_meta(&"forced_combat_team",Team)
	clone.set_meta(&"dice_enemy_copy",true)
	_copy_victory_identity_to(clone)
	clone.global_position = SUBMISSION_TOOLS.safe_spawn_position(
		self,
		global_position + Vector2(_rng.randf_range(-46.0,46.0),_rng.randf_range(-46.0,46.0)),
		24.0
	)
	get_tree().current_scene.add_child(clone,true)
	# 某些角色会在 _ready() 里再次写入自己的基础属性；入树后再压一次，确保投稿规则最终成立。
	_apply_enemy_clone_stats(clone,enemy,original_current_health)
	clone.Master = self
	clone.Master_name = str(name)
	clone.Team = Team
	clone.set_meta(&"forced_combat_team",Team)

func _apply_enemy_clone_stats(clone:ball,enemy:ball,original_current_health:int,apply_current_health:bool = true) -> void:
	if clone == null or enemy == null:
		return
	var original_max_health:int = maxi(int(enemy.Max_health),1)
	clone.Max_health = maxi(int(ceil(float(original_max_health) / 3.0)),1)
	clone.Damage = maxi(int(ceil(float(maxi(enemy.Damage,0)) / 3.0)),0)
	# “除了速度都只有三分之一”按公共 ball 的基础战斗数值执行；Speed 唯一保持原值。
	clone.Speed = enemy.Speed
	clone.Attack_Cooling = maxf(enemy.Attack_Cooling / 3.0,0.01)
	clone.Skill_Cooling = maxf(enemy.Skill_Cooling / 3.0,0.01)
	clone.Health_Restore = maxi(int(ceil(float(maxi(enemy.Health_Restore,0)) / 3.0)),0)
	clone.Damage_reduction = enemy.Damage_reduction / 3.0
	clone.max_block = maxi(int(ceil(float(maxi(enemy.max_block,0)) / 3.0)),0)
	clone.max_energy = maxi(int(ceil(float(maxi(enemy.max_energy,0)) / 3.0)),0)
	if apply_current_health:
		clone.health = clampi(int(ceil(float(original_current_health) / 3.0)),1,clone.Max_health)
		# block/energy 的 setter 会通知 Health_Bar。某些特殊角色在复制时血条仍可能尚未
		# 完成 @onready 绑定，所以只有血条有效时才写当前值；上限已在上面安全写入。
		if clone.health_bar != null:
			if "block" in clone and "block" in enemy:
				clone.block = maxi(int(ceil(float(maxi(enemy.block,0)) / 3.0)),0)
			if "energy" in clone and "energy" in enemy:
				clone.energy = maxi(int(ceil(float(maxi(enemy.energy,0)) / 3.0)),0)
		# World 每帧会从 default_properties 恢复公共属性。复制完成后把 1/3 数值写成
		# 复制体自己的默认值，避免下一帧又跳回原角色场景数值。
		if clone.default_properties != null:
			clone.default_properties["Max_health"] = clone.Max_health
			clone.default_properties["Damage"] = clone.Damage
			clone.default_properties["Speed"] = clone.Speed
			clone.default_properties["Attack_Cooling"] = clone.Attack_Cooling
			clone.default_properties["Skill_Cooling"] = clone.Skill_Cooling
			clone.default_properties["Health_Restore"] = clone.Health_Restore
			clone.default_properties["Damage_reduction"] = clone.Damage_reduction
			clone.default_properties["max_block"] = clone.max_block
			clone.default_properties["max_energy"] = clone.max_energy

func _clone_self_with_weapons() -> void:
	var path:String = str(scene_file_path)
	if path.is_empty() or not ResourceLoader.exists(path):
		path = "res://scenes/characters/人物/掷骰子的人.tscn"
	if not ResourceLoader.exists(path):
		return
	var packed:PackedScene = load(path) as PackedScene
	if packed == null:
		return
	var instance:Node = packed.instantiate()
	if not instance is ball:
		instance.queue_free()
		return
	var clone:ball = instance as ball
	clone.Team = Team
	clone.Master = self
	clone.Master_name = str(name)
	clone.set_meta(&"forced_combat_team",Team)
	clone.set_meta(&"dice_skip_opening_roll",true)
	clone.set_meta(&"dice_initial_health",int(health))
	clone.set_meta(&"dice_weapon_paths",_weapon_paths.duplicate())
	clone.set_meta(&"dice_self_copy",true)
	_copy_victory_identity_to(clone)
	clone.global_position = SUBMISSION_TOOLS.safe_spawn_position(
		self,
		global_position + Vector2(_rng.randf_range(-54.0,54.0),_rng.randf_range(-54.0,54.0)),
		24.0
	)
	get_tree().current_scene.add_child(clone,true)

func _copy_victory_identity_to(target:ball) -> void:
	if target == null:
		return
	for key:StringName in [&"victory_side_key",&"battle_setup_id",&"continuation_side_key"]:
		if has_meta(key):
			target.set_meta(key,get_meta(key))

func _grant_random_ranged_weapon() -> void:
	if _weapon_paths.size() >= MAX_WEAPONS:
		return
	var available:Array[String] = []
	for raw_path:Variant in RANGED_WEAPON_SCENES:
		var path:String = str(raw_path)
		if ResourceLoader.exists(path) and not _weapon_paths.has(path):
			available.append(path)
	if available.is_empty():
		return
	var chosen:String = available[_rng.randi_range(0,available.size() - 1)]
	_append_weapon(chosen)
	_broadcast_weapon_update(_weapon_paths)

func _append_weapon(path:String) -> void:
	if _weapon_paths.size() >= MAX_WEAPONS:
		return
	_weapon_paths.append(path)
	_weapon_names.append(_pretty_weapon_name(path))
	_weapon_cooldowns.append(_rng.randf_range(0.12,0.38))

func _pretty_weapon_name(path:String) -> String:
	var file:String = path.get_file().get_basename()
	return file.replace("_"," ")

func _tick_granted_weapons(delta:float) -> void:
	if _weapon_paths.is_empty():
		return
	var target:ball = SUBMISSION_TOOLS.nearest_enemy(self,900.0 * weapon_range_multiplier)
	for i:int in range(_weapon_paths.size()):
		_weapon_cooldowns[i] = maxf(_weapon_cooldowns[i] - delta,0.0)
		if _weapon_cooldowns[i] > 0.0 or target == null:
			continue
		_fire_granted_weapon(_weapon_paths[i],target,i)
		_weapon_cooldowns[i] = _weapon_base_cooldown(_weapon_paths[i]) * maxf(weapon_cooldown_multiplier,0.05)

func _weapon_base_cooldown(path:String) -> float:
	if "霰弹" in path:
		return 1.55
	if "炸弹" in path:
		return 2.10
	if "时钟" in path or "电球" in path:
		return 1.45
	if "裁判" in path:
		return 1.10
	if "子弹" in path or "黑弹" in path:
		return 0.78
	if "刀" in path or "knife" in path:
		return 0.92
	return 1.18

func _fire_granted_weapon(path:String,target:ball,slot:int) -> void:
	if target == null or not is_instance_valid(target) or not ResourceLoader.exists(path):
		return
	var packed:PackedScene = load(path) as PackedScene
	if packed == null:
		return
	var node:Node = packed.instantiate()
	if not node is Node2D:
		node.queue_free()
		return
	var projectile:Node2D = node as Node2D
	var aim:Vector2 = target.global_position - global_position
	if aim.length_squared() <= 0.000001:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	var side_offset:float = (float(slot) - 0.5 * float(maxi(_weapon_paths.size() - 1,0))) * 12.0
	var spawn_pos:Vector2 = global_position + aim * 30.0 + aim.rotated(PI * 0.5) * side_offset
	projectile.global_position = spawn_pos
	_prepare_generic_projectile(projectile,target,aim,path)
	get_tree().current_scene.add_child(projectile,true)
	_start_special_projectile_if_needed(projectile,target,aim,path,spawn_pos)

func _prepare_generic_projectile(node:Node,target:ball,aim:Vector2,path:String) -> void:
	_set_property_if_present(node,"Master",self)
	_set_property_if_present(node,"Master_name",str(name))
	_set_property_if_present(node,"owner_soldier",self)
	_set_property_if_present(node,"owner_ball",self)
	_set_property_if_present(node,"Team",Team)
	_set_property_if_present(node,"team",Team)
	_set_property_if_present(node,"projectile_team",Team)
	_set_property_if_present(node,"Target_Enemy",target)
	_set_property_if_present(node,"Nearest_Enemy",target)
	_set_property_if_present(node,"direction",aim)
	_set_property_if_present(node,"travel_direction",aim)
	_set_property_if_present(node,"forward",aim)

	# 少数投射物会在 _ready() 读取这些生成参数，必须在 add_child() 前写入。
	if path.ends_with("建筑工人_砖块.tscn"):
		_set_property_if_present(node,"builder_owner",self)
		_set_property_if_present(node,"team",Team)
		_set_property_if_present(node,"enemy_damage",32.0)
	if path.ends_with("炸弹客炸弹.tscn"):
		_set_property_if_present(node,"Master_name",str(name))
		_set_property_if_present(node,"Team",Team)
		_set_property_if_present(node,"is_ground",false)
		_set_property_if_present(node,"attached_target_name",str(target.name))
		_set_property_if_present(node,"damage_amount",90.0)

	# 只在弹丸没有有效伤害时补一个通用值；有原生伤害的武器保留自己的数值和特殊效果。
	for damage_name:String in ["Damage","damage_amount","enemy_damage"]:
		if damage_name in node and float(node.get(damage_name)) <= 0.0:
			node.set(damage_name,35.0)

	# 非 ball projectile 的常见直线速度字段。
	if "velocity" in node:
		var current_velocity:Variant = node.get("velocity")
		if current_velocity is Vector2 and (current_velocity as Vector2).length_squared() <= 1.0:
			node.set("velocity",aim * 430.0)
	if "_velocity" in node:
		var private_velocity:Variant = node.get("_velocity")
		if private_velocity is Vector2 and (private_velocity as Vector2).length_squared() <= 1.0:
			node.set("_velocity",aim * 430.0)

	if node is ball:
		var b:ball = node as ball
		b.Master = self
		b.Master_name = str(name)
		b.Team = Team
		b.direction = aim
		b.Target_Enemy = target
		b.Nearest_Enemy = target
		if b.Damage <= 0:
			b.Damage = 35
		if b.Speed <= 20.0:
			b.Speed = 430.0

func _start_special_projectile_if_needed(node:Node,target:ball,aim:Vector2,path:String,spawn_pos:Vector2) -> void:
	if node == null or not is_instance_valid(node):
		return
	if path.ends_with("战争女神_火焰剑气.tscn") and node.has_method("setup"):
		node.call(
			"setup",
			self,
			Team,
			aim,
			float(node.get("damage_amount")) if "damage_amount" in node else 26.0,
			float(node.get("speed")) if "speed" in node else 560.0,
			float(node.get("max_distance")) if "max_distance" in node else 520.0,
			float(node.get("burn_duration")) if "burn_duration" in node else 3.0,
			float(node.get("burn_tick_interval")) if "burn_tick_interval" in node else 0.5,
			float(node.get("burn_tick_damage")) if "burn_tick_damage" in node else 3.0
		)
		return
	if path.ends_with("建筑工人_砖块.tscn"):
		_set_property_if_present(node,"builder_owner",self)
		_set_property_if_present(node,"team",Team)
		_set_property_if_present(node,"enemy_damage",32.0)
		if node.has_method("launch"):
			node.call("launch",target.global_position)
		return
	if path.ends_with("数学老师公式弹.tscn") or path.ends_with("领导处分文件.tscn") or path.ends_with("领导小领导.tscn"):
		if node.has_method("configure"):
			var config:Dictionary = {
				"origin":spawn_pos,
				"forward":aim,
				"direction":aim,
				"speed":360.0,
				"damage":35.0,
				"team":Team,
				"lifetime":3.2,
				"span":240.0,
				"amplitude":28.0,
				"curve_kind":_rng.randi_range(0,7),
				"stun":1.1,
			}
			node.call("configure",self,config,true)
		return
	if path.ends_with("菊花茶水滴.tscn") and node.has_method("configure_parabolic_launch"):
		node.call(
			"configure_parabolic_launch",
			spawn_pos,
			target.global_position,
			aim,
			target.velocity if target != null else Vector2.ZERO,
			440.0,
			720.0,
			0.12,
			2.6,
			1.0,
			26.0,
			140.0
		)
		return

func _set_property_if_present(node:Node,property_name:String,value:Variant) -> void:
	if node != null and property_name in node:
		node.set(property_name,value)

func _instant_kill_all_enemies() -> void:
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not SUBMISSION_TOOLS.is_enemy(self,target):
			continue
		# 和占卜师“四命运之轮”使用同一种 raw-health 瞬杀语义：越过格挡/减伤，
		# 但仍让目标自身的复活/变身死亡被动有机会按项目规则处理。
		var lethal:float = maxf(float(target.Max_health),float(target.health)) * 12.0 + 9999.0
		target.receive_spatial_raw_health_damage(
			lethal,
			{
				"shape":"dice_seven",
				"point":target.global_position,
				"source":self,
			}
		)

func _set_character_pose_local(pose:String) -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D
	match pose:
		"throw":
			sprite.texture = THROW_TEXTURE
		"wait":
			sprite.texture = WAIT_TEXTURE
		_:
			sprite.texture = NORMAL_TEXTURE

func _on_dice_visual_pose(pose:String) -> void:
	_set_character_pose_local(pose)

func _broadcast_roll_visual(result:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_roll_visual.rpc(result,maxf(roll_animation_time,0.08))
	else:
		_rpc_roll_visual(result,maxf(roll_animation_time,0.08))

@rpc("authority","call_local","reliable")
func _rpc_roll_visual(result:int,duration:float) -> void:
	if _dice_visual == null or not is_instance_valid(_dice_visual):
		_setup_dice_visual()
	if _dice_visual != null and is_instance_valid(_dice_visual) and _dice_visual.has_method("play_roll"):
		_dice_visual.call("play_roll",result,duration)

func _broadcast_hide_dice_visual() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_hide_dice_visual.rpc()
	else:
		_rpc_hide_dice_visual()

@rpc("authority","call_local","reliable")
func _rpc_hide_dice_visual() -> void:
	_set_character_pose_local("normal")
	if _dice_visual != null and is_instance_valid(_dice_visual) and _dice_visual.has_method("hide_after"):
		_dice_visual.call("hide_after",0.42)

func _broadcast_explosion_visual(origin:Vector2,radius:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_explosion_visual.rpc(origin,radius)
	else:
		_rpc_explosion_visual(origin,radius)

@rpc("authority","call_local","reliable")
func _rpc_explosion_visual(origin:Vector2,radius:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var root := Node2D.new()
	root.name = "掷骰子_点数1爆炸"
	root.global_position = origin
	root.z_as_relative = false
	root.z_index = 115
	world.add_child(root)
	for i:int in range(3):
		var ring := Polygon2D.new()
		ring.polygon = _circle_points(radius * (0.28 + 0.16 * float(i)),40)
		ring.color = Color(0.75 + 0.08 * float(i),0.03,0.05,0.28 - 0.05 * float(i))
		root.add_child(ring)
	root.scale = Vector2(0.18,0.18)
	var tween:Tween = root.create_tween().set_parallel(true)
	tween.tween_property(root,"scale",Vector2.ONE,0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(root,"modulate:a",0.0,0.34).set_delay(0.08)
	tween.finished.connect(root.queue_free)

func _circle_points(radius:float,count:int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_count:int = maxi(count,12)
	for i:int in range(safe_count):
		var angle:float = TAU * float(i) / float(safe_count)
		points.append(Vector2(cos(angle),sin(angle)) * radius)
	return points

func _broadcast_weapon_update(paths:Array[String]) -> void:
	var payload:Array = []
	for path:String in paths:
		payload.append(path)
	if multiplayer.has_multiplayer_peer():
		_rpc_weapon_update.rpc(payload)
	else:
		_rpc_weapon_update(payload)

@rpc("authority","call_local","reliable")
func _rpc_weapon_update(paths:Array) -> void:
	# 仅显示简短获得提示；真正开火只在 authority 运行，投射物继续走项目原有同步链。
	var names:Array[String] = []
	for raw:Variant in paths:
		names.append(_pretty_weapon_name(str(raw)))
	_show_weapon_text_local(names)

func _show_weapon_text_local(names:Array[String]) -> void:
	var old:Label = get_node_or_null("DiceWeaponText") as Label
	if old != null:
		old.queue_free()
	if names.is_empty():
		return
	var label := Label.new()
	label.name = "DiceWeaponText"
	label.text = " / ".join(names)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-120.0,-132.0)
	label.size = Vector2(240.0,26.0)
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_color",Color(1.0,0.92,0.44,0.96))
	label.z_index = 125
	add_child(label)
	var tween:Tween = label.create_tween()
	tween.tween_interval(1.15)
	tween.tween_property(label,"modulate:a",0.0,0.45)
	tween.finished.connect(label.queue_free)

func _broadcast_seven_jackpot() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_seven_jackpot.rpc()
	else:
		_rpc_seven_jackpot()

@rpc("authority","call_local","reliable")
func _rpc_seven_jackpot() -> void:
	if Game.has_method("play_blood_jackpot_flash_local"):
		Game.play_blood_jackpot_flash_local()
