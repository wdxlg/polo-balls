extends "res://addons/godot_rl_agents/controller/ai_controller_2d.gd"

# 极速者 RL 第一阶段控制器
# 动作：0=KEEP, 1=DODGE_LEFT, 2=DODGE_RIGHT
#
# 训练场每个 episode 发射一颗真正会威胁极速者的投射物。
# 成功躲过/被命中后只设置 done=true；真正的环境重置等待 Python 发送 reset，
# 由 Sync 把 needs_reset 设为 true 后再原地重置。这样不会 reload scene，也不会断开 TCP。

@export_category("奖励")
@export var episode_success_reward:float = 2.0
@export var episode_failure_penalty:float = 4.0
@export var damage_penalty_per_hp:float = 0.05
@export var survived_threat_reward:float = 0.35
@export var keep_during_threat_penalty:float = 0.01
@export var invalid_dodge_penalty:float = 0.12
@export var energy_penalty_per_point:float = 0.008
@export var living_penalty:float = 0.00025
@export var threat_resolution_margin:float = 0.10

@export_category("训练")
@export var enable_speedster_rl_on_ready:bool = true

var speedster:Node = null
var arena:Node = null
var dodge_action:int = 0

var _pending_reward:float = 0.0
var _last_health:float = 0.0
var _last_energy:float = 0.0

var _tracked_threat_key:String = ""
var _tracked_threat_time_left:float = 0.0
var _tracked_health:float = 0.0

var _episode_finished:bool = false
var _episode_success:bool = false
var _episode_index:int = 0


func _ready() -> void:
	super._ready()
	speedster = get_parent()
	if speedster != null and not speedster.is_node_ready():
		await speedster.ready
	arena = speedster.get_parent() if speedster != null else null
	if speedster == null or not speedster.has_method("rl_get_dodge_observation"):
		push_error("SpeedsterDodgeRLController 必须作为极速者节点的子节点。")
		return
	if enable_speedster_rl_on_ready:
		speedster.set("rl_dodge_training_enabled",true)
	_last_health = float(speedster.get("health"))
	_last_energy = float(speedster.get("energy"))
	init(speedster)


func get_obs() -> Dictionary:
	if speedster == null or not is_instance_valid(speedster):
		return {"obs": _zero_obs()}
	return {"obs": speedster.rl_get_dodge_observation()}


func get_reward() -> float:
	var value:float = _pending_reward
	_pending_reward = 0.0
	return value


func get_action_space() -> Dictionary:
	return {
		"dodge": {
			"size": 3,
			"action_type": "discrete",
		},
	}


func set_action(action = null) -> void:
	if speedster == null or not is_instance_valid(speedster) or action == null:
		return
	if _episode_finished:
		return
	var raw:Variant = action.get("dodge",0) if action is Dictionary else 0
	if raw is Array and not raw.is_empty():
		raw = raw[0]
	dodge_action = clampi(int(raw),0,2)
	speedster.rl_set_dodge_action(dodge_action)


func get_info() -> Dictionary:
	return {
		"is_success": _episode_success if _episode_finished else false,
		"episode": _episode_index,
		"dodge_action": dodge_action,
	}


# 由训练场调用。不要在这里设置 needs_reset：
# done 会先被 Sync 发给 Python，随后 Python 才会回 reset。
func finish_episode(success:bool) -> void:
	if _episode_finished:
		return
	_episode_finished = true
	_episode_success = success
	if success:
		_pending_reward += episode_success_reward
	else:
		_pending_reward -= episode_failure_penalty
	done = true


func _physics_process(delta:float) -> void:
	super._physics_process(delta)
	if speedster == null or not is_instance_valid(speedster):
		return

	# Sync 收到 Python 的 reset 后会把 needs_reset 设为 true。
	# 此时原地重置训练场，保持 TCP 连接和 Sync 节点不变。
	if needs_reset:
		_reset_episode_from_python()
		return

	var health_now:float = float(speedster.get("health"))
	var energy_now:float = float(speedster.get("energy"))
	var health_loss:float = maxf(_last_health - health_now,0.0)
	var energy_used:float = maxf(_last_energy - energy_now,0.0)

	if health_loss > 0.0:
		_pending_reward -= health_loss * damage_penalty_per_hp
	if energy_used > 0.0:
		_pending_reward -= energy_used * energy_penalty_per_point
	if not _episode_finished:
		_pending_reward -= living_penalty

	# 终局以后只等 Python reset，不再创造新的 shaping reward。
	if _episode_finished:
		_last_health = health_now
		_last_energy = energy_now
		return

	var snap:Dictionary = speedster.rl_get_training_snapshot()
	var has_threat:bool = bool(snap.get("has_threat",false))
	var threat_key:String = str(snap.get("threat_key",""))

	# 一个威胁窗口只跟踪一次。
	if has_threat and not threat_key.is_empty() and threat_key != _tracked_threat_key:
		_tracked_threat_key = threat_key
		_tracked_health = health_now
		var ttc:float = clampf(float(snap.get("threat_ttc",0.0)),0.0,1.0)
		_tracked_threat_time_left = ttc + threat_resolution_margin
		if dodge_action == 0:
			_pending_reward -= keep_during_threat_penalty

	if bool(snap.get("action_used",false)) and not bool(snap.get("action_valid",true)):
		_pending_reward -= invalid_dodge_penalty

	if not _tracked_threat_key.is_empty():
		_tracked_threat_time_left -= maxf(delta,0.0)
		if _tracked_threat_time_left <= 0.0:
			if health_now >= _tracked_health - 0.01:
				_pending_reward += survived_threat_reward
			_tracked_threat_key = ""
			_tracked_threat_time_left = 0.0

	_last_health = health_now
	_last_energy = energy_now


func _reset_episode_from_python() -> void:
	# 先重置场景内容，再重置 AIController 自己的 n_steps/needs_reset。
	if arena != null and is_instance_valid(arena) and arena.has_method("rl_reset_episode"):
		arena.call("rl_reset_episode")
	elif speedster.has_method("rl_reset_training_state"):
		speedster.rl_reset_training_state(speedster.global_position)

	reset()
	done = false
	dodge_action = 0
	speedster.rl_set_dodge_action(0)

	_pending_reward = 0.0
	_last_health = float(speedster.get("health"))
	_last_energy = float(speedster.get("energy"))
	_tracked_threat_key = ""
	_tracked_threat_time_left = 0.0
	_tracked_health = _last_health
	_episode_finished = false
	_episode_success = false
	_episode_index += 1


func _zero_obs() -> Array[float]:
	var result:Array[float] = []
	for _i:int in range(17):
		result.append(0.0)
	return result
