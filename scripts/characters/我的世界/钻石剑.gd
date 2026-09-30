extends "res://scripts/characters/我的世界/mc_item_base.gd"

const DIAMOND_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/钻石剑/钻石剑.png")
const NETHERITE_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/钻石剑/下界合金剑.png")
const WEAPON_VISUAL_SIZE = preload("res://scripts/characters/我的世界/weapon_visual_size.gd")
const ARENA_MANAGER_SCRIPT:Script = preload("res://scripts/effects/我的世界/下界合金竞技场.gd")
const SWEEP_EFFECT_SCRIPT:Script = preload("res://scripts/effects/我的世界/钻石剑横扫.gd")

const SWEEP_SFX = [
	preload("res://audio/sfx/我的世界/近战/横扫/横扫01.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫02.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫03.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫04.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫05.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫06.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫07.ogg"),
]

# 与女巫药水伤害反馈共用同一组 Minecraft 受伤音效。
const MC_DAMAGE_SFX = [
	preload("res://audio/characters/女巫/hit1.ogg"),
	preload("res://audio/characters/女巫/hit2.ogg"),
	preload("res://audio/characters/女巫/hit3.ogg"),
]

const SMITHING_SFX = [
	preload("res://audio/sfx/我的世界/锻造/下界合金锻造1.ogg"),
	preload("res://audio/sfx/我的世界/锻造/下界合金锻造2.ogg"),
]

@export_category("钻石剑 / 下界合金升级")
@export_range(1,2000,1) var netherite_health_bonus:int = 500
@export_range(0,500,1) var netherite_damage_bonus:int = 10
@export_range(0.20,1.00,0.01) var netherite_attack_cooldown_multiplier:float = 0.75
@export_range(15.0,120.0,1.0) var smithing_contact_radius:float = 48.0
@export_range(0.20,2.00,0.05) var smithing_wait_duration:float = 0.70

@export_category("钻石剑 / 视觉")
@export_range(0.60,1.10,0.01) var visual_size_vs_wooden_sword:float = 1.0

@export_category("钻石剑 / 横扫攻击")
@export_range(0.2,2.0,0.01) var sword_attack_interval:float = 0.88
@export_range(28.0,100.0,1.0) var direct_swing_range:float = 46.0
@export_range(12.0,80.0,1.0) var sweep_visual_start_distance:float = 18.0
@export_range(20.0,120.0,1.0) var sweep_visual_forward_spread:float = 54.0
@export_range(15.0,90.0,1.0) var direct_half_angle_degrees:float = 38.0
@export_range(0.1,2.0,0.05) var direct_damage_multiplier:float = 1.0
@export_range(0.1,1.5,0.05) var sweep_damage_multiplier:float = 0.55
@export_range(0.05,0.40,0.01) var swing_hit_delay:float = 0.09
@export_range(0.15,0.80,0.01) var swing_visual_duration:float = 0.34
@export_range(-180.0,180.0,1.0) var sword_visual_forward_offset_degrees:float = 45.0
# V132：剑本体只保留贴脸略多一点的近战判定；横扫不再使用角色中心圆形范围，
# 而是由横扫特效逐帧把“当前可见图像包围盒”作为真实伤害区域向前推进。

var has_netherite_ingot:bool = false
var upgraded_to_netherite:bool = false
var _upgrade_flash_left:float = 0.0
var _attack_serial:int = 0
var _swing_reverse:bool = false
var _swing_tween:Tween = null
var _visual_base_position:Vector2 = Vector2.ZERO
var _visual_base_rotation:float = 0.0
var _swing_restore_flip_h:bool = false
var _afterimage_step:int = -1
var _sweep_hit_targets:Dictionary = {}
var _swing_attack_flip_h:bool = false
var _smithing_in_progress:bool = false
var _smithing_wait_left:float = 0.0
var _smithing_table:Node2D = null


func _ready() -> void:
	# V125：钻石剑不再靠身体接触被动撞伤；真正伤害全部来自挥剑 + 横扫。
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	Attack_Cooling = maxf(sword_attack_interval,0.05)
	_fit_visual_to_wooden_sword()
	super._ready()
	add_to_group("MinecraftDiamondSword")
	if image != null:
		_visual_base_position = image.position
		_visual_base_rotation = image.rotation
	if default_properties != null:
		default_properties["Attack_Cooling"] = Attack_Cooling
	call_deferred("_ensure_arena_manager")


func _fit_visual_to_wooden_sword() -> void:
	if image is Sprite2D:
		WEAPON_VISUAL_SIZE.fit_to_wooden_sword(image,visual_size_vs_wooden_sword)


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if _upgrade_flash_left > 0.0:
		_upgrade_flash_left = maxf(_upgrade_flash_left - delta,0.0)
		if image is CanvasItem:
			(image as CanvasItem).modulate = Color(1.0,0.72 + 0.28 * sin(_upgrade_flash_left * 24.0),0.78,1.0)
		if _upgrade_flash_left <= 0.0 and image is CanvasItem:
			(image as CanvasItem).modulate = Color.WHITE

	if not is_multiplayer_authority() or health <= 0 or upgraded_to_netherite or not has_netherite_ingot:
		_cancel_smithing_wait()
		return

	var table:Node2D = get_tree().get_first_node_in_group("MinecraftSmithingTable") as Node2D
	if _smithing_in_progress:
		# 已经碰到锻造台后就在原地完成这一小段锻造等待；不会因为 AI/玩家输入又滑走。
		if table == null or not is_instance_valid(table) or table != _smithing_table:
			_cancel_smithing_wait()
			return
		Repel = Vector2.ZERO
		velocity = Vector2.ZERO
		clear_external_directional_gravity_velocity()
		_smithing_wait_left = maxf(_smithing_wait_left - maxf(delta,0.0),0.0)
		if _smithing_wait_left <= 0.0:
			_upgrade_to_netherite()
		return

	if table != null and is_instance_valid(table) and _is_touching_smithing_table(table):
		_begin_smithing_wait(table)


func move(speed:float,delta:float) -> void:
	if _smithing_in_progress:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.move(speed,delta)


func stand(delta:float) -> void:
	if _smithing_in_progress:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.stand(delta)


func _begin_smithing_wait(table:Node2D) -> void:
	if table == null or not is_instance_valid(table) or upgraded_to_netherite or not has_netherite_ingot:
		return
	_smithing_in_progress = true
	_smithing_table = table
	_smithing_wait_left = maxf(smithing_wait_duration,0.05)
	Attacking = false
	_attack_serial += 1
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_restore_sword_visual()
	Repel = Vector2.ZERO
	velocity = Vector2.ZERO
	clear_external_directional_gravity_velocity()


func _cancel_smithing_wait() -> void:
	_smithing_in_progress = false
	_smithing_wait_left = 0.0
	_smithing_table = null


func _is_touching_smithing_table(table:Node2D) -> bool:
	if table == null or not is_instance_valid(table):
		return false

	# 第一优先：读取这一帧 CharacterBody2D 真正撞到的实体。这样必须实际碰到锻造台，
	# 不会像旧版 48px 圆形距离那样隔着一段距离就原地升级。
	for index:int in range(get_slide_collision_count()):
		var collision:KinematicCollision2D = get_slide_collision(index)
		if collision != null and collision.get_collider() == table:
			return true

	# 站着不动时 move_and_slide() 可能没有新的 slide collision；用真实 Shape2D 再补一次接触检查。
	var table_shape:CollisionShape2D = table.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if (
		collision_shape_2d != null
		and is_instance_valid(collision_shape_2d)
		and not collision_shape_2d.disabled
		and collision_shape_2d.shape != null
		and table_shape != null
		and is_instance_valid(table_shape)
		and not table_shape.disabled
		and table_shape.shape != null
	):
		if collision_shape_2d.shape.collide(
			collision_shape_2d.global_transform,
			table_shape.shape,
			table_shape.global_transform
		):
			return true

	# 仅给 safe_margin / 缩放差异留很小的接触容差，不再使用旧版大半径“远距离升级”。
	return global_position.distance_to(ball.body_point(table,global_position)) <= maxf(8.0,maxf(smithing_contact_radius,1.0) * 0.35)


func Attack() -> void:
	if _smithing_in_progress:
		Attacking = false
		return
	if state_machine == null or state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	super()
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return

	# V135：攻击瞄准与移动彻底分离，并恢复 360° 索敌。
	# 任何方向的敌人都可以成为目标；如果目标在当前视觉背面，只临时左右翻转人物/剑的视觉，
	# 绝不写回 direction / velocity，因此不会因为攻击改变移动方向。
	var attack_dir:Vector2 = Vector2.ZERO
	var target:ball = null

	if has_player_control_aim():
		attack_dir = player_control_aim_direction(_movement_facing_direction())
	else:
		target = _nearest_enemy_360(_sweep_visual_max_reach())
		if target == null or not is_instance_valid(target):
			Attacking = false
			return
		var target_position:Vector2 = combat_target_position(target)
		attack_dir = target_position - global_position

	if attack_dir.length_squared() <= 0.000001:
		Attacking = false
		return

	attack_dir = attack_dir.normalized()
	Attacking = true
	_attack_serial += 1
	_sweep_hit_targets.clear()
	var ticket:int = _attack_serial
	# 不再左右交替反向挥舞；每次都做同一套“从上往下”斩击。
	_swing_reverse = false
	_broadcast_attack_visual(attack_dir,false)

	await get_tree().create_timer(maxf(swing_hit_delay,0.01),false).timeout
	if not _attack_ticket_valid(ticket):
		if ticket == _attack_serial:
			Attacking = false
		return

	_deal_direct_swing_damage(attack_dir)

	var tail_time:float = maxf(swing_visual_duration - swing_hit_delay,0.03)
	await get_tree().create_timer(tail_time,false).timeout
	if ticket == _attack_serial and is_instance_valid(self):
		Attacking = false


func _movement_facing_direction() -> Vector2:
	# 只用于玩家瞄准没有输入时的兜底，不会被攻击流程修改。
	var source:Vector2 = Vector2.ZERO
	if is_player_controlled() and player_control_direction.length_squared() > 0.000001:
		source = player_control_direction
	elif direction.length_squared() > 0.000001:
		source = direction
	if source.length_squared() > 0.000001:
		return source.normalized()
	return Vector2.LEFT if is_character_visual_flipped_h() else Vector2.RIGHT


func _nearest_enemy_360(max_range:float) -> ball:
	var best:ball = null
	var best_distance_sq:float = INF
	var range_sq:float = maxf(max_range,1.0) * maxf(max_range,1.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_enemy_target(candidate):
			continue
		var candidate_position:Vector2 = combat_target_position(candidate)
		var distance_sq:float = global_position.distance_squared_to(candidate_position)
		if distance_sq > range_sq:
			continue
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = candidate
	return best


func _attack_visual_flip_for_direction(attack_dir:Vector2) -> bool:
	# dir_left=false 的本角色：左侧目标使用水平翻转，右侧目标不翻。
	# 目标几乎正上/正下时保留当前视觉朝向，避免 x≈0 时左右抖动。
	if absf(attack_dir.x) <= 0.025:
		return is_character_visual_flipped_h()
	return (attack_dir.x > 0.0) if dir_left else (attack_dir.x < 0.0)


func _attack_ticket_valid(ticket:int) -> bool:
	return (
		ticket == _attack_serial
		and is_instance_valid(self)
		and is_inside_tree()
		and health > 0
		and state_machine != null
		and state_machine.current_state != State.Die
		and not _smithing_in_progress
		and is_combat_runtime_active()
	)


func _deal_direct_swing_damage(attack_dir:Vector2) -> void:
	var targets:Array[ball] = _targets_in_forward_arc(
		attack_dir,
		maxf(direct_swing_range,1.0),
		deg_to_rad(clampf(direct_half_angle_degrees,5.0,175.0))
	)
	var outgoing:float = attack_damage(maxf(direct_damage_multiplier,0.0))
	if outgoing <= 0.0:
		return
	for target:ball in targets:
		if target == null or not is_instance_valid(target):
			continue
		target.receive_positional_damage(
			outgoing,
			global_position + attack_dir * minf(direct_swing_range * 0.72,64.0),
			false,
			self
		)
		_broadcast_mc_damage_sfx(ball.body_point(target,global_position))


func _deal_sweep_visual_damage(area_center:Vector2,area_size:Vector2,area_rotation:float) -> void:
	# 横扫伤害只跟随特效自身的当前位置/尺寸，不再以角色为圆心。
	# effect 每帧传入当前帧透明像素包围盒对应的世界矩形，目标一刀只会吃一次横扫伤害。
	if not is_multiplayer_authority() or not Attacking or health <= 0 or get_world_2d() == null:
		return
	if area_size.x <= 0.5 or area_size.y <= 0.5:
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(area_size.x,1.0),maxf(area_size.y,1.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(area_rotation,area_center)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 2
	var results:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,64)
	var outgoing:float = attack_damage(maxf(sweep_damage_multiplier,0.0))
	if outgoing <= 0.0:
		return
	for result:Dictionary in results:
		var collider:Variant = result.get("collider",null)
		if not collider is hurtbox:
			continue
		var target:ball = (collider as hurtbox).get_parent() as ball
		if target == null or not is_instance_valid(target) or not _is_enemy_target(target):
			continue
		var target_id:int = target.get_instance_id()
		if _sweep_hit_targets.has(target_id):
			continue
		_sweep_hit_targets[target_id] = true
		target.receive_positional_damage(
			outgoing,
			area_center,
			false,
			self
		)
		_broadcast_mc_damage_sfx(ball.body_point(target,global_position))


func _sweep_visual_max_reach() -> float:
	# 末帧视觉深度约 24px；额外留少量 Hurtbox 半径给 AI 接敌。
	# 真实伤害仍严格由横扫特效逐帧矩形决定。
	return maxf(sweep_visual_start_distance + sweep_visual_forward_spread + 18.0,direct_swing_range + 8.0)


func _targets_in_forward_arc(attack_dir:Vector2,range_value:float,half_angle:float) -> Array[ball]:
	var found:Array[ball] = []
	if get_world_2d() == null:
		return found
	var shape := CircleShape2D.new()
	shape.radius = maxf(range_value,1.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 2
	var results:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,96)
	var seen:Dictionary = {}
	var forward:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
	for result:Dictionary in results:
		var collider:Variant = result.get("collider",null)
		if not collider is hurtbox:
			continue
		var target:ball = (collider as hurtbox).get_parent() as ball
		if target == null or not is_instance_valid(target) or target == self:
			continue
		if not _is_enemy_target(target):
			continue
		var target_id:int = target.get_instance_id()
		if seen.has(target_id):
			continue
		var offset:Vector2 = ball.body_point(target,global_position) - global_position
		var distance:float = offset.length()
		if distance > range_value + 0.001:
			continue
		if distance > 0.001:
			var angle_delta:float = absf(forward.angle_to(offset / distance))
			if angle_delta > half_angle:
				continue
		seen[target_id] = true
		found.append(target)
	return found


func _is_enemy_target(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0 or not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true


func _broadcast_attack_visual(attack_dir:Vector2,reverse:bool) -> void:
	_play_attack_visual_local(attack_dir,reverse)
	if multiplayer.has_multiplayer_peer():
		_sync_attack_visual.rpc(attack_dir,reverse)


@rpc("authority","call_remote","unreliable")
func _sync_attack_visual(attack_dir:Vector2,reverse:bool) -> void:
	_play_attack_visual_local(attack_dir,reverse)


func _play_attack_visual_local(attack_dir:Vector2,reverse:bool) -> void:
	if image == null or not is_instance_valid(image):
		return
	if _swing_tween != null and _swing_tween.is_running():
		_swing_tween.kill()
	_swing_restore_flip_h = is_character_visual_flipped_h()
	_afterimage_step = -1
	var direction_value:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
	# V135：360° 攻击时，目标在人物另一侧就只翻视觉，不修改移动方向。
	# flip_h 会改变贴图自身的剑尖轴，因此下面的挥舞角度会同步做 90° 镜像补偿。
	_swing_attack_flip_h = _attack_visual_flip_for_direction(direction_value)
	set_character_visual_flip_h(_swing_attack_flip_h)
	image.position = _visual_base_position
	image.rotation = _visual_base_rotation
	_swing_tween = create_tween()
	_swing_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_method(
		Callable(self,"_apply_sword_visual_progress").bind(direction_value,reverse),
		0.0,
		1.0,
		maxf(swing_visual_duration,0.12)
	)
	_swing_tween.finished.connect(_restore_sword_visual,CONNECT_ONE_SHOT)
	_spawn_sweep_visual(direction_value,reverse)
	_play_sweep_sfx_local()


func _apply_sword_visual_progress(progress:float,attack_dir:Vector2,reverse:bool) -> void:
	if image == null or not is_instance_valid(image):
		return
	var p:float = clampf(progress,0.0,1.0)
	var mirror_compensation:float = 90.0 if _swing_attack_flip_h else 0.0
	var base_attack_angle:float = attack_dir.angle() + deg_to_rad(sword_visual_forward_offset_degrees + mirror_compensation)
	# V130：固定做“从上往下”的斩击。Godot 2D 中角度增加为顺时针视觉方向，
	# 因此从目标方向上方约 76° 摆到下方约 24°，视觉上就是明显的下劈。
	var start_offset:float = deg_to_rad(-76.0)
	var end_offset:float = deg_to_rad(24.0)
	var swing_finish:float = 0.68

	if p <= swing_finish:
		var swing_t:float = clampf(p / swing_finish,0.0,1.0)
		var eased:float = 1.0 - pow(1.0 - swing_t,4.0)
		image.rotation = lerp_angle(base_attack_angle + start_offset,base_attack_angle + end_offset,eased)
		# 只向敌人方向微微探出，不再大幅前伸。
		image.position = _visual_base_position + attack_dir * (sin(swing_t * PI) * 5.0)
		# 挥砍阶段连续留下短残影；残影只负责视觉，不参与碰撞。
		var step:int = int(floor(swing_t * 7.0))
		if step > _afterimage_step:
			_afterimage_step = step
			_spawn_sword_afterimage()
	else:
		# 下劈完成后快速回位，前半段回得快，最后轻微收势。
		var recover_t:float = clampf((p - swing_finish) / maxf(1.0 - swing_finish,0.001),0.0,1.0)
		var recover_eased:float = 1.0 - pow(1.0 - recover_t,4.5)
		image.rotation = lerp_angle(base_attack_angle + end_offset,_visual_base_rotation,recover_eased)
		image.position = (_visual_base_position + attack_dir * 1.5).lerp(_visual_base_position,recover_eased)


func _spawn_sword_afterimage() -> void:
	if not (image is Sprite2D) or image.get_parent() == null:
		return
	var source:Sprite2D = image as Sprite2D
	var ghost := Sprite2D.new()
	ghost.name = "SwordAfterimage"
	ghost.texture = source.texture
	ghost.centered = source.centered
	ghost.offset = source.offset
	ghost.region_enabled = source.region_enabled
	ghost.region_rect = source.region_rect
	ghost.texture_filter = source.texture_filter
	ghost.position = source.position
	ghost.rotation = source.rotation
	ghost.scale = source.scale
	ghost.flip_h = source.flip_h
	ghost.flip_v = source.flip_v
	ghost.z_as_relative = source.z_as_relative
	ghost.z_index = source.z_index - 1
	ghost.self_modulate = Color(0.90,0.96,1.0,0.34)
	image.get_parent().add_child(ghost)
	var fade := ghost.create_tween()
	fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.tween_property(ghost,"self_modulate",Color(0.90,0.96,1.0,0.0),0.13)
	fade.finished.connect(ghost.queue_free,CONNECT_ONE_SHOT)


func _restore_sword_visual() -> void:
	if image == null or not is_instance_valid(image):
		return
	image.position = _visual_base_position
	image.rotation = _visual_base_rotation
	var facing_source:Vector2 = player_control_direction if is_player_controlled() and player_control_direction.length_squared() > 0.000001 else direction
	if facing_source.length_squared() > 0.000001:
		var desired_flip_h:bool = (facing_source.x > 0.0) if dir_left else (facing_source.x <= 0.0)
		set_character_visual_flip_h(desired_flip_h)
	else:
		set_character_visual_flip_h(_swing_restore_flip_h)


func _spawn_sweep_visual(attack_dir:Vector2,reverse:bool) -> void:
	var effect:Node2D = SWEEP_EFFECT_SCRIPT.new() as Node2D
	if effect == null:
		return
	# 挂在角色下面避免直接触碰 World 的 MultiplayerSpawner.spawn_path；effect 自己 top_level，
	# 所以实际仍保持世界坐标，不会跟随角色继续移动。
	add_child(effect)
	if effect.has_method("configure"):
		effect.call(
			"configure",
			global_position,
			attack_dir,
			false, # 横扫弧面始终朝目标；不再跟随左右交替挥剑做前后镜像。
			0.34,
			maxf(sweep_visual_start_distance,0.0),
			maxf(sweep_visual_forward_spread,0.0),
			self
		)


func _play_sweep_sfx_local() -> void:
	if SWEEP_SFX.is_empty():
		return
	var stream:AudioStream = SWEEP_SFX.pick_random()
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MinecraftSwordSweepSfx"
	player.stream = stream
	player.volume_db = 2.0
	player.pitch_scale = randf_range(0.98,1.02)
	player.max_distance = 1350.0
	player.attenuation = 0.68
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.top_level = true
	player.global_position = global_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _broadcast_mc_damage_sfx(world_position:Vector2) -> void:
	if preload("res://scripts/effects/我的世界/mc_hit_feedback.gd").manages(self): return
	if MC_DAMAGE_SFX.is_empty():
		return
	var index:int = randi_range(0,MC_DAMAGE_SFX.size() - 1)
	_play_mc_damage_sfx_local(index,world_position)
	if multiplayer.has_multiplayer_peer():
		_sync_mc_damage_sfx.rpc(index,world_position)


@rpc("authority","call_remote","unreliable")
func _sync_mc_damage_sfx(index:int,world_position:Vector2) -> void:
	_play_mc_damage_sfx_local(index,world_position)


func _play_mc_damage_sfx_local(index:int,world_position:Vector2) -> void:
	if index < 0 or index >= MC_DAMAGE_SFX.size():
		return
	var stream:AudioStream = MC_DAMAGE_SFX[index]
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MinecraftMeleeDamageSfx"
	player.stream = stream
	player.volume_db = 1.0
	player.pitch_scale = randf_range(0.98,1.02)
	player.max_distance = 1450.0
	player.attenuation = 0.68
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.top_level = true
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _broadcast_smithing_sfx() -> void:
	if SMITHING_SFX.is_empty():
		return
	var index:int = randi_range(0,SMITHING_SFX.size() - 1)
	_play_smithing_sfx_local(index)
	if multiplayer.has_multiplayer_peer():
		_sync_smithing_sfx.rpc(index)


@rpc("authority","call_remote","reliable")
func _sync_smithing_sfx(index:int) -> void:
	_play_smithing_sfx_local(index)


func _play_smithing_sfx_local(index:int) -> void:
	if index < 0 or index >= SMITHING_SFX.size():
		return
	var stream:AudioStream = SMITHING_SFX[index]
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MinecraftNetheriteSmithingSfx"
	player.stream = stream
	player.volume_db = 3.0
	player.pitch_scale = randf_range(0.99,1.01)
	player.max_distance = 1600.0
	player.attenuation = 0.62
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.top_level = true
	var table:Node2D = get_tree().get_first_node_in_group("MinecraftSmithingTable") as Node2D
	player.global_position = table.global_position if table != null and is_instance_valid(table) else global_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func receive_netherite_ingot() -> bool:
	if upgraded_to_netherite or has_netherite_ingot or health <= 0:
		return false
	_cancel_smithing_wait()
	has_netherite_ingot = true
	_upgrade_flash_left = 0.42
	return true


# 复制品是全新的钻石剑（未升级）：复制已升级的剑时扣除下界合金加成，
# 避免复制品之后再次升级时加成叠加两次。
func character_copy_template_stats(stats:Dictionary) -> Dictionary:
	if not upgraded_to_netherite: return stats
	stats["Max_health"] = maxi(int(stats.get("Max_health",Max_health))-maxi(netherite_health_bonus,0),1)
	stats["Damage"] = maxi(int(stats.get("Damage",Damage))-maxi(netherite_damage_bonus,0),0)
	stats["Attack_Cooling"] = maxf(float(stats.get("Attack_Cooling",Attack_Cooling))/clampf(netherite_attack_cooldown_multiplier,0.20,1.00),0.05)
	return stats


func _upgrade_to_netherite() -> void:
	if upgraded_to_netherite or not has_netherite_ingot:
		return
	_cancel_smithing_wait()
	has_netherite_ingot = false
	upgraded_to_netherite = true
	var before_health:int = int(health)
	Max_health += maxi(netherite_health_bonus,0)
	default_properties["Max_health"] = Max_health
	health = mini(Max_health,before_health + maxi(netherite_health_bonus,0))

	# 下界合金升级同时强化攻击力与攻速；必须同步 default_properties，
	# 否则 World 的每帧默认属性恢复会把强化数值改回钻石剑阶段。
	Damage += maxi(netherite_damage_bonus,0)
	default_properties["Damage"] = Damage
	Attack_Cooling = maxf(0.05,Attack_Cooling * clampf(netherite_attack_cooldown_multiplier,0.20,1.00))
	default_properties["Attack_Cooling"] = Attack_Cooling

	if image is Sprite2D:
		(image as Sprite2D).texture = NETHERITE_TEXTURE
		_fit_visual_to_wooden_sword()
	_upgrade_flash_left = 0.75
	_broadcast_smithing_sfx()


func _ensure_arena_manager() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var world:Node = get_tree().current_scene
	if world.get_node_or_null("MinecraftNetheriteArenaManager") != null:
		return
	var manager := Node.new()
	manager.name = "MinecraftNetheriteArenaManager"
	manager.set_script(ARENA_MANAGER_SCRIPT)
	world.add_child(manager)


func get_debug_detection_regions() -> Array[Dictionary]:
	if health <= 0 or not is_inside_tree():
		return []
	return [
		{
			"shape":"circle",
			"position":global_position,
			"radius":maxf(direct_swing_range,1.0),
			"kind":"minecraft_diamond_sword_direct",
		},
		{
			"shape":"circle",
			"position":global_position,
			"radius":_sweep_visual_max_reach(),
			"kind":"minecraft_diamond_sword_sweep_visual_max_reach",
		}
	]


func get_preview_texture() -> Texture2D:
	return NETHERITE_TEXTURE if upgraded_to_netherite else DIAMOND_TEXTURE
