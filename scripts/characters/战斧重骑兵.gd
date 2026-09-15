extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")

@onready var body_sprite:AnimatedSprite2D = $Graphics/AnimatedSprite2D
# V53：AxeMotion 本身就是“握把最底端”的旋转轴心。
@onready var axe_motion:Node2D = $Graphics/AxeMotion
@onready var axe_sprite:Sprite2D = $Graphics/AxeMotion/AxeSprite
@onready var axe_hit_area:Area2D = $Graphics/AxeMotion/AxeHitArea
@onready var axe_head_collision:CollisionShape2D = $Graphics/AxeMotion/AxeHitArea/AxeHeadShape
@onready var axe_handle_collision:CollisionShape2D = $Graphics/AxeMotion/AxeHitArea/AxeHandleShape

@export_category("战斧重骑兵 - 战斧")
@export_range(20.0,240.0,2.0) var axe_attack_range:float = 96.0

@export_category("战斧重骑兵 - 有甲形态")
@export_range(0.0,10.0,0.05) var armored_axe_damage_multiplier:float = 1.3333333
@export_range(0.05,3.0,0.05) var armored_axe_windup:float = 1.0
@export_range(10.0,400.0,5.0) var armored_move_speed:float = 100.0
# V55：穿甲攻击期间仍可向面对方向移动，但非常慢。
# 用户没有给精确倍率，默认先用自身当前移速的 0.10 倍。
@export_range(0.0,1.0,0.01) var armored_attack_move_multiplier:float = 0.10

@export_category("战斧重骑兵 - 破甲形态")
@export_range(0.0,10.0,0.05) var broken_axe_damage_multiplier:float = 1.0
@export_range(0.05,3.0,0.05) var broken_axe_windup:float = 0.55
@export_range(10.0,400.0,5.0) var broken_move_speed:float = 140.0
# 用户指定：脱甲后攻击期间以自身当前移速的 0.30 倍移动。
@export_range(0.0,1.0,0.01) var broken_attack_move_multiplier:float = 0.30
@export_range(1.0,5.0,0.05) var armor_broken_damage_multiplier:float = 1.5

@export_category("战斧重骑兵 - 武器蓄力视觉")
# V53：用户原图中握把最底端的本地坐标（相对 1122×1402 图片中心）。
# 这个点现在就是 AxeMotion 的真正旋转轴心。
@export var axe_handle_pivot_local:Vector2 = Vector2(-25.0,676.0)
# 独立斧图整体相对人物的位置微调。
@export var axe_visual_offset:Vector2 = Vector2(0.0,-62.0)
# 前摇时，独立战斧会往攻击反方向慢慢拖。
@export_range(0.0,90.0,1.0) var axe_windup_pull_distance:float = 34.0
# V50：前摇结束时再额外抬高，正式挥击从更高的位置开始。
@export_range(0.0,120.0,1.0) var axe_windup_lift_distance:float = 42.0
@export_range(0.0,60.0,1.0) var axe_windup_rotation_deg:float = 16.0
@export_range(0.1,1.0,0.05) var axe_overlay_alpha:float = 0.82

@export_category("战斧重骑兵 - 武器挥击视觉")
@export_range(0.0,220.0,2.0) var axe_swing_forward_distance:float = 52.0
# V46：挥击不只横移，还明显向下砍。
@export_range(0.0,260.0,2.0) var axe_swing_down_distance:float = 84.0
@export_range(90.0,240.0,1.0) var axe_swing_rotation_deg:float = 180.0
# V51：>1 时形成 ease-out；3.0 = 三次缓出，前快后慢且收尾平滑。
@export_range(1.0,6.0,0.1) var axe_swing_ease_power:float = 3.0
@export_range(0.10,0.80,0.01) var axe_swing_duration:float = 0.32
@export_range(0.0,0.60,0.01) var attack_pose_hold:float = 0.12

@export_category("战斧重骑兵 - 战斧残影")
@export_range(1,12,1) var axe_afterimage_count:int = 8
@export_range(0.05,0.60,0.01) var axe_afterimage_lifetime:float = 0.24
@export_range(0.05,0.90,0.01) var axe_afterimage_alpha:float = 0.30

@export_category("战斧重骑兵 - 音效")
@export_range(-30.0,6.0,0.5) var swing_sfx_volume_db:float = -3.0
@export_range(-30.0,6.0,0.5) var hit_sfx_volume_db:float = -1.5
@export_range(-30.0,6.0,0.5) var armor_break_sfx_volume_db:float = -3.0

var _armor_broken:bool = false
var _attack_serial:int = 0

# V50：挥击伤害完全由真实 AxeHitArea 碰撞产生。
# 同一次挥击内，同一个角色最多被武器命中一次。
var _axe_damage_active:bool = false
var _active_axe_damage:float = 0.0
var _axe_hit_target_ids:Dictionary = {}

# V48：攻击开始时锁定一次，只可能是 -1（左）或 +1（右）。
# 整个前摇/半圈挥击过程中不再重新读取目标位置。
var _attack_facing_sign:float = -1.0
var _visual_stage:StringName = &"idle"
var _axe_base_position:Vector2 = Vector2.ZERO
var _axe_base_scale:Vector2 = Vector2.ONE
var _axe_base_offset:Vector2 = Vector2.ZERO


func _ready() -> void:
	# 每个 ball 本身已有 AnimatedSprite2D，这里直接使用它。
	image = body_sprite
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0

	super._ready()

	block = max_block
	_armor_broken = block <= 0
	_apply_phase_speed()

	# 每个角色实例独立一份武器 Shape，后续镜像几何时不会改到别的实例。
	if axe_head_collision.shape != null:
		axe_head_collision.shape = axe_head_collision.shape.duplicate()
	if axe_handle_collision.shape != null:
		axe_handle_collision.shape = axe_handle_collision.shape.duplicate()

	if not axe_hit_area.area_entered.is_connected(_on_axe_hit_area_area_entered):
		axe_hit_area.area_entered.connect(_on_axe_hit_area_area_entered)

	axe_hit_area.monitoring = false
	axe_hit_area.monitorable = false
	axe_hit_area.collision_layer = 0
	axe_hit_area.collision_mask = 0
	axe_hit_area.set_meta("threat_debug_damage",0.0)

	_cache_axe_base_transform()
	axe_motion.visible = false
	axe_motion.modulate = Color(1.0,1.0,1.0,axe_overlay_alpha)
	_refresh_body_visual()


func get_next_state(state:State) -> int:
	if (
		is_multiplayer_authority()
		and is_combat_runtime_active()
		and Can_Attack
		and not is_damage_output_disabled()
		and state_machine != null
		and state_machine.last_state_dis.Attack >= Attack_Cooling
		and _find_axe_target() == null
	):
		var saved_attack_timer:float = float(state_machine.last_state_dis.Attack)
		Can_Attack = false
		var next_state:int = super.get_next_state(state)
		Can_Attack = true
		state_machine.last_state_dis.Attack = saved_attack_timer
		return next_state

	return super.get_next_state(state)


func Attack() -> void:
	if (
		state_machine == null
		or state_machine.current_state == State.Die
		or not is_multiplayer_authority()
		or health <= 0
		or not is_combat_runtime_active()
		or is_damage_output_disabled()
	):
		Attacking = false
		return

	var target:ball = _find_axe_target()
	if target == null and not has_player_control_aim():
		Attacking = false
		return

	Attacking = true

	# AI 仍看目标；直接控制只看鼠标左右，不要求敌人存在。
	if has_player_control_aim():
		var manual_dir:Vector2 = player_control_aim_direction(direction)
		set_character_visual_flip_h(manual_dir.x > 0.0)
		_sync_axe_flip()
	else:
		_face_target(target)
	_attack_facing_sign = _facing_sign_from_visual()

	# V55：攻击期间允许移动。
	# 实际方向由 tick_physics 锁定为起手时的左右朝向，不追踪目标 y。
	direction = Vector2(_attack_facing_sign,0.0)

	_attack_serial += 1
	var serial:int = _attack_serial
	_run_axe_attack(target,serial)


func tick_physics(state:State,delta:float) -> void:
	if not _armor_broken and block <= 0:
		_break_armor()

	# V55：攻击期间也允许角色移动。
	#
	# 方向：
	# - 只沿 Attack 起手时锁定的左 / 右朝向前进；
	# - 不追踪目标 y；
	# - 目标中途穿身也不会让本次攻击移动方向反转。
	#
	# 速度：
	# - 穿甲：自身当前移速 × armored_attack_move_multiplier（默认 0.10）
	# - 脱甲：自身当前移速 × broken_attack_move_multiplier（固定默认 0.30）
	if Attacking and state == State.Attack:
		var saved_speed:float = Speed
		var saved_direction:Vector2 = direction

		direction = Vector2(_attack_facing_sign,0.0)
		Speed = saved_speed * _current_attack_move_multiplier()

		super.tick_physics(state,delta)

		# ball.move() 会按照通用角色规则自动翻转人物。
		# 战斧重骑兵素材的天然朝向相反，因此移动结束后重新锁回本次攻击朝向。
		set_character_visual_flip_h(_attack_facing_sign > 0.0)

		Speed = saved_speed
		direction = saved_direction
		return

	super.tick_physics(state,delta)


func _run_axe_attack(target:ball,serial:int) -> void:
	var windup:float = _current_axe_windup()

	_visual_stage = &"windup"
	_refresh_body_visual()
	_sync_axe_visual_to_body()
	axe_motion.visible = true

	# 高举斧状态下，独立战斧缓慢往攻击反方向移动，做出蓄力。
	var windup_ok:bool = await _animate_axe_windup(
		target,
		windup,
		serial
	)
	if not windup_ok or not _attack_is_valid(serial):
		_finish_axe_attack(serial)
		return

	# 前摇结束：切换到挥出战斧人物图。
	_visual_stage = &"attack"
	_refresh_body_visual()

	# V50：从这一刻开始，伤害完全由真实武器 Area2D / CollisionShape2D 产生。
	# 不再在动画结束时“固定给锁定目标扣血”。
	_begin_axe_weapon_damage()

	# 用户提供的“挥舞.mp3”：只在正式挥斧开始的一刻播放。
	LOCAL_SFX.play(
		self,
		"waraxe_swing",
		global_position,
		swing_sfx_volume_db,
		1.0,
		900.0
	)

	# 独立战斧快速向攻击方向挥过，并在运动过程中留下武器残影。
	var swing_ok:bool = await _animate_axe_swing(
		target,
		maxf(axe_swing_duration,0.05),
		serial
	)

	_end_axe_weapon_damage()

	if not swing_ok or not _attack_is_valid(serial):
		_finish_axe_attack(serial)
		return

	if attack_pose_hold > 0.0:
		await wait_for_combat_time(attack_pose_hold)

	_finish_axe_attack(serial)


func _animate_axe_windup(
	target:ball,
	duration:float,
	serial:int
) -> bool:
	var forward_sign:float = _attack_forward_sign()
	var start_pos:Vector2 = _axe_base_position
	var end_pos:Vector2 = (
		_axe_base_position
		+ Vector2(
			-forward_sign * axe_windup_pull_distance,
			-axe_windup_lift_distance
		)
	)
	var start_rot:float = 0.0
	var end_rot:float = deg_to_rad(
		-forward_sign * axe_windup_rotation_deg
	)

	return await _animate_axe_transform(
		start_pos,
		end_pos,
		start_rot,
		end_rot,
		duration,
		serial,
		false
	)


func _animate_axe_swing(
	target:ball,
	duration:float,
	serial:int
) -> bool:
	var forward_sign:float = _attack_forward_sign()
	var start_pos:Vector2 = axe_motion.position
	var end_pos:Vector2 = (
		_axe_base_position
		+ Vector2(
			forward_sign * axe_swing_forward_distance,
			axe_swing_down_distance
		)
	)
	var start_rot:float = axe_motion.rotation
	# V49：
	# 蓄力用 -forward_sign，先往面对方向的反方向后拉；
	# 正式攻击必须反过来使用 +forward_sign，朝面对方向挥出完整半圈。
	# 左右朝向仍在起手时锁定，目标中途穿身不会改变本次方向。
	var end_rot:float = (
		start_rot
		+ deg_to_rad(forward_sign * axe_swing_rotation_deg)
	)

	return await _animate_axe_transform(
		start_pos,
		end_pos,
		start_rot,
		end_rot,
		duration,
		serial,
		true
	)


func _animate_axe_transform(
	from_position:Vector2,
	to_position:Vector2,
	from_rotation:float,
	to_rotation:float,
	duration:float,
	serial:int,
	spawn_afterimages:bool
) -> bool:
	var elapsed:float = 0.0
	var last_usec:int = Time.get_ticks_usec()
	var ghosts_spawned:int = 0
	var wanted_ghosts:int = maxi(axe_afterimage_count,1)

	while elapsed < duration:
		if not _attack_is_valid(serial):
			return false

		var tree:SceneTree = get_tree()
		if tree == null:
			return false

		# 武器真实碰撞必须由物理帧更新；前摇仍可走普通 process 帧。
		if spawn_afterimages:
			await tree.physics_frame
			_collect_current_axe_weapon_hits()
		else:
			await tree.process_frame

		var now_usec:int = Time.get_ticks_usec()
		var real_delta:float = clampf(
			float(now_usec - last_usec) / 1000000.0,
			0.0,
			0.05
		)
		last_usec = now_usec

		if not is_combat_runtime_active():
			continue

		elapsed += real_delta * maxf(Engine.time_scale,0.0)
		var t:float = clampf(elapsed / maxf(duration,0.001),0.0,1.0)

		# 前摇继续用 smoothstep。
		# 正式挥击改为 ease-out：
		# 一出手速度最大，随后连续减速，接近终点时自然收斧。
		var motion_t:float
		if spawn_afterimages:
			var ease_power:float = maxf(axe_swing_ease_power,1.0)
			motion_t = 1.0 - pow(1.0 - t,ease_power)
		else:
			motion_t = t * t * (3.0 - 2.0 * t)

		# V53：AxeMotion 本身就是握把最底端。
		# 轴心只做手部式的小幅位移，真正的斧刃大圆弧完全由下面的 180° rotation 产生。
		axe_motion.position = from_position.lerp(
			to_position,
			motion_t
		)

		axe_motion.rotation = lerpf(
			from_rotation,
			to_rotation,
			motion_t
		)

		if spawn_afterimages:
			var should_have:int = floori(
				t * float(wanted_ghosts)
			)
			while ghosts_spawned < should_have:
				_spawn_axe_afterimage()
				ghosts_spawned += 1

	axe_motion.position = to_position
	axe_motion.rotation = to_rotation

	if spawn_afterimages:
		_spawn_axe_afterimage()

		# 最终位置至少保留一个物理步，避免快速挥击恰好跳过终点接触。
		var tree:SceneTree = get_tree()
		if tree != null and _attack_is_valid(serial):
			await tree.physics_frame
			_collect_current_axe_weapon_hits()

	return true


func _spawn_axe_afterimage() -> void:
	if (
		axe_sprite == null
		or not is_instance_valid(axe_sprite)
		or axe_sprite.texture == null
	):
		return

	var ghost := Sprite2D.new()
	ghost.name = "AxeAfterImage"
	ghost.texture = axe_sprite.texture
	ghost.centered = axe_sprite.centered
	ghost.offset = axe_sprite.offset
	ghost.flip_h = axe_sprite.flip_h
	ghost.flip_v = false
	ghost.z_index = axe_motion.z_index - 1
	ghost.modulate = Color(
		1.0,
		1.0,
		1.0,
		clampf(axe_afterimage_alpha,0.0,1.0)
	)

	$Graphics.add_child(ghost)

	# 直接复制真正战斧 Sprite 的全局 Transform。
	# 这样残影天然继承“握把轴心 + 子 Sprite 偏移 + 旋转 + 缩放”的最终结果。
	ghost.global_transform = axe_sprite.global_transform

	_fade_axe_afterimage(ghost)


func _fade_axe_afterimage(ghost:Sprite2D) -> void:
	var elapsed:float = 0.0
	var lifetime:float = maxf(axe_afterimage_lifetime,0.05)
	var last_usec:int = Time.get_ticks_usec()

	while elapsed < lifetime:
		if ghost == null or not is_instance_valid(ghost):
			return

		var tree:SceneTree = get_tree()
		if tree == null:
			break
		await tree.process_frame

		var now_usec:int = Time.get_ticks_usec()
		var real_delta:float = clampf(
			float(now_usec - last_usec) / 1000000.0,
			0.0,
			0.05
		)
		last_usec = now_usec

		if not is_combat_runtime_active():
			continue

		elapsed += real_delta * maxf(Engine.time_scale,0.0)
		var t:float = clampf(elapsed / lifetime,0.0,1.0)
		var color:Color = ghost.modulate
		color.a = axe_afterimage_alpha * (1.0 - t)
		ghost.modulate = color

	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()


# ============================================================
# V50：真实战斧碰撞伤害
# ============================================================
# AxeHitArea 是 AxeMotion 的子节点，因此会跟着独立战斧一起：
# - 平移
# - 旋转
# - 缩放
#
# 两个 ConvexPolygonShape2D 分别近似：
# - 斧头金属头部
# - 长柄
#
# 只有正式挥击期间才打开 monitoring / collision_mask。
# 前摇阶段斧子即使从敌人身边经过也不会造成伤害。

func _begin_axe_weapon_damage() -> void:
	_axe_damage_active = true
	_active_axe_damage = _current_axe_damage()
	_axe_hit_target_ids.clear()

	axe_hit_area.set_meta(
		"threat_debug_damage",
		_active_axe_damage
	)
	axe_hit_area.collision_mask = 2
	axe_hit_area.monitoring = true

	# monitoring 刚开启时，已有重叠会在物理步更新；
	# 同时主动扫一次当前缓存，作为安全兜底。
	_collect_current_axe_weapon_hits()


func _end_axe_weapon_damage() -> void:
	if axe_hit_area == null or not is_instance_valid(axe_hit_area):
		_axe_damage_active = false
		_active_axe_damage = 0.0
		_axe_hit_target_ids.clear()
		return

	axe_hit_area.monitoring = false
	axe_hit_area.collision_mask = 0
	axe_hit_area.set_meta("threat_debug_damage",0.0)

	_axe_damage_active = false
	_active_axe_damage = 0.0
	_axe_hit_target_ids.clear()


func _on_axe_hit_area_area_entered(area:Area2D) -> void:
	_try_damage_axe_overlap(area)


func _collect_current_axe_weapon_hits() -> void:
	if (
		not _axe_damage_active
		or axe_hit_area == null
		or not is_instance_valid(axe_hit_area)
		or not axe_hit_area.monitoring
	):
		return

	for area:Area2D in axe_hit_area.get_overlapping_areas():
		_try_damage_axe_overlap(area)


func _try_damage_axe_overlap(area:Area2D) -> void:
	if not _axe_damage_active or not Attacking:
		return
	if area == null or not is_instance_valid(area):
		return
	if not area is hurtbox:
		return

	var target:ball = area.get_parent() as ball
	if target == null or not is_instance_valid(target):
		return
	if not TOOLS.is_enemy(self,target):
		return

	var target_id:int = target.get_instance_id()
	if _axe_hit_target_ids.has(target_id):
		return

	# 先登记，再结算，避免目标有多个 Hurtbox 时同一物理步重复受伤。
	_axe_hit_target_ids[target_id] = true

	var outgoing_damage:float = effective_outgoing_damage(
		_active_axe_damage
	)
	if outgoing_damage <= 0.0:
		return

	target.receive_positional_damage(
		outgoing_damage,
		target.global_position,
		false,
		self
	)

	# 只有 AxeHitArea 真正碰到 hurtbox 并完成伤害时才播放命中声。
	LOCAL_SFX.play(
		self,
		"waraxe_hit",
		target.global_position,
		hit_sfx_volume_db,
		1.0,
		900.0
	)


# Sprite2D.flip_h 只翻纹理，不会自动镜像子 CollisionShape2D。
# 所以每次人物左右翻转时，同步重建武器碰撞多边形的 x 坐标。
func _sync_axe_hitbox_geometry() -> void:
	if (
		axe_head_collision == null
		or axe_handle_collision == null
		or axe_motion == null
	):
		return

	var head_shape := axe_head_collision.shape as ConvexPolygonShape2D
	var handle_shape := axe_handle_collision.shape as ConvexPolygonShape2D
	if head_shape == null or handle_shape == null:
		return

	var mirror_x:bool = axe_sprite.flip_h
	var pivot_local:Vector2 = _current_axe_pivot_local()

	var head_base:Array[Vector2] = [
		Vector2(-211,-616),
		Vector2(-53,-668),
		Vector2(235,-681),
		Vector2(250,-660),
		Vector2(279,-595),
		Vector2(292,-498),
		Vector2(274,-406),
		Vector2(247,-349),
		Vector2(190,-275),
		Vector2(-69,-273),
	]
	var handle_base:Array[Vector2] = [
		Vector2(-69,-301),
		Vector2(8,-301),
		Vector2(33,676),
		Vector2(-86,676),
	]

	head_shape.points = _build_pivoted_axe_points(
		head_base,
		mirror_x,
		pivot_local
	)
	handle_shape.points = _build_pivoted_axe_points(
		handle_base,
		mirror_x,
		pivot_local
	)


func _build_pivoted_axe_points(
	source:Array[Vector2],
	mirror_x:bool,
	pivot_local:Vector2
) -> PackedVector2Array:
	var result := PackedVector2Array()

	for raw_point:Vector2 in source:
		var point:Vector2 = raw_point
		if mirror_x:
			point.x = -point.x

		# Area2D 与 Sprite 都是 AxeMotion 的子节点，
		# 所以真实碰撞也必须以握把最底端为 (0,0)。
		point -= pivot_local
		result.append(point)

	return result


func _finish_axe_attack(serial:int) -> void:
	if serial != _attack_serial:
		return

	_end_axe_weapon_damage()

	Attacking = false
	direction = Vector2.ZERO
	_visual_stage = &"idle"

	if axe_motion != null and is_instance_valid(axe_motion):
		axe_motion.visible = false
		axe_motion.position = _axe_base_position
		axe_motion.rotation = 0.0

	_refresh_body_visual()


func _attack_is_valid(serial:int) -> bool:
	return (
		serial == _attack_serial
		and is_inside_tree()
		and health > 0
		and Attacking
		and state_machine != null
		and state_machine.current_state != State.Die
		and not is_damage_output_disabled()
	)


func _find_axe_target() -> ball:
	return TOOLS.nearest_enemy(self,axe_attack_range)


func _face_target(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return

	# 用户提供的原图天然攻击方向朝左：
	# 目标在左 -> 使用原图；
	# 目标在右 -> 水平镜像整套人物/战斧。
	set_character_visual_flip_h(
		target.global_position.x > global_position.x
	)
	_sync_axe_flip()


func _attack_forward_sign() -> float:
	# V49：挥斧只认人物当前锁定的左右朝向。
	# 不使用目标 y，也不会在目标穿过人物时半途反向。
	return -1.0 if _attack_facing_sign < 0.0 else 1.0


func _facing_sign_from_visual() -> float:
	# 这套人物素材原始方向朝左：
	# 未镜像 = 面朝左；水平镜像 = 面朝右。
	return 1.0 if is_character_visual_flipped_h() else -1.0


func _cache_axe_base_transform() -> void:
	if axe_motion == null or axe_sprite == null or body_sprite == null:
		return

	_axe_base_scale = body_sprite.scale
	_axe_base_offset = body_sprite.offset

	axe_motion.scale = _axe_base_scale
	axe_motion.rotation = 0.0
	axe_sprite.centered = true
	axe_sprite.scale = Vector2.ONE
	axe_sprite.offset = Vector2.ZERO

	_sync_axe_flip()


func _sync_axe_visual_to_body() -> void:
	if axe_motion == null or axe_sprite == null or body_sprite == null:
		return

	_axe_base_scale = body_sprite.scale
	_axe_base_offset = body_sprite.offset

	axe_motion.scale = _axe_base_scale
	axe_motion.rotation = 0.0
	axe_motion.modulate = Color(
		1.0,
		1.0,
		1.0,
		clampf(axe_overlay_alpha,0.0,1.0)
	)

	axe_sprite.centered = true
	axe_sprite.scale = Vector2.ONE
	axe_sprite.offset = Vector2.ZERO

	_sync_axe_flip()


func _current_axe_pivot_local() -> Vector2:
	var pivot:Vector2 = axe_handle_pivot_local
	if axe_sprite != null and axe_sprite.flip_h:
		pivot.x = -pivot.x
	return pivot


func _sync_axe_pivot_layout() -> void:
	if axe_motion == null or axe_sprite == null or body_sprite == null:
		return

	var pivot:Vector2 = _current_axe_pivot_local()

	# 人物 Sprite 的 offset 会改变整张画布的实际显示中心。
	var body_draw_offset:Vector2 = Vector2(
		_axe_base_offset.x * _axe_base_scale.x,
		_axe_base_offset.y * _axe_base_scale.y
	)

	var pivot_scaled:Vector2 = Vector2(
		pivot.x * _axe_base_scale.x,
		pivot.y * _axe_base_scale.y
	)

	# AxeMotion 的 Node2D 原点 = 握把最底端。
	# 先求原本整张战斧图片的中心位置，再加上 pivot 到中心的缩放后向量。
	var image_center_position:Vector2 = (
		body_sprite.position
		+ axe_visual_offset
		+ body_draw_offset
	)
	_axe_base_position = image_center_position + pivot_scaled
	axe_motion.position = _axe_base_position

	# 战斧图片作为 pivot 的子节点，把图片中心反向偏移到握把底端。
	axe_sprite.position = -pivot


func _sync_axe_flip() -> void:
	if axe_motion == null or axe_sprite == null:
		return

	# 独立战斧原图与人物手持战斧天然朝向相反，所以纹理 flip 继续与人物逻辑取反。
	axe_sprite.flip_h = not is_character_visual_flipped_h()
	axe_sprite.flip_v = false

	# flip 会改变握把底端的 x 坐标，因此必须同时重算 pivot 与碰撞几何。
	_sync_axe_pivot_layout()
	_sync_axe_hitbox_geometry()


func _refresh_body_visual() -> void:
	if (
		body_sprite == null
		or body_sprite.sprite_frames == null
	):
		return

	var animation_name:StringName

	if _armor_broken:
		match _visual_stage:
			&"windup":
				animation_name = &"BrokenWindup"
			&"attack":
				animation_name = &"BrokenAttack"
			_:
				animation_name = &"BrokenIdle"
	else:
		match _visual_stage:
			&"windup":
				animation_name = &"ArmoredWindup"
			&"attack":
				animation_name = &"ArmoredAttack"
			_:
				animation_name = &"ArmoredIdle"

	if body_sprite.sprite_frames.has_animation(animation_name):
		body_sprite.animation = animation_name
		body_sprite.frame = 0


func take_damage(
	damage:float,
	ignore_block:bool = false
) -> void:
	if damage <= 0.0:
		return

	if not _armor_broken and block <= 0:
		_break_armor()

	var block_before:float = float(block)
	var adjusted_damage:float = damage

	if _armor_broken:
		adjusted_damage *= maxf(
			armor_broken_damage_multiplier,
			1.0
		)

	super.take_damage(adjusted_damage,ignore_block)

	if (
		not _armor_broken
		and not ignore_block
		and block_before > 0.0
		and block <= 0
	):
		_break_armor()


func _break_armor() -> void:
	if _armor_broken:
		return

	_armor_broken = true
	_apply_phase_speed()

	# 用户提供的“破甲.mp3”：只在护甲第一次真正归零时播放一次。
	LOCAL_SFX.play(
		self,
		"waraxe_armor_break",
		global_position,
		armor_break_sfx_volume_db,
		1.0,
		1000.0
	)

	# 破甲如果发生在前摇/挥击中，人物图立即切到对应的卸甲姿态。
	_refresh_body_visual()


func _apply_phase_speed() -> void:
	Speed = (
		broken_move_speed
		if _armor_broken
		else armored_move_speed
	)


func _current_axe_damage() -> float:
	var multiplier:float = broken_axe_damage_multiplier if _armor_broken else armored_axe_damage_multiplier
	return attack_damage(multiplier)


func _current_axe_windup() -> float:
	return (
		broken_axe_windup
		if _armor_broken
		else armored_axe_windup
	)


func _current_attack_move_multiplier() -> float:
	return clampf(
		broken_attack_move_multiplier
		if _armor_broken
		else armored_attack_move_multiplier,
		0.0,
		1.0
	)


func is_armor_broken() -> bool:
	return _armor_broken
