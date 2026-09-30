extends "res://scripts/characters/我的世界/mc_item_base.gd"

const WEAPON_VISUAL_SIZE = preload("res://scripts/characters/我的世界/weapon_visual_size.gd")

const MACE_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/重锤/重锤.png")
const IMPACT_EFFECT_SCRIPT:Script = preload("res://scripts/effects/我的世界/重锤落地冲击.gd")
const MC_DAMAGE_SFX:Script = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
# 仅增强重锤命中人物的声音；挥空、砸空和其他武器保持原音量。
const MACE_HIT_GAIN_DB:float = 6.0
const MACE_SMASH_LIGHT_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/近战/重锤/猛击轻/重锤猛击轻01.ogg"),
	preload("res://audio/sfx/我的世界/近战/重锤/猛击轻/重锤猛击轻02.ogg"),
	preload("res://audio/sfx/我的世界/近战/重锤/猛击轻/重锤猛击轻03.ogg"),
]
const MACE_SMASH_MEDIUM_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/近战/重锤/猛击中/重锤猛击中01.ogg"),
	preload("res://audio/sfx/我的世界/近战/重锤/猛击中/重锤猛击中02.ogg"),
	preload("res://audio/sfx/我的世界/近战/重锤/猛击中/重锤猛击中03.ogg"),
	preload("res://audio/sfx/我的世界/近战/重锤/猛击中/重锤猛击中04.ogg"),
]
const MACE_SMASH_HEAVY_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/近战/重锤/猛击重/重锤猛击重.ogg"),
]


@export_category("重锤 / 普通砸击")
@export_range(0.1,3.0,0.05) var swing_damage_multiplier:float = 1.25
@export_range(0.0,20.0,0.5) var swing_knockback_distance:float = 2.5
@export_range(0.10,0.80,0.01) var swing_duration:float = 0.22
@export_range(-180.0,180.0,1.0) var swing_start_angle_degrees:float = -62.0
@export_range(300.0,540.0,1.0) var swing_rotation_degrees:float = 360.0
@export_range(8.0,80.0,1.0) var swing_hammer_head_reach:float = 18.0
@export_range(1.0,24.0,0.25) var swing_hammer_head_radius:float = 3.0
@export_range(1.0,3.0,0.05) var swing_peak_scale_multiplier:float = 2.0
@export_range(0.5,20.0,0.5) var swing_hit_sample_step:float = 2.0
@export_range(0.02,0.20,0.01) var swing_recover_time:float = 0.06

@export_category("重锤 / 挥舞残影")
@export_range(0.015,0.12,0.005) var swing_afterimage_interval:float = 0.03
@export_range(0.05,0.50,0.01) var swing_afterimage_lifetime:float = 0.20
@export_range(0.0,1.0,0.02) var swing_afterimage_alpha:float = 0.34
@export var swing_afterimage_tint:Color = Color(1.0,0.92,0.72,1.0)

@export_category("重锤 / 风爆连砸")
@export_range(20.0,180.0,1.0) var base_flight_height:float = 58.0
@export_range(0.0,90.0,1.0) var flight_height_gain:float = 28.0
@export_range(0.35,2.0,0.01) var base_flight_duration:float = 0.92
@export_range(0.0,0.004,0.00005) var landing_duration_gain_per_height:float = 0.0011
@export_range(0.0,0.40,0.01) var maximum_landing_duration_bonus:float = 0.22
@export_range(1,12,1) var max_chain_level:int = 8
@export_range(18.0,160.0,1.0) var base_landing_radius:float = 32.0
@export_range(0.0,40.0,1.0) var landing_radius_gain:float = 6.0
@export_range(0.1,8.0,0.05) var base_landing_damage_multiplier:float = 1.85
@export_range(1.0,4.0,0.05) var landing_damage_jump_multiplier:float = 2.0
@export_range(0.0,50.0,0.5) var base_landing_knockback_distance:float = 5.0
@export_range(0.0,20.0,0.5) var landing_knockback_gain:float = 4.0
@export_range(40.0,320.0,5.0) var landing_knockback_speed:float = 125.0

@export_category("重锤 / 猛击音效")
@export_range(40.0,260.0,1.0) var medium_smash_height:float = 100.0
@export_range(60.0,320.0,1.0) var heavy_smash_height:float = 170.0

@export_category("重锤 / 空中旋转")
@export_range(180.0,1200.0,10.0) var base_spin_speed_degrees:float = 540.0
@export_range(0.0,8.0,0.1) var spin_speed_per_height:float = 4.0
@export_range(0.70,0.95,0.01) var spin_settle_start_ratio:float = 0.84

@export_category("重锤 / 空中透视")
# 按“真实离地高度”直接增加视觉比例，不做最高点归一化，也不设最大倍率。
# 例如默认 0.0045：58 高度约 1.261x，114 高度约 1.513x，254 高度约 2.143x。
@export var visual_scale_gain_per_world_height:float = 0.0045

var _airborne:bool = false
var _flight_elapsed:float = 0.0
var _flight_duration:float = 1.0
var _rise_duration:float = 0.46
var _fall_duration:float = 0.46
var _flight_height:float = 58.0
var _chain_level:int = 1
var _chain_damage_multiplier:float = 0.0
var _visual_base_position:Vector2 = Vector2.ZERO
var _visual_base_rotation:float = 0.0
var _health_bar_base_position:Vector2 = Vector2.ZERO
var _flight_start_rotation:float = 0.0
var _shadow_base_scale:Vector2 = Vector2.ONE
var _shadow_scale_captured:bool = false
var _air_visual_base_scale:Vector2 = Vector2.ONE
var _air_visual_scale_captured:bool = false
var _swing_tween:Tween = null
var _landing_recover_tween:Tween = null
var _opening_swing_sfx:Array[AudioStream] = []

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	if image is Sprite2D:
		WEAPON_VISUAL_SIZE.fit_to_wooden_sword(image)
	add_to_group("MinecraftMace")
	_resolve_opening_swing_sfx()
	if graphics != null:
		_visual_base_position = graphics.position
		_visual_base_rotation = graphics.rotation
		# 重锤腾空时允许视觉跨出地图矩形，但仍压在 z=100 的地图边框下面。
		# 地图外视觉遮罩在 World 中是 z=90，因此这里固定到 98。
		graphics.z_as_relative = false
		graphics.z_index = 98
	if image != null and is_instance_valid(image):
		_air_visual_base_scale = image.scale
		_air_visual_scale_captured = true
	if health_bar != null:
		_health_bar_base_position = health_bar.position
		health_bar.z_as_relative = false
		health_bar.z_index = 99

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	# Graphics.position 已由基础同步器同步，血条/地面影子可以在所有 peer 本地跟随。
	_sync_air_visual_followers()
	if not is_multiplayer_authority() or not _airborne or health <= 0:
		return
	_update_flight(maxf(delta,0.0))
	_sync_air_visual_followers()

func move(speed:float,delta:float) -> void:
	if _airborne:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.move(speed,delta)

func stand(delta:float) -> void:
	if _airborne:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.stand(delta)

func get_next_state(state:State) -> int:
	if not is_multiplayer_authority():
		return -1

	# V113：AI 只有在“这一圈锤头真实能扫到”的区域内已经存在敌人时才进入 Attack。
	# 这样不会因为公共攻击冷却到点就在远处空挥，也不会把后续跳砸的落地圆误当成起手范围。
	if (
		not is_player_controlled()
		and not _airborne
		and Can_Attack
		and not Attacking
		and state_machine != null
		and float(state_machine.last_state_dis.get("Attack",0.0)) >= Attack_Cooling
		and _find_opening_swing_target() == null
	):
		var saved_attack_timer:float = float(state_machine.last_state_dis.get("Attack",0.0))
		var saved_can_attack:bool = Can_Attack
		Can_Attack = false
		var next_state:int = super.get_next_state(state)
		Can_Attack = saved_can_attack
		state_machine.last_state_dis["Attack"] = saved_attack_timer
		return next_state

	return super.get_next_state(state)


func Attack() -> void:
	if _airborne or Attacking or state_machine == null or state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	super()
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return
	var target:ball = _find_opening_swing_target()
	if target == null:
		Attacking = false
		return
	var attack_dir:Vector2 = combat_target_position(target) - global_position
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()
	Attacking = true

	# V111：第一击不再“延时后直接给目标/范围伤害”。
	# 先真实挥动锤头；锤头弧线碰到谁，谁才受伤。只有这一挥至少命中 1 个敌人，
	# 才允许进入后续腾空砸地连段。空挥会正常收锤并结束 Attack，不会凭空起跳。
	var swing_hits:int = await _perform_opening_swing(attack_dir)
	if not is_instance_valid(self) or health <= 0:
		return
	if swing_hits > 0 and is_combat_runtime_active() and not is_damage_output_disabled():
		_begin_flight(1)
	else:
		Attacking = false


func _perform_opening_swing(attack_dir:Vector2) -> int:
	if image == null or not is_instance_valid(image):
		return 0
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = null

	# V115：第一挥一开始就播放 Minecraft player strong/重击，作为整圈挥锤音效。
	_broadcast_opening_swing_sfx()

	var safe_dir:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
	var duration:float = maxf(swing_duration,0.05)
	var start_angle:float = deg_to_rad(swing_start_angle_degrees)
	var rotation_amount:float = deg_to_rad(maxf(swing_rotation_degrees,1.0))
	var elapsed:float = 0.0
	var afterimage_elapsed:float = 0.0
	var hit_ids:Dictionary = {}
	var swing_base_scale:Vector2 = image.scale
	var hit_count:int = 0
	var impact_sound_played:bool = false
	var previous_scale_multiplier:float = 1.0
	var previous_head_position:Vector2 = _opening_swing_head_position(safe_dir,start_angle,previous_scale_multiplier)

	# 起手姿态立即和真正锤头碰撞位置一致。图片方向 = 锤头方向 + 90°。
	# V114：第一击完整旋转一圈；锤头轨迹使用更小的真实接触圆，并由物理空间直接查询 Hurtbox。
	image.rotation = safe_dir.angle() + start_angle + PI * 0.5
	image.scale = swing_base_scale
	_spawn_swing_afterimage()

	while elapsed < duration:
		if health <= 0 or is_damage_output_disabled() or not is_combat_runtime_active():
			break
		await get_tree().physics_frame
		if not is_instance_valid(self) or image == null or not is_instance_valid(image):
			return hit_count
		var dt:float = maxf(get_physics_process_delta_time(),0.001)
		elapsed = minf(elapsed + dt,duration)
		var t:float = clampf(elapsed / duration,0.0,1.0)
		# 完整一圈使用稳定角速度，避免尾段减速导致锤头在最后一小段堆叠。
		var local_angle:float = start_angle + rotation_amount * t
		image.rotation = safe_dir.angle() + local_angle + PI * 0.5
		# 0° -> 180°：锤子逐渐放大；180° -> 360°：再缩回原尺寸。
		# sin(PI*t) 在半圈处精确到峰值，起点/终点都回到 1。
		var scale_multiplier:float = _swing_scale_multiplier(t)
		image.scale = swing_base_scale * scale_multiplier
		afterimage_elapsed += dt
		var afterimage_interval:float = maxf(swing_afterimage_interval,0.015)
		if afterimage_elapsed >= afterimage_interval:
			afterimage_elapsed = fmod(afterimage_elapsed,afterimage_interval)
			_spawn_swing_afterimage()
		var head_position:Vector2 = _opening_swing_head_position(safe_dir,local_angle,scale_multiplier)
		var contact_radius:float = maxf(swing_hammer_head_radius,0.5) * maxf(previous_scale_multiplier,scale_multiplier)
		var new_hits:Array[ball] = _damage_opening_swing_segment(previous_head_position,head_position,hit_ids,contact_radius)
		for target:ball in new_hits:
			if target == null or not is_instance_valid(target):
				continue
			hit_count += 1
			if not impact_sound_played:
				_play_world_sfx(_pick_sfx(MACE_SMASH_LIGHT_SFX),head_position,3.0 + MACE_HIT_GAIN_DB)
				impact_sound_played = true
		previous_head_position = head_position
		previous_scale_multiplier = scale_multiplier

	# 收锤以后才决定是否进入跳砸。
	var recover:float = maxf(swing_recover_time,0.0)
	if recover > 0.001 and image != null and is_instance_valid(image):
		_swing_tween = create_tween()
		_swing_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_swing_tween.set_parallel(true)
		_swing_tween.tween_property(image,"rotation",0.0,recover)
		_swing_tween.tween_property(image,"scale",swing_base_scale,recover)
		await _swing_tween.finished
	elif image != null and is_instance_valid(image):
		image.rotation = 0.0
		image.scale = swing_base_scale
	return hit_count


func _spawn_swing_afterimage() -> void:
	if image == null or not is_instance_valid(image) or not image.visible:
		return
	# 复用 ball 的快照残影系统，但只在这一圈挥舞期间手动生成。
	# 生成后立刻恢复公共参数，避免影响角色平时移动与后续空中旋转。
	var old_lifetime:float = AfterImage_Lifetime
	var old_alpha:float = AfterImage_Alpha
	var old_end_alpha:float = AfterImage_End_Alpha
	var old_tint:Color = AfterImage_Tint
	var old_end_tint:Color = AfterImage_End_Tint
	var old_blur:float = AfterImage_Blur_Pixels
	var old_end_blur:float = AfterImage_End_Blur_Pixels
	var old_smear:float = AfterImage_Smear_Pixels
	var old_end_smear:float = AfterImage_End_Smear_Pixels
	var old_start_scale:Vector2 = AfterImage_Start_Scale
	var old_end_scale:Vector2 = AfterImage_End_Scale

	AfterImage_Lifetime = maxf(swing_afterimage_lifetime,0.05)
	AfterImage_Alpha = clampf(swing_afterimage_alpha,0.0,1.0)
	AfterImage_End_Alpha = 0.0
	AfterImage_Tint = swing_afterimage_tint
	AfterImage_End_Tint = Color(swing_afterimage_tint.r,swing_afterimage_tint.g,swing_afterimage_tint.b,0.0)
	AfterImage_Blur_Pixels = 0.5
	AfterImage_End_Blur_Pixels = 1.8
	AfterImage_Smear_Pixels = 0.0
	AfterImage_End_Smear_Pixels = 0.0
	AfterImage_Start_Scale = Vector2.ONE
	AfterImage_End_Scale = Vector2(0.96,0.96)
	AfterImage()

	AfterImage_Lifetime = old_lifetime
	AfterImage_Alpha = old_alpha
	AfterImage_End_Alpha = old_end_alpha
	AfterImage_Tint = old_tint
	AfterImage_End_Tint = old_end_tint
	AfterImage_Blur_Pixels = old_blur
	AfterImage_End_Blur_Pixels = old_end_blur
	AfterImage_Smear_Pixels = old_smear
	AfterImage_End_Smear_Pixels = old_end_smear
	AfterImage_Start_Scale = old_start_scale
	AfterImage_End_Scale = old_end_scale


func _swing_scale_multiplier(progress:float) -> float:
	var t:float = clampf(progress,0.0,1.0)
	var scale_wave:float = sin(PI * t)
	return lerpf(1.0,maxf(swing_peak_scale_multiplier,1.0),scale_wave)


func _opening_swing_head_position(attack_dir:Vector2,local_angle:float,scale_multiplier:float = 1.0) -> Vector2:
	var direction_value:Vector2 = Vector2.RIGHT.rotated(attack_dir.angle() + local_angle)
	return global_position + direction_value * maxf(swing_hammer_head_reach,0.0) * maxf(scale_multiplier,0.01)


func _damage_opening_swing_segment(from_position:Vector2,to_position:Vector2,hit_ids:Dictionary,contact_radius:float) -> Array[ball]:
	var newly_hit:Array[ball] = []
	var radius:float = maxf(contact_radius,0.5)
	var segment_length:float = from_position.distance_to(to_position)
	var step_size:float = maxf(swing_hit_sample_step,0.5)
	var sample_count:int = maxi(int(ceil(segment_length / step_size)),1)
	for sample_index:int in range(sample_count + 1):
		var sample_t:float = float(sample_index) / float(sample_count)
		var sample_position:Vector2 = from_position.lerp(to_position,sample_t)
		# V114：第一挥不再用目标碰撞体 AABB 做“近似圆相交”。AABB 会在斜向、较大
		# Hurtbox 上产生明显的视觉外扩，出现“锤子看着没碰到却已经受伤”。这里直接让
		# PhysicsDirectSpaceState 用一个真实 CircleShape2D 查询敌方 Hurtbox Area2D；只有物理
		# 形状本身与锤头小圆真实重叠才算接触。
		for target:ball in _opening_swing_targets_at(sample_position,radius,hit_ids):
			var target_id:int = target.get_instance_id()
			var applied:bool = target.receive_positional_damage(
				attack_damage(swing_damage_multiplier),
				sample_position,
				false,
				self
			)
			if not applied:
				continue
			hit_ids[target_id] = true
			newly_hit.append(target)
			if not preload("res://scripts/effects/我的世界/mc_hit_feedback.gd").manages(self): MC_DAMAGE_SFX.play(target,sample_position,MACE_HIT_GAIN_DB)
			if swing_knockback_distance > 0.0 and target.health > 0:
				var knock_dir:Vector2 = ball.body_point(target,global_position) - global_position
				if knock_dir.length_squared() <= 0.000001:
					knock_dir = (to_position - from_position).normalized() if to_position.distance_squared_to(from_position) > 0.000001 else Vector2.RIGHT
				target.apply_knockback(
					knock_dir.normalized(),
					swing_knockback_distance,
					78.0,
					0.0,
					0.0,
					{"source":self,"stop_on_character":true}
				)
	return newly_hit


func _opening_swing_targets_at(center:Vector2,radius:float,excluded_ids:Dictionary = {}) -> Array[ball]:
	var targets:Array[ball] = []
	if get_world_2d() == null:
		return targets
	var circle:=CircleShape2D.new()
	circle.radius = maxf(radius,0.5)
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0,center)
	# ball.tscn 的 hurtbox Area2D 位于 collision layer 2。这里只查询 Area，不查询
	# CharacterBody2D，避免身体碰撞框比实际受击 Hurtbox 大时提前命中。
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var results:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,128)
	var seen:Dictionary = {}
	for result:Dictionary in results:
		var collider:Object = result.get("collider",null)
		if not collider is Node:
			continue
		var target:ball = _ball_owner_from_collision_node(collider as Node)
		if not _is_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		if excluded_ids.has(target_id) or seen.has(target_id):
			continue
		seen[target_id] = true
		targets.append(target)
	return targets


func _ball_owner_from_collision_node(node:Node) -> ball:
	var cursor:Node = node
	while cursor != null:
		if cursor is ball:
			return cursor as ball
		cursor = cursor.get_parent()
	return null

func get_projectile_embed_parent() -> Node2D:
	# 位置跳跃在 Graphics，挥锤旋转/腾空缩放在 Image；挂到 Image 才能完整跟随。
	return image if image is Node2D else graphics

func get_projectile_embed_local_transform(world_pose:Transform2D) -> Transform2D:
	var local_pose:Transform2D = image.global_transform.affine_inverse()*world_pose
	# 重锤的物理命中体仍在地面，腾空只是视觉偏移。命中点应映射到同一身体位置，
	# 不能把离地高度反向存成插箭偏移，否则在空中被射中仍会把箭留在地面。
	var rest_image := Transform2D(0.0,_air_visual_base_scale,0.0,image.position)
	var rest_global:Transform2D = global_transform*Transform2D(_visual_base_rotation,_visual_base_position)*rest_image
	local_pose.origin = rest_global.affine_inverse()*world_pose.origin
	return local_pose

func rider_graphics_freedom() -> bool:
	# 上船时座位组件对该乘客改用增量合成：砸地腾空每帧写入的
	# graphics 位置(升空高度)/旋转(空翻)偏移不再被硬覆盖吞掉。
	return true

func _begin_flight(level:int) -> void:
	# 新的一整段连砸从基础倍率开始；后续成功续跳时，倍率由 _finish_landing()
	# 在进入下一跳前直接乘 landing_damage_jump_multiplier。这样即使高度/范围等级
	# 已经达到 max_chain_level，伤害仍然会“每成功续跳一次继续翻倍”。
	var starting_new_chain:bool = not _airborne
	if starting_new_chain and graphics != null:
		# 以当前姿态重捕获视觉基线：被船搭载时 graphics 停在座位姿态(含脚底抬高)，
		# 沿用 ready 时的旧基线会让整段飞行/落地都悬在错误的高度上。
		_visual_base_position = graphics.position
		_visual_base_rotation = graphics.rotation
	_chain_level = clampi(level,1,maxi(max_chain_level,1))
	if starting_new_chain or _chain_damage_multiplier <= 0.0:
		_chain_damage_multiplier = maxf(base_landing_damage_multiplier,0.0)
	_airborne = true
	Attacking = true
	_flight_elapsed = 0.0
	_flight_height = base_flight_height + flight_height_gain * float(_chain_level - 1)
	# V79：上升保持基础节奏；飞得更高时，只把“从顶点砸到地面”的时间略微拉长。
	# 这样高度真的会体现出更长落距，但增幅很小，不会把连续重锤变成慢动作。
	var half_base_duration:float = maxf(base_flight_duration * 0.5,0.10)
	var extra_height:float = maxf(_flight_height - base_flight_height,0.0)
	var fall_bonus:float = minf(
		extra_height * maxf(landing_duration_gain_per_height,0.0),
		maxf(maximum_landing_duration_bonus,0.0)
	)
	_rise_duration = half_base_duration
	_fall_duration = half_base_duration + fall_bonus
	_flight_duration = _rise_duration + _fall_duration
	if _landing_recover_tween != null and _landing_recover_tween.is_valid():
		_landing_recover_tween.kill()
	_landing_recover_tween = null
	_flight_start_rotation = graphics.rotation if graphics != null else _visual_base_rotation
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO

func _update_flight(delta:float) -> void:
	_flight_elapsed += delta
	var p:float = clampf(_flight_elapsed / maxf(_flight_duration,0.05),0.0,1.0)

	# V144：把腾空轨迹改成明确的两段三次曲线。
	# 上升：一开始快，越接近最高点越慢；下降：离开最高点时慢，越接近地面越快。
	# 这比单纯匀速推进位置更像“被弹起 -> 顶点滞空 -> 加速砸地”的重锤手感。
	var world_height:float = 0.0
	if _flight_elapsed <= _rise_duration:
		var rise_t:float = clampf(_flight_elapsed / maxf(_rise_duration,0.05),0.0,1.0)
		var rise_eased:float = 1.0 - pow(1.0 - rise_t,3.0)
		world_height = rise_eased * _flight_height
	else:
		var fall_elapsed:float = _flight_elapsed - _rise_duration
		var fall_t:float = clampf(fall_elapsed / maxf(_fall_duration,0.05),0.0,1.0)
		var fall_eased:float = pow(fall_t,3.0)
		world_height = (1.0 - fall_eased) * _flight_height

	# V94：按“当前真实离地高度”直接放大，不再把每一跳都归一化到同一个最高倍率。
	# 因此飞得越高，最高点就会真的更大；这里没有最大倍率限制。
	# 只改人物视觉，不改变碰撞体/攻击范围。
	if image != null and is_instance_valid(image):
		if not _air_visual_scale_captured:
			_air_visual_base_scale = image.scale
			_air_visual_scale_captured = true
		var visual_scale_multiplier:float = 1.0 + maxf(world_height,0.0) * maxf(visual_scale_gain_per_world_height,0.0)
		image.scale = _air_visual_base_scale * visual_scale_multiplier

	if graphics != null:
		var local_origin:Vector2 = to_local(global_position)
		var local_up:Vector2 = to_local(global_position + Vector2(0.0,-world_height)) - local_origin
		graphics.position = _visual_base_position + local_up

		# 旋转速度直接由本轮实际飞行高度驱动：飞得越高，每秒转得越快。
		# 最后一小段会继续沿同一方向补到“锤头朝下”的精确落地角度，避免触地姿态漂移。
		var landing_rotation:float = _visual_base_rotation + PI
		var spin_speed:float = deg_to_rad(
			maxf(base_spin_speed_degrees,0.0)
			+ maxf(_flight_height,0.0) * maxf(spin_speed_per_height,0.0)
		)
		var settle_start:float = clampf(spin_settle_start_ratio,0.60,0.98)
		if p <= settle_start:
			graphics.rotation = _flight_start_rotation + spin_speed * (_flight_duration * p)
		else:
			var spin_end:float = _flight_start_rotation + spin_speed * (_flight_duration * settle_start)
			var settle_target:float = spin_end + fposmod(landing_rotation - spin_end,TAU)
			var settle_t:float = clampf((p - settle_start) / maxf(1.0 - settle_start,0.001),0.0,1.0)
			var settle_eased:float = 1.0 - pow(1.0 - settle_t,3.0)
			graphics.rotation = lerpf(spin_end,settle_target,settle_eased)

	if p >= 1.0:
		_finish_landing()

func _finish_landing() -> void:
	# _update_flight() 在 p=1 时已经把位置放回地面，同时保留锤头朝下。
	# 先以这个姿态结算冲击，避免视觉上“正着落地”后才爆炸。
	if graphics != null:
		graphics.position = _visual_base_position
	if image != null and is_instance_valid(image) and _air_visual_scale_captured:
		image.scale = _air_visual_base_scale
	var radius:float = base_landing_radius + landing_radius_gain * float(_chain_level - 1)
	# 伤害倍率不再从“高度等级”反推。它由每次成功续跳直接累乘，
	# 所以达到 max_chain_level 后也不会停止翻倍。
	var multiplier:float = maxf(_chain_damage_multiplier,base_landing_damage_multiplier)
	var knock_distance:float = base_landing_knockback_distance + landing_knockback_gain * float(_chain_level - 1)
	# 落地攻击圆必须以自己的真实脚底/地面中心为圆心。以前直接用角色根节点
	# global_position，而目标判定却使用脚底椭圆，二者 Y 偏移不同会造成“贴脸却漏判”。
	var impact_center:Vector2 = _ground_impact_center()
	_spawn_impact_visual(impact_center,radius)
	# “风爆再次起跳”与实际攻击使用完全相同的半径。
	# 只有本次真实受到猛击生命伤害的目标才计入续跳。
	var retrigger_radius:float = radius
	var hit_result:Dictionary = _damage_area(
		impact_center,
		radius,
		attack_damage(multiplier),
		knock_distance,
		landing_knockback_speed + float(_chain_level - 1) * 16.0,
		retrigger_radius
	)
	_play_height_based_smash_sfx(impact_center,_flight_height,int(hit_result.get("hits",0)) > 0)
	var retrigger_hits:int = int(hit_result.get("retrigger_hits",0))
	if retrigger_hits > 0 and health > 0 and is_combat_runtime_active():
		# 成功续跳：下一次落地伤害严格等于这一次的 landing_damage_jump_multiplier 倍。
		# 默认就是 x2，并且不受高度等级上限影响。
		_chain_damage_multiplier = maxf(multiplier * maxf(landing_damage_jump_multiplier,1.0),0.0)
		_begin_flight(mini(_chain_level + 1,maxi(max_chain_level,1)))
	else:
		_airborne = false
		Attacking = false
		_chain_level = 1
		_chain_damage_multiplier = 0.0
		_recover_from_landing_pose()
	_sync_air_visual_followers()

func _recover_from_landing_pose() -> void:
	if graphics == null or not is_instance_valid(graphics):
		return
	if _landing_recover_tween != null and _landing_recover_tween.is_valid():
		_landing_recover_tween.kill()
	_landing_recover_tween = create_tween()
	_landing_recover_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_landing_recover_tween.tween_interval(0.08)
	_landing_recover_tween.tween_property(graphics,"rotation",_visual_base_rotation,0.12)

func _sync_air_visual_followers() -> void:
	if graphics == null or not is_instance_valid(graphics):
		return
	var local_offset:Vector2 = graphics.position - _visual_base_position

	# 血条只跟随腾空位移，不继承锤子的旋转，所以始终保持正向可读。
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.position = _health_bar_base_position + local_offset

	# 地面影子永远留在角色根节点的原地，仅随“离地高度”变短。
	var shadow:Node2D = get_node_or_null("CharacterGroundShadow") as Node2D
	if shadow == null or not is_instance_valid(shadow):
		return
	if not _shadow_scale_captured:
		_shadow_base_scale = shadow.scale
		_shadow_scale_captured = true
	var world_offset:Vector2 = to_global(_visual_base_position + local_offset) - to_global(_visual_base_position)
	var height_world:float = maxf(-world_offset.y,0.0)
	var height_ratio:float = clampf(height_world / 130.0,0.0,1.0)
	var width_scale:float = lerpf(1.0,0.82,height_ratio)
	var height_scale:float = lerpf(1.0,0.28,height_ratio)
	shadow.scale = _shadow_base_scale * Vector2(width_scale,height_scale)

func _damage_area(
	center:Vector2,
	radius:float,
	damage_value:float,
	knock_distance:float,
	knock_speed:float,
	retrigger_radius:float = -1.0
) -> Dictionary:
	if get_world_2d() == null or damage_value <= 0.0:
		return {"hits":0,"retrigger_hits":0}
	# 不再依赖 intersect_shape(..., 64) 作为唯一命中来源。
	# 大规模战斗或特殊角色碰撞层变化时，固定 64 个结果和 CharacterBody 层都可能漏掉
	# 明明已经进入地面攻击圆的目标。这里直接按项目权威 Ball 组逐个做范围判定，
	# 并把角色脚底椭圆半径计入相交测试，因此“人物身体已经压进攻击圈”也算命中。
	#
	# 先收集完整命中集合；目标数量不再改变逐目标反馈。
	var targets:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_enemy(target):
			continue
		if not _target_overlaps_damage_circle(target,center,radius):
			continue
		targets.append(target)

	var hit_count:int = 0
	var retrigger_hit_count:int = 0

	for target_index:int in range(targets.size()):
		var target:ball = targets[target_index]
		if target == null or not is_instance_valid(target):
			continue

		# 续跳判定必须使用“命中前”的同一份几何结果。
		# 某些角色在 receive_positional_damage() 中会立刻改变位置/姿态，
		# 若伤害结算后再重新测一次范围，就会出现“明明砸中了却没有续跳”的错觉。
		var was_in_retrigger_range:bool = (
			retrigger_radius > 0.0
			and _target_overlaps_damage_circle(target,center,retrigger_radius)
		)
		var applied:bool = target.receive_positional_damage(damage_value,center,false,self)
		if applied:
			hit_count += 1
			if was_in_retrigger_range:
				retrigger_hit_count += 1
			if not preload("res://scripts/effects/我的世界/mc_hit_feedback.gd").manages(self): MC_DAMAGE_SFX.play(target,center,MACE_HIT_GAIN_DB)
		# 已经被这一锤打到 0HP 的目标不再做击退计算。死亡目标下一物理帧会进入
		# Die；继续写 Repel/速度既没有可见收益，又会让批量击杀多做一套碰撞运动状态。
		if knock_distance > 0.0 and is_instance_valid(target) and target.health > 0:
			var knock_dir:Vector2 = ball.body_point(target,center) - center
			if knock_dir.length_squared() <= 0.000001:
				knock_dir = Vector2.RIGHT
			target.apply_knockback(knock_dir.normalized(),knock_distance,knock_speed,0.0,0.0,{"source":self,"stop_on_character":true})

	return {"hits":hit_count,"retrigger_hits":retrigger_hit_count}


# 每个实际受击目标都保留公共受击反馈，不因群体命中而削减。
func handles_positional_hit_feedback() -> bool:
	return false

func _ground_impact_center() -> Vector2:
	# 重锤攻击圆和落地特效统一以自己的真实脚底中心为原点。
	# CharacterGroundShadow 不跟随空中 Graphics 位移，所以腾空时它仍准确表示地面落点。
	var own_ring:Dictionary = get_character_ground_shadow_ring_data(0.0)
	if not own_ring.is_empty():
		var resolved:Vector2 = own_ring.get("center",global_position)
		return resolved
	return global_position

func _target_overlaps_damage_circle(target:ball,center:Vector2,radius:float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var safe_radius:float = maxf(radius,0.0)
	var radius_sq:float = safe_radius * safe_radius

	# 第一层：角色根节点是项目最稳定的战斗坐标。
	if ball.body_point(target,center).distance_squared_to(center) <= radius_sq:
		return true

	# 第二层：直接检查目标的真实角色碰撞体 / Hurtbox。
	# 这层不依赖 PhysicsServer 的 overlap 缓存，因此不会因为物理帧刷新时机、
	# 大规模战斗模式或碰撞层临时调整而漏掉已经贴进攻击圈的人物。
	if _target_combat_shapes_overlap_circle(target,center,safe_radius):
		return true

	# 第三层：脚底椭圆兜底。对图片脚底与根节点存在偏移的角色，
	# 只要攻击圆真正碰到脚底轮廓也算命中。
	var ring:Dictionary = target.get_character_ground_shadow_ring_data(0.0)
	if ring.is_empty():
		return false

	var ellipse_center:Vector2 = ring.get("center",target.global_position)
	var radii:Vector2 = ring.get("radii",Vector2.ZERO)
	radii = Vector2(maxf(absf(radii.x),0.0),maxf(absf(radii.y),0.0))
	var offset:Vector2 = center - ellipse_center
	var center_distance:float = offset.length()
	if center_distance <= safe_radius:
		return true
	if center_distance <= 0.0001 or radii.x <= 0.01 or radii.y <= 0.01:
		return center_distance <= safe_radius

	var direction_to_attack:Vector2 = offset / center_distance
	var denom:float = sqrt(
		(direction_to_attack.x * direction_to_attack.x) / (radii.x * radii.x)
		+ (direction_to_attack.y * direction_to_attack.y) / (radii.y * radii.y)
	)
	var footprint_extent:float = 0.0 if denom <= 0.000001 else 1.0 / denom
	return center_distance <= safe_radius + footprint_extent


func _target_combat_shapes_overlap_circle(target:ball,center:Vector2,radius:float) -> bool:
	var body_shape:CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape_aabb_overlaps_circle(body_shape,center,radius):
		return true

	var hurt_area:Area2D = target.get_node_or_null("hurtbox") as Area2D
	if hurt_area != null and is_instance_valid(hurt_area):
		for node:Node in hurt_area.find_children("*","CollisionShape2D",true,false):
			if node is CollisionShape2D and _collision_shape_aabb_overlaps_circle(node as CollisionShape2D,center,radius):
				return true
	return false


func _collision_shape_aabb_overlaps_circle(shape_node:CollisionShape2D,center:Vector2,radius:float) -> bool:
	if shape_node == null or not is_instance_valid(shape_node) or shape_node.disabled or shape_node.shape == null:
		return false

	var rect:Rect2 = shape_node.shape.get_rect()
	var corners:Array[Vector2] = [
		rect.position,
		rect.position + Vector2(rect.size.x,0.0),
		rect.end,
		rect.position + Vector2(0.0,rect.size.y),
	]
	var world_min:Vector2 = Vector2(INF,INF)
	var world_max:Vector2 = Vector2(-INF,-INF)
	for local_point:Vector2 in corners:
		var world_point:Vector2 = shape_node.global_transform * local_point
		world_min.x = minf(world_min.x,world_point.x)
		world_min.y = minf(world_min.y,world_point.y)
		world_max.x = maxf(world_max.x,world_point.x)
		world_max.y = maxf(world_max.y,world_point.y)

	var closest:=Vector2(
		clampf(center.x,world_min.x,world_max.x),
		clampf(center.y,world_min.y,world_max.y)
	)
	return closest.distance_squared_to(center) <= radius * radius

func _opening_swing_target_alignment_scale() -> float:
	# Attack() 会先用“自己 -> 目标”的方向作为 attack_dir。锤头第一次转到这个方向时，
	# 对应的缩放就是实际近战起手半径应采用的缩放。默认 -62° 起手时约为 1.18x。
	var start_angle:float = deg_to_rad(swing_start_angle_degrees)
	var rotation_amount:float = deg_to_rad(maxf(swing_rotation_degrees,1.0))
	var angle_until_forward:float = fposmod(-start_angle,TAU)
	var t:float = clampf(angle_until_forward / maxf(rotation_amount,0.0001),0.0,1.0)
	return _swing_scale_multiplier(t)


func _opening_swing_outer_radius() -> float:
	var scale_multiplier:float = _opening_swing_target_alignment_scale()
	return (maxf(swing_hammer_head_reach,0.0) + maxf(swing_hammer_head_radius,0.5)) * scale_multiplier


func _opening_swing_inner_radius() -> float:
	var scale_multiplier:float = _opening_swing_target_alignment_scale()
	return maxf((maxf(swing_hammer_head_reach,0.0) - maxf(swing_hammer_head_radius,0.5)) * scale_multiplier,0.0)


func _opening_swing_can_hit(target:ball) -> bool:
	if not _is_enemy(target):
		return false
	# 起手检测与实际挥舞伤害使用同一套“真实 Hurtbox Area2D + 锤头 CircleShape2D”查询。
	# 这样不会出现 AI 因近似 AABB 判断而认为能打到，真正挥舞却在视觉上离目标还有一截。
	var safe_dir:Vector2 = combat_target_position(target) - global_position
	if safe_dir.length_squared() <= 0.000001:
		safe_dir = Vector2.RIGHT
	else:
		safe_dir = safe_dir.normalized()
	var start_angle:float = deg_to_rad(swing_start_angle_degrees)
	var rotation_amount:float = deg_to_rad(maxf(swing_rotation_degrees,1.0))
	var step_count:int = maxi(int(ceil(absf(rad_to_deg(rotation_amount)) / 5.0)),72)
	for i:int in range(step_count + 1):
		var t:float = float(i) / float(step_count)
		var local_angle:float = start_angle + rotation_amount * t
		var scale_multiplier:float = _swing_scale_multiplier(t)
		var head_position:Vector2 = _opening_swing_head_position(safe_dir,local_angle,scale_multiplier)
		var radius:float = maxf(swing_hammer_head_radius,0.5) * scale_multiplier
		for hit_target:ball in _opening_swing_targets_at(head_position,radius):
			if hit_target == target:
				return true
	return false


func _find_opening_swing_target() -> ball:
	var best:ball = null
	var best_distance_sq:float = INF
	# V434 性能：_opening_swing_can_hit() 每个候选要做 73 次物理形状查询；100 人混战里
	# 每 tick 对全场 Ball 组逐个调用会占用十几毫秒。锤头在整圈挥舞中的所有采样圆都落在
	# 以自身为圆心、半径 (reach + head_radius) * peak_scale 的大圆内，因此先用同一套
	# Hurtbox Area 查询取一次大圆内的单位集合（严格超集），只对这些候选做精确判定。结果不变。
	for candidate:ball in _opening_swing_reachable_candidates():
		if not _opening_swing_can_hit(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(combat_target_position(candidate))
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = candidate
	return best


func _opening_swing_reachable_candidates() -> Array[ball]:
	var peak_scale:float = maxf(swing_peak_scale_multiplier,1.0)
	var reach_radius:float = (maxf(swing_hammer_head_reach,0.0) + maxf(swing_hammer_head_radius,0.5)) * peak_scale + 1.0
	var candidates:Array[ball] = _opening_swing_targets_at(global_position,reach_radius)
	if candidates.size() >= 128:
		# 极端拥挤时结果被 intersect_shape 上限截断，退回全量扫描，保证不漏目标。
		candidates.clear()
		for node:Node in get_tree().get_nodes_in_group("Ball"):
			if node is ball:
				candidates.append(node as ball)
	return candidates


# 威胁调试里的蓝色起手范围直接画“真实锤头扫过的环带”边界。
# 外圈 = 锤头中心半径 + 锤头碰撞半径；内圈 = 锤头中心半径 - 锤头碰撞半径。
# 两条圆之间才是第一挥锤头实际可以接触到的区域，和后续落地攻击圆完全分开。
func get_debug_detection_regions() -> Array[Dictionary]:
	var regions:Array[Dictionary] = []
	var outer:float = _opening_swing_outer_radius()
	var inner:float = _opening_swing_inner_radius()
	if outer > 0.0:
		regions.append({
			"shape":"circle",
			"position":global_position,
			"radius":outer,
			"kind":"minecraft_mace_swing_outer",
		})
	if inner > 0.0:
		regions.append({
			"shape":"circle",
			"position":global_position,
			"radius":inner,
			"kind":"minecraft_mace_swing_inner",
		})
	return regions


func _nearest_enemy(max_range:float) -> ball:
	var best:ball = null
	var best_sq:float = maxf(max_range,1.0) * maxf(max_range,1.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_enemy(candidate):
			continue
		var d:float = global_position.distance_squared_to(combat_target_position(candidate))
		if d <= best_sq:
			best_sq = d
			best = candidate
	return best

func _is_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0 or not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and Team == target.Team:
		return false
	return true

func _spawn_impact_visual(position_value:Vector2,radius:float) -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var effect:Node2D = IMPACT_EFFECT_SCRIPT.new() as Node2D
	effect.name = "重锤落地冲击_%d" % effect.get_instance_id()
	_runtime_container().add_child(effect)
	effect.call("setup",position_value,radius)

func _runtime_container() -> Node:
	var world:Node = get_tree().current_scene
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func _resolve_opening_swing_sfx() -> void:
	# 与铁匠村民的剑挥舞一致：优先在既有 Minecraft SFX 树里找 player strong/重击。
	_opening_swing_sfx = _find_minecraft_audio_by_keywords([
		"strong_attack",
		"attack_strong",
		"strong attack",
		"重击",
	])
	# 老项目音效树未随本轮更新包上传时，用现有重锤猛击重作为安全兜底，避免完全无声。
	if _opening_swing_sfx.is_empty():
		for stream:AudioStream in MACE_SMASH_HEAVY_SFX:
			if stream != null:
				_opening_swing_sfx.append(stream)


func _find_minecraft_audio_by_keywords(keywords:Array[String]) -> Array[AudioStream]:
	var result:Array[AudioStream] = []
	_collect_matching_audio("res://audio/sfx/我的世界",keywords,result)
	return result


func _collect_matching_audio(root_path:String,keywords:Array[String],output:Array[AudioStream]) -> void:
	var dir:DirAccess = DirAccess.open(root_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry:String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path:String = root_path.path_join(entry)
			if dir.current_is_dir():
				_collect_matching_audio(child_path,keywords,output)
			else:
				var lower_path:String = child_path.to_lower()
				var extension:String = entry.get_extension().to_lower()
				if extension in ["ogg","wav","mp3"]:
					for keyword:String in keywords:
						if keyword.to_lower() in lower_path:
							var loaded:Resource = load(child_path)
							if loaded is AudioStream and not output.has(loaded):
								output.append(loaded as AudioStream)
							break
		entry = dir.get_next()
	dir.list_dir_end()


func _broadcast_opening_swing_sfx() -> void:
	if _opening_swing_sfx.is_empty():
		return
	var stream:AudioStream = _opening_swing_sfx.pick_random()
	if stream == null:
		return
	_play_world_sfx(stream,global_position,1.5)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_opening_swing_sfx.rpc(stream.resource_path)


@rpc("authority","call_remote","unreliable")
func _rpc_play_opening_swing_sfx(resource_path:String) -> void:
	if resource_path.is_empty():
		return
	var loaded:Resource = load(resource_path)
	if loaded is AudioStream:
		_play_world_sfx(loaded as AudioStream,global_position,1.5)


func _play_height_based_smash_sfx(position_value:Vector2,height_value:float,hit_character:bool = false) -> void:
	# 按实际腾空高度选择用户提供的轻 / 中 / 重三档猛击音效。
	# 目前连砸高度为 58, 86, 114, 142, 170...，因此默认约为：
	# 1-2 层轻，3-4 层中，5 层及以上重。
	var stream:AudioStream = null
	var volume:float = 3.0
	if height_value >= heavy_smash_height:
		stream = _pick_sfx(MACE_SMASH_HEAVY_SFX)
		volume = 4.0
	elif height_value >= medium_smash_height:
		stream = _pick_sfx(MACE_SMASH_MEDIUM_SFX)
		volume = 2.5
	else:
		stream = _pick_sfx(MACE_SMASH_LIGHT_SFX)
		volume = 3.0
	_play_world_sfx(stream,position_value,volume + (MACE_HIT_GAIN_DB if hit_character else 0.0))

func _pick_sfx(pool:Array[AudioStream]) -> AudioStream:
	if pool.is_empty():
		return null
	return pool[randi_range(0,pool.size() - 1)]

func _play_world_sfx(stream:AudioStream,position_value:Vector2,volume:float) -> void:
	if stream == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = randf_range(0.97,1.03)
	player.max_distance = 1450.0
	player.attenuation = 0.66
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


# 给通用威胁分析器的运行时攻击声明：腾空期间整段都能看到真正的落地攻击圈，
# 而不是只在落地结算的单帧里闪一下。
func get_ai_attack_threats(_receiver:ball) -> Array:
	if health <= 0 or not _airborne:
		return []
	var radius:float = base_landing_radius + landing_radius_gain * float(_chain_level - 1)
	var multiplier:float = maxf(_chain_damage_multiplier,base_landing_damage_multiplier)
	return [{
		"shape":"circle",
		"position":_ground_impact_center(),
		"radius":radius,
		"damage":attack_damage(multiplier),
		"danger_in":maxf(_flight_duration - _flight_elapsed,0.0),
		"danger_duration":0.12,
		"kind":"minecraft_mace_landing",
		"source":self,
	}]


# 只给“威胁调试显示”使用，不进入 AI observation。
# 即使重锤当前没有在攻击，也把下一次落地真正使用的圆画出来，方便现场校准。
func get_debug_attack_regions() -> Array:
	if health <= 0:
		return []
	var level:int = _chain_level if _airborne else 1
	var radius:float = base_landing_radius + landing_radius_gain * float(level - 1)
	var multiplier:float = (
		maxf(_chain_damage_multiplier,base_landing_damage_multiplier)
		if _airborne
		else base_landing_damage_multiplier
	)
	return [{
		"shape":"circle",
		"position":_ground_impact_center(),
		"radius":radius,
		"damage":attack_damage(multiplier),
		"danger_in":maxf(_flight_duration - _flight_elapsed,0.0) if _airborne else 0.0,
		"danger_duration":0.12,
		"kind":"minecraft_mace_debug_range",
		"source":self,
	}]

func get_preview_texture() -> Texture2D:
	return MACE_TEXTURE
