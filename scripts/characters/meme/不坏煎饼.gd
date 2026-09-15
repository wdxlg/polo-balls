extends ball

const PANCAKE_PROJECTILE_SCENE:PackedScene = preload("res://scenes/shooter/不坏煎饼弹.tscn")
const PANCAKE_REFRESH_AUDIO:AudioStream = preload("res://audio/characters/meme/不坏煎饼/DM_20260901232423_001.mp3")
const WILD_DOG_MILK_AGE_META:StringName = &"wild_dog_milk_age_percent"
const GENERIC_MOTION_LOCK_META:StringName = &"generic_motion_lock_count"
const GENERIC_MOTION_BASELINE_META:StringName = &"generic_motion_lock_baseline"

@export_category("不坏煎饼 - 永久弹体")
@export_range(10.0,220.0,1.0) var projectile_spawn_offset:float = 78.0
@export_range(0.02,2.0,0.01) var projectile_repair_scan_interval:float = 0.05
@export_range(4.0,80.0,1.0) var projectile_map_inset:float = 26.0
@export_range(0.0,240.0,5.0) var projectile_outside_recovery_margin:float = 80.0

@export_category("不坏煎饼 - 完全刷新")
@export_range(1.0,60.0,0.1) var full_refresh_cooldown:float = 32.0
@export_range(0.05,1.5,0.01) var refresh_visual_duration:float = 0.30

var _projectile:ball = null
var _projectile_scan_left:float = 0.0
var _initial_properties:Dictionary = {}
var _initial_max_block:int = 0
var _initial_max_energy:int = 0
var _initial_can_attack:bool = false
var _initial_can_skill:bool = true
var _refresh_visual_tween:Tween = null
var _full_refresh_cycle_left:float = 0.0
var _refresh_in_progress:bool = false


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = true
	Health_Restore = 0
	Skill_Cooling = maxf(full_refresh_cooldown,0.1)
	super._ready()
	add_to_group("UnspoiledPancakeCharacter")

	_initial_properties = default_properties.duplicate(true)
	_initial_properties["Skill_Cooling"] = maxf(full_refresh_cooldown,0.1)
	default_properties["Skill_Cooling"] = maxf(full_refresh_cooldown,0.1)
	_initial_max_block = max_block
	_initial_max_energy = max_energy
	_initial_can_attack = Can_Attack
	_initial_can_skill = Can_Skill
	_projectile_scan_left = 0.0
	_full_refresh_cycle_left = maxf(full_refresh_cooldown,0.1)
	_spawn_or_restore_projectile(true)


func _exit_tree() -> void:
	_cleanup_projectile()


func Die() -> void:
	_cleanup_projectile()
	super.Die()


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health > 0 and state != State.Die:
		var safe_delta:float = maxf(delta,0.0)

		# V273：永久弹体是角色核心机制。每 0.05s 重新确认一次，异常 queue_free、
		# BattleTransient 清理或飞出地图后都要自动找回/重建，不能整局消失。
		_projectile_scan_left -= safe_delta
		if _projectile_scan_left <= 0.0:
			_projectile_scan_left = maxf(projectile_repair_scan_interval,0.02)
			_spawn_or_restore_projectile(false)

		if is_combat_runtime_active():
			_full_refresh_cycle_left = maxf(_full_refresh_cycle_left - safe_delta,0.0)

			# V274：刷新主条件改为“永久煎饼弹腐烂进度到 100%”。
			# 直接读取弹体自己的腐烂比例；到 100% 当帧就刷新，不再依赖公共 Skill 条。
			var rot_refresh_due:bool = false
			if _projectile != null and is_instance_valid(_projectile):
				if _projectile.has_method("is_fully_rotten"):
					rot_refresh_due = bool(_projectile.call("is_fully_rotten"))
				elif _projectile.has_method("get_rot_ratio"):
					rot_refresh_due = float(_projectile.call("get_rot_ratio")) >= 1.0 - 0.0001
			if rot_refresh_due and not _refresh_in_progress:
				_perform_full_refresh()

			# 公共技能进度与 32 秒周期只保留兼容兜底。
			# 不再要求状态机一定成功切进 State.Skill；眩晕/禁攻/玩家直控等情况
			# 都不能让完全刷新卡在 100%。独立 32 秒兜底也继续保留。
			var public_refresh_due:bool = false
			if state_machine != null:
				public_refresh_due = (
					float(state_machine.last_state_dis.get("Skill",0.0))
					>= maxf(Skill_Cooling,0.1)
				)
			if (_full_refresh_cycle_left <= 0.0 or public_refresh_due) and not _refresh_in_progress:
				_perform_full_refresh()

	super.tick_physics(state,delta)


func on_pancake_rot_reached_full() -> void:
	# V274：腐烂进度到 100% 的同一物理帧直接刷新，不等公共 Skill 状态。
	if not is_multiplayer_authority() or health <= 0:
		return
	_perform_full_refresh()


func Skill() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		Using_Skill = false
		return
	Using_Skill = true
	_perform_full_refresh()
	Using_Skill = false


func _perform_full_refresh() -> void:
	if _refresh_in_progress or health <= 0 or not is_multiplayer_authority():
		return
	_refresh_in_progress = true

	# 无论由公共 Skill、公共进度到点还是独立兜底触发，都从现在开始下一轮。
	_full_refresh_cycle_left = maxf(full_refresh_cooldown,0.1)

	# 1) 删除所有外部 Buff，并把开局属性快照写回。
	Buff_Dic.clear()
	for raw_key:Variant in _initial_properties.keys():
		var key:String = str(raw_key)
		default_properties[key] = _initial_properties[raw_key]
		self.set(key,_initial_properties[raw_key])

	# 2) 生命、护盾、能量回到开局满状态。
	max_block = _initial_max_block
	max_energy = _initial_max_energy
	Max_health = maxi(int(_initial_properties.get("Max_health",Max_health)),1)
	health = Max_health
	block = max_block
	energy = max_energy

	# 3) 删除持续状态、衰老记录、眩晕/击退控制，并停止 Hurt 状态计时。
	remove_meta(WILD_DOG_MILK_AGE_META)
	if side_status_ui != null and is_instance_valid(side_status_ui) and side_status_ui.has_method("clear_permanent"):
		side_status_ui.call("clear_permanent")
	if status_image != null and is_instance_valid(status_image):
		status_image.self_modulate = Color(1.0,1.0,1.0,0.0)
	for child:Node in get_children().duplicate():
		if child == null or not is_instance_valid(child):
			continue
		if child.get_script() == KNOCKBACK_EFFECT_SCRIPT:
			child.queue_free()
	remove_meta(GENERIC_MOTION_LOCK_META)
	remove_meta(GENERIC_MOTION_BASELINE_META)
	dizziness = false
	_damage_output_disabled_until_msec = 0
	Repel = Vector2.ZERO
	velocity = Vector2.ZERO
	clear_external_directional_gravity_velocity()
	hurting_timer.stop()
	if hit_white_tween != null and hit_white_tween.is_valid():
		hit_white_tween.kill()
	hit_white_method(0.0)
	set_image_color()

	# 4) 冷却/状态累计真正归零。尤其 Skill 进度必须从 0 重新走，不能保持“满条”。
	Can_Attack = _initial_can_attack
	Can_Skill = _initial_can_skill
	Attacking = false
	Using_Skill = false
	continue_attack_time = 0.0
	Skill_Cooling = maxf(full_refresh_cooldown,0.1)
	default_properties["Skill_Cooling"] = Skill_Cooling
	if state_machine != null:
		state_machine.state_time = 0.0
		for state_key:Variant in state_machine.last_state_dis.keys():
			state_machine.last_state_dis[state_key] = 0.0
		state_machine.last_state_dis["Skill"] = 0.0

	# 5) 刷新永久煎饼弹；异常缺失时必须现场重建。
	_spawn_or_restore_projectile(true)
	if _projectile != null and is_instance_valid(_projectile) and _projectile.has_method("reset_pancake_state"):
		_projectile.call("reset_pancake_state")

	# V275：每次真正完成“完全刷新”都播放时间倒流音效。
	_play_full_refresh_audio()
	_play_refresh_visual()
	_refresh_in_progress = false


func _play_full_refresh_audio() -> void:
	if PANCAKE_REFRESH_AUDIO == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "UnspoiledPancakeRefreshAudio"
	player.stream = PANCAKE_REFRESH_AUDIO
	player.max_distance = 1400.0
	player.attenuation = 1.0
	player.volume_db = 0.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _spawn_or_restore_projectile(force_reset:bool) -> void:
	if not is_multiplayer_authority():
		return
	if health <= 0 or not is_inside_tree() or not is_combat_runtime_active():
		return

	# 先尝试从组里重新认领自己的永久弹，防止脚本引用丢失但弹体仍在场上。
	if _projectile == null or not is_instance_valid(_projectile) or _projectile.is_queued_for_deletion():
		_projectile = _find_existing_owned_projectile()

	if _projectile != null and is_instance_valid(_projectile) and not _projectile.is_queued_for_deletion():
		_recover_projectile_if_outside_map(_projectile)
		if force_reset and _projectile.has_method("reset_pancake_state"):
			_projectile.call("reset_pancake_state")
		return

	var projectile:ball = PANCAKE_PROJECTILE_SCENE.instantiate() as ball
	if projectile == null:
		push_error("不坏煎饼：无法实例化永久煎饼弹")
		return

	var launch_direction:Vector2 = _resolve_projectile_launch_direction()
	projectile.Master = self
	projectile.Master_name = str(name)
	projectile.Team = Team
	projectile.direction = launch_direction
	projectile.name = Game.return_random_name(projectile)

	var parent:Node = get_tree().current_scene
	if parent == null:
		projectile.queue_free()
		return
	parent.add_child(projectile,true)
	projectile.global_position = _resolve_projectile_spawn_position(launch_direction)
	_projectile = projectile
	projectile.tree_exited.connect(_on_owned_projectile_tree_exited.bind(projectile),CONNECT_ONE_SHOT)
	if force_reset and projectile.has_method("reset_pancake_state"):
		projectile.call("reset_pancake_state")


func _find_existing_owned_projectile() -> ball:
	var found:ball = null
	for node:Node in get_tree().get_nodes_in_group("UnspoiledPancakeProjectile"):
		if not (node is ball) or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var candidate:ball = node as ball
		if candidate.Master != self:
			continue
		if found == null:
			found = candidate
			if not candidate.tree_exited.is_connected(_on_owned_projectile_tree_exited.bind(candidate)):
				candidate.tree_exited.connect(_on_owned_projectile_tree_exited.bind(candidate),CONNECT_ONE_SHOT)
		else:
			# 同一个煎饼只允许一枚永久弹；异常重复实例清掉多余项。
			candidate.queue_free()
	return found


func _on_owned_projectile_tree_exited(projectile:ball) -> void:
	if _projectile == projectile:
		_projectile = null
	# 下一物理帧立即进入修复扫描。不要在 tree_exited 回调里直接生成，
	# 避免 Reset/换回合正在清 BattleTransient 时反向制造新节点。
	_projectile_scan_left = 0.0


func _resolve_projectile_launch_direction() -> Vector2:
	var launch_direction:Vector2 = direction
	var target:Node = return_reusable_combat_target()
	if target is Node2D and is_instance_valid(target):
		var to_target:Vector2 = combat_target_position(target) - global_position
		if to_target.length_squared() > 0.000001:
			launch_direction = to_target.normalized()
	if launch_direction.length_squared() <= 0.000001:
		launch_direction = Vector2.RIGHT
	return launch_direction.normalized()


func _resolve_projectile_spawn_position(launch_direction:Vector2) -> Vector2:
	var spawn_position:Vector2 = global_position + launch_direction * maxf(projectile_spawn_offset,1.0)
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return spawn_position
	var inset:float = minf(
		maxf(projectile_map_inset,4.0),
		maxf(minf(map_rect.size.x,map_rect.size.y) * 0.45,4.0)
	)
	var safe_rect:Rect2 = map_rect.grow(-inset)
	if safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		return map_rect.get_center()
	return Vector2(
		clampf(spawn_position.x,safe_rect.position.x,safe_rect.end.x),
		clampf(spawn_position.y,safe_rect.position.y,safe_rect.end.y)
	)


func _recover_projectile_if_outside_map(projectile:ball) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	var allowed_rect:Rect2 = map_rect.grow(maxf(projectile_outside_recovery_margin,0.0))
	if allowed_rect.has_point(projectile.global_position):
		return
	var launch_direction:Vector2 = _resolve_projectile_launch_direction()
	projectile.global_position = _resolve_projectile_spawn_position(launch_direction)
	projectile.direction = launch_direction
	projectile.velocity = launch_direction * maxf(projectile.Speed,1.0)


func _current_map_world_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var map_group_value:Variant = world.get("map_group")
	var chosen_value:Variant = world.get("now_choose_map")
	if not (map_group_value is Dictionary):
		return Rect2()
	var map_group:Dictionary = map_group_value as Dictionary
	if not map_group.has(chosen_value):
		return Rect2()
	var map_node:Variant = map_group[chosen_value]
	if not (map_node is TileMapLayer):
		return Rect2()
	var result:Variant = world.call("return_map_world_rect",map_node as TileMapLayer)
	if result is Rect2:
		return result
	return Rect2()


func _cleanup_projectile() -> void:
	if _projectile != null and is_instance_valid(_projectile):
		_projectile.queue_free()
	_projectile = null
	side_status_remove_permanent("right","unspoiled_pancake_rot")


func _play_refresh_visual() -> void:
	if image == null or not is_instance_valid(image) or not image is CanvasItem:
		return
	if _refresh_visual_tween != null and _refresh_visual_tween.is_valid():
		_refresh_visual_tween.kill()
	var item:CanvasItem = image as CanvasItem
	item.self_modulate = Color(0.72,1.0,0.80,1.0)
	_refresh_visual_tween = create_tween()
	_refresh_visual_tween.tween_property(
		item,
		"self_modulate",
		Color.WHITE,
		maxf(refresh_visual_duration,0.05)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
