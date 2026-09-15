extends Node

# Sans 的 KARMA / KR 持续伤害（V157）。
# 设计目标：
# 1) 直接命中本身每物理帧造成 1 点伤害；
# 2) 非重力攻击额外积累粉紫色 KARMA；
# 3) KARMA 上限 40，越高掉得越快；
# 4) KARMA 自身永远不能把目标扣到 0 HP；
# 5) 生命条只显示“当前生命中未来会被 KARMA 扣掉的那一段”。

const MAX_KARMA:float = 40.0

var target:ball = null
var pending_karma:float = 0.0
var _drain_accumulator:float = 0.0
var _preview_key:String = ""
var _last_source_ref:WeakRef = null


func _ready() -> void:
	target = get_parent() as ball
	_preview_key = "sans_karma_%d" % get_instance_id()
	set_physics_process(target != null)
	_sync_preview()


func add_karma(amount:float,source:Node = null) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.health <= 1:
		return
	if amount <= 0.0:
		return
	if source != null and is_instance_valid(source):
		_last_source_ref = weakref(source)

	var room:float = maxf(float(target.health) - 1.0,0.0)
	pending_karma = minf(MAX_KARMA,minf(pending_karma + amount,room))
	_sync_preview()


func get_pending_karma() -> float:
	return pending_karma


func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	if target.health <= 0:
		pending_karma = 0.0
		_sync_preview()
		queue_free()
		return

	# 其它攻击可能先把目标血量压低；KARMA 预留区必须同步缩短，且始终留 1 HP。
	var room:float = maxf(float(target.health) - 1.0,0.0)
	if pending_karma > room:
		pending_karma = room
		_sync_preview()

	if pending_karma <= 0.0001:
		_sync_preview()
		queue_free()
		return

	# 只在拥有该角色权威的一端真正扣血，避免多人端重复结算。
	if not target.is_multiplayer_authority():
		return

	_drain_accumulator += maxf(delta,0.0)
	var interval:float = _current_drain_interval()
	while _drain_accumulator + 0.000001 >= interval and pending_karma > 0.0001 and target.health > 1:
		_drain_accumulator -= interval
		_apply_one_karma_damage()
		interval = _current_drain_interval()


func _current_drain_interval() -> float:
	# 参考 UNDERTALE 原作 KR 的分段速度（60fps）：
	# 40 -> 每帧；30~39 -> 2帧；20~29 -> 5帧；10~19 -> 15帧；1~9 -> 30帧。
	if pending_karma >= 40.0:
		return 1.0 / 60.0
	if pending_karma >= 30.0:
		return 2.0 / 60.0
	if pending_karma >= 20.0:
		return 5.0 / 60.0
	if pending_karma >= 10.0:
		return 15.0 / 60.0
	return 30.0 / 60.0


func _apply_one_karma_damage() -> void:
	if target == null or target.health <= 1 or pending_karma <= 0.0:
		return

	var before_health:float = float(target.health)
	if target.health_bar != null:
		target.health_bar.force_instant_update_once = true
		target.health_bar.suppress_floating_text = true

	# 不能击杀：无论积累多少，最低停在 1 HP。
	target.health = maxi(int(target.health) - 1,1)
	pending_karma = maxf(pending_karma - 1.0,0.0)

	if target.health_bar != null:
		target.health_bar.suppress_floating_text = false

	var actual_damage:float = maxf(before_health - float(target.health),0.0)
	var source:Node = null
	if _last_source_ref != null:
		source = _last_source_ref.get_ref() as Node
	if actual_damage > 0.0 and source != null and is_instance_valid(source):
		target.record_combat_damage_source(source,before_health)
		if Game.has_method("report_combat_damage"):
			Game.report_combat_damage(source,target,actual_damage,before_health)

		# V181：KR 同样直接修改 health；把这 1 点真实生命损失通知给
		# 依赖受伤量推进自身机制的角色（例如军官怒气），但绝不再次扣血。
		if target.has_method("notify_external_actual_health_damage"):
			target.call("notify_external_actual_health_damage",actual_damage,source)

		if source.has_method("play_sans_damage_feedback"):
			# KR 的真实掉血使用紫色闪烁，不走公共白闪。
			source.call("play_sans_damage_feedback",target,true)
		if source.has_method("queue_sans_damage_text"):
			source.call("queue_sans_damage_text",target,actual_damage)

	_sync_preview()


func _sync_preview() -> void:
	if target == null or not is_instance_valid(target) or target.health_bar == null:
		return
	if target.health_bar.has_method("set_karma_preview"):
		target.health_bar.call("set_karma_preview",_preview_key,pending_karma)


func _exit_tree() -> void:
	if target != null and is_instance_valid(target) and target.health_bar != null:
		if target.health_bar.has_method("clear_karma_preview"):
			target.health_bar.call("clear_karma_preview",_preview_key)
