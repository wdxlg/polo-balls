extends ball

const LAYOUT_POINT_SCRIPT := preload("res://scripts/characters/智者_布局点.gd")

# ========================================================
# 智者：预测路径 + 自适应重排 + 战术走位的逐点布局 v11
#
# 核心规则：
# - 平时仍然遵循 ball 默认移动/撞墙反弹。
# - 需要布局时，只允许在当前默认运动方向附近、有限距离/有限时间内主动偏转。
# - 必须由智者本人走到位置后才放下一个点；每次只放一个。
# - 放点位置优先选择“敌人未来运动轨迹与智者可达区域的交点”，没有合适交点就不瞎放。
# - 敌人按 1 -> 2 -> 3 -> 4 顺序踩点；1 不伤害，2 开始逐级增伤。
# - 如果当前应踩的点在预测时间内已经很难踩到，会在较长冷却结束后：
#     1) 优先把更容易踩到的已有点改成当前编号；
#     2) 如果所有未完成点都难以踩到，则撤销 1~N 个未完成点，让智者重新布局。
# - 已经有“当前应踩点”时，智者会把有限的主动移动也纳入布局：
#     * 敌人本来就快踩到点时，优先侧移让路，避免自己把敌人撞偏；
#     * 敌人偏离布局但几何位置合适时，尝试绕到敌人背侧并把它撞向当前布局点。
# ========================================================

@export_category("布局节奏")
@export_range(0.5,20.0,0.1) var layout_interval:float = 4.8
@export_range(2,8,1) var points_per_layout:int = 4
@export_range(1.0,30.0,0.1) var layout_lifetime:float = 13.0
@export_range(0.0,3.0,0.05) var between_point_delay:float = 0.38
@export_range(3.0,24.0,0.5) var layout_point_radius:float = 6.0
@export_range(0.5,5.0,0.1) var layout_line_width:float = 1.15
@export var layout_line_color:Color = Color(0.90,0.78,0.20,0.62)

@export_category("受限主动移动")
@export_range(12.0,160.0,1.0) var active_move_max_distance:float = 56.0
@export_range(0.15,3.0,0.05) var active_move_max_time:float = 1.10
@export_range(8.0,85.0,1.0) var active_turn_limit_deg:float = 52.0
@export_range(0.05,1.0,0.05) var active_steer_strength:float = 0.76
@export_range(3.0,30.0,0.5) var placement_reach:float = 7.0
@export_range(8.0,100.0,1.0) var point_spacing_min:float = 21.0
@export_range(12.0,160.0,1.0) var point_spacing_max:float = 52.0
@export_range(4.0,60.0,1.0) var map_margin:float = 12.0
@export_range(0.05,0.8,0.05) var active_retarget_interval:float = 0.16

@export_category("敌人轨迹预测")
@export_range(0.6,6.0,0.1) var prediction_horizon:float = 3.0
@export_range(0.04,0.5,0.01) var prediction_step:float = 0.12
# 智者至少要比敌人早这么久到达落点，避免刚走到敌人已经经过。
@export_range(0.0,1.0,0.05) var intercept_min_lead:float = 0.16
@export_range(0.05,2.0,0.05) var intercept_preferred_lead:float = 0.48
@export_range(6.0,60.0,1.0) var predicted_touch_radius:float = 23.0

@export_category("布局自适应")
@export_range(0.1,2.0,0.05) var adaptive_check_interval:float = 0.28
@export_range(0.3,5.0,0.1) var unreachable_grace_time:float = 1.35
@export_range(0.5,12.0,0.1) var adaptive_cooldown:float = 4.8
@export_range(1,4,1) var adaptive_remove_max:int = 2
# 自适应判断会比放点预测稍微看得更远，避免太频繁撤销。
@export_range(0.8,8.0,0.1) var adaptive_prediction_horizon:float = 3.6

@export_category("布局战术移动")
# 战术移动仍然只改 direction，不增加 Speed，也不会绕开 ball 的碰撞/反弹。
@export_range(0.4,6.0,0.1) var tactic_cooldown:float = 1.9
@export_range(0.05,0.8,0.05) var tactic_check_interval:float = 0.15
@export_range(12.0,120.0,1.0) var tactic_move_max_distance:float = 44.0
@export_range(0.15,2.0,0.05) var tactic_move_max_time:float = 0.82
@export_range(10.0,85.0,1.0) var tactic_turn_limit_deg:float = 62.0
@export_range(0.1,1.0,0.05) var tactic_steer_strength:float = 0.82
# 敌人马上要踩点时，智者离路线太近就主动让开。
@export_range(0.2,2.5,0.05) var dodge_eta_window:float = 1.15
@export_range(8.0,70.0,1.0) var dodge_interference_radius:float = 25.0
@export_range(8.0,70.0,1.0) var dodge_side_distance:float = 29.0
# 敌人偏离当前布局点时，智者可尝试从背侧撞过去。
@export_range(16.0,160.0,1.0) var push_activation_range:float = 78.0
@export_range(16.0,160.0,1.0) var push_point_max_distance:float = 92.0
@export_range(6.0,50.0,1.0) var push_setup_offset:float = 23.0
@export_range(0.1,1.0,0.05) var push_commit_time:float = 0.34
@export_range(8.0,80.0,1.0) var push_distance:float = 34.0
@export_range(80.0,900.0,10.0) var push_speed:float = 430.0

@export_category("布局伤害")
# 1号点伤害固定为0；2号 = start，之后每一号 + step。
@export_range(0.0,10.0,0.05) var point_damage_start_multiplier:float = 1.0
@export_range(0.0,10.0,0.05) var point_damage_step_multiplier:float = 0.9
@export var point_hit_audio:String = "balls_hit1"
@export var place_audio:String = "ButtonDown1"

var _layout_points:Array[Area2D] = []
var _layout_line:Line2D = null
var _layout_cooldown_left:float = 0.0
var _layout_lifetime_left:float = 0.0
var _between_point_left:float = 0.0
var _next_point_index:int = 0
# 敌人下一次必须踩的编号。0代表1号，1代表2号……
var _target_progress:int = 0

var _moving_to_layout_point:bool = false
var _move_destination:Vector2 = Vector2.ZERO
var _move_origin:Vector2 = Vector2.ZERO
var _move_time_left:float = 0.0
var _move_target:ball = null
var _normal_direction:Vector2 = Vector2.ZERO
var _active_retarget_left:float = 0.0

var _adaptive_check_left:float = 0.0
var _adaptive_cooldown_left:float = 0.0
var _expected_unreachable_time:float = 0.0

const TACTIC_NONE:int = 0
const TACTIC_DODGE:int = 1
const TACTIC_PUSH_SETUP:int = 2
const TACTIC_PUSH_COMMIT:int = 3
var _tactical_mode:int = TACTIC_NONE
var _tactical_target:ball = null
var _tactical_destination:Vector2 = Vector2.ZERO
var _tactical_origin:Vector2 = Vector2.ZERO
var _tactical_base_direction:Vector2 = Vector2.ZERO
var _tactical_time_left:float = 0.0
var _tactical_cooldown_left:float = 0.0
var _tactical_check_left:float = 0.0


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	_layout_cooldown_left = randf_range(0.7,1.5)
	_adaptive_check_left = randf_range(0.08,0.22)
	_tactical_check_left = randf_range(0.05,0.16)
	_tactical_cooldown_left = randf_range(0.35,0.9)
	super._ready()


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and state != State.Die and health > 0:
		if is_player_controlled():
			_update_manual_layout_timers(delta)
		else:
			_update_layout(delta)
	super.tick_physics(state,delta)


func _update_manual_layout_timers(delta:float) -> void:
	# 不再由 AI 选落点/接管走位；已有布局仍按原寿命到期且碰触伤害有效。
	_cleanup_dead_points()
	_moving_to_layout_point = false
	_tactical_mode = TACTIC_NONE
	_between_point_left = maxf(_between_point_left - delta,0.0)
	if _layout_points.is_empty() and _next_point_index == 0:
		_layout_cooldown_left = maxf(_layout_cooldown_left - delta,0.0)
	if not _layout_points.is_empty():
		_layout_lifetime_left -= delta
		if _layout_lifetime_left <= 0.0:
			_finish_layout_round()


func controlled_attack_action() -> void:
	# 左键：必须亲自走到目标落点附近，维持布点间隔、最小间距和一轮点数。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active() or not has_player_control_aim():
		return
	if _between_point_left > 0.0 or _next_point_index >= maxi(points_per_layout,2):
		return
	if _layout_points.is_empty() and _layout_cooldown_left > 0.0:
		return
	if _get_target() == null or global_position.distance_to(player_control_aim_world_position()) > placement_reach:
		return
	_place_point_at_current_position()


func _update_layout(delta:float) -> void:
	_cleanup_dead_points()
	_adaptive_cooldown_left = maxf(_adaptive_cooldown_left - delta,0.0)
	_tactical_cooldown_left = maxf(_tactical_cooldown_left - delta,0.0)
	_tactical_check_left = maxf(_tactical_check_left - delta,0.0)

	if not _layout_points.is_empty():
		_layout_lifetime_left -= delta
		if _layout_lifetime_left <= 0.0:
			_finish_layout_round()
			return

	_update_adaptive_layout(delta)

	if _moving_to_layout_point:
		_update_active_move(delta)
		return

	if _tactical_mode != TACTIC_NONE:
		_update_tactical_move(delta)
		return

	# 已经存在当前应踩点时，有限主动移动不仅用于“去放点”，也参与保护/利用布局。
	# 只有满足明确几何条件且战术冷却结束才会介入，其余时间仍按 ball 默认方向移动。
	if _tactical_check_left <= 0.0:
		_tactical_check_left = maxf(tactic_check_interval,0.05)
		if _tactical_cooldown_left <= 0.0 and _try_begin_layout_tactic():
			return

	_between_point_left -= delta
	if _between_point_left > 0.0:
		return

	if _next_point_index >= maxi(points_per_layout,2):
		return

	if _layout_points.is_empty() and _next_point_index == 0:
		_layout_cooldown_left -= delta
		if _layout_cooldown_left > 0.0:
			return

	var target:ball = _get_target()
	if target == null:
		if _layout_points.is_empty():
			_layout_cooldown_left = 0.35
		return

	# 不再“为了必须放点而放点”。只有敌人未来路径上存在智者能够有限走到的拦截位置，
	# 才开始主动移动。否则继续默认运动，等一个更好的布局机会。
	_begin_active_move(target)


func _begin_active_move(target:ball) -> void:
	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		_layout_cooldown_left = 0.5
		return

	var base_dir:Vector2 = direction
	if base_dir.length_squared() <= 0.000001:
		base_dir = combat_target_position(target) - global_position
	if base_dir.length_squared() <= 0.000001:
		base_dir = Vector2.from_angle(randf_range(0.0,TAU))
	base_dir = base_dir.normalized()

	var choice:Dictionary = _choose_intercept_destination(target,rect,base_dir)
	if not bool(choice.get("ok",false)):
		# 没有合适拦截点时，不强行去敌人附近瞎摆圆。
		_between_point_left = 0.18
		return

	_normal_direction = base_dir
	_move_origin = global_position
	_move_target = target
	_move_destination = choice.get("position",global_position)
	_move_time_left = maxf(active_move_max_time,0.15)
	_active_retarget_left = maxf(active_retarget_interval,0.05)
	_moving_to_layout_point = true


func _choose_intercept_destination(target:ball,rect:Rect2,base_dir:Vector2) -> Dictionary:
	var path:Array[Dictionary] = _predict_enemy_path(target,rect,prediction_horizon,prediction_step)
	if path.is_empty():
		return {"ok":false}

	var max_distance:float = maxf(active_move_max_distance,12.0)
	var turn_limit:float = deg_to_rad(clampf(active_turn_limit_deg,1.0,89.0))
	var own_speed:float = maxf(Speed,1.0)
	var best_position:Vector2 = Vector2.ZERO
	var best_score:float = -INF
	var found:bool = false

	for sample in path:
		var candidate:Vector2 = _clamp_point(sample.get("position",combat_target_position(target)),rect)
		var target_eta:float = float(sample.get("time",0.0))
		var travel_vec:Vector2 = candidate - global_position
		var travel:float = travel_vec.length()

		# 必须真正在“一次允许的主动移动”内走得到。
		if travel > max_distance or travel < maxf(placement_reach * 0.65,3.0):
			continue
		if travel_vec.length_squared() <= 0.000001:
			continue

		var travel_dir:Vector2 = travel_vec.normalized()
		if absf(base_dir.angle_to(travel_dir)) > turn_limit:
			continue

		# 估算智者到达时间。敌人至少要比智者晚一点到，点才能真正落下来拦路。
		var wise_eta:float = travel / own_speed
		var lead:float = target_eta - wise_eta
		if lead < intercept_min_lead:
			continue

		if not _candidate_has_reasonable_spacing(candidate):
			continue

		# 轨迹交点是第一优先级；同时更喜欢“智者到后约半秒敌人才踩到”的位置。
		var score:float = 0.0
		score -= absf(lead - intercept_preferred_lead) * 80.0
		score -= travel * 0.10
		score += minf(_edge_distance(candidate,rect),30.0) * 0.05
		# 越靠近当前需要的编号，越应该优先放近期就能踩到的位置。
		var pending_ahead:int = maxi(_next_point_index - _target_progress,0)
		score -= absf(target_eta - (0.60 + float(pending_ahead) * 0.24)) * 7.0
		score += randf_range(-0.35,0.35)

		if score > best_score:
			best_score = score
			best_position = candidate
			found = true

	return {"ok":found,"position":best_position,"score":best_score}


func _candidate_has_reasonable_spacing(candidate:Vector2) -> bool:
	for point in _layout_points:
		if point == null or not is_instance_valid(point):
			continue
		if candidate.distance_to(point.global_position) < point_spacing_min * 0.70:
			return false
	return true


func _update_active_move(delta:float) -> void:
	if _move_target == null or not is_instance_valid(_move_target) or _move_target.health <= 0:
		_cancel_active_move(0.25)
		return

	# 去放点途中如果敌人正迎面冲来，继续硬走通常会先发生实体碰撞，把这一轮布局位置打乱。
	# 这里允许智者放弃本次落点，先做一次受限侧移；闪避结束后再重新寻找落点。
	if _tactical_cooldown_left <= 0.0 and _is_enemy_collision_threat(_move_target):
		var evade_rect:Rect2 = _get_map_rect()
		var evade_position:Vector2 = _choose_general_dodge_destination(_move_target,evade_rect)
		if evade_position != Vector2.INF:
			_cancel_active_move(0.14)
			_start_tactical_move(TACTIC_DODGE,_move_target,evade_position)
			return

	_move_time_left -= delta
	_active_retarget_left -= delta

	# 走过去的过程中也会重新观察敌人的当前轨迹，但仍受同一个移动距离/时间/转向上限约束。
	# 这样敌人中途撞墙后，智者不会继续冲向已经失效的旧预测点。
	if _active_retarget_left <= 0.0:
		_active_retarget_left = maxf(active_retarget_interval,0.05)
		var rect:Rect2 = _get_map_rect()
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			var choice:Dictionary = _choose_intercept_destination(_move_target,rect,_normal_direction)
			if bool(choice.get("ok",false)):
				var new_destination:Vector2 = choice.get("position",_move_destination)
				# 目标点必须继续落在本次主动移动总距离上限里。
				if _move_origin.distance_to(new_destination) <= active_move_max_distance + 0.01:
					_move_destination = new_destination

	var to_destination:Vector2 = _move_destination - global_position
	if to_destination.length() <= placement_reach:
		_finish_active_move_and_place()
		return

	var traveled:float = _move_origin.distance_to(global_position)
	if _move_time_left <= 0.0 or traveled >= active_move_max_distance:
		_cancel_active_move(0.20)
		return

	if to_destination.length_squared() <= 0.000001:
		_finish_active_move_and_place()
		return

	var desired:Vector2 = to_destination.normalized()
	var bounded:Vector2 = _clamp_direction_to_base(_normal_direction,desired,deg_to_rad(active_turn_limit_deg))
	var weight:float = clampf(active_steer_strength,0.05,1.0)
	var mixed:Vector2 = _normal_direction * (1.0 - weight) + bounded * weight
	if mixed.length_squared() > 0.000001:
		direction = mixed.normalized()


func _clamp_direction_to_base(base:Vector2,wanted:Vector2,max_angle:float) -> Vector2:
	if base.length_squared() <= 0.000001:
		return wanted.normalized()
	if wanted.length_squared() <= 0.000001:
		return base.normalized()
	var base_n:Vector2 = base.normalized()
	var wanted_n:Vector2 = wanted.normalized()
	var signed_angle:float = base_n.angle_to(wanted_n)
	var limited:float = clampf(signed_angle,-absf(max_angle),absf(max_angle))
	return base_n.rotated(limited).normalized()


func _finish_active_move_and_place() -> void:
	_moving_to_layout_point = false
	_move_target = null
	_move_time_left = 0.0
	if _normal_direction.length_squared() > 0.000001:
		direction = _normal_direction.normalized()
	_place_point_at_current_position()


func _cancel_active_move(delay:float) -> void:
	_moving_to_layout_point = false
	_move_target = null
	_move_time_left = 0.0
	if _normal_direction.length_squared() > 0.000001:
		direction = _normal_direction.normalized()
	_between_point_left = maxf(delay,0.05)


func _place_point_at_current_position() -> void:
	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		_layout_cooldown_left = 0.4
		return

	var position:Vector2 = global_position
	position.x = clampf(position.x,rect.position.x + 1.0,rect.end.x - 1.0)
	position.y = clampf(position.y,rect.position.y + 1.0,rect.end.y - 1.0)

	if not _candidate_has_reasonable_spacing(position):
		_between_point_left = 0.20
		return

	var point:Area2D = LAYOUT_POINT_SCRIPT.new()
	point.name = "WiseLayoutPoint_%d_%d" % [get_instance_id(),_next_point_index + 1]
	get_tree().current_scene.add_child(point)
	point.global_position = position
	point.call("configure",self,_next_point_index,layout_point_radius)
	_layout_points.append(point)

	if _layout_points.size() == 1:
		_layout_lifetime_left = maxf(layout_lifetime,1.0)
		_target_progress = 0
		_expected_unreachable_time = 0.0

	_next_point_index += 1
	_between_point_left = maxf(between_point_delay,0.0)
	_sort_layout_points()
	_refresh_layout_line()
	_refresh_point_states()
	if place_audio != "":
		Audios.play_sfx.rpc(place_audio,{},true)


# --------------------------------------------------------
# 布局战术走位：
# 1) 当前点本来就要被踩到 -> 智者主动让路，避免自己把敌人撞离轨迹。
# 2) 当前点暂时踩不到，但敌人离点/智者都不远 -> 绕到敌人背侧，尝试撞向该点。
# 两种行为都受距离、时间、转向和独立冷却限制。
# --------------------------------------------------------
func _try_begin_layout_tactic() -> bool:
	var expected:Area2D = _find_point_by_index(_target_progress)
	var target:ball = _get_target()
	if expected == null or target == null:
		return false

	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return false

	var path:Array[Dictionary] = _predict_enemy_path(target,rect,maxf(dodge_eta_window,1.2),prediction_step)
	var eta:float = _estimate_point_eta_from_path(expected.global_position,path)

	# 敌人已经在正确轨迹上时，不去抢着撞它；若智者自己挡在这条路附近，先侧移让路。
	if eta >= 0.0 and eta <= dodge_eta_window:
		var locked_target_position:Vector2 = combat_target_position(target)
		var line_distance:float = _point_to_segment_distance(
			global_position,
			locked_target_position,
			expected.global_position
		)
		if (
			global_position.distance_to(expected.global_position) <= dodge_interference_radius
			or line_distance <= dodge_interference_radius * 0.72
		):
			var dodge_position:Vector2 = _choose_dodge_destination(target,expected,rect)
			if dodge_position != Vector2.INF:
				_start_tactical_move(TACTIC_DODGE,target,dodge_position)
				return true
		return false

	# 当前点不在敌人近期自然轨迹上时，只有几何条件很合适才尝试“撞回布局”。
	var target_to_point:Vector2 = expected.global_position - combat_target_position(target)
	var point_distance:float = target_to_point.length()
	if point_distance < layout_point_radius + 2.0 or point_distance > push_point_max_distance:
		return false
	if global_position.distance_to(combat_target_position(target)) > push_activation_range:
		return false
	if target_to_point.length_squared() <= 0.000001:
		return false

	var push_dir:Vector2 = target_to_point.normalized()
	# 敌人自己已经明显朝圆走，就不多此一举。
	if target.direction.length_squared() > 0.000001 and target.direction.normalized().dot(push_dir) > 0.62:
		return false

	var behind:Vector2 = _clamp_point(combat_target_position(target) - push_dir * push_setup_offset,rect)
	if not _tactical_destination_reachable(behind):
		return false

	_start_tactical_move(TACTIC_PUSH_SETUP,target,behind)
	return true


func _choose_dodge_destination(target:ball,expected:Area2D,rect:Rect2) -> Vector2:
	var route:Vector2 = expected.global_position - combat_target_position(target)
	if route.length_squared() <= 0.000001:
		route = target.direction
	if route.length_squared() <= 0.000001:
		return Vector2.INF
	route = route.normalized()
	var side:Vector2 = Vector2(-route.y,route.x)

	var candidate_a:Vector2 = _clamp_point(global_position + side * dodge_side_distance,rect)
	var candidate_b:Vector2 = _clamp_point(global_position - side * dodge_side_distance,rect)
	var best:Vector2 = Vector2.INF
	var best_score:float = -INF
	for candidate in [candidate_a,candidate_b]:
		if not _tactical_destination_reachable(candidate):
			continue
		# 更远离“敌人 -> 当前布局点”的通路，也更远离敌人本体。
		var score:float = _point_to_segment_distance(
			candidate,combat_target_position(target),expected.global_position
		) * 2.0
		score += candidate.distance_to(combat_target_position(target)) * 0.18
		score += minf(_edge_distance(candidate,rect),24.0) * 0.05
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _is_enemy_collision_threat(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var to_self:Vector2 = global_position - target.global_position
	var distance:float = to_self.length()
	if distance > dodge_interference_radius * 1.35 or distance <= 0.001:
		return false
	if target.direction.length_squared() <= 0.000001:
		return distance <= dodge_interference_radius * 0.72
	return target.direction.normalized().dot(to_self.normalized()) >= 0.46


func _choose_general_dodge_destination(target:ball,rect:Rect2) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.INF
	var route:Vector2 = target.direction
	if route.length_squared() <= 0.000001:
		route = global_position - target.global_position
	if route.length_squared() <= 0.000001:
		return Vector2.INF
	route = route.normalized()
	var side:Vector2 = Vector2(-route.y,route.x)
	var candidates:Array[Vector2] = [
		_clamp_point(global_position + side * dodge_side_distance,rect),
		_clamp_point(global_position - side * dodge_side_distance,rect),
	]
	var best:Vector2 = Vector2.INF
	var best_score:float = -INF
	for candidate in candidates:
		if not _tactical_destination_reachable(candidate):
			continue
		var score:float = candidate.distance_to(target.global_position)
		score += minf(_edge_distance(candidate,rect),24.0) * 0.08
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _tactical_destination_reachable(candidate:Vector2) -> bool:
	var travel:Vector2 = candidate - global_position
	if travel.length() > maxf(tactic_move_max_distance,8.0):
		return false
	if travel.length_squared() <= 0.000001:
		return false

	var base_dir:Vector2 = direction
	if base_dir.length_squared() <= 0.000001:
		base_dir = travel.normalized()
	else:
		base_dir = base_dir.normalized()
	return absf(base_dir.angle_to(travel.normalized())) <= deg_to_rad(clampf(tactic_turn_limit_deg,1.0,89.0))


func _start_tactical_move(mode:int,target:ball,destination:Vector2) -> void:
	_tactical_mode = mode
	_tactical_target = target
	_tactical_origin = global_position
	_tactical_destination = destination
	_tactical_time_left = maxf(tactic_move_max_time,0.15)
	_tactical_base_direction = direction
	if _tactical_base_direction.length_squared() <= 0.000001:
		_tactical_base_direction = destination - global_position
	if _tactical_base_direction.length_squared() <= 0.000001:
		_tactical_base_direction = Vector2.RIGHT
	_tactical_base_direction = _tactical_base_direction.normalized()


func _update_tactical_move(delta:float) -> void:
	if _tactical_target == null or not is_instance_valid(_tactical_target) or _tactical_target.health <= 0:
		_finish_tactical_move(false)
		return

	var expected:Area2D = _find_point_by_index(_target_progress)
	# 纯闪避可以发生在还没放出1号点、或正在去放下一点的途中；
	# 只有“推向布局”必须依赖当前有效的目标圆。
	if _tactical_mode in [TACTIC_PUSH_SETUP,TACTIC_PUSH_COMMIT] and expected == null:
		_finish_tactical_move(false)
		return

	_tactical_time_left -= delta
	if _tactical_time_left <= 0.0:
		_finish_tactical_move(false)
		return
	if _tactical_origin.distance_to(global_position) >= tactic_move_max_distance:
		_finish_tactical_move(false)
		return

	if _tactical_mode == TACTIC_PUSH_SETUP:
		var to_point:Vector2 = expected.global_position - combat_target_position(_tactical_target)
		if to_point.length_squared() <= 0.000001:
			_finish_tactical_move(false)
			return
		var rect:Rect2 = _get_map_rect()
		var behind:Vector2 = _clamp_point(
			combat_target_position(_tactical_target) - to_point.normalized() * push_setup_offset,
			rect
		)
		if _tactical_origin.distance_to(behind) <= tactic_move_max_distance + 0.01:
			_tactical_destination = behind
		if global_position.distance_to(_tactical_destination) <= placement_reach + 2.0:
			_tactical_mode = TACTIC_PUSH_COMMIT
			_tactical_time_left = minf(_tactical_time_left,maxf(push_commit_time,0.1))
			_tactical_destination = combat_target_position(_tactical_target)
	elif _tactical_mode == TACTIC_PUSH_COMMIT:
		_tactical_destination = combat_target_position(_tactical_target)

	var to_destination:Vector2 = _tactical_destination - global_position
	if _tactical_mode == TACTIC_DODGE and to_destination.length() <= placement_reach:
		_finish_tactical_move(true)
		return
	if to_destination.length_squared() <= 0.000001:
		_finish_tactical_move(_tactical_mode == TACTIC_DODGE)
		return

	var desired:Vector2 = to_destination.normalized()
	var bounded:Vector2 = _clamp_direction_to_base(
		_tactical_base_direction,
		desired,
		deg_to_rad(tactic_turn_limit_deg)
	)
	var weight:float = clampf(tactic_steer_strength,0.05,1.0)
	var mixed:Vector2 = _tactical_base_direction * (1.0 - weight) + bounded * weight
	if mixed.length_squared() > 0.000001:
		direction = mixed.normalized()


func _finish_tactical_move(_success:bool) -> void:
	var finished_mode:int = _tactical_mode
	_tactical_mode = TACTIC_NONE
	_tactical_target = null
	_tactical_time_left = 0.0
	if _tactical_base_direction.length_squared() > 0.000001:
		direction = _tactical_base_direction.normalized()
	# 推人比单纯让路更强，所以成功或失败都稍微多等一会儿。
	var cooldown_scale:float = 1.25 if finished_mode in [TACTIC_PUSH_SETUP,TACTIC_PUSH_COMMIT] else 1.0
	_tactical_cooldown_left = maxf(tactic_cooldown * cooldown_scale,0.4)
	_tactical_check_left = maxf(tactic_check_interval,0.05)


func _point_to_segment_distance(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var ab_len_sq:float = ab.length_squared()
	if ab_len_sq <= 0.000001:
		return point.distance_to(a)
	var t:float = clampf((point - a).dot(ab) / ab_len_sq,0.0,1.0)
	var closest:Vector2 = a + ab * t
	return point.distance_to(closest)


# --------------------------------------------------------
# 自适应：判断“当前应该踩的圆”是否还在敌人可能经过的轨迹上。
# --------------------------------------------------------
func _update_adaptive_layout(delta:float) -> void:
	# 正在亲自走位放点/闪避/推人时不现场改编号，避免目标在脚下突然换号。
	if _moving_to_layout_point or _tactical_mode != TACTIC_NONE:
		_expected_unreachable_time = 0.0
		return
	if _layout_points.is_empty():
		_expected_unreachable_time = 0.0
		return

	var target:ball = _get_target()
	if target == null:
		_expected_unreachable_time = 0.0
		return

	var expected:Area2D = _find_point_by_index(_target_progress)
	# 下一号还没布出来，就不做重排/撤销。
	if expected == null:
		_expected_unreachable_time = 0.0
		return

	_adaptive_check_left -= delta
	if _adaptive_check_left > 0.0:
		return
	_adaptive_check_left = maxf(adaptive_check_interval,0.10)

	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var path:Array[Dictionary] = _predict_enemy_path(
		target,
		rect,
		adaptive_prediction_horizon,
		prediction_step
	)
	var eta:float = _estimate_point_eta_from_path(expected.global_position,path)
	if eta >= 0.0:
		_expected_unreachable_time = 0.0
		return

	_expected_unreachable_time += maxf(adaptive_check_interval,0.10)
	if _expected_unreachable_time < unreachable_grace_time:
		return
	if _adaptive_cooldown_left > 0.0:
		return

	_adapt_pending_layout(path)


func _adapt_pending_layout(path:Array[Dictionary]) -> void:
	var expected:Area2D = _find_point_by_index(_target_progress)
	if expected == null:
		return

	# 先找“虽然编号靠后，但敌人马上就会经过”的点。
	var best_point:Area2D = null
	var best_eta:float = INF
	for point in _layout_points:
		if point == null or not is_instance_valid(point):
			continue
		var index:int = int(point.get("layout_index"))
		if index < _target_progress:
			continue
		var eta:float = _estimate_point_eta_from_path(point.global_position,path)
		if eta >= 0.0 and eta < best_eta:
			best_eta = eta
			best_point = point

	if best_point != null and best_point != expected:
		# 直接交换编号：例如原本3号正在敌人脚下，而1号已经完全偏离路线，
		# 那么3号变成1号，原1号变成3号。位置不瞬移，只改布局顺序。
		var expected_index:int = int(expected.get("layout_index"))
		var best_index:int = int(best_point.get("layout_index"))
		expected.call("set_layout_index",best_index)
		best_point.call("set_layout_index",expected_index)
		_sort_layout_points()
		_refresh_layout_line()
		_refresh_point_states()
		_expected_unreachable_time = 0.0
		_adaptive_cooldown_left = maxf(adaptive_cooldown,0.3)
		return

	# 所有未完成点都不在近期轨迹上：撤销当前坏点，并可额外撤掉最难重新利用的点。
	var pending:Array[Area2D] = []
	for point in _layout_points:
		if point != null and is_instance_valid(point):
			if int(point.get("layout_index")) >= _target_progress:
				pending.append(point)
	if pending.is_empty():
		return

	var remove_count:int = mini(maxi(adaptive_remove_max,1),pending.size())
	# 当前应踩点一定优先撤销。
	var to_remove:Array[Area2D] = [expected]
	while to_remove.size() < remove_count:
		var farthest:Area2D = null
		var farthest_distance:float = -1.0
		for candidate in pending:
			if candidate == null or not is_instance_valid(candidate) or to_remove.has(candidate):
				continue
			var min_path_distance:float = _minimum_distance_to_path(candidate.global_position,path)
			if min_path_distance > farthest_distance:
				farthest_distance = min_path_distance
				farthest = candidate
		if farthest == null:
			break
		to_remove.append(farthest)

	for point in to_remove:
		_layout_points.erase(point)
		if point != null and is_instance_valid(point):
			point.queue_free()

	_reindex_pending_points()
	_next_point_index = _layout_points.size()
	_between_point_left = maxf(between_point_delay * 0.55,0.15)
	_expected_unreachable_time = 0.0
	_adaptive_cooldown_left = maxf(adaptive_cooldown,0.3)
	_refresh_layout_line()
	_refresh_point_states()


func _reindex_pending_points() -> void:
	_sort_layout_points()
	var next_index:int = _target_progress
	for point in _layout_points:
		if point == null or not is_instance_valid(point):
			continue
		var old_index:int = int(point.get("layout_index"))
		if old_index < _target_progress:
			continue
		point.call("set_layout_index",next_index)
		next_index += 1
	_sort_layout_points()


func _estimate_point_eta_from_path(point_position:Vector2,path:Array[Dictionary]) -> float:
	var radius:float = maxf(predicted_touch_radius,layout_point_radius + 5.0)
	for sample in path:
		var sample_position:Vector2 = sample.get("position",point_position)
		if sample_position.distance_to(point_position) <= radius:
			return float(sample.get("time",0.0))
	return -1.0


func _minimum_distance_to_path(point_position:Vector2,path:Array[Dictionary]) -> float:
	var best:float = INF
	for sample in path:
		var sample_position:Vector2 = sample.get("position",point_position)
		best = minf(best,sample_position.distance_to(point_position))
	return best


# 对矩形地图做轻量预测，包含外墙反弹。它不是“作弊寻路”，只用角色当前方向/速度
# 推算未来几秒可能经过的位置；真实移动仍然完全交给 ball / CharacterBody2D。
func _predict_enemy_path(target:ball,rect:Rect2,horizon:float,step:float) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	if target == null or not is_instance_valid(target):
		return result

	var pos:Vector2 = combat_target_position(target)
	var lock_velocity:Vector2 = combat_target_velocity(target)
	var speed:float = lock_velocity.length()
	var dir:Vector2 = lock_velocity.normalized() if speed > 0.000001 else Vector2.ZERO

	var safe_step:float = clampf(step,0.04,0.5)
	var safe_horizon:float = maxf(horizon,safe_step)
	var count:int = maxi(int(ceil(safe_horizon / safe_step)),1)
	var margin:float = maxf(layout_point_radius + 3.0,5.0)
	var left:float = rect.position.x + margin
	var right:float = rect.end.x - margin
	var top:float = rect.position.y + margin
	var bottom:float = rect.end.y - margin
	if left > right:
		left = rect.position.x + rect.size.x * 0.5
		right = left
	if top > bottom:
		top = rect.position.y + rect.size.y * 0.5
		bottom = top

	for i in range(1,count + 1):
		var dt:float = safe_step
		if speed > 0.0 and dir.length_squared() > 0.000001:
			pos += dir * speed * dt
			# 一帧预测步长很小，分别反射X/Y足以覆盖角落反弹。
			if pos.x < left:
				pos.x = left + (left - pos.x)
				dir.x = absf(dir.x)
			elif pos.x > right:
				pos.x = right - (pos.x - right)
				dir.x = -absf(dir.x)
			if pos.y < top:
				pos.y = top + (top - pos.y)
				dir.y = absf(dir.y)
			elif pos.y > bottom:
				pos.y = bottom - (pos.y - bottom)
				dir.y = -absf(dir.y)
		result.append({"time":float(i) * safe_step,"position":pos})

	return result


func _refresh_layout_line() -> void:
	if _layout_line == null or not is_instance_valid(_layout_line):
		_layout_line = Line2D.new()
		_layout_line.name = "WiseLayoutLine_%d" % get_instance_id()
		_layout_line.width = maxf(layout_line_width,0.5)
		_layout_line.default_color = layout_line_color
		_layout_line.z_as_relative = false
		_layout_line.z_index = 37
		get_tree().current_scene.add_child(_layout_line)

	var points := PackedVector2Array()
	_sort_layout_points()
	for point in _layout_points:
		if point != null and is_instance_valid(point):
			points.append(point.global_position)
	_layout_line.points = points


func _refresh_point_states() -> void:
	for point in _layout_points:
		if point == null or not is_instance_valid(point):
			continue
		var index:int = int(point.get("layout_index"))
		point.call("set_state",index == _target_progress,index < _target_progress)


func on_wise_layout_point_touched(point:Area2D,target:ball) -> void:
	if not is_multiplayer_authority():
		return
	if point == null or not is_instance_valid(point):
		return
	if target == null or not is_instance_valid(target) or not _is_enemy(target):
		return

	var index:int = int(point.get("layout_index"))
	# 真正按布局顺序走：提前踩到3、4不会跳关；自适应系统会在必要时主动改编号。
	if index != _target_progress:
		return

	if index > 0:
		var damage:float = attack_damage(point_damage_start_multiplier + point_damage_step_multiplier * float(index - 1))
		if damage > 0:
			target.receive_spatial_damage(
				damage,
				{"shape":"circle","center":point.global_position,"radius":maxf(layout_point_radius,1.0),"source":point},
				false
			)
			if point_hit_audio != "":
				Audios.play_sfx.rpc(point_hit_audio,{},true)

	_target_progress += 1
	_expected_unreachable_time = 0.0
	_adaptive_cooldown_left = maxf(adaptive_cooldown * 0.65,0.8)
	_refresh_point_states()

	if _target_progress >= maxi(points_per_layout,2):
		call_deferred("_finish_layout_round")


func _find_point_by_index(index:int) -> Area2D:
	for point in _layout_points:
		if point != null and is_instance_valid(point):
			if int(point.get("layout_index")) == index:
				return point
	return null


func _sort_layout_points() -> void:
	# 数量最多只有几颗，手写稳定排序比依赖Lambda更稳，也方便兼容项目当前GDScript风格。
	for i in range(_layout_points.size()):
		for j in range(i + 1,_layout_points.size()):
			var a:Area2D = _layout_points[i]
			var b:Area2D = _layout_points[j]
			if a == null or not is_instance_valid(a):
				continue
			if b == null or not is_instance_valid(b):
				continue
			if int(a.get("layout_index")) > int(b.get("layout_index")):
				_layout_points[i] = b
				_layout_points[j] = a


func _is_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target):
		return false
	if target == self or not target.is_combat_targetable():
		return false
	if Team != "" and target.Team != "" and Team == target.Team:
		return false
	return true


func _get_target() -> ball:
	var target = Target_Enemy if is_instance_valid(Target_Enemy) else Nearest_Enemy
	if target == null or not is_instance_valid(target) or not (target is ball):
		return null
	var typed_target:ball = target as ball
	return typed_target if _is_enemy(typed_target) else null


func _cleanup_dead_points() -> void:
	var changed:bool = false
	var kept:Array[Area2D] = []
	for point in _layout_points:
		if point != null and is_instance_valid(point):
			kept.append(point)
		else:
			changed = true
	if changed:
		_layout_points = kept
		_sort_layout_points()
		_refresh_layout_line()
		_refresh_point_states()


func _finish_layout_round() -> void:
	_tactical_mode = TACTIC_NONE
	_tactical_target = null
	_tactical_time_left = 0.0
	_clear_layout()
	_next_point_index = 0
	_target_progress = 0
	_between_point_left = 0.0
	_expected_unreachable_time = 0.0
	_layout_cooldown_left = maxf(layout_interval,0.5)


func _clear_layout() -> void:
	for point in _layout_points:
		if point != null and is_instance_valid(point):
			point.queue_free()
	_layout_points.clear()
	if _layout_line != null and is_instance_valid(_layout_line):
		_layout_line.queue_free()
	_layout_line = null
	_layout_lifetime_left = 0.0


func _clamp_point(point:Vector2,rect:Rect2) -> Vector2:
	var margin:float = maxf(map_margin,layout_point_radius + 2.0)
	var min_x:float = rect.position.x + margin
	var max_x:float = rect.end.x - margin
	var min_y:float = rect.position.y + margin
	var max_y:float = rect.end.y - margin
	if min_x > max_x:
		min_x = rect.position.x + rect.size.x * 0.5
		max_x = min_x
	if min_y > max_y:
		min_y = rect.position.y + rect.size.y * 0.5
		max_y = min_y
	return Vector2(clampf(point.x,min_x,max_x),clampf(point.y,min_y,max_y))


func _edge_distance(point:Vector2,rect:Rect2) -> float:
	return minf(
		minf(point.x - rect.position.x,rect.end.x - point.x),
		minf(point.y - rect.position.y,rect.end.y - point.y)
	)


func _get_map_rect() -> Rect2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var map_name:String = str(world.now_choose_map)
	if not world.map_group.has(map_name):
		return Rect2()
	var map_node = world.map_group[map_name]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.return_map_world_rect(map_node)


func when_collide(speed:float,collision:KinematicCollision2D):
	var collider = collision.get_collider()
	var collided_tactical_target:bool = (
		_tactical_target != null
		and is_instance_valid(_tactical_target)
		and collider == _tactical_target
	)
	var push_target:ball = _tactical_target if collided_tactical_target else null
	var push_dir:Vector2 = Vector2.ZERO
	var push_alignment:float = -1.0
	if collided_tactical_target and _tactical_mode in [TACTIC_PUSH_SETUP,TACTIC_PUSH_COMMIT]:
		var expected:Area2D = _find_point_by_index(_target_progress)
		if expected != null and push_target != null:
			push_dir = expected.global_position - push_target.global_position
			var approach:Vector2 = push_target.global_position - global_position
			if push_dir.length_squared() > 0.000001 and approach.length_squared() > 0.000001:
				# 接近方向和“敌人 -> 布局点”越一致，越说明智者确实位于敌人背侧。
				push_alignment = approach.normalized().dot(push_dir.normalized())

	super.when_collide(speed,collision)

	if _moving_to_layout_point and direction.length_squared() > 0.000001:
		_normal_direction = direction.normalized()
	if _tactical_mode != TACTIC_NONE and direction.length_squared() > 0.000001:
		_tactical_base_direction = direction.normalized()

	if not collided_tactical_target:
		return

	# 闪避过程中如果还是撞上敌人，说明这次避让失败，立刻回到默认移动，避免持续贴着敌人修正。
	if _tactical_mode == TACTIC_DODGE:
		_finish_tactical_move(false)
		return

	# PUSH_SETUP 途中也可能已经从正确背侧撞到敌人；不要求必须先到达一个精确“站位点”。
	# 但方向不对的碰撞不会强行把敌人吸向圆，只会视为这次尝试失败。
	if _tactical_mode in [TACTIC_PUSH_SETUP,TACTIC_PUSH_COMMIT]:
		if push_target != null and is_instance_valid(push_target) and push_alignment >= 0.52:
			if push_dir.length_squared() > 0.000001:
				push_target.apply_knockback(
					push_dir.normalized(),
					maxf(push_distance,8.0),
					maxf(push_speed,80.0),
					0.25,
					0.0,
					{
						"source":self,
						"lock_control":true,
						"stop_on_character":false,
						"max_wall_bounces":1,
					}
				)
			_finish_tactical_move(true)
		else:
			_finish_tactical_move(false)


func _exit_tree() -> void:
	_clear_layout()


func Die() -> void:
	_moving_to_layout_point = false
	_move_target = null
	_tactical_mode = TACTIC_NONE
	_tactical_target = null
	_clear_layout()
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
