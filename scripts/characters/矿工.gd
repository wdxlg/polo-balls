extends ball

const STONE_SCENE:PackedScene = preload("res://scenes/terrain/矿工小石头.tscn")
const MINER_ATTACK_SFX:AudioStream = preload("res://audio/characters/矿工/攻击.mp3")
const MINER_IMPACT_LAYER_SFX:AudioStream = preload("res://audio/characters/矿工/重击叠加.mp3")
const MINER_SWING_SFX:AudioStream = preload("res://audio/characters/矿工/挥舞.mp3")

# ============================================================
# 矿工
# - 攻击冷却完成时保持正常状态，不会空挥。
# - 敌人进入原版锤击范围后才蓄力；起手只读取一次敌人方向。
# - 攻击范围半径由 hammer_attack_radius 控制；额外用 hammer_base_offset 控制攻击圈与角色之间的基础偏移。
# - 蓄力期间矿工移动时，提示圈与实际伤害点一起平移，和矿工的相对位置始终不变。
# - 攻击结束后进入疲劳状态，使用休息立绘并减速；疲劳结束恢复正常状态。
# - 每次锤击会从攻击位置抛出若干小石头，石头落地后才成为地形。
# ============================================================

@export_category("矿工 - 外观")
@export var normal_texture:Texture2D
@export var windup_texture:Texture2D
@export var attack_texture:Texture2D
@export var rest_texture:Texture2D

@export_category("矿工 - 锤击")
# 实际攻击圆半径（世界坐标/像素尺度）。
# 攻击中心距离角色中心 = hammer_base_offset + hammer_attack_radius。
# 默认 R=20、基础偏移=10，因此攻击中心前移 30；圆本身的可见/伤害半径仍然严格是 20。
@export_range(4.0,220.0,1.0) var hammer_attack_radius:float = 20.0
@export_range(0.0,160.0,1.0) var hammer_base_offset:float = 10.0
@export_range(0.05,2.0,0.05) var hammer_windup:float = 0.82
@export_range(0.0,1.5,0.01) var windup_move_speed_multiplier:float = 0.05
# 蓄力结束后先切攻击图、保持警告圈、播放挥舞声；经过此时间才真正造成伤害。
@export_range(0.02,0.5,0.01) var attack_hit_delay:float = 0.10
# 真正造成伤害后，攻击立绘继续保持的时间。
@export_range(0.05,1.5,0.01) var attack_pose_hold:float = 0.45
@export_range(0.1,12.0,0.05) var hammer_damage_multiplier:float = 6.50
@export_range(0.05,1.0,0.05) var hammer_edge_damage_ratio:float = 0.35
@export_range(0.0,300.0,5.0) var hammer_knockback_distance:float = 62.0
@export_range(50.0,1800.0,10.0) var hammer_knockback_speed:float = 620.0

@export_category("矿工 - 疲劳")
@export_range(0.05,1.0,0.01) var fatigue_speed_multiplier:float = 0.45
# 0 = 自动持续到本次 Attack_Cooling 基本结束；这样攻击重新可用时一定回到正常状态。
@export_range(0.0,10.0,0.05) var fatigue_duration:float = 0.0

@export_category("矿工 - 小石头")
@export_range(1,8,1) var stone_min_count:int = 2
@export_range(1,10,1) var stone_max_count:int = 3
@export_range(4.0,120.0,1.0) var stone_land_min_radius:float = 28.0
@export_range(4.0,180.0,1.0) var stone_land_max_radius:float = 76.0
@export_range(0.5,1.5,0.02) var stone_min_scale:float = 0.82
@export_range(0.5,1.5,0.02) var stone_max_scale:float = 1.12
@export_range(0.08,1.2,0.01) var stone_throw_duration:float = 0.34
@export_range(0.0,120.0,1.0) var stone_arc_height:float = 34.0
@export_range(0.0,120.0,1.0) var stone_lifetime:float = 24.0
@export_range(0.0,80.0,1.0) var stone_map_margin:float = 14.0

const VISUAL_NORMAL:int = 0
const VISUAL_WINDUP:int = 1
const VISUAL_ATTACK:int = 2
const VISUAL_REST:int = 3

var _hammer_winding_up:bool = false
var _hammer_strike_hold:bool = false
var _attack_serial:int = 0
var _fatigue_left:float = 0.0
var _visual_state:int = -1
var _default_texture:Texture2D = null
var _locked_attack_direction:Vector2 = Vector2.RIGHT
var _locked_attack_offset:Vector2 = Vector2.ZERO
var _locked_attack_center:Vector2 = Vector2.ZERO
var _hammer_threat_impact_msec:int = -1


func _ready() -> void:
	super._ready()
	_auto_load_textures()
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_set_visual_state_local(VISUAL_NORMAL)


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _try_load_texture("res://Images/characters/人物/矿工/矿工_正常.png")
	if windup_texture == null:
		# 兼容两种项目状态：若之前已经把旧攻击图改名为“蓄力”，优先用它；
		# 否则直接把项目现有的“矿工_攻击.png”作为蓄力图，不覆盖/移动旧资源。
		windup_texture = _try_load_texture("res://Images/characters/人物/矿工/矿工_蓄力.png")
		if windup_texture == null:
			windup_texture = _try_load_texture("res://Images/characters/人物/矿工/矿工_攻击.png")
	if attack_texture == null:
		attack_texture = _try_load_texture("res://Images/characters/人物/矿工/矿工_落锤.png")
	if rest_texture == null:
		rest_texture = _try_load_texture("res://Images/characters/人物/矿工/矿工_休息.png")


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func get_next_state(state:State) -> int:
	# 基类默认“冷却一到就攻击”。矿工要保持待机就绪，直到附近真的有敌人才挥锤。
	# 临时关掉 Can_Attack 让父类照常处理 Move/Hurt/Die，再恢复攻击计时，避免空挥消耗冷却。
	if (
		is_multiplayer_authority()
		and Can_Attack
		and not is_damage_output_disabled()
		and state_machine.last_state_dis.Attack >= Attack_Cooling
		and _find_attack_target() == null
	):
		var saved_attack_timer:float = float(state_machine.last_state_dis.Attack)
		Can_Attack = false
		var next_state:int = super.get_next_state(state)
		Can_Attack = true
		state_machine.last_state_dis.Attack = saved_attack_timer
		return next_state

	return super.get_next_state(state)


func Attack() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled():
		Attacking = false
		return
	# 二次确认：找一个当前确实位于原版锤击几何范围里的敌人。
	# 这里只用它决定起手方向，之后不再读取敌人的位置。
	var attack_target:ball = _find_attack_target()
	if attack_target == null and not has_player_control_aim():
		Attacking = false
		return

	Attacking = true
	_hammer_winding_up = true
	_fatigue_left = 0.0
	if has_player_control_aim():
		_locked_attack_direction = player_control_aim_direction(_current_attack_direction())
	else:
		var to_target:Vector2 = attack_target.global_position - global_position
		_locked_attack_direction = to_target.normalized() if to_target.length_squared() > 0.000001 else _current_attack_direction()
	# 这里只锁“方向”，绝不锁敌人的位置。
	# 落锤点始终是：矿工当前位置 + 起手方向 * (基础偏移 + 攻击半径)。
	# 用本地偏移保存后，蓄力期间矿工移动会带着提示圈/伤害点一起移动，
	# 但这个偏移向量本身不会再改变，也不会继续追踪敌人。
	# 默认基础偏移=10、R=20，因此圆心距离角色中心固定为 30。
	var locked_world_center:Vector2 = global_position + _locked_attack_direction * _attack_center_distance()
	_locked_attack_offset = to_local(locked_world_center)
	_locked_attack_center = _current_locked_attack_center()
	_hammer_threat_impact_msec = Time.get_ticks_msec() + int(round((maxf(hammer_windup,0.05) + maxf(attack_hit_delay,0.0)) * 1000.0))
	_attack_serial += 1
	var token:int = _attack_serial
	# 蓄力开始：使用原来的“攻击”立绘作为蓄力图；若项目里已有 矿工_蓄力.png 则优先使用。
	_broadcast_visual_state(VISUAL_WINDUP)
	_show_windup_everywhere(_locked_attack_offset,_attack_radius())

	await get_tree().create_timer(maxf(hammer_windup/preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self),0.05)).timeout
	if not is_instance_valid(self) or token != _attack_serial or health <= 0:
		_hammer_threat_impact_msec = -1
		return
	if is_damage_output_disabled():
		_hammer_winding_up = false
		_hammer_strike_hold = false
		_hammer_threat_impact_msec = -1
		Attacking = false
		_clear_hammer_warning_everywhere()
		_broadcast_visual_state(VISUAL_NORMAL)
		return

	# 蓄力结束：先进入攻击姿势，但暂时不造成伤害。
	# 此时最终警告圈保持原样不动，播放挥舞声；0.1 秒后才真正落锤。
	_hammer_winding_up = false
	_hammer_strike_hold = true
	_broadcast_visual_state(VISUAL_ATTACK)
	_play_miner_sfx_everywhere(2,global_position,-5.0,randf_range(0.98,1.02),760.0)

	await get_tree().create_timer(maxf(attack_hit_delay,0.0)).timeout
	if not is_instance_valid(self) or token != _attack_serial or health <= 0:
		return
	if is_damage_output_disabled():
		_hammer_strike_hold = false
		_hammer_threat_impact_msec = -1
		Attacking = false
		_clear_hammer_warning_everywhere()
		_broadcast_visual_state(VISUAL_NORMAL)
		return

	# 命中帧：先清掉提示圈，再造成伤害、播放攻击双音效并生成石头。
	_clear_hammer_warning_everywhere()
	_hammer_strike_hold = false
	_hammer_threat_impact_msec = -1
	_hammer_impact()
	_start_fatigue()
	Attacking = false
	_hold_attack_pose_then_rest(token)


func tick_physics(state:State,delta:float) -> void:
	if (_hammer_winding_up or _hammer_strike_hold) and is_multiplayer_authority():
		# 蓄力以及“攻击图 + 挥舞声”的 0.1 秒预击阶段都只保留极少移动。
		# 这段移动只会平移整个攻击圈；圆心与矿工之间的相对偏移保持不变。
		# 攻击偏移在起手时锁定，提示圈只跟随人物平移，不会追踪目标。
		var original_speed:float = Speed
		Speed = original_speed * clampf(windup_move_speed_multiplier,0.0,1.5)
		super.tick_physics(state,delta)
		Speed = original_speed
		_locked_attack_center = _current_locked_attack_center()
		return

	if _fatigue_left > 0.0:
		_fatigue_left = maxf(_fatigue_left - delta,0.0)
		var original_speed:float = Speed
		Speed = original_speed * clampf(fatigue_speed_multiplier,0.05,1.0)
		super.tick_physics(state,delta)
		Speed = original_speed
		if _fatigue_left <= 0.0 and is_multiplayer_authority():
			_broadcast_visual_state(VISUAL_NORMAL)
		return

	super.tick_physics(state,delta)


# 高级 AI 可选接口：矿工真正危险的是“前方锁定落锤点”，不是矿工身体周围。
func get_ai_attack_threats(receiver:ball) -> Array:
	var result:Array = []
	if not (_hammer_winding_up or _hammer_strike_hold) or receiver == null or not is_instance_valid(receiver):
		return result
	if not _is_valid_enemy(receiver):
		return result
	var now_msec:int = Time.get_ticks_msec()
	var impact_msec:int = _hammer_threat_impact_msec
	if impact_msec < 0:
		impact_msec = now_msec + int(round(maxf(hammer_windup,0.05) * 1000.0))
	var threat_center:Vector2 = _current_locked_attack_center()
	result.append({
		"shape":"circle",
		"position":threat_center,
		"velocity":velocity,
		"radius":_attack_radius(),
		"danger_in":maxf(float(impact_msec - now_msec) / 1000.0,0.0),
		"danger_duration":0.12,
		"kind":"miner_hammer",
		"damage":attack_damage(hammer_damage_multiplier),
		"source":self,
	})
	return result


func _start_fatigue() -> void:
	var duration:float = fatigue_duration
	if duration <= 0.0:
		# 攻击冷却从进入 Attack 状态时已经开始计时，所以扣掉前摇时间。
		duration = maxf(Attack_Cooling - hammer_windup - attack_hit_delay,0.15)
	_fatigue_left = duration


func _hold_attack_pose_then_rest(token:int) -> void:
	await get_tree().create_timer(maxf(attack_pose_hold,0.05)).timeout
	if not is_instance_valid(self) or token != _attack_serial or health <= 0:
		return
	if _fatigue_left > 0.0:
		_broadcast_visual_state(VISUAL_REST)
	else:
		_broadcast_visual_state(VISUAL_NORMAL)


func _hammer_impact() -> void:
	# 最终伤害点使用此刻人物位置 + 开始蓄力时锁定的相对偏移。
	# 因而矿工蓄力移动时，提示圈和伤害范围完全一起移动。
	var impact_center:Vector2 = _current_locked_attack_center()
	_locked_attack_center = impact_center
	# 落锤瞬间同时播放原来的攻击声和新的重击层。两个独立 AudioStreamPlayer2D
	# 会真正同时播放，不会互相截断。
	_play_miner_sfx_everywhere(0,impact_center,-1.0,randf_range(0.98,1.02),820.0)
	_play_miner_sfx_everywhere(1,impact_center,-4.0,randf_range(0.98,1.02),820.0)
	# 伤害按目标到落锤中心的距离线性衰减：
	# 中心 = 100% 高伤害；攻击圈边缘 = hammer_edge_damage_ratio。
	# 这样真正站在锤心的人吃满伤，擦到外圈的人仍然会受伤但明显更低。
	var max_damage_amount:float = attack_damage(hammer_damage_multiplier)
	var safe_radius:float = _attack_radius()
	var edge_ratio:float = clampf(hammer_edge_damage_ratio,0.0,1.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue
		var distance_from_center:float = impact_center.distance_to(target.global_position)
		if distance_from_center > safe_radius:
			continue
		var distance_ratio:float = clampf(distance_from_center / safe_radius,0.0,1.0)
		var damage_ratio:float = lerpf(1.0,edge_ratio,distance_ratio)
		var target_damage:float = max_damage_amount * damage_ratio
		if target_damage > 0.0:
			target.receive_spatial_damage(
				target_damage,
				{"shape":"circle","center":impact_center,"radius":safe_radius,"source":self},
				false
			)
		var push:Vector2 = target.global_position - impact_center
		if push.length_squared() <= 0.000001:
			push = _locked_attack_direction
		target.apply_knockback(
			push.normalized(),
			hammer_knockback_distance,
			hammer_knockback_speed,
			0.28,
			0.0,
			{"source":self,"max_wall_bounces":1,"stop_on_character":true}
		)

	_spawn_random_stones(impact_center)


func _spawn_random_stones(impact_center:Vector2) -> void:
	var low:int = mini(stone_min_count,stone_max_count)
	var high:int = maxi(stone_min_count,stone_max_count)
	var count:int = randi_range(maxi(low,1),maxi(high,1))
	var min_radius:float = minf(stone_land_min_radius,stone_land_max_radius)
	var max_radius:float = maxf(stone_land_min_radius,stone_land_max_radius)

	for i:int in range(count):
		var stone:StaticBody2D = STONE_SCENE.instantiate() as StaticBody2D
		if stone == null:
			continue

		var angle:float = randf_range(0.0,TAU)
		var landing_distance:float = randf_range(min_radius,max_radius)
		var chosen_scale:float = randf_range(minf(stone_min_scale,stone_max_scale),maxf(stone_min_scale,stone_max_scale))
		var landing_position:Vector2 = impact_center + Vector2.RIGHT.rotated(angle) * landing_distance
		var start_position:Vector2 = impact_center + Vector2.RIGHT.rotated(randf_range(0.0,TAU)) * randf_range(0.0,7.0)
		# 石头碰撞半径约 8px；按缩放再加安全边距，保证整个石头留在地图内部。
		var safe_margin:float = maxf(stone_map_margin,10.0 * chosen_scale)
		landing_position = _clamp_point_to_map(landing_position,safe_margin)
		start_position = _clamp_point_to_map(start_position,4.0)

		stone.global_position = start_position
		stone.scale = Vector2.ONE * chosen_scale
		stone.set("Master_name",name)
		stone.set("lifetime",stone_lifetime)
		stone.set("spawn_collision_delay",stone_throw_duration)
		stone.name = Game.return_random_name(stone)
		get_tree().current_scene.add_child(stone,true)

		# 只让矿工本人忽略自己的石头；其他角色会把落地石头当成真实地形。
		preload("res://classes/body_collision_exclusions.gd").add_exception(self,stone)
		preload("res://classes/body_collision_exclusions.gd").add_exception(stone,self)

		if stone.has_method("launch"):
			stone.call("launch",start_position,landing_position,stone_throw_duration,stone_arc_height)
		else:
			stone.global_position = landing_position


func _get_map_rect() -> Rect2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	if not world.map_group.has(str(world.now_choose_map)):
		return Rect2()
	var map_node = world.map_group[str(world.now_choose_map)]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.return_map_world_rect(map_node)


func _clamp_point_to_map(point:Vector2,margin_value:float) -> Vector2:
	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return point
	var margin:float = maxf(margin_value,0.0)
	var min_x:float = rect.position.x + margin
	var max_x:float = rect.end.x - margin
	var min_y:float = rect.position.y + margin
	var max_y:float = rect.end.y - margin
	if min_x > max_x:
		min_x = (rect.position.x + rect.end.x) * 0.5
		max_x = min_x
	if min_y > max_y:
		min_y = (rect.position.y + rect.end.y) * 0.5
		max_y = min_y
	return Vector2(clampf(point.x,min_x,max_x),clampf(point.y,min_y,max_y))


func _play_miner_sfx_everywhere(kind:int,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_miner_sfx.rpc(kind,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_miner_sfx(kind,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_miner_sfx(kind:int,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	var stream:AudioStream = null
	match kind:
		0:
			stream = MINER_ATTACK_SFX
		1:
			stream = MINER_IMPACT_LAYER_SFX
		2:
			stream = MINER_SWING_SFX
		_:
			return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MinerSFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.attenuation = 1.0
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free)
	player.play()


func _find_attack_target() -> ball:
	# 索敌几何：对每个敌人先求“矿工 -> 敌人”的方向，再把攻击圆心放在
	# 该方向前方 (基础偏移 + R) 的位置，攻击圆本身半径仍然是 R。
	# 默认 R=20、基础偏移=10：圆心前移 30，可覆盖沿该方向距离角色 10~50 的敌人。
	# 敌人静止时不会因为矿工随机移动方向而漏判。
	var best_target:ball = null
	var best_score:float = INF
	var radius:float = _attack_radius()
	var center_distance:float = _attack_center_distance()
	var max_reach:float = center_distance + radius

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue

		var to_target:Vector2 = target.global_position - global_position
		var target_distance:float = to_target.length()
		if target_distance <= 0.000001 or target_distance > max_reach:
			continue

		var attack_dir:Vector2 = to_target / target_distance
		var candidate_center:Vector2 = global_position + attack_dir * center_distance
		var miss_distance:float = candidate_center.distance_to(target.global_position)
		if miss_distance > radius:
			continue

		# 优先选最靠近未来落锤中心的敌人；相同时选离矿工更近的。
		var score:float = miss_distance * 10000.0 + target_distance
		if score < best_score:
			best_score = score
			best_target = target

	return best_target


func _attack_radius() -> float:
	# 这是世界坐标半径：伤害判定、AI 威胁半径、提示圈可见半径全部读取同一个值。
	return maxf(hammer_attack_radius,4.0)


func _attack_center_distance() -> float:
	# 攻击中心与角色中心的固定距离 = 基础偏移 + 半径。
	return maxf(hammer_base_offset,0.0) + _attack_radius()


func _current_attack_direction() -> Vector2:
	# 普通方向查询不保存/追踪任何敌人引用。真正攻击起手方向只在 Attack() 开头计算一次。
	if direction.length_squared() > 0.000001:
		return direction.normalized()
	var nearest:ball = _find_attack_target()
	if nearest != null:
		var to_enemy:Vector2 = nearest.global_position - global_position
		if to_enemy.length_squared() > 0.000001:
			return to_enemy.normalized()
	return Vector2.RIGHT


func _attack_center_from_direction(attack_dir:Vector2) -> Vector2:
	var dir:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
	return global_position + dir * _attack_center_distance()


func _current_locked_attack_center() -> Vector2:
	# _locked_attack_offset 在蓄力开始时只写一次。
	# 它是相对矿工的固定局部偏移，所以矿工平移时落锤中心会同步平移，
	# 但不会根据敌人的后续位置重新计算。
	return to_global(_locked_attack_offset)


func _has_enemy_in_attack_range() -> bool:
	return _find_attack_target() != null


func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if not target.is_combat_targetable():
		return false
	if Team != "" and target.Team == Team:
		return false
	return true


func _broadcast_visual_state(state_value:int) -> void:
	if _visual_state == state_value:
		return
	_visual_state = state_value
	if multiplayer.has_multiplayer_peer():
		_rpc_set_visual_state.rpc(state_value)
	else:
		_rpc_set_visual_state(state_value)


@rpc("authority","call_local","reliable")
func _rpc_set_visual_state(state_value:int) -> void:
	_set_visual_state_local(state_value)


func _set_visual_state_local(state_value:int) -> void:
	if not (image is Sprite2D):
		return
	var fallback_normal:Texture2D = normal_texture if normal_texture != null else _default_texture
	var wanted:Texture2D = fallback_normal
	match state_value:
		VISUAL_WINDUP:
			wanted = windup_texture if windup_texture != null else fallback_normal
		VISUAL_ATTACK:
			wanted = attack_texture if attack_texture != null else (windup_texture if windup_texture != null else fallback_normal)
		VISUAL_REST:
			wanted = rest_texture if rest_texture != null else fallback_normal
		_:
			wanted = fallback_normal
	if wanted != null:
		(image as Sprite2D).texture = wanted
		_refit_visual_only()


func _refit_visual_only() -> void:
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _show_windup_everywhere(local_offset:Vector2,radius:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_hammer_warning.rpc(local_offset,radius,maxf(hammer_windup,0.05))
	else:
		_rpc_show_hammer_warning(local_offset,radius,maxf(hammer_windup,0.05))


@rpc("authority","call_local","reliable")
func _rpc_show_hammer_warning(local_offset:Vector2,radius:float,duration:float) -> void:
	# 提示圈由两层组成：
	# 1) 最外层白色细描边始终停在真实攻击半径上，用来持续标出危险范围边界；
	# 2) 内层倒计时圈从外边界直接缩到中心，同时由白变红、由细变粗。
	# 内层起始透明度固定为 50%。两层都是矿工子节点，所以矿工蓄力移动时会一起移动，
	# 而 local_offset 始终不变，不会继续追踪敌人。
	var final_radius:float = maxf(radius,4.0)
	var base_points := _make_warning_circle_points(final_radius)

	var outer_ring := Line2D.new()
	outer_ring.name = "MinerHammerWarningOuter"
	outer_ring.closed = true
	outer_ring.width = 0.85
	outer_ring.default_color = Color(1.0,1.0,1.0,0.82)
	outer_ring.antialiased = true
	outer_ring.z_index = 31
	outer_ring.points = base_points
	outer_ring.position = local_offset
	add_child(outer_ring)
	# ball.tscn 的角色根节点本身是缩放的（当前为 0.2）。
	# 提示圈虽然需要作为角色子节点跟随移动，但它的可见半径必须使用世界坐标尺寸，
	# 所以取消继承到 Line2D 上的全局缩放。这样“画出来的半径”才和伤害判定半径完全一致。
	outer_ring.global_scale = Vector2.ONE

	var countdown_ring := Line2D.new()
	countdown_ring.name = "MinerHammerWarningCountdown"
	countdown_ring.closed = true
	countdown_ring.width = 0.85
	countdown_ring.default_color = Color(1.0,1.0,1.0,0.50)
	countdown_ring.antialiased = true
	countdown_ring.z_index = 32
	countdown_ring.points = base_points
	countdown_ring.position = local_offset
	add_child(countdown_ring)
	countdown_ring.global_scale = Vector2.ONE

	var tween:Tween = countdown_ring.create_tween()
	tween.set_parallel(true)
	# 直接把圆的点半径收敛到 0，而不是缩放整个 Node2D；这样线宽仍可真正逐渐加粗。
	tween.tween_method(_set_warning_ring_radius_factor.bind(countdown_ring,final_radius),1.0,0.0,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(countdown_ring,"width",5.2,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(countdown_ring,"default_color",Color(1.0,0.04,0.04,0.98),duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 蓄力完成后不自动删除。最终形态会保持 attack_hit_delay（默认 0.1 秒），
	# 直到真正命中帧由权威端统一清除。


func _clear_hammer_warning_everywhere() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_clear_hammer_warning.rpc()
	else:
		_rpc_clear_hammer_warning()


@rpc("authority","call_local","reliable")
func _rpc_clear_hammer_warning() -> void:
	for child:Node in get_children():
		if child.name == "MinerHammerWarningOuter" or child.name == "MinerHammerWarningCountdown":
			if child is CanvasItem:
				(child as CanvasItem).visible = false
			child.queue_free()


func _make_warning_circle_points(radius:float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i:int in range(64):
		var a:float = TAU * float(i) / 64.0
		points.append(Vector2(cos(a),sin(a)) * radius)
	return points


func _set_warning_ring_radius_factor(factor:float,ring:Line2D,base_radius:float) -> void:
	if ring == null or not is_instance_valid(ring):
		return
	ring.points = _make_warning_circle_points(maxf(base_radius,0.0) * clampf(factor,0.0,1.0))


func _free_hammer_warning_rings(countdown_ring:Line2D,outer_ring:Line2D) -> void:
	if countdown_ring != null and is_instance_valid(countdown_ring):
		countdown_ring.queue_free()
	if outer_ring != null and is_instance_valid(outer_ring):
		outer_ring.queue_free()


func Die() -> void:
	_attack_serial += 1
	_hammer_winding_up = false
	_hammer_strike_hold = false
	_clear_hammer_warning_everywhere()
	_locked_attack_offset = Vector2.ZERO
	_hammer_threat_impact_msec = -1
	_fatigue_left = 0.0
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
