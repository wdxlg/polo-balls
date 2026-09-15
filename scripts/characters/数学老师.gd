extends ball

const FORMULA_PROJECTILE_SCENE:PackedScene = preload("res://scenes/shooter/数学老师公式弹.tscn")
const TEACHER_NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/数学老师/老师(2).png")
const TEACHER_THROW_TEXTURE:Texture2D = preload("res://Images/characters/人物/数学老师/老师扔(2).png")
const CHALK_HIT_SFX:AudioStream = preload("res://audio/sfx/physics/balls_hit1.sfxr")
const FORMULA_WRITE_SFX:AudioStream = preload("res://audio/characters/数学老师/写字.mp3")
const CHALK_THROW_SFX:AudioStream = preload("res://audio/characters/数学老师/扔笔.wav")
const CHALK_WALL_SFX:AudioStream = preload("res://audio/characters/数学老师/打到墙.mp3")

const TRAJECTORY_KIND_COUNT:int = 8
const SPEED_FORMULA_KIND_COUNT:int = 5
const DAMAGE_FORMULA_KIND_COUNT:int = 15

enum TeacherActionSfx {
	CHALK_THROW,
	CHALK_WALL,
}

@export_category("数学老师 - 公式技能")
@export_range(0.02,0.30,0.01) var formula_character_interval:float = 0.085
@export_range(0.0,1.0,0.01) var formula_hold_after_reveal:float = 0.08
# V313：公式弹不再使用固定 projectile_speed。
# 速度直接由本次轨迹长度 L 通过 v = L / (t0 + L / D) 计算：
# 短轨迹不会快得离谱，长轨迹会适度提速，同时统一限制在 min/max 内。
@export_range(0.15,2.0,0.01) var speed_formula_base_time:float = 0.62
@export_range(120.0,1200.0,10.0) var speed_formula_distance_divisor:float = 520.0
@export_range(60.0,400.0,5.0) var speed_formula_min:float = 150.0
@export_range(80.0,500.0,5.0) var speed_formula_max:float = 260.0
@export_range(0.3,8.0,0.1) var projectile_lifetime:float = 3.6
@export_range(0.1,5.0,0.05) var projectile_damage_multiplier:float = 1.0
@export_range(6.0,90.0,1.0) var trajectory_amplitude_min:float = 18.0
@export_range(6.0,120.0,1.0) var trajectory_amplitude_max:float = 42.0
@export_range(80.0,600.0,5.0) var trajectory_span_min:float = 150.0
@export_range(80.0,900.0,5.0) var trajectory_span_max:float = 360.0

@export_category("数学老师 - AI命中辅助")
@export_range(0.0,1.5,0.05) var target_lead_strength:float = 0.90
@export_range(0.0,2.0,0.05) var target_lead_max_time:float = 1.10
@export_range(0.0,220.0,5.0) var target_lead_max_distance:float = 110.0
@export_range(6,32,1) var formula_font_size:int = 14
@export var formula_world_offset:Vector2 = Vector2(0.0,30.0)

@export_category("数学老师 - 正式图片")
@export_range(50.0,300.0,1.0) var teacher_visual_height:float = 190.0

var _formula_label:Label = null
var _formula_write_audio:AudioStreamPlayer2D = null
var _formula_visual_token:int = 0

# V352：每一道伤害公式都有唯一 serial。
# 发射端不再根据“字符数 × 间隔”估算计算结束，而是等待本机实际逐字显示协程
# 把同一 serial 标记为 finished。这样 deferred/RPC/帧率差异都不能让子弹抢跑。
var _formula_sequence_serial:int = 0
var _formula_visual_finished_serial:int = 0

# Skill_Cooling 由数学老师自己管理：上一颗粉笔真正发射后开始计时。
# 冷却归零后才允许开始写下一道公式；公式完整写完后才发射。
# 因此不会再让“上一颗子弹发射”和“下一道公式刚开始写”出现在同一时刻。
var _formula_shot_cooldown_remaining:float = 0.0


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	# V351：关闭公共技能冷却入口，避免“公式书写时间 + Skill_Cooling”叠加成不固定攻速。
	# 数学老师改由 tick_physics() 自己按“发射时刻”调度下一发。
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	_apply_teacher_texture(false)
	_create_formula_label()
	_create_formula_write_audio()


func _process(_delta:float) -> void:
	if _formula_label != null and is_instance_valid(_formula_label):
		_formula_label.global_position = global_position + formula_world_offset - Vector2(_formula_label.size.x * 0.5,0.0)


func tick_physics(state:State,delta:float) -> void:
	# V351：发射冷却独立于 Using_Skill 和公式弹寿命。
	# 即使上一颗粉笔还在地图里飞，这个计时也会继续下降。
	if is_multiplayer_authority():
		if is_combat_runtime_active() and not is_damage_output_disabled() and health > 0:
			_formula_shot_cooldown_remaining = maxf(_formula_shot_cooldown_remaining - maxf(delta,0.0),0.0)

			# AI 可以在上一发后的下一物理帧进入 Skill 协程，但 Skill 内部会先等发射冷却结束。
			# 因此屏幕上不会出现“上一发射出的同时，下一道公式刚开始写”的错觉。
			if (
				not is_player_controlled()
				and not Using_Skill
				and not dizziness
				and state_machine != null
				and state_machine.current_state != State.Die
			):
				Skill()

	super.tick_physics(state,delta)


func controlled_skill_action() -> void:
	# 玩家直接控制时右键负责准备下一发。
	# 若仍在冷却，会先等待冷却归零，再开始逐字写公式；写完之后才发射。
	if not is_multiplayer_authority() or Using_Skill:
		return
	if dizziness or health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		return
	Skill()


func _wait_for_formula_shot_cooldown() -> bool:
	# 不使用 projectile lifetime / 节点数量作为条件。
	# 只等待上一发在 _spawn_formula_projectile() 中写入的独立冷却归零，
	# 冷却归零以后才开始下一道公式的视觉。
	while _formula_shot_cooldown_remaining > 0.0001:
		if not is_instance_valid(self) or health <= 0:
			return false
		if state_machine == null or state_machine.current_state == State.Die:
			return false
		if not is_inside_tree():
			return false
		await get_tree().physics_frame
	return true


func _wait_for_formula_calculation_finished(formula_serial:int) -> bool:
	# V352：必须等“本机实际公式显示协程”完成，而不是等估算秒数。
	# `_rpc_show_formula` 是 call_local，因此 authority 自己也会收到相同 serial，
	# 最后一个字符 + hold 完成后 `_mark_formula_visual_finished()` 才会推进 finished serial。
	while _formula_visual_finished_serial < formula_serial:
		if not is_instance_valid(self) or health <= 0:
			return false
		if state_machine == null or state_machine.current_state == State.Die:
			return false
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return true


func _mark_formula_visual_finished(formula_serial:int) -> void:
	_formula_visual_finished_serial = maxi(_formula_visual_finished_serial,formula_serial)


func _create_formula_label() -> void:
	if _formula_label != null and is_instance_valid(_formula_label):
		return
	var label := Label.new()
	label.name = "数学老师公式"
	label.top_level = true
	label.z_as_relative = false
	label.z_index = 96
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",formula_font_size)
	label.add_theme_color_override("font_color",Color(0.98,0.98,0.94,1.0))
	label.add_theme_color_override("font_outline_color",Color(0.03,0.03,0.03,0.95))
	label.add_theme_constant_override("outline_size",2)
	label.size = Vector2(360.0,30.0)
	label.visible = false
	add_child(label)
	_formula_label = label


func Skill() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority() or Using_Skill:
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		return

	var target_point:Vector2 = _resolve_skill_target_point()
	if not has_player_control_aim() and target_point == global_position:
		Using_Skill = false
		return

	Using_Skill = true

	# 发射节奏改成严格的三段顺序：冷却结束 -> 写完整公式 -> 发射。
	# 冷却期间不提前显示下一道公式，因此不会再出现“刚开始写字就有一颗子弹射出”的视觉错配。
	if not (await _wait_for_formula_shot_cooldown()):
		Using_Skill = false
		return
	if not is_instance_valid(self) or health <= 0 or state_machine.current_state == State.Die:
		Using_Skill = false
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Using_Skill = false
		return

	_call_teacher_pose(true)
	var formula_data:Dictionary = _make_arithmetic_formula_data()
	var formula:String = str(formula_data.get("text","1=1"))
	var formula_result:int = maxi(int(formula_data.get("result",1)),0)

	# 给本次公式唯一 serial。只有最后一个字符实际显示完成（并结束短暂停留）后，
	# _formula_visual_finished_serial 才会推进，随后才允许生成对应公式弹。
	_formula_sequence_serial += 1
	var formula_serial:int = _formula_sequence_serial
	if multiplayer.has_multiplayer_peer():
		_rpc_show_formula.rpc(formula,formula_character_interval,formula_hold_after_reveal,formula_serial)
	else:
		_rpc_show_formula(formula,formula_character_interval,formula_hold_after_reveal,formula_serial)

	if not (await _wait_for_formula_calculation_finished(formula_serial)):
		_call_teacher_pose(false)
		Using_Skill = false
		return
	if not is_instance_valid(self) or health <= 0 or state_machine.current_state == State.Die:
		_call_teacher_pose(false)
		Using_Skill = false
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		_call_teacher_pose(false)
		Using_Skill = false
		return

	# 发射前再取一次当前目标和真实速度类型，保证等待冷却期间目标移动不会让瞄准完全过期。
	var curve_kind:int = randi_range(0,TRAJECTORY_KIND_COUNT - 1)
	var speed_kind:int = randi_range(0,SPEED_FORMULA_KIND_COUNT - 1)
	target_point = _resolve_skill_target_point(true,speed_kind)
	_spawn_formula_projectile(target_point,formula_result,curve_kind,speed_kind)

	# 当前发射动作到这里结束。下一次 Skill 可以马上进入等待，
	# 但必须等本次发射冷却归零以后才会真正开始显示下一道公式。
	_call_teacher_pose(false)
	Using_Skill = false


func _call_teacher_pose(throwing:bool) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_set_teacher_pose.rpc(throwing)
	else:
		_rpc_set_teacher_pose(throwing)


@rpc("authority","call_local","unreliable")
func _rpc_set_teacher_pose(throwing:bool) -> void:
	_apply_teacher_texture(throwing)


func _apply_teacher_texture(throwing:bool) -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D
	var texture:Texture2D = TEACHER_THROW_TEXTURE if throwing else TEACHER_NORMAL_TEXTURE
	sprite.texture = texture
	sprite.visible = true
	var source_height:float = maxf(float(texture.get_height()),1.0)
	sprite.scale = Vector2.ONE * (teacher_visual_height / source_height)


func _resolve_skill_target_point(predict_motion:bool = false,speed_kind:int = 0) -> Vector2:
	if has_player_control_aim():
		return player_control_aim_position
	var target:ball = _nearest_legal_enemy()
	if target != null:
		return _predict_target_point(target,speed_kind) if predict_motion else target.global_position
	return global_position


func _predict_target_point(target:ball,speed_kind:int = 0) -> Vector2:
	if target == null or not is_instance_valid(target):
		return global_position
	var current:Vector2 = target.global_position
	var target_velocity:Vector2 = target.velocity
	if target_velocity.length_squared() <= 0.000001 or target_lead_strength <= 0.0:
		return current

	# 两次迭代：先按当前位置估计飞行时间，再用预测点重新估计一次。
	# 这样继续保留 v=L/(t0+L/D) 的数学速度公式，同时减少慢速粉笔总是落在移动目标身后的情况。
	var predicted:Vector2 = current
	for _i in range(2):
		var aim:Vector2 = predicted - global_position
		var distance:float = maxf(aim.length(),1.0)
		var span:float = clampf(distance,trajectory_span_min,trajectory_span_max)
		var speed:float = maxf(_formula_projectile_speed(span,speed_kind),1.0)
		var flight_time:float = minf(distance / speed,maxf(target_lead_max_time,0.0))
		var lead:Vector2 = target_velocity * flight_time * target_lead_strength
		var max_lead:float = maxf(target_lead_max_distance,0.0)
		if max_lead > 0.0 and lead.length() > max_lead:
			lead = lead.normalized() * max_lead
		predicted = current + lead
	return predicted


func _nearest_legal_enemy() -> ball:
	var best:ball = null
	var best_dist_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball):
			continue
		var candidate:ball = raw as ball
		if candidate == self or not candidate.is_combat_targetable():
			continue
		if (
			not bool(Game.Game_Settings.get("Have_Team_Damage",false))
			and Team != ""
			and candidate.Team != ""
			and candidate.Team == Team
		):
			continue
		var dist_sq:float = global_position.distance_squared_to(candidate.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best


func _make_arithmetic_formula_data() -> Dictionary:
	# V340：不修改 Damage / projectile_damage_multiplier。
	# 伤害仍严格等于公式右侧答案，只把“出题方式”升级成更高级、自然答案更有威胁的数学公式池。
	match randi_range(0,DAMAGE_FORMULA_KIND_COUNT - 1):
		0:
			var a:int = randi_range(4,9)
			var b:int = randi_range(3,8)
			var c:int = randi_range(2,5)
			var result:int = (a + b) * c
			return {"text":"(%d+%d)×%d=%d" % [a,b,c,result],"result":result}
		1:
			var a:int = randi_range(4,8)
			var b:int = randi_range(5,18)
			var result:int = a * a + b
			return {"text":"%d²+%d=%d" % [a,b,result],"result":result}
		2:
			var a:int = randi_range(3,4)
			var b:int = randi_range(2,10)
			var result:int = a * a * a - b
			return {"text":"%d³-%d=%d" % [a,b,result],"result":result}
		3:
			var root_value:int = randi_range(5,9)
			var multiplier:int = randi_range(4,7)
			var square:int = root_value * root_value
			var result:int = root_value * multiplier
			return {"text":"√%d×%d=%d" % [square,multiplier,result],"result":result}
		4:
			var n:int = 4
			var b:int = randi_range(5,20)
			var result:int = _factorial_int(n) + b
			return {"text":"%d!+%d=%d" % [n,b,result],"result":result}
		5:
			var low:int = randi_range(1,5)
			var high:int = low + randi_range(4,9)
			var multiplier:int = randi_range(4,7)
			var result:int = absi(high - low) * multiplier
			return {"text":"|%d-%d|×%d=%d" % [high,low,multiplier,result],"result":result}
		6:
			var n:int = randi_range(7,10)
			var result:int = int(n * (n + 1) / 2)
			return {"text":"Σ(k=1..%d)k=%d" % [n,result],"result":result}
		7:
			var n:int = randi_range(8,11)
			var bonus:int = randi_range(3,12)
			var combination:int = int(n * (n - 1) / 2)
			var result:int = combination + bonus
			return {"text":"C(%d,2)+%d=%d" % [n,bonus,result],"result":result}
		8:
			var pair_kind:int = randi_range(0,4)
			var a:int = 6
			var b:int = 8
			match pair_kind:
				1:
					a = 8
					b = 12
				2:
					a = 9
					b = 12
				3:
					a = 10
					b = 12
				4:
					a = 6
					b = 15
			var bonus:int = randi_range(2,10)
			var result:int = _lcm_int(a,b) + bonus
			return {"text":"lcm(%d,%d)+%d=%d" % [a,b,bonus,result],"result":result}
		9:
			var matrix_kind:int = randi_range(0,5)
			var a:int = 8
			var b:int = 2
			var c:int = 3
			var d:int = 7
			match matrix_kind:
				1:
					a = 7
					b = 3
					c = 2
					d = 8
				2:
					a = 9
					b = 4
					c = 3
					d = 7
				3:
					a = 8
					b = 5
					c = 2
					d = 9
				4:
					a = 6
					b = 4
					c = 3
					d = 8
				5:
					a = 7
					b = 5
					c = 4
					d = 9
			var result:int = absi(a * d - b * c)
			return {"text":"det[[%d,%d],[%d,%d]]=%d" % [a,b,c,d,result],"result":result}
		10:
			var a:int = randi_range(2,4)
			var x:int = randi_range(3,4)
			var b:int = randi_range(5,15)
			var result:int = a * x * x + b
			return {"text":"f(x)=%dx²+%d,f(%d)=%d" % [a,b,x,result],"result":result}
		11:
			var exponent:int = randi_range(5,8)
			var multiplier:int = randi_range(4,7)
			var result:int = exponent * multiplier
			return {"text":"log₂(2^%d)×%d=%d" % [exponent,multiplier,result],"result":result}
		12:
			var triple_kind:int = randi_range(0,2)
			var a:int = 3
			var b:int = 4
			var hypotenuse:int = 5
			match triple_kind:
				1:
					a = 6
					b = 8
					hypotenuse = 10
				2:
					a = 5
					b = 12
					hypotenuse = 13
			var multiplier:int = randi_range(4,6)
			var result:int = hypotenuse * multiplier
			return {"text":"√(%d²+%d²)×%d=%d" % [a,b,multiplier,result],"result":result}
		13:
			var n:int = randi_range(7,10)
			var bonus:int = randi_range(0,8)
			var permutation:int = n * (n - 1)
			var result:int = permutation + bonus
			return {"text":"P(%d,2)+%d=%d" % [n,bonus,result],"result":result}
		_:
			var discriminants:Array[Vector3i] = [
				Vector3i(1,8,3),Vector3i(1,9,5),Vector3i(2,10,4),
				Vector3i(1,10,7),Vector3i(2,11,6),Vector3i(2,12,8),
			]
			var abc:Vector3i = discriminants[randi_range(0,discriminants.size() - 1)]
			var a:int = abc.x
			var b:int = abc.y
			var c:int = abc.z
			var result:int = b * b - 4 * a * c
			return {"text":"Δ=%d²-4×%d×%d=%d" % [b,a,c,result],"result":result}


func _factorial_int(n:int) -> int:
	var result:int = 1
	for i:int in range(2,maxi(n,1) + 1):
		result *= i
	return result


func _gcd_int(a:int,b:int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var remainder:int = a % b
		a = b
		b = remainder
	return maxi(a,1)


func _lcm_int(a:int,b:int) -> int:
	return int(absi(a * b) / _gcd_int(a,b))


func _spawn_formula_projectile(target_point:Vector2,formula_result:int,curve_kind:int,speed_kind:int) -> void:
	# V351：固定攻速的唯一计时起点就是“真正射出一颗粉笔”的这一刻。
	_formula_shot_cooldown_remaining = maxf(Skill_Cooling,0.0)

	var aim:Vector2 = target_point - global_position
	if aim.length_squared() <= 0.000001:
		aim = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var forward:Vector2 = aim.normalized()
	var distance:float = maxf(aim.length(),trajectory_span_min)
	var span:float = clampf(distance,trajectory_span_min,trajectory_span_max)
	var amplitude:float = randf_range(minf(trajectory_amplitude_min,trajectory_amplitude_max),maxf(trajectory_amplitude_min,trajectory_amplitude_max))
	if randf() < 0.5:
		amplitude = -amplitude
	curve_kind = clampi(curve_kind,0,TRAJECTORY_KIND_COUNT - 1)
	speed_kind = clampi(speed_kind,0,SPEED_FORMULA_KIND_COUNT - 1)
	var calculated_speed:float = _formula_projectile_speed(span,speed_kind)
	var projectile_id:String = "%s_%s" % [str(get_instance_id()),str(Time.get_ticks_usec())]
	# V317：算式右侧答案就是本发“基准伤害”。
	# 仍遵守 V107 的统一 Damage 语义：用默认 Damage 作为参考值换算 attack_damage() 倍率，
	# 因此未被 Buff/Debuff 改攻击力时，1+1=2 就造成 2、3*4=12 就造成 12；
	# 攻击力被改变时则按相同比例放大/缩小，而不是另存一套绝对伤害系统。
	var base_damage:float = maxf(float(default_properties.get("Damage",Damage)),1.0)
	var answer_damage_multiplier:float = maxf(float(formula_result),0.0) / base_damage
	var resolved_formula_damage:float = attack_damage(answer_damage_multiplier * projectile_damage_multiplier)
	var config:Dictionary = {
		"id": projectile_id,
		"origin": global_position,
		"forward": forward,
		"speed": calculated_speed,
		"speed_kind": speed_kind,
		"lifetime": projectile_lifetime,
		"damage": resolved_formula_damage,
		"formula_result": formula_result,
		"team": Team,
		"span": span,
		"amplitude": amplitude,
		"curve_kind": curve_kind,
	}
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_formula_projectile.rpc(config)
	else:
		_rpc_spawn_formula_projectile(config)
	_call_chalk_throw_audio(global_position)




func _formula_projectile_speed(span:float,speed_kind:int = 0) -> float:
	var path_length:float = maxf(span,1.0)
	var lo:float = minf(speed_formula_min,speed_formula_max)
	var hi:float = maxf(speed_formula_min,speed_formula_max)
	var span_lo:float = minf(trajectory_span_min,trajectory_span_max)
	var span_hi:float = maxf(trajectory_span_min,trajectory_span_max)
	var span_range:float = maxf(span_hi - span_lo,1.0)
	var q:float = clampf((path_length - span_lo) / span_range,0.0,1.0)
	var raw_speed:float = lo
	match clampi(speed_kind,0,SPEED_FORMULA_KIND_COUNT - 1):
		0:
			var base_time:float = maxf(speed_formula_base_time,0.05)
			var distance_divisor:float = maxf(speed_formula_distance_divisor,1.0)
			raw_speed = path_length / maxf(base_time + path_length / distance_divisor,0.01)
		1:
			raw_speed = lerpf(lo,hi,q)
		2:
			raw_speed = lerpf(lo,hi,sqrt(q))
		3:
			raw_speed = lerpf(lo,hi,q * q)
		_:
			raw_speed = lerpf(lo,hi,sin(q * PI * 0.5))
	return clampf(raw_speed,lo,hi)



@rpc("authority","call_local","reliable")
func _rpc_show_formula(formula:String,char_interval:float,hold_time:float,formula_serial:int) -> void:
	# 同一个 authority serial 在所有客户端显示同一道公式。
	# token 仍用于取消旧视觉，但不再由每个客户端各自自增，避免时序漂移。
	_formula_visual_token = formula_serial
	call_deferred("_play_formula_visual",formula,char_interval,hold_time,formula_serial)


func _play_formula_visual(formula:String,char_interval:float,hold_time:float,formula_serial:int) -> void:
	_create_formula_label()
	_create_formula_write_audio()
	if _formula_label == null:
		# 极端情况下 Label 无法创建，也要结束本次握手，避免 authority 永久卡死。
		if is_multiplayer_authority():
			_mark_formula_visual_finished(formula_serial)
		return

	_formula_label.text = formula
	_formula_label.visible_characters = 0
	_formula_label.visible = true
	_start_formula_write_audio()

	for i:int in range(1,formula.length() + 1):
		if formula_serial != _formula_visual_token:
			return
		if not is_instance_valid(_formula_label):
			_stop_formula_write_audio()
			if is_multiplayer_authority():
				_mark_formula_visual_finished(formula_serial)
			return
		_formula_label.visible_characters = i
		await get_tree().create_timer(maxf(char_interval,0.01)).timeout

	if formula_serial != _formula_visual_token:
		return

	# 公式最后一个字符已经真正写完，先停止写字声，再保留原有短暂停留。
	_stop_formula_write_audio()
	if not is_instance_valid(_formula_label):
		if is_multiplayer_authority():
			_mark_formula_visual_finished(formula_serial)
		return

	await get_tree().create_timer(maxf(hold_time,0.0)).timeout
	if formula_serial != _formula_visual_token:
		return

	if is_instance_valid(_formula_label):
		_formula_label.visible = false

	# 只有执行到这里，才允许本次伤害公式对应的粉笔进入发射阶段。
	if is_multiplayer_authority():
		_mark_formula_visual_finished(formula_serial)


func _create_formula_write_audio() -> void:
	if _formula_write_audio != null and is_instance_valid(_formula_write_audio):
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "数学老师写公式音效"
	player.stream = FORMULA_WRITE_SFX
	player.volume_db = 0.0
	player.max_distance = 1800.0
	player.attenuation = 0.35
	player.max_polyphony = 1
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	_formula_write_audio = player


func _start_formula_write_audio() -> void:
	if _formula_write_audio == null or not is_instance_valid(_formula_write_audio):
		_create_formula_write_audio()
	if _formula_write_audio != null and is_instance_valid(_formula_write_audio):
		_formula_write_audio.stop()
		# 用户提供的写字.mp3 开头约 0.08 秒接近静音；短算式若从 0 开始会几乎来不及听见有效笔画声。
		_formula_write_audio.play(0.08)


func _stop_formula_write_audio() -> void:
	if _formula_write_audio != null and is_instance_valid(_formula_write_audio):
		_formula_write_audio.stop()


@rpc("authority","call_local","reliable")
func _rpc_spawn_formula_projectile(config:Dictionary) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var container:Node = _ensure_runtime_container(world)
	var projectile:Node = FORMULA_PROJECTILE_SCENE.instantiate()
	projectile.name = "数学公式弹_" + str(config.get("id","0"))
	container.add_child(projectile,true)
	if projectile.has_method("configure"):
		projectile.call("configure",self,config,is_multiplayer_authority())


func _call_chalk_hit_audio(world_pos:Vector2) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_play_chalk_hit_audio.rpc(world_pos)
	else:
		_rpc_play_chalk_hit_audio(world_pos)


func _call_chalk_throw_audio(world_pos:Vector2) -> void:
	_call_teacher_action_audio(TeacherActionSfx.CHALK_THROW,world_pos)


func _call_chalk_wall_audio(world_pos:Vector2) -> void:
	_call_teacher_action_audio(TeacherActionSfx.CHALK_WALL,world_pos)


func _call_teacher_action_audio(kind:int,world_pos:Vector2) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_play_teacher_action_audio.rpc(kind,world_pos)
	else:
		_rpc_play_teacher_action_audio(kind,world_pos)


@rpc("authority","call_local","reliable")
func _rpc_play_chalk_hit_audio(world_pos:Vector2) -> void:
	_spawn_positioned_sfx("数学老师粉笔命中音效",CHALK_HIT_SFX,world_pos,-4.0,1200.0,0.55)


@rpc("authority","call_local","reliable")
func _rpc_play_teacher_action_audio(kind:int,world_pos:Vector2) -> void:
	match kind:
		TeacherActionSfx.CHALK_THROW:
			_spawn_positioned_sfx("数学老师扔粉笔音效",CHALK_THROW_SFX,world_pos,2.0,1800.0,0.35,0.06)
		TeacherActionSfx.CHALK_WALL:
			_spawn_positioned_sfx("数学老师粉笔撞墙音效",CHALK_WALL_SFX,world_pos,0.0,1800.0,0.35,0.08)


func _spawn_positioned_sfx(node_name:String,stream:AudioStream,world_pos:Vector2,volume_db:float,max_distance:float,attenuation:float,start_offset:float = 0.0) -> void:
	var world:Node = get_tree().current_scene
	if world == null or stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = max_distance
	player.attenuation = attenuation
	player.max_polyphony = 1
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	_ensure_runtime_container(world).add_child(player,true)
	player.global_position = world_pos
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play(maxf(start_offset,0.0))


func _ensure_runtime_container(world:Node) -> Node:
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func Die() -> void:
	_formula_shot_cooldown_remaining = 0.0
	# V352：推进 serial/token，使仍在等待的旧公式视觉立刻失效。
	_formula_sequence_serial += 1
	_formula_visual_token = _formula_sequence_serial
	_formula_visual_finished_serial = maxi(_formula_visual_finished_serial,_formula_sequence_serial)
	if _formula_label != null and is_instance_valid(_formula_label):
		_formula_label.visible = false
	_stop_formula_write_audio()
	if is_multiplayer_authority():
		_call_teacher_pose(false)
	super()
