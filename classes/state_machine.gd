extends Node

@onready var current_state := -1:
	set(v):
		if v == -1 or current_state == v or current_state == ball.State.Die:
			return
		state_time = 0
		owner.transition_state(current_state,v)
		current_state = v

const keep_state := -1
@export_range(1,32,1) var max_transitions_per_physics_tick:int = 8
# 状态循环保护仍然生效；默认只阻止循环，不再每秒向调试器刷黄字。
@export var debug_state_cycle_warnings:bool = false
# V106：大规模战斗只把 AI/状态“决策”错峰到 30Hz；owner.tick_physics()、移动、碰撞、伤害仍是 60Hz。
@export_range(1,4,1) var large_battle_state_decision_divisor:int = 2

var state_time:float = 0
var last_state_dis:Dictionary = {}
var _last_cycle_warning_frame:int = -100000

func _ready() -> void:
	await owner.ready
	current_state = 0

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	# 乘坐只锁定位置与朝向；仍完整运行角色AI、攻击、技能和冷却。
	if owner is ball: owner.apply_transport_pose()

	# V106：大规模战斗中 get_next_state()（AI/冷却/目标状态判断）按实例错峰。
	# 只减少决策次数；tick_physics() 仍每个物理帧执行，所以移动、击退、碰撞和攻击动作不会降到 30Hz。
	var run_state_decision:bool = true
	if owner is ball:
		var owner_ball:ball = owner as ball
		if owner_ball.is_large_battle_performance_mode():
			var divisor:int = maxi(large_battle_state_decision_divisor,1)
			# V430：大规模战斗物理 tick 已降到 30Hz 时不再二次抽稀，保持 AI 决策仍为 30Hz。
			if Engine.physics_ticks_per_second <= 30:
				divisor = 1
			run_state_decision = divisor <= 1 or ((Engine.get_physics_frames() + owner_ball.get_instance_id()) % divisor) == 0

	if run_state_decision:
		# 性能：绝大多数物理帧状态不会变化，先做一次无分配快速路径。
		var next = owner.get_next_state(current_state)
		if next != keep_state and next != current_state:
			# V411：ball.State 只有少量非负枚举值，用位掩码记录本 tick 已访问状态。
			# 旧版每次发生状态切换都会创建临时 Dictionary；多人高频攻击时产生大量短命分配。
			# 位掩码与原循环检测语义完全相同。
			var visited_mask:int = 0
			if current_state >= 0 and current_state < 63:
				visited_mask |= (1 << current_state)
			var transition_count:int = 0

			while transition_count < max_transitions_per_physics_tick:
				if next == keep_state or next == current_state:
					break
				if next >= 0 and next < 63 and (visited_mask & (1 << next)) != 0:
					_warn_state_cycle(current_state,next)
					break

				if next >= 0 and next < 63:
					visited_mask |= (1 << next)
				current_state = next
				transition_count += 1
				next = owner.get_next_state(current_state)

			if transition_count >= max_transitions_per_physics_tick:
				_warn_state_cycle(current_state,current_state)

	owner.tick_physics(current_state,delta)
	if owner is ball: owner.apply_transport_pose()
	state_time += delta

	# 项目实际冷却读取只使用 Attack / Skill；其它状态时长由 state_time 负责。
	# 不再每个单位每帧遍历整个 Dictionary 并做 str() 转换。
	if not owner.Attacking and not owner.Using_Skill and not owner.dizziness:
		# owner.ready 后 ball._ready() 已初始化 Attack / Skill 键；不再 60Hz 重复做 Dictionary.has()。
		last_state_dis["Attack"] = float(last_state_dis.get("Attack",0.0)) + delta
		last_state_dis["Skill"] = float(last_state_dis.get("Skill",0.0)) + delta

func _warn_state_cycle(from_state:int,to_state:int) -> void:
	if not debug_state_cycle_warnings:
		return

	var now_frame:int = Engine.get_physics_frames()
	if now_frame - _last_cycle_warning_frame < 60:
		return
	_last_cycle_warning_frame = now_frame
	push_warning(
		"State cycle prevented on %s: %s -> %s"
		% [owner.name,str(from_state),str(to_state)]
	)
