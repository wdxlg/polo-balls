extends ball
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")

# 极速者 V23 / Phase 2
# ============================================================
# 核心规则：
# 1. 普通状态绝不接管 direction，完全沿用项目原 AI。
# 2. 防御是 interrupt，不会删除攻击计划。
# 3. 子弹既看已生成投射物，也看远程角色“即将发射”的 windup，解决贴脸生成来不及闪。
# 4. 近战统一建模成未来攻击走廊：决斗者突刺、拳击手冲拳等不再依赖角色名判断。
# 5. 防御只选择能真正脱离危险的最短侧闪/后撤；两边都堵就不浪费能量。
# 6. 主动攻击只通过“先撞墙，再利用真实 bounce 方向去命中目标”；第一段直撞目标永远无效。
# 7. 攻击极速与防御极速解耦：攻击中被打断闪一下，闪完立刻从新位置重算反弹路线，速度层不清零。
# 8. 快速状态才做棋子/矿工石头等危险地形局部绕行；普通状态不增加任何专属避障。
# 9. 攻击速度按真实高速移动距离逐级提升，退出攻击极速立即清零；
#    V107 起 Damage 始终保持“整体基础攻击力”，高速只改变当前命中倍率，不再改写 Damage。

const ThreatData = preload("res://scripts/characters/speedster_threat.gd")
const MotionPlanData = preload("res://scripts/characters/speedster_motion_plan.gd")
const RicochetPlannerData = preload("res://scripts/characters/speedster_ricochet_planner.gd")
const SPEEDSTER_ENTER_AUDIO_PATH:String = "res://audio/characters/极速者/极速者进入.mp3"
const MOJANGLES_FONT = preload("res://fonts/Mojangles.ttf")


# ============================================================
# Inspector
# ============================================================

@export_category("极速表现")
@export var normal_texture:Texture2D
@export var speed_texture:Texture2D
@export_range(1.0,2.0,0.01) var speed_visual_scale_multiplier:float = 1.13
@export_range(0.20,1.0,0.01) var world_slow_factor:float = 0.48
@export var speed_world_tint:Color = Color(0.16,0.52,1.0,0.16)
@export var speed_mode_enter_sfx:String = "DefenseBreak"
@export var speed_mode_exit_sfx:String = ""

@export_category("能量")
@export_range(0.0,100.0,0.5) var dodge_energy_drain_per_second:float = 18.0
@export_range(0.0,100.0,0.5) var attack_energy_drain_per_second:float = 14.0
@export_range(0.0,20.0,0.5) var attack_stage_extra_drain:float = 1.5
@export_range(0.0,100.0,0.5) var energy_recharge_per_second:float = 17.0
@export_range(0.0,3.0,0.05) var energy_recharge_delay:float = 0.55
@export_range(0,1000,1) var minimum_dodge_energy:int = 1
@export_range(0,1000,1) var attack_start_energy:int = 24
@export_range(0,1000,1) var attack_stop_energy:int = 8

@export_category("防御极速")
@export_range(1.05,4.0,0.05) var dodge_speed_multiplier:float = 1.90
@export_range(0.02,0.24,0.005) var max_dodge_speed_burst:float = 0.12
@export_range(0.02,0.35,0.01) var dodge_min_carry_time:float = 0.07
@export_range(0.05,0.40,0.01) var dodge_max_carry_time:float = 0.22
@export_range(10.0,200.0,5.0) var dodge_probe_distance:float = 135.0
@export_range(8.0,120.0,2.0) var dodge_min_clearance:float = 34.0
@export_range(0.005,0.04,0.005) var simulation_step:float = 0.01

@export_category("投射物 / 发射预警")
@export_range(100.0,1200.0,10.0) var projectile_scan_radius:float = 560.0
@export_range(0.08,0.80,0.01) var projectile_prediction_horizon:float = 0.48
@export_range(0.04,0.50,0.01) var projectile_reaction_ttc:float = 0.28
@export_range(0.0,80.0,1.0) var projectile_extra_margin:float = 7.0
@export_range(0.03,0.30,0.01) var ranged_windup_lead:float = 0.13
@export_range(120.0,2000.0,10.0) var ranged_prefire_scan_radius:float = 650.0
@export_range(100.0,2000.0,10.0) var ranged_projectile_speed_fallback:float = 320.0
@export_range(4.0,60.0,1.0) var ranged_projectile_radius_fallback:float = 13.0
@export_range(0.05,0.80,0.01) var same_threat_lock_time:float = 0.24

@export_category("近战攻击预判")
@export_range(100.0,1000.0,10.0) var melee_scan_radius:float = 700.0
@export_range(0.03,0.40,0.01) var melee_windup_lead:float = 0.18
@export_range(50.0,700.0,5.0) var melee_default_reach:float = 165.0
@export_range(50.0,1600.0,10.0) var melee_default_dash_speed:float = 620.0
@export_range(0.05,0.60,0.01) var melee_default_active_duration:float = 0.22
@export_range(0.0,80.0,1.0) var melee_extra_margin:float = 15.0

@export_category("反弹攻击")
@export_range(120.0,1800.0,10.0) var attack_search_radius:float = 1050.0
@export_range(32,160,1) var ricochet_direction_samples:int = 96
@export_range(200.0,1800.0,10.0) var ricochet_ray_length:float = 1050.0
@export_range(10.0,180.0,2.0) var ricochet_min_wall_distance:float = 52.0
@export_range(0.01,0.90,0.01) var ricochet_min_incidence:float = 0.08
@export_range(20.0,500.0,5.0) var ricochet_setup_max_line_miss:float = 330.0
@export_range(-0.30,0.95,0.01) var ricochet_setup_min_alignment:float = 0.16
@export_range(10.0,100.0,1.0) var ricochet_target_extra_radius:float = 22.0
@export_range(40.0,220.0,5.0) var ricochet_corner_probe:float = 105.0
@export_range(15.0,120.0,2.0) var ricochet_corner_min_open:float = 44.0
@export_range(0.02,0.40,0.01) var attack_replan_interval:float = 0.10
@export_range(0.05,0.70,0.01) var attack_no_plan_grace:float = 0.32
@export_range(0.03,0.30,0.01) var physics_bounce_commit_time:float = 0.09
@export_range(0.0,1.0,0.01) var attack_reenter_delay:float = 0.10

@export_category("攻击加速 / 伤害")
@export_range(1.1,3.0,0.05) var attack_speed_stage_0:float = 1.70
@export_range(1.1,3.5,0.05) var attack_speed_stage_1:float = 2.05
@export_range(1.1,4.0,0.05) var attack_speed_stage_2:float = 2.45
@export_range(1.1,4.5,0.05) var attack_speed_stage_3:float = 2.95
@export_range(1.1,5.0,0.05) var attack_speed_stage_4:float = 3.60
@export_range(20.0,500.0,5.0) var attack_stage_distance_1:float = 90.0
@export_range(40.0,800.0,5.0) var attack_stage_distance_2:float = 220.0
@export_range(80.0,1200.0,5.0) var attack_stage_distance_3:float = 410.0
@export_range(120.0,1800.0,5.0) var attack_stage_distance_4:float = 650.0
@export_range(1.0,5.0,0.05) var max_damage_multiplier:float = 3.45
@export_range(0.0,2.0,0.05) var damage_speed_slope:float = 0.82

@export_category("快速地形避障")
@export_range(30.0,240.0,5.0) var hazard_lookahead:float = 125.0
@export_range(0.02,0.30,0.01) var hazard_detour_time:float = 0.11
@export_range(20.0,200.0,5.0) var hazard_detour_probe:float = 115.0
@export_range(20.0,200.0,5.0) var hazard_min_exit_space:float = 55.0

@export_category("扫描 / 调试")
@export_range(0.01,0.20,0.005) var threat_scan_interval:float = 0.025
@export_range(0.02,0.30,0.01) var attack_scan_interval:float = 0.08
@export var debug_speedster_ai:bool = false

@export_category("强化学习 / RL")
@export var rl_dodge_training_enabled:bool = false
# V2：RL 训练时仍扫描近战 / 范围 / 地形威胁；这个开关仅用于完全禁用主动攻击的防御课程。
@export var rl_disable_melee_and_attack_during_training:bool = false
@export var rl_combat_training_enabled:bool = false
@export_range(0.0,0.25,0.005) var rl_action_hold_seconds:float = 0.06


# ============================================================
# Runtime
# ============================================================

var _base_speed:float = 0.0
var _last_speed_written:float = 0.0
var _wrote_speed_last_tick:bool = false
# 当前高速攻击倍率；只作用于真实 Hitbox，绝不写回 Damage。
var _current_attack_damage_multiplier:float = 1.0
var _base_image_scale:Vector2 = Vector2.ONE

var _energy_precise:float = 0.0
var _recharge_delay_left:float = 0.0
var _speed_visual_active:bool = false
var _speed_source_key:String = ""
var _dead_shutdown:bool = false

var _clock:float = 0.0
var _threat_scan_left:float = 0.0
var _attack_scan_left:float = 0.0
var _attack_reenter_left:float = 0.0
var _threat_locks:Dictionary = {}

# 普通控制器的移动意图。NORMAL 时不覆盖 direction。
var _controller_direction:Vector2 = Vector2.ZERO
var _last_override_direction:Vector2 = Vector2.ZERO
var _wrote_direction_last_tick:bool = false
var _handoff_direction:Vector2 = Vector2.ZERO
var _handoff_time_left:float = 0.0

# 防御 interrupt
var _interrupt:SpeedsterMotionPlan = null
var _interrupt_threat:SpeedsterThreat = null

# 主动反弹攻击（独立于 interrupt）
var _attack_active:bool = false
var _attack_target:ball = null
var _attack_heading:Vector2 = Vector2.ZERO
var _attack_expected_reflect:Vector2 = Vector2.ZERO
var _attack_plan_timeout:float = 0.0
var _attack_replan_left:float = 0.0
var _attack_no_plan_left:float = 0.0
var _physics_commit_left:float = 0.0
var _wall_credit:bool = false
var _attack_distance:float = 0.0
var _hazard_detour_direction:Vector2 = Vector2.ZERO
var _hazard_detour_left:float = 0.0
var _ricochet_planner:SpeedsterRicochetPlanner = null

# Debug snapshot
var _debug_threat:SpeedsterThreat = null
var _debug_dodge_direction:Vector2 = Vector2.ZERO
var _debug_dodge_burst:float = 0.0
var _debug_attack_wall:Vector2 = Vector2.ZERO
var _debug_attack_reflect:Vector2 = Vector2.ZERO
var _debug_attack_target:Vector2 = Vector2.ZERO
var _debug_plan_label:String = "NORMAL"

# RL 防御动作：
# 0=保持，1=相对威胁左侧闪，2=右侧闪，3=远离威胁/后撤。
# 主动战斗动作：0=暂缓主动攻击，1=允许原精确反弹规划器进攻。
var _rl_dodge_action:int = 0
var _rl_combat_action:int = 1
var _rl_action_left:float = 0.0
var _rl_last_action_valid:bool = true
var _rl_last_action_used:bool = false
var _rl_last_threat:SpeedsterThreat = null
var _rl_last_left_plan:SpeedsterMotionPlan = null
var _rl_last_right_plan:SpeedsterMotionPlan = null
var _rl_last_away_plan:SpeedsterMotionPlan = null


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	super._ready()
	_base_speed = maxf(Speed,0.0)
	_last_speed_written = Speed
	_current_attack_damage_multiplier = 1.0
	_energy_precise = float(energy)
	_speed_source_key = "speedster_v23:%s" % str(get_path())
	_interrupt = MotionPlanData.new()
	_ricochet_planner = RicochetPlannerData.new()
	_ricochet_planner.configure(self,{
		"collision_mask":1,
		"sample_count":ricochet_direction_samples,
		"ray_length":ricochet_ray_length,
		"min_wall_distance":ricochet_min_wall_distance,
		"min_incidence":ricochet_min_incidence,
		"target_extra_radius":ricochet_target_extra_radius,
		"setup_max_line_miss":ricochet_setup_max_line_miss,
		"setup_min_alignment":ricochet_setup_min_alignment,
		"corner_probe":ricochet_corner_probe,
		"corner_min_open":ricochet_corner_min_open,
	})
	if image != null and is_instance_valid(image):
		_base_image_scale = image.scale


func transition_state(from:State,to:State) -> void:
	if to == State.Die:
		_shutdown_speedster()
	super.transition_state(from,to)


func _exit_tree() -> void:
	_shutdown_speedster()


func _shutdown_speedster() -> void:
	if _dead_shutdown and not _speed_visual_active:
		return
	_dead_shutdown = true
	if _interrupt != null:
		_interrupt.clear()
	_interrupt_threat = null
	_stop_attack("shutdown",false)
	_handoff_time_left = 0.0
	_handoff_direction = Vector2.ZERO
	_set_speed_visual(false)
	Speed = _base_speed
	_current_attack_damage_multiplier = 1.0
	_last_speed_written = Speed
	_wrote_speed_last_tick = true
	if debug_speedster_ai:
		queue_redraw()


# ============================================================
# Main physics hook
# ============================================================

func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return

	if _dead_shutdown or health <= 0 or state == State.Die:
		_shutdown_speedster()
		super.tick_physics(state,delta)
		return

	_capture_external_stats()
	_capture_controller_direction()

	var real_dt:float = _real_delta(delta)
	_clock += real_dt
	_threat_scan_left = maxf(_threat_scan_left - real_dt,0.0)
	_attack_scan_left = maxf(_attack_scan_left - real_dt,0.0)
	_attack_reenter_left = maxf(_attack_reenter_left - real_dt,0.0)
	_recharge_delay_left = maxf(_recharge_delay_left - real_dt,0.0)
	_attack_replan_left = maxf(_attack_replan_left - real_dt,0.0)
	_attack_plan_timeout = maxf(_attack_plan_timeout - real_dt,0.0)
	_attack_no_plan_left = maxf(_attack_no_plan_left - real_dt,0.0)
	_physics_commit_left = maxf(_physics_commit_left - real_dt,0.0)
	_hazard_detour_left = maxf(_hazard_detour_left - real_dt,0.0)
	_handoff_time_left = maxf(_handoff_time_left - real_dt,0.0)
	_rl_action_left = maxf(_rl_action_left - real_dt,0.0)
	_cleanup_threat_locks()

	_update_interrupt(real_dt)
	_scan_threats()
	if is_player_controlled():
		# V130：直接控制时禁用“发现敌人 -> 自动规划撞墙路线 -> 自动攻击”。
		# 左键只切换手动极速攻击状态，实际运动方向始终由 WASD 决定。
		if _attack_active and energy <= attack_stop_energy:
			_stop_attack("player_control_low_energy",false)
	elif rl_dodge_training_enabled and rl_combat_training_enabled:
		if _rl_combat_action == 1:
			_update_attack_planner()
		elif _attack_active:
			_stop_attack("rl_hold_attack",false)
	elif not (rl_dodge_training_enabled and rl_disable_melee_and_attack_during_training):
		_update_attack_planner()
	elif _attack_active:
		_stop_attack("rl_training",false)
	_update_fast_hazard_detour()
	_apply_direction_owner()
	_update_speed_damage_energy(real_dt)

	var before_move:Vector2 = global_position
	var attack_movement_counts:bool = _attack_active and not (_interrupt != null and _interrupt.active())
	super.tick_physics(state,delta)

	if attack_movement_counts and _attack_active:
		var moved:float = before_move.distance_to(global_position)
		# 网络修正/传送不算极速积累。
		if moved > 0.001 and moved < 220.0:
			_attack_distance += moved

	if debug_speedster_ai:
		queue_redraw()


# ============================================================
# Preserve normal controller ownership
# ============================================================

func _capture_external_stats() -> void:
	if not _wrote_speed_last_tick:
		_base_speed = maxf(Speed,0.0)
	elif absf(Speed - _last_speed_written) > 0.01:
		var logical_scale:float = maxf(_logical_speed_multiplier(),0.001)
		_base_speed = maxf(Speed / logical_scale,0.0) if _is_any_speed_active() else maxf(Speed,0.0)
	_wrote_speed_last_tick = false


func _capture_controller_direction() -> void:
	var current:Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO
	if not _wrote_direction_last_tick:
		_controller_direction = current
	elif current.distance_squared_to(_last_override_direction) > 0.0004:
		# 可能是正常控制器更新，也可能是真实物理 bounce；两者都应作为最新运动事实保留。
		_controller_direction = current
	_wrote_direction_last_tick = false


func _write_override_direction(value:Vector2) -> void:
	if value.length_squared() <= 0.0001:
		return
	direction = value.normalized()
	_last_override_direction = direction
	_wrote_direction_last_tick = true


# ============================================================
# Threat scan: projectile + ranged windup + melee corridor
# ============================================================

func _scan_threats() -> void:
	if _threat_scan_left > 0.0:
		return
	_threat_scan_left = maxf(threat_scan_interval,0.01)

	var best:SpeedsterThreat = null
	var candidates:Array[SpeedsterThreat] = []

	# RL V2 优先使用训练场的“通用威胁抽象层”。它不依赖角色名字，
	# 会把投射物、碰撞伤害体、拳路/叉路、落锤区、危险地形、控制场、核弹等统一成几何威胁。
	if rl_dodge_training_enabled:
		var generic:SpeedsterThreat = _find_training_generic_threat()
		if generic != null:
			candidates.append(generic)
	else:
		var projectile:SpeedsterThreat = _find_projectile_threat()
		if projectile != null:
			candidates.append(projectile)
		var ranged:SpeedsterThreat = _find_ranged_windup_threat()
		if ranged != null:
			candidates.append(ranged)
		var melee:SpeedsterThreat = _find_melee_threat()
		if melee != null:
			candidates.append(melee)

	for threat:SpeedsterThreat in candidates:
		if best == null or threat.severity > best.severity:
			best = threat

	_debug_threat = best
	_rl_last_threat = best
	_rl_last_action_used = false
	_rl_last_action_valid = true
	_rl_last_left_plan = null
	_rl_last_right_plan = null
	_rl_last_away_plan = null
	if best == null:
		return

	if rl_dodge_training_enabled:
		_rl_last_left_plan = _build_rl_directional_dodge(best,1)
		_rl_last_right_plan = _build_rl_directional_dodge(best,-1)
		_rl_last_away_plan = _build_rl_away_dodge(best)

		if _interrupt != null and _interrupt.active():
			return
		if _rl_action_left <= 0.0:
			return

		_rl_last_action_used = true
		var chosen:SpeedsterMotionPlan = null
		match _rl_dodge_action:
			1:
				chosen = _rl_last_left_plan
			2:
				chosen = _rl_last_right_plan
			3:
				chosen = _rl_last_away_plan
			_:
				chosen = null

		if _rl_dodge_action != 0 and chosen == null:
			_rl_last_action_valid = false
			return
		if chosen == null:
			return

		_interrupt = chosen
		_interrupt_threat = best
		_debug_dodge_direction = chosen.direction
		_debug_dodge_burst = chosen.speed_time_left
		if _attack_active:
			_attack_plan_timeout = 0.0
			_attack_replan_left = 0.0
		return

	if _threat_locks.has(best.source_key) and float(_threat_locks[best.source_key]) > _clock:
		return

	if _interrupt != null and _interrupt.active():
		if best.source_key == _interrupt.source_key:
			return
		if best.severity <= _interrupt.priority + 0.22:
			return

	var plan:SpeedsterMotionPlan = null
	if best.is_projectile_like():
		plan = _build_projectile_like_dodge(best)
	elif best.is_line_threat():
		plan = _build_melee_dodge(best)
	elif best.is_area_threat():
		plan = _build_area_dodge(best)

	if plan == null:
		_threat_locks[best.source_key] = _clock + minf(same_threat_lock_time,0.14)
		return

	_interrupt = plan
	_interrupt_threat = best
	_threat_locks[best.source_key] = _clock + maxf(same_threat_lock_time,plan.speed_time_left + plan.carry_time_left + 0.08)
	_debug_dodge_direction = plan.direction
	_debug_dodge_burst = plan.speed_time_left
	if _attack_active:
		_attack_plan_timeout = 0.0
		_attack_replan_left = 0.0


func _training_threat_analyzer() -> Node:
	var scene:Node = get_tree().current_scene
	if scene == null:
		return null
	var analyzer:Node = scene.get_node_or_null("CombatThreatAnalyzer")
	if analyzer == null and scene.has_node("SpeedsterRLWorldController"):
		analyzer = scene.get_node_or_null("CombatThreatAnalyzer")
	return analyzer


func _find_training_generic_threat() -> SpeedsterThreat:
	var analyzer:Node = _training_threat_analyzer()
	if analyzer == null or not analyzer.has_method("get_best_threat"):
		# 若训练场没有抽象器，退回旧的 projectile 路径，避免普通场景因训练开关误开而失效。
		return _find_projectile_threat()
	if analyzer.has_method("set_receiver"):
		analyzer.call("set_receiver",self)
	var raw:Variant = analyzer.call("get_best_threat")
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return null
	return _speedster_threat_from_generic(raw as Dictionary)


func _speedster_threat_from_generic(info:Dictionary) -> SpeedsterThreat:
	var source_node:Node = info.get("source",null)
	if source_node == null or not is_instance_valid(source_node) or not source_node is Node2D:
		return null

	var threat:SpeedsterThreat = ThreatData.new()
	threat.source = source_node as Node2D
	threat.source_key = "G:%s:%s" % [str(source_node.get_instance_id()),str(info.get("kind","threat"))]
	threat.origin = Vector2(info.get("position",(source_node as Node2D).global_position))
	threat.source_velocity = Vector2(info.get("velocity",Vector2.ZERO))
	threat.active_from = maxf(float(info.get("danger_in",0.0)),0.0)
	threat.active_until = threat.active_from + maxf(float(info.get("danger_duration",0.10)),0.03)
	threat.time_to_impact = threat.active_from
	threat.severity = maxf(float(info.get("severity",1.0)),0.01)
	threat.label = str(info.get("kind","generic"))

	var shape:String = str(info.get("shape","circle"))
	if shape == "segment":
		var start_p:Vector2 = Vector2(info.get("start",threat.origin))
		var end_p:Vector2 = Vector2(info.get("end",start_p))
		var axis:Vector2 = end_p - start_p
		if axis.length_squared() <= 0.0001:
			axis = Vector2.RIGHT
		threat.kind = ThreatData.Kind.MELEE_LINE
		threat.origin = start_p
		threat.axis = axis.normalized()
		threat.reach = axis.length()
		var own_radius:float = _collision_support_radius(self,Vector2(-threat.axis.y,threat.axis.x))
		threat.hard_radius = maxf(float(info.get("radius",4.0)) + own_radius,1.0)
		threat.radius = threat.hard_radius + melee_extra_margin * 0.35
	elif shape == "circle" and threat.source_velocity.length_squared() > 1.0 and str(info.get("kind","")).find("field") < 0:
		threat.kind = ThreatData.Kind.PROJECTILE
		var axis:Vector2 = threat.source_velocity
		if axis.length_squared() <= 0.0001:
			axis = threat.origin - global_position
		threat.axis = axis.normalized() if axis.length_squared() > 0.0001 else Vector2.RIGHT
		var own_radius:float = _collision_support_radius(self,Vector2(-threat.axis.y,threat.axis.x))
		threat.hard_radius = maxf(float(info.get("radius",4.0)) + own_radius,1.0)
		threat.radius = threat.hard_radius + projectile_extra_margin
	else:
		# 圆/矩形/控制场/爆炸/地形统一为“面积危险”。
		threat.kind = ThreatData.Kind.HAZARD
		var ext:Vector2 = Vector2(info.get("extent",Vector2.ONE * float(info.get("radius",8.0))))
		var own_radius:float = _collision_support_radius(self,Vector2.RIGHT)
		threat.hard_radius = maxf(maxf(ext.x,ext.y) + own_radius,1.0)
		threat.radius = threat.hard_radius + melee_extra_margin * 0.25
		var away:Vector2 = global_position - threat.origin
		threat.axis = away.normalized() if away.length_squared() > 0.0001 else Vector2.RIGHT
		threat.reach = threat.radius
	return threat


func _build_rl_directional_dodge(threat:SpeedsterThreat,side:int) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid():
		return null
	if threat.is_projectile_like():
		return _build_projectile_side_dodge(threat,side)
	if threat.is_line_threat():
		var perpendicular:Vector2 = Vector2(-threat.axis.y,threat.axis.x).normalized()
		return _build_melee_direction_plan(threat,perpendicular if side >= 0 else -perpendicular,"rl_left" if side >= 0 else "rl_right")
	if threat.is_area_threat():
		var radial:Vector2 = global_position - threat.origin
		if radial.length_squared() <= 0.0001:
			radial = Vector2.RIGHT
		var tangent:Vector2 = Vector2(-radial.y,radial.x).normalized()
		return _build_area_direction_plan(threat,tangent if side >= 0 else -tangent,"rl_left" if side >= 0 else "rl_right")
	return null


func _build_rl_away_dodge(threat:SpeedsterThreat) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid():
		return null
	var candidate:Vector2
	if threat.is_line_threat():
		candidate = -threat.axis.normalized()
	else:
		candidate = global_position - threat.origin
		if candidate.length_squared() <= 0.0001:
			candidate = -threat.axis
		if candidate.length_squared() <= 0.0001:
			candidate = Vector2.RIGHT
		candidate = candidate.normalized()

	if threat.is_projectile_like():
		return _build_projectile_direction_plan(threat,candidate,"rl_away")
	if threat.is_line_threat():
		return _build_melee_direction_plan(threat,candidate,"rl_away")
	if threat.is_area_threat():
		return _build_area_direction_plan(threat,candidate,"rl_away")
	return null


func _find_projectile_threat() -> SpeedsterThreat:
	var best:SpeedsterThreat = null
	var best_score:float = -INF
	var scan_sq:float = projectile_scan_radius * projectile_scan_radius
	var self_velocity:Vector2 = _controller_direction * _base_speed

	for node:Node in PROJECTILE_API.candidates(get_tree()):
		if not node is Node2D:
			continue
		var projectile_ball:Node2D = node as Node2D
		if not _is_hostile_projectile(projectile_ball):
			continue
		if global_position.distance_squared_to(projectile_ball.global_position) > scan_sq:
			continue

		var projectile_velocity:Vector2 = PROJECTILE_API.velocity_of(projectile_ball)
		if projectile_velocity.length_squared() <= 1.0:
			continue

		var relative_position:Vector2 = projectile_ball.global_position - global_position
		var relative_velocity:Vector2 = projectile_velocity - self_velocity
		var rv_sq:float = relative_velocity.length_squared()
		if rv_sq <= 1.0 or relative_position.dot(relative_velocity) >= 0.0:
			continue

		var t_closest:float = clampf(-relative_position.dot(relative_velocity) / rv_sq,0.0,projectile_prediction_horizon)
		if t_closest > projectile_reaction_ttc:
			continue

		var closest:Vector2 = relative_position + relative_velocity * t_closest
		var hard_radius:float = _collision_support_radius(self,closest.normalized()) + PROJECTILE_API.radius_of(projectile_ball)
		var wanted_radius:float = hard_radius + projectile_extra_margin
		if closest.length() >= wanted_radius:
			continue

		var threat:SpeedsterThreat = ThreatData.new()
		threat.kind = ThreatData.Kind.PROJECTILE
		threat.source = projectile_ball
		threat.source_key = "P:%s" % str(projectile_ball.get_instance_id())
		threat.origin = projectile_ball.global_position
		threat.axis = projectile_velocity.normalized()
		threat.source_velocity = projectile_velocity
		threat.active_from = 0.0
		threat.active_until = projectile_prediction_horizon
		threat.radius = wanted_radius
		threat.hard_radius = hard_radius
		threat.time_to_impact = t_closest
		threat.label = "projectile"
		var time_score:float = 1.0 - clampf(t_closest / maxf(projectile_reaction_ttc,0.001),0.0,1.0)
		var overlap_score:float = 1.0 - clampf(closest.length() / maxf(wanted_radius,0.001),0.0,1.0)
		threat.severity = 1.1 + time_score * 1.6 + overlap_score
		if threat.severity > best_score:
			best = threat
			best_score = threat.severity

	# 手动训练模式会直接实例化部分 Area2D/Node2D 投射物。它们不是 ball，
	# 因此原来的 Ball 组扫描看不到。所有手动训练攻击都会加入这个组。
	for node:Node in get_tree().get_nodes_in_group("ManualTrainingProjectile"):
		if node == null or not is_instance_valid(node) or PROJECTILE_API.is_projectile(node) or node is ball or not node is Node2D:
			continue
		var projectile_node:Node2D = node as Node2D
		if global_position.distance_squared_to(projectile_node.global_position) > scan_sq:
			continue

		var projectile_velocity:Vector2 = _manual_projectile_velocity(projectile_node)
		if projectile_velocity.length_squared() <= 1.0:
			continue

		var relative_position:Vector2 = projectile_node.global_position - global_position
		var relative_velocity:Vector2 = projectile_velocity - self_velocity
		var rv_sq:float = relative_velocity.length_squared()
		if rv_sq <= 1.0 or relative_position.dot(relative_velocity) >= 0.0:
			continue

		var t_closest:float = clampf(-relative_position.dot(relative_velocity) / rv_sq,0.0,projectile_prediction_horizon)
		if t_closest > projectile_reaction_ttc:
			continue

		var closest:Vector2 = relative_position + relative_velocity * t_closest
		var approach_axis:Vector2 = closest.normalized() if closest.length_squared() > 0.0001 else Vector2.UP
		var self_radius:float = _collision_support_radius(self,approach_axis)
		var projectile_radius:float = maxf(float(projectile_node.get_meta("manual_training_radius",8.0)),2.0)
		var hard_radius:float = self_radius + projectile_radius
		var wanted_radius:float = hard_radius + projectile_extra_margin
		if closest.length() >= wanted_radius:
			continue

		var threat:SpeedsterThreat = ThreatData.new()
		threat.kind = ThreatData.Kind.PROJECTILE
		threat.source = projectile_node
		threat.source_key = "MP:%s" % str(projectile_node.get_instance_id())
		threat.origin = projectile_node.global_position
		threat.axis = projectile_velocity.normalized()
		threat.source_velocity = projectile_velocity
		threat.active_from = 0.0
		threat.active_until = projectile_prediction_horizon
		threat.radius = wanted_radius
		threat.hard_radius = hard_radius
		threat.time_to_impact = t_closest
		threat.label = "manual_projectile"
		var time_score:float = 1.0 - clampf(t_closest / maxf(projectile_reaction_ttc,0.001),0.0,1.0)
		var overlap_score:float = 1.0 - clampf(closest.length() / maxf(wanted_radius,0.001),0.0,1.0)
		threat.severity = 1.15 + time_score * 1.6 + overlap_score
		if threat.severity > best_score:
			best = threat
			best_score = threat.severity

	return best


func _find_ranged_windup_threat() -> SpeedsterThreat:
	var best:SpeedsterThreat = null
	var best_score:float = -INF
	var scan_sq:float = ranged_prefire_scan_radius * ranged_prefire_scan_radius

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var enemy:ball = node as ball
		if not _is_hostile_character(enemy):
			continue
		if global_position.distance_squared_to(enemy.global_position) > scan_sq:
			continue
		if not _is_ranged_character(enemy):
			continue
		if not _enemy_likely_targets_self(enemy):
			continue

		var current_action:bool = _enemy_currently_attacking(enemy)
		var cooldown_left:float = _enemy_next_offense_delay(enemy)
		if not current_action and cooldown_left > ranged_windup_lead:
			continue

		var axis:Vector2 = _enemy_attack_axis(enemy)
		if axis.length_squared() <= 0.0001:
			continue
		var to_self:Vector2 = global_position - enemy.global_position
		if to_self.dot(axis) <= 0.0:
			continue

		var projectile_speed:float = _first_numeric_property(enemy,["projectile_speed","bullet_speed","sniper_bullet_speed","throw_speed"],ranged_projectile_speed_fallback)
		var active_from:float = 0.02 if current_action else maxf(cooldown_left,0.0)
		var lateral:float = absf(to_self.dot(Vector2(-axis.y,axis.x)))
		var self_radius:float = _collision_support_radius(self,Vector2(-axis.y,axis.x))
		var wanted_radius:float = self_radius + ranged_projectile_radius_fallback + projectile_extra_margin
		if lateral > wanted_radius * 1.8:
			continue

		var forward:float = maxf(to_self.dot(axis),0.0)
		var impact_time:float = active_from + forward / maxf(projectile_speed,1.0)
		if impact_time > projectile_prediction_horizon + ranged_windup_lead:
			continue

		var threat:SpeedsterThreat = ThreatData.new()
		threat.kind = ThreatData.Kind.RANGED_WINDUP
		threat.source = enemy
		threat.source_key = "R:%s" % str(enemy.get_instance_id())
		threat.origin = enemy.global_position
		threat.axis = axis
		threat.source_velocity = axis * projectile_speed
		threat.active_from = active_from
		threat.active_until = active_from + projectile_prediction_horizon
		threat.radius = wanted_radius
		threat.hard_radius = self_radius + ranged_projectile_radius_fallback
		threat.time_to_impact = impact_time
		threat.label = "ranged_windup"
		var close_bonus:float = 1.0 - clampf(forward / maxf(ranged_prefire_scan_radius,1.0),0.0,1.0)
		var timing_bonus:float = 1.0 - clampf(active_from / maxf(ranged_windup_lead,0.01),0.0,1.0)
		threat.severity = 1.2 + close_bonus * 0.8 + timing_bonus * 0.9
		if threat.severity > best_score:
			best = threat
			best_score = threat.severity

	return best


func _find_melee_threat() -> SpeedsterThreat:
	var best:SpeedsterThreat = null
	var best_score:float = -INF
	var scan_sq:float = melee_scan_radius * melee_scan_radius

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var enemy:ball = node as ball
		if not _is_hostile_character(enemy):
			continue
		if global_position.distance_squared_to(enemy.global_position) > scan_sq:
			continue
		if not _is_melee_character(enemy):
			continue
		if not _enemy_likely_targets_self(enemy):
			continue

		var current_action:bool = _enemy_currently_attacking(enemy)
		var cooldown_left:float = _enemy_next_offense_delay(enemy)
		if not current_action and cooldown_left > melee_windup_lead:
			continue

		var axis:Vector2 = _enemy_attack_axis(enemy)
		if axis.length_squared() <= 0.0001:
			continue

		var reach:float = _estimate_melee_reach(enemy)
		var attack_speed:float = _estimate_melee_speed(enemy)
		var perpendicular:Vector2 = Vector2(-axis.y,axis.x)
		var corridor_radius:float = _collision_support_radius(self,perpendicular) + _collision_support_radius(enemy,perpendicular) * 0.45 + melee_extra_margin
		var relative:Vector2 = global_position - enemy.global_position
		var forward:float = relative.dot(axis)
		var lateral:float = absf(relative.dot(perpendicular))
		if forward < -corridor_radius or forward > reach + corridor_radius:
			continue
		if lateral > corridor_radius * 1.45:
			continue

		var active_from:float = 0.0 if current_action else maxf(cooldown_left,0.0)
		var duration:float = _first_numeric_property(enemy,["stab_pose_duration","fist_extend_time"],melee_default_active_duration)
		duration = clampf(maxf(duration,0.08),0.08,0.45)
		var travel_time:float = maxf(forward,0.0) / maxf(attack_speed,1.0)

		var threat:SpeedsterThreat = ThreatData.new()
		threat.kind = ThreatData.Kind.MELEE_LINE
		threat.source = enemy
		threat.source_key = "M:%s" % str(enemy.get_instance_id())
		threat.origin = enemy.global_position
		threat.axis = axis
		threat.source_velocity = axis * attack_speed
		threat.active_from = active_from
		threat.active_until = active_from + maxf(duration,travel_time + 0.07)
		threat.reach = reach
		threat.radius = corridor_radius
		threat.hard_radius = maxf(corridor_radius - melee_extra_margin,1.0)
		threat.time_to_impact = active_from + travel_time
		threat.label = "melee_line"
		var time_bonus:float = 1.0 - clampf(threat.time_to_impact / maxf(melee_windup_lead + 0.24,0.01),0.0,1.0)
		var lane_bonus:float = 1.0 - clampf(lateral / maxf(corridor_radius,1.0),0.0,1.0)
		threat.severity = 1.5 + time_bonus * 1.4 + lane_bonus * 0.7
		if threat.severity > best_score:
			best = threat
			best_score = threat.severity

	# 拳击手的拳头并不是独立场景。手动训练控制器会把它作为短时“胶囊走廊”
	# 暴露给极速者，因此这里把它并入原本的近战威胁规划。
	for provider:Node in get_tree().get_nodes_in_group("ManualTrainingThreatProvider"):
		if provider == null or not is_instance_valid(provider) or not provider.has_method("get_active_manual_melee_threats"):
			continue
		var manual_threats:Variant = provider.call("get_active_manual_melee_threats",self)
		if not manual_threats is Array:
			continue
		for raw_info:Variant in manual_threats:
			if not raw_info is Dictionary:
				continue
			var info:Dictionary = raw_info
			var origin:Vector2 = info.get("origin",Vector2.ZERO)
			var axis:Vector2 = info.get("axis",Vector2.ZERO)
			if axis.length_squared() <= 0.0001:
				continue
			axis = axis.normalized()
			var reach:float = maxf(float(info.get("reach",melee_default_reach)),1.0)
			var radius:float = maxf(float(info.get("radius",melee_extra_margin + 8.0)),1.0)
			var relative:Vector2 = global_position - origin
			var forward:float = relative.dot(axis)
			var lateral:float = absf(relative.cross(axis))
			if forward < -radius or forward > reach + radius or lateral > radius * 1.45:
				continue

			var manual:SpeedsterThreat = ThreatData.new()
			manual.kind = ThreatData.Kind.MELEE_LINE
			manual.source = provider as Node2D
			manual.source_key = str(info.get("source_key","MM:%s" % str(provider.get_instance_id())))
			manual.origin = origin
			manual.axis = axis
			manual.source_velocity = Vector2.ZERO
			manual.active_from = maxf(float(info.get("active_from",0.0)),0.0)
			manual.active_until = maxf(float(info.get("active_until",manual.active_from + melee_default_active_duration)),manual.active_from + 0.01)
			manual.reach = reach
			manual.radius = radius
			manual.hard_radius = maxf(radius - melee_extra_margin,1.0)
			manual.time_to_impact = maxf(float(info.get("time_to_impact",manual.active_from)),0.0)
			manual.label = "manual_melee"
			var time_bonus:float = 1.0 - clampf(manual.time_to_impact / maxf(melee_windup_lead + 0.24,0.01),0.0,1.0)
			var lane_bonus:float = 1.0 - clampf(lateral / maxf(radius,1.0),0.0,1.0)
			manual.severity = 1.55 + time_bonus * 1.4 + lane_bonus * 0.7
			if manual.severity > best_score:
				best = manual
				best_score = manual.severity

	return best


# ============================================================
# Dodge planner
# ============================================================

func _build_projectile_side_dodge(threat:SpeedsterThreat,side:int) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid() or threat.axis.length_squared() <= 0.0001:
		return null
	var left:Vector2 = Vector2(-threat.axis.y,threat.axis.x).normalized()
	var candidate:Vector2 = left if side >= 0 else -left
	var clearance:float = _body_motion_clearance(candidate,dodge_probe_distance)
	if clearance < dodge_min_clearance:
		return null
	var carry:float = clampf(threat.time_to_impact + 0.045,dodge_min_carry_time,dodge_max_carry_time)
	var burst:float = _find_minimum_projectile_burst(threat,candidate,carry)
	if burst < 0.0:
		return null
	var plan:SpeedsterMotionPlan = MotionPlanData.new()
	plan.kind = MotionPlanData.Kind.DODGE_PROJECTILE
	plan.direction = candidate
	plan.speed_time_left = burst
	plan.carry_time_left = carry
	plan.source_key = threat.source_key
	plan.reason = "rl_left" if side >= 0 else "rl_right"
	plan.priority = threat.severity
	return plan


func _build_projectile_direction_plan(threat:SpeedsterThreat,candidate:Vector2,reason:String) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid() or candidate.length_squared() <= 0.0001:
		return null
	candidate = candidate.normalized()
	var clearance:float = _body_motion_clearance(candidate,dodge_probe_distance)
	if clearance < dodge_min_clearance:
		return null
	var carry:float = clampf(threat.time_to_impact + 0.045,dodge_min_carry_time,dodge_max_carry_time)
	var burst:float = _find_minimum_projectile_burst(threat,candidate,carry)
	if burst < 0.0:
		return null
	var plan:SpeedsterMotionPlan = MotionPlanData.new()
	plan.kind = MotionPlanData.Kind.DODGE_PROJECTILE
	plan.direction = candidate
	plan.speed_time_left = burst
	plan.carry_time_left = carry
	plan.source_key = threat.source_key
	plan.reason = reason
	plan.priority = threat.severity
	return plan


func _build_melee_direction_plan(threat:SpeedsterThreat,candidate:Vector2,reason:String) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid() or candidate.length_squared() <= 0.0001:
		return null
	candidate = candidate.normalized()
	var clearance:float = _body_motion_clearance(candidate,dodge_probe_distance)
	if clearance < dodge_min_clearance:
		return null
	var carry:float = clampf(threat.active_until + 0.035,dodge_min_carry_time,dodge_max_carry_time)
	var burst:float = _find_minimum_melee_burst(threat,candidate,carry)
	if burst < 0.0:
		return null
	var plan:SpeedsterMotionPlan = MotionPlanData.new()
	plan.kind = MotionPlanData.Kind.DODGE_MELEE
	plan.direction = candidate
	plan.speed_time_left = burst
	plan.carry_time_left = carry
	plan.source_key = threat.source_key
	plan.reason = reason
	plan.priority = threat.severity
	return plan


func _build_area_direction_plan(threat:SpeedsterThreat,candidate:Vector2,reason:String) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid() or candidate.length_squared() <= 0.0001:
		return null
	candidate = candidate.normalized()
	var clearance:float = _body_motion_clearance(candidate,dodge_probe_distance)
	if clearance < dodge_min_clearance:
		return null
	var carry:float = clampf(threat.active_until + 0.05,dodge_min_carry_time,dodge_max_carry_time)
	var burst:float = _find_minimum_area_burst(threat,candidate,carry)
	if burst < 0.0:
		return null
	var plan:SpeedsterMotionPlan = MotionPlanData.new()
	plan.kind = MotionPlanData.Kind.DODGE_MELEE
	plan.direction = candidate
	plan.speed_time_left = burst
	plan.carry_time_left = carry
	plan.source_key = threat.source_key
	plan.reason = reason
	plan.priority = threat.severity
	return plan


func _build_area_dodge(threat:SpeedsterThreat) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid():
		return null
	var radial:Vector2 = global_position - threat.origin
	if radial.length_squared() <= 0.0001:
		radial = Vector2.RIGHT
	radial = radial.normalized()
	var tangent:Vector2 = Vector2(-radial.y,radial.x)
	var candidates:Array[Vector2] = [radial,tangent,-tangent]
	var best:SpeedsterMotionPlan = null
	var best_cost:float = INF
	for candidate:Vector2 in candidates:
		var plan:SpeedsterMotionPlan = _build_area_direction_plan(threat,candidate,"hazard")
		if plan == null:
			continue
		var cost:float = plan.speed_time_left * dodge_energy_drain_per_second + plan.carry_time_left * 0.02
		# 面积危险优先真正向外逃，切线只在墙体/能耗上更合适时采用。
		if candidate.dot(radial) < 0.5:
			cost += 0.08
		if cost < best_cost:
			best = plan
			best_cost = cost
	return best


func _build_projectile_like_dodge(threat:SpeedsterThreat) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid() or threat.axis.length_squared() <= 0.0001:
		return null

	var left:Vector2 = Vector2(-threat.axis.y,threat.axis.x).normalized()
	var right:Vector2 = -left
	var signed_side:float = (global_position - threat.origin).dot(left)
	var ordered:Array[Vector2] = [left,right]
	if signed_side > 1.0:
		ordered = [left,right]
	elif signed_side < -1.0:
		ordered = [right,left]
	# 正中时 left 优先；例如子弹向左 -> left 就是向下/上取决于坐标，后续墙体硬过滤。

	var best_plan:SpeedsterMotionPlan = null
	var best_cost:float = INF
	for candidate:Vector2 in ordered:
		var clearance:float = _body_motion_clearance(candidate,dodge_probe_distance)
		if clearance < dodge_min_clearance:
			continue
		var carry:float = clampf(threat.time_to_impact + 0.045,dodge_min_carry_time,dodge_max_carry_time)
		var burst:float = _find_minimum_projectile_burst(threat,candidate,carry)
		if burst < 0.0:
			continue
		var cost:float = burst * dodge_energy_drain_per_second + carry * 0.025
		if cost < best_cost:
			var plan:SpeedsterMotionPlan = MotionPlanData.new()
			plan.kind = MotionPlanData.Kind.DODGE_PROJECTILE
			plan.direction = candidate
			plan.speed_time_left = burst
			plan.carry_time_left = carry
			plan.source_key = threat.source_key
			plan.reason = threat.label
			plan.priority = threat.severity
			best_plan = plan
			best_cost = cost
	return best_plan


func _build_melee_dodge(threat:SpeedsterThreat) -> SpeedsterMotionPlan:
	if threat == null or not threat.is_valid() or threat.axis.length_squared() <= 0.0001:
		return null

	var perpendicular:Vector2 = Vector2(-threat.axis.y,threat.axis.x).normalized()
	var candidates:Array[Vector2] = [perpendicular,-perpendicular,-threat.axis.normalized()]
	var best_plan:SpeedsterMotionPlan = null
	var best_cost:float = INF
	var carry:float = clampf(threat.active_until + 0.035,dodge_min_carry_time,dodge_max_carry_time)

	for candidate:Vector2 in candidates:
		var clearance:float = _body_motion_clearance(candidate,dodge_probe_distance)
		if clearance < dodge_min_clearance:
			continue
		var burst:float = _find_minimum_melee_burst(threat,candidate,carry)
		if burst < 0.0:
			continue
		# 侧闪略优于后撤；但如果后撤明显更省能量仍会选后撤。
		var retreat_penalty:float = 0.35 if candidate.dot(-threat.axis.normalized()) > 0.95 else 0.0
		var cost:float = burst * dodge_energy_drain_per_second + carry * 0.02 + retreat_penalty
		if cost < best_cost:
			var plan:SpeedsterMotionPlan = MotionPlanData.new()
			plan.kind = MotionPlanData.Kind.DODGE_MELEE
			plan.direction = candidate.normalized()
			plan.speed_time_left = burst
			plan.carry_time_left = carry
			plan.source_key = threat.source_key
			plan.reason = "melee"
			plan.priority = threat.severity
			best_plan = plan
			best_cost = cost
	return best_plan


func _find_minimum_projectile_burst(threat:SpeedsterThreat,dodge_direction:Vector2,carry:float) -> float:
	if _simulate_projectile_like_dodge(threat,dodge_direction,0.0,carry):
		return 0.0
	if energy < minimum_dodge_energy:
		return -1.0
	var affordable:float = _affordable_dodge_burst()
	if affordable <= 0.001 or not _simulate_projectile_like_dodge(threat,dodge_direction,affordable,carry):
		return -1.0
	return _binary_search_burst(threat,dodge_direction,carry,affordable,true)


func _find_minimum_melee_burst(threat:SpeedsterThreat,dodge_direction:Vector2,carry:float) -> float:
	if _simulate_melee_dodge(threat,dodge_direction,0.0,carry):
		return 0.0
	if energy < minimum_dodge_energy:
		return -1.0
	var affordable:float = _affordable_dodge_burst()
	if affordable <= 0.001 or not _simulate_melee_dodge(threat,dodge_direction,affordable,carry):
		return -1.0
	return _binary_search_burst(threat,dodge_direction,carry,affordable,false)


func _find_minimum_area_burst(threat:SpeedsterThreat,dodge_direction:Vector2,carry:float) -> float:
	if _simulate_area_dodge(threat,dodge_direction,0.0,carry):
		return 0.0
	if energy < minimum_dodge_energy:
		return -1.0
	var affordable:float = _affordable_dodge_burst()
	if affordable <= 0.001 or not _simulate_area_dodge(threat,dodge_direction,affordable,carry):
		return -1.0
	var low:float = 0.0
	var high:float = affordable
	for _i:int in range(8):
		var middle:float = (low + high) * 0.5
		if _simulate_area_dodge(threat,dodge_direction,middle,carry):
			high = middle
		else:
			low = middle
	var physics_step:float = 1.0 / maxf(float(Engine.physics_ticks_per_second),1.0)
	return minf(maxf(high,physics_step),affordable)


func _binary_search_burst(threat:SpeedsterThreat,dodge_direction:Vector2,carry:float,high_value:float,projectile_like:bool) -> float:
	var low:float = 0.0
	var high:float = high_value
	for _i:int in range(8):
		var middle:float = (low + high) * 0.5
		var safe:bool = _simulate_projectile_like_dodge(threat,dodge_direction,middle,carry) if projectile_like else _simulate_melee_dodge(threat,dodge_direction,middle,carry)
		if safe:
			high = middle
		else:
			low = middle
	var physics_step:float = 1.0 / maxf(float(Engine.physics_ticks_per_second),1.0)
	return minf(maxf(high,physics_step),high_value)


func _affordable_dodge_burst() -> float:
	var allowed:float = max_dodge_speed_burst
	if dodge_energy_drain_per_second > 0.001 and not _attack_active:
		allowed = minf(allowed,maxf(float(energy) - 0.05,0.0) / dodge_energy_drain_per_second)
	return maxf(allowed,0.0)


func _simulate_projectile_like_dodge(threat:SpeedsterThreat,dodge_direction:Vector2,burst_time:float,carry_time:float) -> bool:
	var horizon:float = maxf(projectile_prediction_horizon,threat.time_to_impact + 0.12)
	var dt:float = clampf(simulation_step,0.005,0.04)
	var self_pos:Vector2 = global_position
	var threat_pos:Vector2 = threat.origin
	var game_clock:float = 0.0
	var real_clock:float = 0.0
	var base_speed:float = maxf(_base_speed,0.0)
	var fast_speed:float = base_speed * maxf(dodge_speed_multiplier,1.0)
	var spawned:bool = threat.kind == ThreatData.Kind.PROJECTILE

	while real_clock < horizon:
		var step:float = minf(dt,horizon - real_clock)
		var in_burst:bool = real_clock < burst_time - 0.0001
		var in_carry:bool = real_clock < burst_time + carry_time - 0.0001
		var world_factor:float = world_slow_factor if in_burst else 1.0
		game_clock += step * world_factor

		var self_velocity:Vector2
		if in_burst:
			self_velocity = dodge_direction * fast_speed
		elif in_carry:
			self_velocity = dodge_direction * base_speed
		else:
			self_velocity = _controller_direction * base_speed
		self_pos += self_velocity * step

		if not spawned and game_clock >= threat.active_from:
			spawned = true
			threat_pos = threat.origin
		if spawned:
			threat_pos += threat.source_velocity * step * world_factor
			# 不在 t=0 用“额外安全边距”判死刑。贴脸生成时允许极速者在第一个 physics tick 抽身。
			var threshold:float = threat.radius
			if real_clock <= dt * 1.1:
				threshold = maxf(threat.hard_radius * 0.82,1.0)
			if threat_pos.distance_to(self_pos) <= threshold:
				return false

		real_clock += step
	return true


func _simulate_melee_dodge(threat:SpeedsterThreat,dodge_direction:Vector2,burst_time:float,carry_time:float) -> bool:
	var horizon:float = maxf(threat.active_until + 0.08,burst_time + carry_time + 0.03)
	var dt:float = clampf(simulation_step,0.005,0.04)
	var self_pos:Vector2 = global_position
	var game_clock:float = 0.0
	var real_clock:float = 0.0
	var base_speed:float = maxf(_base_speed,0.0)
	var fast_speed:float = base_speed * maxf(dodge_speed_multiplier,1.0)

	while real_clock < horizon:
		var step:float = minf(dt,horizon - real_clock)
		var in_burst:bool = real_clock < burst_time - 0.0001
		var in_carry:bool = real_clock < burst_time + carry_time - 0.0001
		var world_factor:float = world_slow_factor if in_burst else 1.0
		game_clock += step * world_factor

		if in_burst:
			self_pos += dodge_direction * fast_speed * step
		elif in_carry:
			self_pos += dodge_direction * base_speed * step
		else:
			self_pos += _controller_direction * base_speed * step

		if game_clock >= threat.active_from and game_clock <= threat.active_until:
			var line_a:Vector2 = threat.origin
			var line_b:Vector2 = threat.origin + threat.axis.normalized() * threat.reach
			if _point_segment_distance(self_pos,line_a,line_b) <= threat.radius:
				return false
		real_clock += step
	return true


func _simulate_area_dodge(threat:SpeedsterThreat,dodge_direction:Vector2,burst_time:float,carry_time:float) -> bool:
	var horizon:float = maxf(threat.active_until + 0.10,burst_time + carry_time + 0.04)
	var dt:float = clampf(simulation_step,0.005,0.04)
	var self_pos:Vector2 = global_position
	var center:Vector2 = threat.origin
	var game_clock:float = 0.0
	var real_clock:float = 0.0
	var base_speed:float = maxf(_base_speed,0.0)
	var fast_speed:float = base_speed * maxf(dodge_speed_multiplier,1.0)

	while real_clock < horizon:
		var step:float = minf(dt,horizon-real_clock)
		var in_burst:bool = real_clock < burst_time - 0.0001
		var in_carry:bool = real_clock < burst_time + carry_time - 0.0001
		var world_factor:float = world_slow_factor if in_burst else 1.0
		game_clock += step * world_factor

		if in_burst:
			self_pos += dodge_direction * fast_speed * step
		elif in_carry:
			self_pos += dodge_direction * base_speed * step
		else:
			self_pos += _controller_direction * base_speed * step

		center += threat.source_velocity * step * world_factor
		if game_clock >= threat.active_from and game_clock <= threat.active_until:
			if self_pos.distance_to(center) <= threat.radius:
				return false
		real_clock += step
	return true


func _update_interrupt(real_dt:float) -> void:
	if _interrupt == null or not _interrupt.active():
		return
	if _interrupt.speed_time_left > 0.0:
		_interrupt.speed_time_left = maxf(_interrupt.speed_time_left - real_dt,0.0)
	else:
		_interrupt.carry_time_left = maxf(_interrupt.carry_time_left - real_dt,0.0)
	if _interrupt.speed_time_left <= 0.0 and _interrupt.carry_time_left <= 0.0:
		var finished_direction:Vector2 = _interrupt.direction
		_interrupt.clear()
		_interrupt_threat = null
		if _attack_active:
			_attack_replan_left = 0.0
			_attack_plan_timeout = 0.0
		else:
			_handoff_direction = finished_direction
			_handoff_time_left = 0.10


# ============================================================
# Ricochet attack planner
# ============================================================

func player_control_action_hold_repeat_allowed(action_index:int) -> bool:
	# V380：极速者左键是“开启/再次点击关闭”的切换动作，不应因为长按被自动反复开关。
	# 右/中键若存在仍沿用公共长按语义。
	return action_index != 0


func controlled_attack_action() -> void:
	if not is_multiplayer_authority() or not is_player_controlled() or health <= 0:
		return
	if is_damage_output_disabled():
		return
	if _attack_active:
		_stop_attack("player_control_toggle_off",false)
		return
	if energy < attack_start_energy:
		return

	# 手动极速攻击不绑定目标、不写自动反弹规划。开启后伤害/能量/极速视觉仍复用原机制，
	# 但真实移动方向完全服从玩家 WASD，因此可以朝任意方向冲撞。再次左键可主动关闭。
	_attack_active = true
	_attack_target = null
	_attack_heading = Vector2.ZERO
	_attack_expected_reflect = Vector2.ZERO
	_attack_distance = 0.0
	_attack_plan_timeout = 0.0
	_attack_replan_left = 0.0
	_attack_no_plan_left = attack_no_plan_grace
	_physics_commit_left = 0.0
	_wall_credit = false
	_debug_attack_wall = Vector2.ZERO
	_debug_attack_reflect = Vector2.ZERO
	_debug_attack_target = player_control_aim_world_position(global_position)
	_debug_plan_label = "ATTACK: PLAYER CONTROL"


func _update_attack_planner() -> void:
	if _attack_active:
		if energy <= attack_stop_energy:
			_stop_attack("low_energy")
			return
		if not _valid_attack_target(_attack_target):
			_attack_target = _preferred_attack_target()
			_attack_plan_timeout = 0.0
			_attack_replan_left = 0.0
			_wall_credit = false
		if not _valid_attack_target(_attack_target):
			_stop_attack("no_target")
			return

		if _interrupt != null and _interrupt.active():
			return
		if _physics_commit_left > 0.0:
			return

		# 刚从墙上真实 bounce 出来：如果当前真实方向本来就会穿过目标，绝不重新瞄准，直接吃物理轨迹。
		if _wall_credit:
			var natural_hit:Dictionary = _ricochet_planner.current_heading_hits_target(_attack_target,direction,_attack_speed_world_value(),760.0)
			if bool(natural_hit.get("valid",false)):
				_attack_heading = direction.normalized()
				_attack_plan_timeout = maxf(_attack_plan_timeout,0.18)
				_debug_attack_target = natural_hit.get("predicted_target",_attack_target.global_position)
				_debug_plan_label = "ATTACK: PHYSICS STRIKE"
				return

		if _attack_plan_timeout > 0.0 and _attack_heading.length_squared() > 0.0001:
			return
		if _attack_replan_left > 0.0:
			return

		_attack_replan_left = maxf(attack_replan_interval,0.03)
		var next_plan:Dictionary = _ricochet_planner.find_wall_plan(_attack_target,direction,_attack_speed_world_value())
		if bool(next_plan.get("valid",false)):
			_apply_attack_wall_plan(next_plan)
			_attack_no_plan_left = attack_no_plan_grace
		elif _attack_no_plan_left <= 0.0:
			_stop_attack("no_wall_plan")
		return

	# NORMAL：只有这里允许启动主动攻击。没有敌人/没能量时完全不碰 direction。
	if _attack_reenter_left > 0.0 or energy < attack_start_energy:
		return
	if _attack_scan_left > 0.0:
		return
	_attack_scan_left = maxf(attack_scan_interval,0.03)

	var target:ball = _preferred_attack_target()
	if not _valid_attack_target(target):
		return
	if global_position.distance_to(target.global_position) > attack_search_radius:
		return

	var plan:Dictionary = _ricochet_planner.find_wall_plan(target,_controller_direction,_base_speed * attack_speed_stage_0)
	if not bool(plan.get("valid",false)):
		return

	_attack_active = true
	_attack_target = target
	_attack_distance = 0.0
	_wall_credit = false
	_attack_no_plan_left = attack_no_plan_grace
	_apply_attack_wall_plan(plan)
	_debug_plan_label = "ATTACK: %s" % str(plan.get("kind","wall"))


func _apply_attack_wall_plan(plan:Dictionary) -> void:
	var heading:Vector2 = plan.get("direction",Vector2.ZERO)
	if heading.length_squared() <= 0.0001:
		return
	_attack_heading = heading.normalized()
	var planned_reflect:Vector2 = plan.get("reflected",Vector2.ZERO)
	_attack_expected_reflect = planned_reflect.normalized() if planned_reflect.length_squared() > 0.0001 else Vector2.ZERO
	_attack_plan_timeout = maxf(float(plan.get("timeout",0.18)),0.08)
	_debug_attack_wall = plan.get("wall_point",Vector2.ZERO)
	_debug_attack_reflect = _attack_expected_reflect
	_debug_attack_target = plan.get("predicted_target",_attack_target.global_position if _attack_target != null else Vector2.ZERO)
	_debug_plan_label = "ATTACK: %s" % str(plan.get("kind","wall"))


func _stop_attack(reason:String,apply_reenter:bool = true) -> void:
	if debug_speedster_ai and _attack_active:
		print("[极速者 V23] stop attack: ",reason)
	_attack_active = false
	_attack_target = null
	_attack_heading = Vector2.ZERO
	_attack_expected_reflect = Vector2.ZERO
	_attack_plan_timeout = 0.0
	_attack_replan_left = 0.0
	_attack_no_plan_left = 0.0
	_physics_commit_left = 0.0
	_wall_credit = false
	_attack_distance = 0.0
	_hazard_detour_direction = Vector2.ZERO
	_hazard_detour_left = 0.0
	_debug_attack_wall = Vector2.ZERO
	_debug_attack_reflect = Vector2.ZERO
	_debug_attack_target = Vector2.ZERO
	if apply_reenter:
		_attack_reenter_left = maxf(_attack_reenter_left,attack_reenter_delay)


# ============================================================
# Fast-mode hazard detour
# ============================================================

func _update_fast_hazard_detour() -> void:
	if not _attack_active or _interrupt.active() or _physics_commit_left > 0.0:
		return
	if _hazard_detour_left > 0.0 and _hazard_detour_direction.length_squared() > 0.0001:
		return
	var heading:Vector2 = _attack_heading if _attack_heading.length_squared() > 0.0001 else direction
	if heading.length_squared() <= 0.0001:
		return
	var hit:Dictionary = _raycast_layer1(global_position,heading,hazard_lookahead)
	if hit.is_empty() or not _is_hazard_collider(hit.get("collider",null)):
		return

	var detour:Vector2 = _choose_hazard_detour(heading)
	if detour.length_squared() <= 0.0001:
		# 快速模式前方被危险地形封死且没有出口：直接退出攻击，普通 AI 自己处理，不在这里烧能量。
		_stop_attack("hazard_closed")
		return
	_hazard_detour_direction = detour
	_hazard_detour_left = hazard_detour_time
	_attack_plan_timeout = 0.0
	_attack_replan_left = hazard_detour_time
	_debug_plan_label = "ATTACK: HAZARD DETOUR"


func _choose_hazard_detour(base_heading:Vector2) -> Vector2:
	var angles:Array[float] = [28.0,-28.0,46.0,-46.0,66.0,-66.0,82.0,-82.0]
	var best:Vector2 = Vector2.ZERO
	var best_score:float = -INF
	for degrees:float in angles:
		var candidate:Vector2 = base_heading.rotated(deg_to_rad(degrees)).normalized()
		var clearance:float = _body_motion_clearance(candidate,hazard_detour_probe)
		if clearance < hazard_min_exit_space:
			continue
		var endpoint:Vector2 = global_position + candidate * minf(clearance,hazard_detour_probe) * 0.72
		var openness:float = _local_openness(endpoint,candidate,90.0)
		if openness < hazard_min_exit_space * 0.72:
			continue
		var score:float = openness - absf(degrees) * 0.22 + clearance * 0.15
		if score > best_score:
			best = candidate
			best_score = score
	return best


# ============================================================
# Direction arbitration
# ============================================================

func _apply_direction_owner() -> void:
	# 1. 防御 interrupt 永远是最高优先级，但只是短暂覆盖。
	if _interrupt != null and _interrupt.active():
		_write_override_direction(_interrupt.direction)
		_debug_plan_label = "DODGE: %s" % _interrupt.reason
		return

	# 2. 真实碰撞后的短 commit：绝不覆盖 ball.gd 刚算出的 bounce direction。
	if _attack_active and _physics_commit_left > 0.0:
		_debug_plan_label = "ATTACK: PHYSICS COMMIT"
		return

	# 3. 快速状态危险地形局部绕行。
	if _attack_active and _hazard_detour_left > 0.0 and _hazard_detour_direction.length_squared() > 0.0001:
		_write_override_direction(_hazard_detour_direction)
		return

	# 4. 主动反弹攻击只负责“去墙的入射方向”；拿到真实反弹后若 heading==direction 则继续真实轨迹。
	if _attack_active and _attack_heading.length_squared() > 0.0001:
		_write_override_direction(_attack_heading)
		return

	# 5. 普通防御结束后的极短 carry，不开极速，避免刚躲开就被普通 AI 拉回攻击线。
	if not _attack_active and _handoff_time_left > 0.0 and _handoff_direction.length_squared() > 0.0001:
		_write_override_direction(_handoff_direction)
		return

	# HARD RULE：NORMAL 时不写 direction。
	_debug_plan_label = "NORMAL"


# ============================================================
# Speed / damage / energy executor
# ============================================================

func _update_speed_damage_energy(real_dt:float) -> void:
	if _attack_active and energy <= attack_stop_energy:
		_stop_attack("energy_stop")

	var wants_defense_speed:bool = _interrupt != null and _interrupt.active() and _interrupt.speed_time_left > 0.0
	if wants_defense_speed and not _attack_active and energy < minimum_dodge_energy:
		_interrupt.speed_time_left = 0.0
		wants_defense_speed = false

	var speed_active:bool = _attack_active or wants_defense_speed
	_set_speed_visual(speed_active)

	var logical_multiplier:float = _logical_speed_multiplier()
	var slow:float = clampf(Game.get_time_scale_override_factor(),0.05,1.0) if speed_active else 1.0
	Speed = _base_speed * logical_multiplier / slow if speed_active else _base_speed
	_last_speed_written = Speed
	_wrote_speed_last_tick = true

	_current_attack_damage_multiplier = _current_damage_multiplier()

	var drain:float = 0.0
	if _attack_active:
		drain = attack_energy_drain_per_second + float(_attack_speed_stage()) * attack_stage_extra_drain
	elif wants_defense_speed:
		drain = dodge_energy_drain_per_second

	if drain > 0.0:
		_energy_precise = maxf(_energy_precise - drain * real_dt,0.0)
		_recharge_delay_left = maxf(_recharge_delay_left,energy_recharge_delay)
	else:
		if absf(float(energy) - _energy_precise) >= 1.1:
			_energy_precise = float(energy)
		if _recharge_delay_left <= 0.0 and max_energy > 0:
			_energy_precise = minf(_energy_precise + energy_recharge_per_second * real_dt,float(max_energy))
	energy = clampi(int(floor(_energy_precise + 0.0001)),0,max_energy)


func _attack_speed_stage() -> int:
	if not _attack_active:
		return 0
	if _attack_distance >= attack_stage_distance_4:
		return 4
	if _attack_distance >= attack_stage_distance_3:
		return 3
	if _attack_distance >= attack_stage_distance_2:
		return 2
	if _attack_distance >= attack_stage_distance_1:
		return 1
	return 0


func _attack_speed_multiplier() -> float:
	match _attack_speed_stage():
		0:
			return attack_speed_stage_0
		1:
			return attack_speed_stage_1
		2:
			return attack_speed_stage_2
		3:
			return attack_speed_stage_3
		_:
			return attack_speed_stage_4


func _logical_speed_multiplier() -> float:
	if _attack_active:
		return maxf(_attack_speed_multiplier(),1.0)
	if _interrupt != null and _interrupt.active() and _interrupt.speed_time_left > 0.0:
		return maxf(dodge_speed_multiplier,1.0)
	return 1.0


func _current_damage_multiplier() -> float:
	var speed_mult:float = _logical_speed_multiplier()
	if speed_mult <= 1.0:
		return 1.0
	return clampf(1.0 + (speed_mult - 1.0) * damage_speed_slope,1.0,max_damage_multiplier)


func current_hit_damage_multiplier() -> float:
	return maxf(_current_attack_damage_multiplier,0.0)


func _attack_speed_world_value() -> float:
	return _base_speed * maxf(_attack_speed_multiplier(),1.0)


func _is_any_speed_active() -> bool:
	return _attack_active or (_interrupt != null and _interrupt.active() and _interrupt.speed_time_left > 0.0)


func _set_speed_visual(active:bool) -> void:
	if active == _speed_visual_active:
		return
	_speed_visual_active = active
	if multiplayer.has_multiplayer_peer():
		_sync_speed_visual.rpc(active)
	else:
		_sync_speed_visual(active)


@rpc("authority","call_local","reliable")
func _sync_speed_visual(active:bool) -> void:
	if health <= 0 or _dead_shutdown:
		active = false
	if _speed_source_key.is_empty():
		_speed_source_key = "speedster_v23:%s" % str(get_path())
	if active:
		Game.request_time_scale_override(_speed_source_key,world_slow_factor,speed_world_tint)
	else:
		Game.release_time_scale_override(_speed_source_key)

	if image != null and is_instance_valid(image):
		if image is Sprite2D:
			var sprite:Sprite2D = image as Sprite2D
			if active and speed_texture != null:
				sprite.texture = speed_texture
			elif not active and normal_texture != null:
				sprite.texture = normal_texture
		image.scale = _base_image_scale * (speed_visual_scale_multiplier if active else 1.0)

	if health <= 0 or _dead_shutdown:
		return
	if active:
		# V283：进入任意极速状态时使用用户提供的角色定位音效。
		# _sync_speed_visual 本身是 authority/call_local RPC，所以房主和房客都会各自在同一角色位置听到一次。
		if not _play_speedster_enter_audio() and not speed_mode_enter_sfx.is_empty():
			# 文件意外缺失时才回退旧项目 SFX，避免正常情况下双重播放。
			Audios.play_sfx(speed_mode_enter_sfx,{},true)
	elif not speed_mode_exit_sfx.is_empty():
		Audios.play_sfx(speed_mode_exit_sfx,{},true)


func _play_speedster_enter_audio() -> bool:
	if not ResourceLoader.exists(SPEEDSTER_ENTER_AUDIO_PATH):
		return false
	var loaded:Resource = ResourceLoader.load(SPEEDSTER_ENTER_AUDIO_PATH)
	if not loaded is AudioStream:
		return false
	var player := AudioStreamPlayer2D.new()
	player.name = "SpeedsterEnterAudio"
	player.stream = loaded as AudioStream
	# V284：用户反馈原始音源很轻。保留 2D 定位，但显著减弱距离衰减并提高播放增益。
	player.max_distance = 3000.0
	player.attenuation = 0.20
	player.volume_db = 7.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return true


# ============================================================
# Real collision integration
# ============================================================

func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	var collider:Variant = collision.get_collider() if collision != null else null
	super.when_collide(speed,collision)
	if not _attack_active or collision == null:
		return

	if collider is ball:
		var other:ball = collider as ball
		if _is_hostile_character(other):
			# 命中角色之后必须再次先碰墙，禁止“弹开一点就重新追着同一个人撞”。
			_wall_credit = false
			_attack_heading = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO
			_attack_plan_timeout = 0.0
			_attack_replan_left = physics_bounce_commit_time
			_physics_commit_left = physics_bounce_commit_time
			_debug_plan_label = "ATTACK: HIT -> NEED WALL"
		return

	if _is_hazard_collider(collider):
		_attack_plan_timeout = 0.0
		_attack_replan_left = 0.0
		_hazard_detour_left = 0.0
		return

	# 非角色、非危险实体视为真正可利用的墙面。ball.gd 已经使用真实 normal 完成 bounce。
	_wall_credit = true
	_attack_heading = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO
	_physics_commit_left = physics_bounce_commit_time
	_attack_plan_timeout = physics_bounce_commit_time
	_attack_replan_left = physics_bounce_commit_time
	_debug_plan_label = "ATTACK: WALL BOUNCE"


# ============================================================
# Combat lock: 极速时敌人瞄“运动残影”
# ============================================================

func get_combat_lock_position() -> Vector2:
	if not _is_any_speed_active() or health <= 0 or _dead_shutdown:
		return global_position
	var motion:Vector2 = velocity
	if motion.length_squared() <= 1.0 and direction.length_squared() > 0.0001:
		motion = direction.normalized() * _base_speed * _logical_speed_multiplier()
	if motion.length_squared() <= 1.0:
		return global_position

	var logical_mult:float = _logical_speed_multiplier()
	var lead_time:float = lerpf(0.045,0.18,clampf((logical_mult - 1.0) / 2.7,0.0,1.0))
	var dir:Vector2 = motion.normalized()
	var distance:float = motion.length() * lead_time
	var hit:Dictionary = _raycast_layer1(global_position,dir,distance)
	if hit.is_empty():
		return global_position + dir * distance
	if _is_hazard_collider(hit.get("collider",null)):
		return hit.get("position",global_position) - dir * 4.0
	var point:Vector2 = hit.get("position",global_position)
	var normal:Vector2 = hit.get("normal",Vector2.ZERO)
	if normal.length_squared() <= 0.0001:
		return point
	var first_distance:float = global_position.distance_to(point)
	var remaining:float = maxf(distance - first_distance,0.0)
	var reflected:Vector2 = dir.bounce(normal.normalized()).normalized()
	return point + normal.normalized() * 3.0 + reflected * remaining


# ============================================================
# Character / threat helpers
# ============================================================

func _is_hostile_projectile(candidate:Node) -> bool:
	return candidate != self and PROJECTILE_API.supports(candidate,"predict") and PROJECTILE_API.hostile(self,candidate)

func _is_hostile_character(candidate:ball) -> bool:
	if candidate == self or not is_instance_valid(candidate):
		return false
	if not candidate.is_combat_targetable():
		return false
	if candidate.health <= 0:
		return false
	if candidate.state_machine != null and candidate.state_machine.current_state == State.Die:
		return false
	if not Team.is_empty() and candidate.Team == Team:
		return false
	return true


func _valid_attack_target(candidate) -> bool:
	# candidate 可能是上一帧已经 free 的目标。这里故意不写 :ball，
	# 否则 GDScript 会在进入函数体之前先做强类型参数检查，
	# 对 previously freed 引用直接报 Invalid type，根本来不及 is_instance_valid()。
	if not is_instance_valid(candidate):
		return false
	if not candidate is ball:
		return false
	return _is_hostile_character(candidate as ball)


func _preferred_attack_target() -> ball:
	# Object 引用被 free 后不会自动变成 null；必须先验证实例，再做 `is ball`。
	if is_instance_valid(Target_Enemy) and Target_Enemy is ball:
		var forced_target:ball = Target_Enemy as ball
		if _is_hostile_character(forced_target):
			return forced_target
	if is_instance_valid(Nearest_Enemy) and Nearest_Enemy is ball:
		var nearest_target:ball = Nearest_Enemy as ball
		if _is_hostile_character(nearest_target):
			return nearest_target
	var best:ball = null
	var best_distance:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_hostile_character(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < best_distance:
			best = candidate
			best_distance = distance_sq
	return best


func _enemy_likely_targets_self(enemy:ball) -> bool:
	if enemy.Target_Enemy == self or enemy.Nearest_Enemy == self:
		return true
	# 有明确别的目标时不替它脑补。
	if enemy.Target_Enemy != null and is_instance_valid(enemy.Target_Enemy):
		return false
	# 兜底：若我们确实是它最近的敌人，则允许预判；1v1 尤其重要。
	# V432 性能：先用一次“我到它的距离”做早退——只要场上任意一个敌人比我更近，我就不是它的最近敌人。
	# 以下仍是同一套判定，只是把 get_nodes_in_group 全量扫描换成 World 已缓存的战斗单位表并允许提前返回。
	var my_distance:float = enemy.global_position.distance_squared_to(global_position)
	var units:Array = []
	if _cached_world != null and is_instance_valid(_cached_world) and _cached_world.has_method("get_battle_units_fast"):
		units = _cached_world.get_battle_units_fast()
	else:
		units = get_tree().get_nodes_in_group("Ball")
	var closest:ball = null
	var best_distance:float = INF
	for node:Node in units:
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if candidate == enemy or candidate.Type != Ball_Type.Ball or candidate.health <= 0:
			continue
		if not enemy.Team.is_empty() and candidate.Team == enemy.Team:
			continue
		var d:float = enemy.global_position.distance_squared_to(candidate.global_position)
		if candidate != self and d < my_distance:
			return false
		if d < best_distance:
			best_distance = d
			closest = candidate
	return closest == self


func _is_ranged_character(enemy:ball) -> bool:
	return enemy.has_type_tag("射手") or enemy.has_type_tag("高频") or enemy.has_type_tag("远程")


func _is_melee_character(enemy:ball) -> bool:
	if enemy.has_type_tag("近战"):
		return true
	for property_name:String in ["dash_speed","dash_distance","dash_max_distance","stab_range","fist_max_length"]:
		if _has_property(enemy,property_name):
			return true
	return false


func _enemy_currently_attacking(enemy:ball) -> bool:
	if enemy.Attacking or enemy.Using_Skill:
		return true
	if enemy.state_machine != null:
		return enemy.state_machine.current_state == State.Attack or enemy.state_machine.current_state == State.Skill
	return false


func _enemy_next_offense_delay(enemy:ball) -> float:
	if _enemy_currently_attacking(enemy):
		return 0.0
	if enemy.state_machine == null:
		return INF
	var result:float = INF
	if enemy.Can_Attack:
		var attack_elapsed:float = float(enemy.state_machine.last_state_dis.get("Attack",0.0))
		result = minf(result,maxf(enemy.Attack_Cooling - attack_elapsed,0.0))
	if enemy.Can_Skill:
		var skill_elapsed:float = float(enemy.state_machine.last_state_dis.get("Skill",0.0))
		result = minf(result,maxf(enemy.Skill_Cooling - skill_elapsed,0.0))
	return result


func _enemy_attack_axis(enemy:ball) -> Vector2:
	# 真正高速突进时 velocity 比普通 direction 可信得多。
	if enemy.velocity.length() > maxf(enemy.Speed * 1.35,180.0):
		return enemy.velocity.normalized()
	for property_name:String in ["dash_direction","thrust_direction","stab_direction","attack_direction","skill_direction"]:
		var value:Variant = _property_value(enemy,property_name,null)
		if value is Vector2:
			var vector_value:Vector2 = value
			if vector_value.length_squared() > 0.0001:
				return vector_value.normalized()
	if _enemy_likely_targets_self(enemy):
		var to_self:Vector2 = global_position - enemy.global_position
		if to_self.length_squared() > 0.0001:
			return to_self.normalized()
	if enemy.direction.length_squared() > 0.0001:
		return enemy.direction.normalized()
	return Vector2.ZERO


func _estimate_melee_reach(enemy:ball) -> float:
	var values:Array[float] = [melee_default_reach]
	for property_name:String in ["dash_max_distance","dash_distance","stab_range","fist_max_length","fist_rest_length"]:
		var value:Variant = _property_value(enemy,property_name,null)
		if value is float or value is int:
			values.append(float(value))
	# 拳击手 dash_distance + fist_max_length 是组合威胁距离。
	var dash_distance:float = _first_numeric_property(enemy,["dash_distance"],0.0)
	var fist_length:float = _first_numeric_property(enemy,["fist_max_length"],0.0)
	if dash_distance > 0.0 and fist_length > 0.0:
		values.append(dash_distance + fist_length)
	var result:float = melee_default_reach
	for value:float in values:
		result = maxf(result,value)
	return result


func _estimate_melee_speed(enemy:ball) -> float:
	return maxf(_first_numeric_property(enemy,["dash_speed","thrust_speed","stab_speed"],melee_default_dash_speed),enemy.velocity.length())


func _manual_projectile_velocity(projectile:Node2D) -> Vector2:
	if projectile == null or not is_instance_valid(projectile):
		return Vector2.ZERO
	var raw_velocity:Variant = _property_value(projectile,"velocity",null)
	if raw_velocity is Vector2:
		var velocity_value:Vector2 = raw_velocity
		if velocity_value.length_squared() > 1.0:
			return velocity_value
	var raw_direction:Variant = _property_value(projectile,"direction",null)
	if raw_direction is Vector2:
		var direction_value:Vector2 = raw_direction
		if direction_value.length_squared() > 0.0001:
			var speed_value:float = _first_numeric_property(projectile,["Speed","speed","max_speed","bullet_speed","projectile_speed","throw_speed"],320.0)
			return direction_value.normalized() * speed_value
	return Vector2.ZERO


func _first_numeric_property(object:Object,names:Array[String],fallback:float) -> float:
	for property_name:String in names:
		var value:Variant = _property_value(object,property_name,null)
		if value is float or value is int:
			var number:float = float(value)
			if number > 0.0:
				return number
	return fallback


func _has_property(object:Object,property_name:String) -> bool:
	# V431 性能：按脚本缓存属性名集合（classes/property_index.gd），不再逐次 get_property_list()。
	return PROPERTY_INDEX.has_property(object,property_name)


const PROPERTY_INDEX = preload("res://classes/property_index.gd")


func _property_value(object:Object,property_name:String,fallback:Variant) -> Variant:
	if not _has_property(object,property_name):
		return fallback
	return object.get(property_name)


# ============================================================
# Physics helpers
# ============================================================

func _body_motion_clearance(test_direction:Vector2,max_distance:float) -> float:
	if test_direction.length_squared() <= 0.0001 or max_distance <= 0.0:
		return 0.0
	var dir:Vector2 = test_direction.normalized()
	if not test_move(global_transform,dir * max_distance,null,0.08,false):
		return max_distance
	var low:float = 0.0
	var high:float = max_distance
	for _i:int in range(8):
		var middle:float = (low + high) * 0.5
		if test_move(global_transform,dir * middle,null,0.08,false):
			high = middle
		else:
			low = middle
	return low


func _combined_collision_clearance(other:ball,separation_axis:Vector2) -> float:
	var axis:Vector2 = separation_axis.normalized() if separation_axis.length_squared() > 0.0001 else Vector2.UP
	return _collision_support_radius(self,axis) + _collision_support_radius(other,axis)


func _collision_support_radius(entity:ball,world_axis:Vector2) -> float:
	if entity == null or not is_instance_valid(entity):
		return 12.0
	var collision:CollisionShape2D = entity.collision_shape_2d
	if collision == null or collision.shape == null:
		return 12.0
	var axis:Vector2 = world_axis.normalized() if world_axis.length_squared() > 0.0001 else Vector2.UP
	var local_axis:Vector2 = axis.rotated(-collision.global_rotation)
	var scale_abs:Vector2 = Vector2(absf(collision.global_scale.x),absf(collision.global_scale.y))
	var shape:Shape2D = collision.shape
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius * maxf(scale_abs.x,scale_abs.y)
	if shape is RectangleShape2D:
		var half_size:Vector2 = (shape as RectangleShape2D).size * scale_abs * 0.5
		return absf(local_axis.x) * half_size.x + absf(local_axis.y) * half_size.y
	if shape is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape as CapsuleShape2D
		var radius:float = capsule.radius * maxf(scale_abs.x,scale_abs.y)
		var half_segment:float = maxf(capsule.height * scale_abs.y * 0.5 - radius,0.0)
		return radius + absf(local_axis.y) * half_segment
	return 12.0 * maxf(scale_abs.x,scale_abs.y)


func _ball_motion_velocity(entity:ball) -> Vector2:
	if entity.velocity.length_squared() > 1.0:
		return entity.velocity
	if entity.direction.length_squared() > 0.0001:
		return entity.direction.normalized() * maxf(entity.Speed,0.0)
	return Vector2.ZERO


func _raycast_layer1(origin:Vector2,direction_value:Vector2,distance:float) -> Dictionary:
	if get_world_2d() == null or direction_value.length_squared() <= 0.0001:
		return {}
	var query := PhysicsRayQueryParameters2D.new()
	query.from = origin
	query.to = origin + direction_value.normalized() * maxf(distance,1.0)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query)


func _is_hazard_collider(collider:Variant) -> bool:
	if collider == null or collider is ball or not collider is Node:
		return false
	var node:Node = collider as Node
	var text:String = node.name.to_lower()
	var script:Script = node.get_script() as Script
	if script != null:
		text += " " + script.resource_path.to_lower()
	for token:String in ["矿工小石头","棋子","棋石","stone","rock","chess","piece"]:
		if text.contains(token.to_lower()):
			return true
	return false


func _local_openness(point:Vector2,heading:Vector2,probe:float) -> float:
	var directions:Array[Vector2] = [heading,heading.rotated(deg_to_rad(45.0)),heading.rotated(deg_to_rad(-45.0)),heading.rotated(deg_to_rad(90.0)),heading.rotated(deg_to_rad(-90.0))]
	var total:float = 0.0
	var best:float = 0.0
	for candidate:Vector2 in directions:
		var hit:Dictionary = _raycast_layer1(point,candidate,probe)
		var clear:float = probe
		if not hit.is_empty():
			clear = point.distance_to(hit.get("position",point))
		total += clear
		best = maxf(best,clear)
	if best < probe * 0.35:
		return 0.0
	return total / float(directions.size())


func _point_segment_distance(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var denom:float = ab.length_squared()
	if denom <= 0.000001:
		return point.distance_to(a)
	var t:float = clampf((point - a).dot(ab) / denom,0.0,1.0)
	return point.distance_to(a + ab * t)


func _cleanup_threat_locks() -> void:
	var stale:Array[String] = []
	for raw_key:Variant in _threat_locks.keys():
		var key:String = str(raw_key)
		if float(_threat_locks[raw_key]) <= _clock:
			stale.append(key)
	for key:String in stale:
		_threat_locks.erase(key)


func _real_delta(delta:float) -> float:
	var factor:float = clampf(Game.get_time_scale_override_factor(),0.05,1.0)
	return delta / factor


# ============================================================
# Debug visualization
# ============================================================

func _draw() -> void:
	if not debug_speedster_ai:
		return

	if _debug_threat != null and _debug_threat.is_valid():
		var origin_local:Vector2 = to_local(_debug_threat.origin)
		var axis:Vector2 = _debug_threat.axis.normalized()
		var line_length:float = _debug_threat.reach if _debug_threat.is_line_threat() else 240.0
		draw_line(origin_local,origin_local + axis * line_length,Color(1.0,0.25,0.2,0.82),2.0)
		draw_circle(origin_local,_debug_threat.radius,Color(1.0,0.25,0.2,0.18),false,1.0)

	if _debug_dodge_direction.length_squared() > 0.0001:
		draw_line(Vector2.ZERO,_debug_dodge_direction * 110.0,Color(0.2,1.0,0.35,0.95),4.0)

	if _attack_active:
		if _debug_attack_wall != Vector2.ZERO:
			var wall_local:Vector2 = to_local(_debug_attack_wall)
			draw_line(Vector2.ZERO,wall_local,Color(0.25,0.65,1.0,0.95),3.0)
			draw_circle(wall_local,5.0,Color(0.9,0.95,1.0,1.0),true)
			if _debug_attack_reflect.length_squared() > 0.0001:
				draw_line(wall_local,wall_local + _debug_attack_reflect * 150.0,Color(0.55,0.35,1.0,0.95),3.0)
		if _debug_attack_target != Vector2.ZERO:
			draw_circle(to_local(_debug_attack_target),8.0,Color(1.0,0.2,0.8,0.9),false,2.0)

	draw_string(
		MOJANGLES_FONT,
		Vector2(14.0,-22.0),
		"%s | E:%d | S:%d | x%.2f | DODGE %.3f" % [_debug_plan_label,energy,_attack_speed_stage(),_logical_speed_multiplier(),_debug_dodge_burst],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color.WHITE
	)


# ============================================================
# RL public API (Godot RL Agents controller calls these)
# ============================================================

func rl_set_dodge_action(action:int) -> void:
	_rl_dodge_action = clampi(action,0,3)
	_rl_action_left = maxf(rl_action_hold_seconds,threat_scan_interval * 1.5)


func rl_set_combat_action(action:int) -> void:
	_rl_combat_action = clampi(action,0,1)


func rl_get_dodge_observation() -> Array[float]:
	var analyzer:Node = _training_threat_analyzer()
	if analyzer != null and analyzer.has_method("get_observation_for"):
		return analyzer.call("get_observation_for",self)

	# 只有不在 V2 训练场时才回退到旧 17 维观察。Controller 会用 analyzer 的固定长度，
	# 因此正式 V2 训练不会在运行中改变 observation shape。
	var obs:Array[float] = []
	var energy_ratio:float = float(energy) / maxf(float(max_energy),1.0)
	obs.append(clampf(energy_ratio,0.0,1.0))
	obs.append(clampf(_base_speed / 1200.0,0.0,1.0))
	obs.append(clampf(direction.x,-1.0,1.0))
	obs.append(clampf(direction.y,-1.0,1.0))
	var threat:SpeedsterThreat = _find_projectile_threat()
	if threat == null or not threat.is_valid():
		for _i:int in range(13):
			obs.append(0.0)
		return obs
	var rel:Vector2 = threat.origin - global_position
	var rel_vel:Vector2 = threat.source_velocity - (_controller_direction * _base_speed)
	var left_plan:SpeedsterMotionPlan = _build_projectile_side_dodge(threat,1)
	var right_plan:SpeedsterMotionPlan = _build_projectile_side_dodge(threat,-1)
	var left_dir:Vector2 = Vector2(-threat.axis.y,threat.axis.x).normalized()
	var right_dir:Vector2 = -left_dir
	var left_clear:float = _body_motion_clearance(left_dir,dodge_probe_distance)
	var right_clear:float = _body_motion_clearance(right_dir,dodge_probe_distance)
	obs.append(1.0)
	obs.append(clampf(rel.x / maxf(projectile_scan_radius,1.0),-1.0,1.0))
	obs.append(clampf(rel.y / maxf(projectile_scan_radius,1.0),-1.0,1.0))
	obs.append(clampf(rel_vel.x / 1600.0,-1.0,1.0))
	obs.append(clampf(rel_vel.y / 1600.0,-1.0,1.0))
	obs.append(clampf(threat.time_to_impact / maxf(projectile_reaction_ttc,0.001),0.0,1.0))
	obs.append(clampf(threat.severity / 4.0,0.0,1.0))
	obs.append(1.0 if left_plan != null else 0.0)
	obs.append(1.0 if right_plan != null else 0.0)
	obs.append(clampf(left_clear / maxf(dodge_probe_distance,1.0),0.0,1.0))
	obs.append(clampf(right_clear / maxf(dodge_probe_distance,1.0),0.0,1.0))
	obs.append(clampf((left_plan.speed_time_left if left_plan != null else max_dodge_speed_burst) / maxf(max_dodge_speed_burst,0.001),0.0,1.0))
	obs.append(clampf((right_plan.speed_time_left if right_plan != null else max_dodge_speed_burst) / maxf(max_dodge_speed_burst,0.001),0.0,1.0))
	return obs


func rl_get_training_snapshot() -> Dictionary:
	var threat:SpeedsterThreat = _rl_last_threat
	if threat == null or not threat.is_valid():
		threat = _find_training_generic_threat() if rl_dodge_training_enabled else _find_projectile_threat()
	return {
		"health":float(health),
		"max_health":float(Max_health),
		"energy":float(energy),
		"has_threat":threat != null,
		"threat_ttc":threat.time_to_impact if threat != null else INF,
		"threat_key":threat.source_key if threat != null else "",
		"action":_rl_dodge_action,
		"combat_action":_rl_combat_action,
		"action_used":_rl_last_action_used,
		"action_valid":_rl_last_action_valid,
		"speed_active":_is_any_speed_active(),
		"attack_active":_attack_active,
	}
