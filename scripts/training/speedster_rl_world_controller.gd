extends "res://addons/godot_rl_agents/controller/ai_controller_2d.gd"

# ============================================================
# 极速者完整战斗 RL Controller V3
# ============================================================
# Observation 不再按“角色名字”编码，而是读 CombatThreatAnalyzer 的统一抽象：
#   self + 最危险威胁槽 + 敌方目标槽。
# Action 分成两个离散分支（Godot RL Agents 支持 multi-discrete）：
#   dodge : 0 KEEP / 1 LEFT / 2 RIGHT / 3 AWAY
#   combat: 0 HOLD_FIRE / 1 ATTACK
#
# 奖励核心：
#   - 不再有“活着就扣分”的 living penalty。
#   - 受到真实伤害扣分。
#   - 躲过真实威胁加分。
#   - 对敌方造成真实生命伤害加分；1 秒内伤害越集中，额外 burst 奖励越高。
#   - 对高反制风险目标仍坚持 ATTACK，会有轻微 shaping penalty。

@export_category("训练目标")
@export var target_team:String = ""
@export var print_bind_status:bool = true

@export_category("防御奖励")
@export var damage_received_penalty_per_hp:float = 0.12
@export var death_penalty:float = 8.0
@export var survived_threat_reward:float = 0.8
@export var invalid_dodge_penalty:float = 0.10
@export var energy_penalty_per_point:float = 0.008
@export var threat_resolution_margin:float = 0.12

@export_category("进攻奖励")
@export var damage_dealt_reward_per_hp:float = 0.045
@export var burst_window_seconds:float = 1.0
@export var burst_bonus_per_hp:float = 0.012
@export var burst_reference_damage:float = 120.0
@export var dangerous_attack_risk_threshold:float = 0.82
@export var dangerous_attack_penalty:float = 0.025

@export_category("回合")
@export var rebind_delay_frames:int = 2

var speedster:Node2D = null
var dodge_action:int = 0
var combat_action:int = 1

var _pending_reward:float = 0.0
var _last_health:float = 0.0
var _last_energy:float = 0.0
var _tracked_threat_key:String = ""
var _tracked_threat_remaining:float = 0.0
var _tracked_threat_was_hit:bool = false
var _death_reported:bool = false
var _reset_in_progress:bool = false
var _warned_multiple:bool = false
var _enemy_health:Dictionary = {}
var _burst_events:Array[Dictionary] = []


func _ready() -> void:
	Game.set_training_mode(true)
	super._ready()
	init(self)
	_try_bind_speedster()


func _exit_tree() -> void:
	if Game.is_training_mode():
		Game.set_training_mode(false)


func _analyzer() -> Node:
	var scene:Node = get_tree().current_scene
	return scene.get_node_or_null("CombatThreatAnalyzer") if scene != null else null


func get_obs() -> Dictionary:
	var analyzer:Node = _analyzer()
	if analyzer != null and analyzer.has_method("get_observation_for"):
		if speedster != null and is_instance_valid(speedster):
			return {"obs": analyzer.call("get_observation_for",speedster)}
		if analyzer.has_method("zero_observation"):
			return {"obs": analyzer.call("zero_observation")}
	return {"obs": _zero_obs()}


func get_reward() -> float:
	var value:float = _pending_reward
	_pending_reward = 0.0
	return value


func get_action_space() -> Dictionary:
	return {
		"dodge": {"size":4,"action_type":"discrete"},
		"combat": {"size":2,"action_type":"discrete"},
	}


func _discrete_value(action:Dictionary,key:String,default_value:int) -> int:
	var raw:Variant = action.get(key,default_value)
	if raw is Array and not raw.is_empty(): raw = raw[0]
	return int(raw)


func set_action(action = null) -> void:
	if not action is Dictionary:
		return
	dodge_action = clampi(_discrete_value(action,"dodge",0),0,3)
	combat_action = clampi(_discrete_value(action,"combat",1),0,1)
	if speedster != null and is_instance_valid(speedster):
		speedster.call("rl_set_dodge_action",dodge_action)
		if speedster.has_method("rl_set_combat_action"):
			speedster.call("rl_set_combat_action",combat_action)


func _physics_process(delta:float) -> void:
	if speedster == null or not is_instance_valid(speedster) or float(speedster.get("health")) <= 0.0:
		_try_bind_speedster()
		if needs_reset and not _reset_in_progress:
			call_deferred("_perform_agent_reset")
		return

	super._physics_process(delta)
	if needs_reset and not _reset_in_progress:
		call_deferred("_perform_agent_reset")
		return

	var health_now:float = float(speedster.get("health"))
	var energy_now:float = float(speedster.get("energy"))
	var health_loss:float = maxf(_last_health-health_now,0.0)
	var energy_used:float = maxf(_last_energy-energy_now,0.0)

	if health_loss > 0.0:
		_pending_reward -= health_loss * damage_received_penalty_per_hp
		_tracked_threat_was_hit = true
	if energy_used > 0.0:
		_pending_reward -= energy_used * energy_penalty_per_point

	_update_enemy_damage_reward(delta)
	_update_threat_reward(delta)
	_update_strategy_shaping()

	if health_now <= 0.0 and not _death_reported:
		_pending_reward -= death_penalty
		_death_reported = true
		done = true
		needs_reset = true

	_last_health = health_now
	_last_energy = energy_now


func _update_threat_reward(delta:float) -> void:
	var snap:Dictionary = speedster.call("rl_get_training_snapshot")
	var has_threat:bool = bool(snap.get("has_threat",false))
	var threat_key:String = str(snap.get("threat_key",""))
	if has_threat and not threat_key.is_empty() and threat_key != _tracked_threat_key:
		_tracked_threat_key = threat_key
		_tracked_threat_was_hit = false
		var ttc:float = clampf(float(snap.get("threat_ttc",0.0)),0.0,2.5)
		_tracked_threat_remaining = ttc + threat_resolution_margin

	if bool(snap.get("action_used",false)) and not bool(snap.get("action_valid",true)):
		_pending_reward -= invalid_dodge_penalty

	if not _tracked_threat_key.is_empty():
		_tracked_threat_remaining -= delta
		if _tracked_threat_remaining <= 0.0:
			if not _tracked_threat_was_hit:
				_pending_reward += survived_threat_reward
			_tracked_threat_key = ""
			_tracked_threat_remaining = 0.0
			_tracked_threat_was_hit = false


func _update_enemy_damage_reward(delta:float) -> void:
	# 不要求每个新角色显式告诉 RL “是谁打的”。在单极速者训练中，
	# 敌方人物真实 health 的下降就是可靠的输出结果；标准 hitbox/直伤/范围伤都覆盖。
	var seen:Dictionary = {}
	var dealt_this_tick:float = 0.0
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == speedster or target.Type != ball.Ball_Type.Ball:
			continue
		if not _is_hostile(target):
			continue
		var id:int = target.get_instance_id()
		var hp:float = float(target.health)
		seen[id] = true
		if _enemy_health.has(id):
			dealt_this_tick += maxf(float(_enemy_health[id])-hp,0.0)
		_enemy_health[id] = hp
	for id:Variant in _enemy_health.keys():
		if not seen.has(id): _enemy_health.erase(id)

	if dealt_this_tick <= 0.0:
		_trim_burst_events(delta)
		return

	_burst_events.append({"age":0.0,"damage":dealt_this_tick})
	_trim_burst_events(delta)
	var recent_damage:float = 0.0
	for event:Dictionary in _burst_events:
		recent_damage += float(event.get("damage",0.0))
	var burst_factor:float = clampf(recent_damage/maxf(burst_reference_damage,1.0),0.0,1.0)
	_pending_reward += dealt_this_tick * damage_dealt_reward_per_hp
	_pending_reward += dealt_this_tick * burst_bonus_per_hp * burst_factor


func _trim_burst_events(delta:float) -> void:
	for event:Dictionary in _burst_events:
		event["age"] = float(event.get("age",0.0)) + delta
	for i:int in range(_burst_events.size()-1,-1,-1):
		if float(_burst_events[i].get("age",0.0)) > burst_window_seconds:
			_burst_events.remove_at(i)


func _update_strategy_shaping() -> void:
	if combat_action != 1:
		return
	var analyzer:Node = _analyzer()
	if analyzer == null or not analyzer.has_method("get_targets"):
		return
	var targets:Array = analyzer.call("get_targets")
	if targets.is_empty():
		return
	var risk:float = float((targets[0] as Dictionary).get("counter_risk",0.0))
	if risk >= dangerous_attack_risk_threshold:
		_pending_reward -= dangerous_attack_penalty * inverse_lerp(dangerous_attack_risk_threshold,1.0,risk)


func _is_hostile(target:ball) -> bool:
	if speedster == null or not is_instance_valid(speedster): return false
	return str(target.Team).is_empty() or str(speedster.get("Team")).is_empty() or str(target.Team) != str(speedster.get("Team"))


func _try_bind_speedster() -> void:
	var candidates:Array[Node] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node == null or not is_instance_valid(node): continue
		if not node.has_method("rl_get_dodge_observation"): continue
		if not node.has_method("rl_get_training_snapshot"): continue
		if not node.has_method("rl_set_dodge_action"): continue
		if float(node.get("health")) <= 0.0: continue
		if not target_team.is_empty() and str(node.get("Team")) != target_team: continue
		candidates.append(node)
	if candidates.is_empty(): return
	if candidates.size() > 1 and not _warned_multiple:
		_warned_multiple = true
		push_warning("SpeedsterRLWorldController: 场上有多个可训练极速者；当前只绑定一个。")
	candidates.sort_custom(func(a:Node,b:Node)->bool:return a.get_instance_id()<b.get_instance_id())
	_bind_speedster(candidates[0] as Node2D)


func _bind_speedster(node:Node2D) -> void:
	if node == null or not is_instance_valid(node) or speedster == node: return
	speedster = node
	speedster.set("rl_dodge_training_enabled",true)
	if _has_property(speedster,"rl_combat_training_enabled"):
		speedster.set("rl_combat_training_enabled",true)
	if _has_property(speedster,"rl_disable_melee_and_attack_during_training"):
		speedster.set("rl_disable_melee_and_attack_during_training",false)
	speedster.call("rl_set_dodge_action",dodge_action)
	if speedster.has_method("rl_set_combat_action"):
		speedster.call("rl_set_combat_action",combat_action)
	_last_health = float(speedster.get("health"))
	_last_energy = float(speedster.get("energy"))
	_death_reported = false
	_tracked_threat_key = ""
	_tracked_threat_remaining = 0.0
	_tracked_threat_was_hit = false
	_enemy_health.clear()
	_burst_events.clear()
	var analyzer:Node = _analyzer()
	if analyzer != null and analyzer.has_method("set_receiver"):
		analyzer.call("set_receiver",speedster)
	if print_bind_status:
		print("[Speedster RL V3] 已绑定极速者: ",speedster.name," Team=",str(speedster.get("Team")))


func _clear_binding() -> void:
	if speedster != null and is_instance_valid(speedster) and speedster.has_method("rl_set_dodge_action"):
		speedster.call("rl_set_dodge_action",0)
	speedster = null
	_last_health = 0.0
	_last_energy = 0.0
	_tracked_threat_key = ""
	_tracked_threat_remaining = 0.0
	_tracked_threat_was_hit = false
	_death_reported = false
	_enemy_health.clear()
	_burst_events.clear()


func _perform_agent_reset() -> void:
	if _reset_in_progress: return
	_reset_in_progress = true
	reset()
	done = false
	dodge_action = 0
	combat_action = 1
	_pending_reward = 0.0
	# 不重置整个 World。训练模式死亡由 TrainingRespawnManager 单独复活人物；
	# 鼠标删除和玩家按 Reset 都不会被此处反向生成。
	if speedster == null or not is_instance_valid(speedster) or float(speedster.get("health")) <= 0.0:
		_clear_binding()
	for _i:int in range(maxi(rebind_delay_frames,1)):
		await get_tree().process_frame
	_try_bind_speedster()
	_reset_in_progress = false


func _has_property(node:Object,name:String) -> bool:
	for info:Dictionary in node.get_property_list():
		if str(info.get("name","")) == name: return true
	return false


func _zero_obs() -> Array[float]:
	# 默认与 CombatThreatAnalyzer: self8 + threat6*12 + target4*12 = 128 对齐。
	var result:Array[float] = []
	for _i:int in range(128): result.append(0.0)
	return result
