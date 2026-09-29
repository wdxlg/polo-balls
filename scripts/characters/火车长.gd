extends ball

# =============================================================================
# 火车长
# - 自己不直接攻击；Damage 是列车撞击的整体基础攻击力。
# - 战斗开始立刻有一列火车横穿战场。
# - 列车完全离开“当前地图真实 world rect”后，在地图下方排队：车头在左，车厢/车尾在右。
# - 地图边缘生成可循环开采的煤矿。火车长只有真实碰到煤矿时才：举镐前摇 -> 挖矿 -> 煤块抛物线飞回。
# - 火车长平时完全使用 ball 的正常移动逻辑；持煤也不会自动寻路。只有碰到停靠列车的加煤区才加煤。
# - 定时发车，煤越多车厢越多/发车越快；V123 起 30 秒基础等待，每煤缩短 4 秒。
# =============================================================================

const TRAIN_SCENE:PackedScene = preload("res://scenes/creatures/火车长_列车.tscn")
const MINE_SCENE:PackedScene = preload("res://scenes/terrain/火车长_煤矿.tscn")
const TRAIN_HIT_BURST_EFFECT_SCRIPT = preload("res://scripts/effects/hit_burst_effect.gd")

const NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/01_蒸汽火车司机_正常.png")
const PICKAXE_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/02_蒸汽火车司机_手持矿镐.png")
const MINING_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/03_蒸汽火车司机_挖矿.png")
const REFUEL_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/04_蒸汽火车司机_加煤.png")
const COAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/09_单独煤块.png")
const MINING_AUDIO:AudioStream = preload("res://audio/characters/火车长/挖矿_[cut_0sec] (1).mp3")
const REFUEL_AUDIO:AudioStream = preload("res://audio/characters/火车长/加煤.mp3")

@export_group("煤矿")
@export_range(3,12,1) var mine_count:int = 5
# V123：矿心只向墙外嵌约 8px；配合 0.90~1.10 随机缩放时，必须保证不会只漏一丁点。
@export_range(2.0,32.0,1.0,"or_greater") var mine_edge_inset:float = 8.0
# V120 兼容旧保存值：不再用于自动接近/触发；真实触发只看煤矿 Area2D.body_entered。
@export_range(12.0,100.0,1.0,"or_greater") var mine_reach_distance:float = 48.0
@export_range(0.05,2.0,0.01,"or_greater") var mining_windup:float = 0.22
@export_range(0.05,1.0,0.01,"or_greater") var mining_hit_hold:float = 0.16
@export_range(1,8,1) var mining_strikes_min:int = 2
@export_range(1,12,1) var mining_strikes_max:int = 4
@export_range(0.02,0.80,0.01,"or_greater") var mining_repeat_pause_min:float = 0.08
@export_range(0.02,1.20,0.01,"or_greater") var mining_repeat_pause_max:float = 0.20
@export_range(0.05,1.0,0.01) var mining_move_speed_multiplier:float = 0.28
@export_range(1,10,1) var max_held_coal:int = 5
@export_range(0.10,1.5,0.01,"or_greater") var coal_fly_time:float = 0.46
@export_range(4.0,120.0,1.0,"or_greater") var coal_arc_height:float = 38.0
@export_range(10.0,80.0,1.0,"or_greater") var coal_visual_size:float = 26.0

@export_group("挖矿受击式白线")
# V125：白线必须像人物受击一样，从矿点沿“火车长 -> 煤矿”的真实落镐方向继续射出，
# 只在该主轴附近做小角度随机扩散，禁止再做 360° 放射圈。
@export_range(3,18,1) var mining_white_line_count:int = 8
@export_range(4.0,68.0,1.0,"or_greater") var mining_white_line_spread_degrees:float = 22.0
@export_range(8.0,100.0,1.0,"or_greater") var mining_white_line_distance_min:float = 40.0
@export_range(12.0,140.0,1.0,"or_greater") var mining_white_line_distance_max:float = 68.0
@export_range(0.25,2.5,0.05,"or_greater") var mining_white_line_width_min:float = 0.55
@export_range(0.3,3.0,0.05,"or_greater") var mining_white_line_width_max:float = 0.95
@export_range(0.08,0.6,0.01,"or_greater") var mining_white_line_duration:float = 0.26

@export_group("挖矿震波")
@export_range(12.0,120.0,1.0,"or_greater") var mining_shockwave_radius:float = 46.0
@export_range(0.05,1.0,0.01,"or_greater") var mining_shockwave_damage_multiplier:float = 0.65
@export_range(0.0,80.0,1.0,"or_greater") var mining_shockwave_knockback_distance:float = 18.0
@export_range(20.0,600.0,5.0,"or_greater") var mining_shockwave_knockback_speed:float = 165.0
@export_range(0.10,1.0,0.01,"or_greater") var mining_shockwave_visual_time:float = 0.34
@export_range(0.05,0.95,0.01) var mining_shockwave_start_scale:float = 0.24
@export_range(0.5,6.0,0.1,"or_greater") var mining_shockwave_line_width:float = 1.5

@export_group("动作音效")
@export_range(-30.0,18.0,0.5,"or_greater") var mining_audio_volume_db:float = 3.0
@export_range(-30.0,18.0,0.5,"or_greater") var refuel_audio_volume_db:float = 5.0
@export_range(200.0,3000.0,50.0,"or_greater") var action_audio_max_distance:float = 1400.0

@export_group("加煤")
# V120 兼容旧保存值：不再用于自动接近/触发；真实触发只看列车 RefuelArea 重叠。
@export_range(10.0,90.0,1.0,"or_greater") var refuel_reach_distance:float = 28.0
@export_range(0.05,3.0,0.05,"or_greater") var refuel_duration:float = 0.58
@export_range(0.10,1.2,0.01,"or_greater") var refuel_coal_fly_time:float = 0.34
@export_range(6.0,120.0,1.0,"or_greater") var refuel_coal_arc_height:float = 44.0
@export_range(10.0,80.0,1.0,"or_greater") var refuel_coal_visual_size:float = 28.0

var _world_map_rect:Rect2 = Rect2()
var _train:Node = null
var _mechanics_ready:bool = false
var _initial_train_started:bool = false
var _action_busy:bool = false
var _mining_active:bool = false
var _refueling_active:bool = false
var _held_coal:int = 0
var _current_mine:Node = null
var _action_serial:int = 0


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	super._ready()
	_set_character_texture(NORMAL_TEXTURE)
	call_deferred("_try_prepare_mechanics")


func is_train_conductor() -> bool:
	return true


func controlled_attack_action() -> void:
	# 列车不是 ball；点击火车长发令，保留开局首趟和停靠后的煤量缩短冷却。
	if not is_player_controlled() or not is_multiplayer_authority():
		return
	if _train == null or not is_instance_valid(_train) or not is_combat_runtime_active():
		return
	if not _train.call("can_request_manual_launch"):
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_launch_waiting_train.rpc()
	else:
		_rpc_launch_waiting_train()


func tick_physics(state:State,delta:float) -> void:
	if state == State.Die or health <= 0:
		direction = Vector2.ZERO
		super.tick_physics(State.Die,delta)
		return

	if not _mechanics_ready:
		_try_prepare_mechanics()
		super.tick_physics(state,delta)
		return

	if is_multiplayer_authority() and is_combat_runtime_active() and not _initial_train_started:
		_initial_train_started = true
		_broadcast_start_initial_train()

	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return

	if not is_combat_runtime_active() or not Game.Game_Settings.Ball_Can_Move:
		direction = Vector2.ZERO
		super.tick_physics(State.Stand,delta)
		return

	# V123：挖矿不是定身。进入矿区后仍保留 ball 原本 direction/状态机，只在 move() 中降低实际移动速度。
	# 只要人物走出煤矿 Area，矿会通过 body_exited 立刻取消挖矿；加煤仍然短暂原地动作。
	if _refueling_active:
		direction = Vector2.ZERO
		super.tick_physics(State.Stand,delta)
		return

	super.tick_physics(state,delta)


func move(speed:float,delta:float):
	var effective_speed:float = speed
	if _mining_active:
		effective_speed *= clampf(mining_move_speed_multiplier,0.0,1.0)
	super.move(effective_speed,delta)


func notify_coal_mine_contact(mine:Node) -> void:
	if not is_multiplayer_authority() or _refueling_active:
		return
	if _mining_active:
		return
	if _held_coal >= maxi(max_held_coal,1):
		return
	if mine == null or not is_instance_valid(mine):
		return
	if not mine.has_method("claim_mine") or not bool(mine.call("claim_mine",self)):
		return
	_begin_mining(mine)


func notify_coal_mine_exit(mine:Node) -> void:
	# 离开真实煤矿交互 Area 就立即停止挖矿。煤矿本身永久存在，之后重新进入同一个矿还能继续挖。
	if not is_multiplayer_authority() or not _mining_active:
		return
	if mine == null or mine != _current_mine:
		return
	_cancel_mining()


func notify_train_refuel_contact(train:Node) -> void:
	# 加煤仍只由停靠列车真实 RefuelArea 的重叠触发。
	if not is_multiplayer_authority() or _action_busy or _held_coal <= 0:
		return
	if train == null or not is_instance_valid(train) or train != _train:
		return
	if not train.has_method("is_waiting_for_coal") or not bool(train.call("is_waiting_for_coal")):
		return
	_begin_refuel()


func _try_prepare_mechanics() -> void:
	if _mechanics_ready or not is_inside_tree():
		return
	_world_map_rect = _resolve_current_map_rect()
	if _world_map_rect.size.x <= 1.0 or _world_map_rect.size.y <= 1.0:
		return

	# 每个火车长都有自己的列车；煤矿则是场上共享的一组，默认只放 5 个，避免边缘被矿体铺满。
	var train_instance:Node = TRAIN_SCENE.instantiate()
	if train_instance != null:
		train_instance.name = "火车长_列车_%d" % get_instance_id()
		get_tree().current_scene.add_child(train_instance,true)
		train_instance.call("setup",self,_world_map_rect)
		_train = train_instance

	if get_tree().get_nodes_in_group("TrainConductorMine").is_empty():
		_spawn_edge_mines()
	_mechanics_ready = _train != null


func _resolve_current_map_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var group_variant:Variant = world.get("map_group")
	var map_name:String = str(world.get("now_choose_map"))
	if not group_variant is Dictionary:
		return Rect2()
	var map_group:Dictionary = group_variant as Dictionary
	if not map_group.has(map_name) or not map_group[map_name] is TileMapLayer:
		return Rect2()
	var rect_variant:Variant = world.call("return_map_world_rect",map_group[map_name])
	if rect_variant is Rect2:
		return rect_variant
	return Rect2()


func _spawn_edge_mines() -> void:
	var points:Array[Vector2] = _build_edge_mine_positions(maxi(mine_count,4))
	for index:int in range(points.size()):
		var mine:Node2D = MINE_SCENE.instantiate() as Node2D
		if mine == null:
			continue
		mine.name = "火车长_煤矿_%02d" % index
		get_tree().current_scene.add_child(mine,true)
		mine.global_position = points[index]
		if mine.has_method("apply_visual_variation"):
			mine.call("apply_visual_variation",index + 1)


func _build_edge_mine_positions(count:int) -> Array[Vector2]:
	var result:Array[Vector2] = []
	var rect:Rect2 = _world_map_rect
	# V118：矿不是摆在“墙内的可玩区域”，而是把矿心推到地图边界外侧。
	# Sprite 仍位于 MapOutsideVisualMask 下方，因此外侧的大部分会被墙外遮罩压住，
	# 只让一小部分从黑色地图边线内侧露出来，看起来像真正嵌在墙里。
	var embed_depth:float = maxf(mine_edge_inset,2.0)
	var left:float = rect.position.x - embed_depth
	var right:float = rect.end.x + embed_depth
	var top:float = rect.position.y - embed_depth
	var bottom:float = rect.end.y + embed_depth
	var perimeter_slots:int = maxi(count,4)

	for index:int in range(perimeter_slots):
		var t:float = (float(index) + 0.5) / float(perimeter_slots)
		var perimeter_pos:float = t * 4.0
		var side:int = clampi(int(floor(perimeter_pos)),0,3)
		var side_t:float = perimeter_pos - float(side)
		var point:Vector2
		match side:
			0:
				point = Vector2(lerpf(left,right,side_t),top)
			1:
				point = Vector2(right,lerpf(top,bottom,side_t))
			2:
				point = Vector2(lerpf(right,left,side_t),bottom)
			_:
				point = Vector2(left,lerpf(bottom,top,side_t))
		result.append(point)
	return result


func _begin_mining(mine:Node) -> void:
	_action_busy = true
	_mining_active = true
	_refueling_active = false
	_current_mine = mine
	_action_serial += 1
	var serial:int = _action_serial
	_broadcast_conductor_visual(1)
	_mining_sequence(mine,serial)


func _mining_sequence(mine:Node,serial:int) -> void:
	# 每次进入矿区随机连续挖 2~4 下；如果这一批结束后仍站在矿区、煤还没拿满，会继续下一批。
	# 人物始终以 mining_move_speed_multiplier 的低速保留正常移动；一旦走出 Area，body_exited 会让 serial 失效。
	while _action_still_valid(serial) and _mining_active:
		if mine == null or not is_instance_valid(mine):
			_cancel_mining()
			return
		if _held_coal >= maxi(max_held_coal,1):
			_finish_action(true)
			return
		if mine.has_method("is_body_overlapping") and not bool(mine.call("is_body_overlapping",self)):
			_cancel_mining()
			return

		var rng := RandomNumberGenerator.new()
		rng.seed = Game.battle_rng_seed_or("scripts/characters/火车长.gd:mining_batch",hash("TrainConductorMining|%d|%d|%d" % [get_instance_id(),serial,_held_coal]))
		var min_hits:int = maxi(1,mini(mining_strikes_min,mining_strikes_max))
		var max_hits:int = maxi(min_hits,maxi(mining_strikes_min,mining_strikes_max))
		var strike_count:int = rng.randi_range(min_hits,max_hits)

		for strike_index:int in range(strike_count):
			if not _action_still_valid(serial) or not _mining_active:
				return
			if mine == null or not is_instance_valid(mine):
				_cancel_mining()
				return
			if _held_coal >= maxi(max_held_coal,1):
				_finish_action(true)
				return
			if mine.has_method("is_body_overlapping") and not bool(mine.call("is_body_overlapping",self)):
				_cancel_mining()
				return

			_broadcast_conductor_visual(1)
			var ok:bool = await wait_for_combat_time(maxf(mining_windup,0.05))
			if not ok or not _action_still_valid(serial) or not _mining_active:
				return
			if mine.has_method("is_body_overlapping") and not bool(mine.call("is_body_overlapping",self)):
				_cancel_mining()
				return

			var mine_position:Vector2 = (mine as Node2D).global_position
			var feedback_seed:int = Game.battle_rng_seed_or("scripts/characters/火车长.gd:mining_feedback",hash("TrainConductorMiningFeedback|%d|%d|%d|%d" % [get_instance_id(),serial,_held_coal,strike_index]))
			_broadcast_conductor_visual(2)
			_broadcast_mining_feedback(mine,mine_position,feedback_seed)
			_apply_mining_shockwave_damage(mine_position)
			if mine.has_method("consume_mine"):
				mine.call("consume_mine",self)
			_held_coal = mini(_held_coal + 1,maxi(max_held_coal,1))

			ok = await wait_for_combat_time(maxf(mining_hit_hold,0.05))
			if not ok or not _action_still_valid(serial) or not _mining_active:
				return
			if _held_coal >= maxi(max_held_coal,1):
				_finish_action(true)
				return

			if strike_index < strike_count - 1:
				_broadcast_conductor_visual(1)
				var pause_min:float = minf(mining_repeat_pause_min,mining_repeat_pause_max)
				var pause_max:float = maxf(mining_repeat_pause_min,mining_repeat_pause_max)
				var pause_time:float = rng.randf_range(maxf(pause_min,0.02),maxf(pause_max,0.02))
				ok = await wait_for_combat_time(pause_time)
				if not ok or not _action_still_valid(serial) or not _mining_active:
					return

		_broadcast_conductor_visual(1)
		var batch_pause:float = maxf(mining_repeat_pause_min,0.03)
		var batch_ok:bool = await wait_for_combat_time(batch_pause)
		if not batch_ok or not _action_still_valid(serial) or not _mining_active:
			return


func _cancel_mining() -> void:
	if not _mining_active:
		return
	_action_serial += 1
	_finish_action(false)


func _begin_refuel() -> void:
	if _action_busy or _held_coal <= 0 or _train == null or not is_instance_valid(_train):
		return
	if not bool(_train.call("is_waiting_for_coal")):
		return
	_action_busy = true
	_mining_active = false
	_refueling_active = true
	_action_serial += 1
	var serial:int = _action_serial
	_broadcast_conductor_visual(3)
	_refuel_sequence(serial)


func _refuel_sequence(serial:int) -> void:
	# V124：加煤不再只等一段时间后数字 +1。先做短前摇，再把真实煤块视觉抛进车头；
	# 煤块真正抵达后才扣携煤/增加列车煤，并让停靠列车视觉弹一下。
	var fly_time:float = maxf(refuel_coal_fly_time,0.10)
	var windup_time:float = maxf(maxf(refuel_duration,0.05) - fly_time,0.05)
	var ok:bool = await wait_for_combat_time(windup_time)
	if not ok or not _action_still_valid(serial):
		_finish_action(false)
		return
	if _held_coal <= 0 or _train == null or not is_instance_valid(_train):
		_finish_action(false)
		return
	if not bool(_train.call("is_waiting_for_coal")):
		_finish_action(false)
		return

	var target_position:Vector2 = global_position
	if _train is Node2D:
		target_position = (_train as Node2D).global_position
	if _train.has_method("get_refuel_visual_target_position"):
		var target_variant:Variant = _train.call("get_refuel_visual_target_position")
		if target_variant is Vector2:
			target_position = target_variant
	_broadcast_refuel_coal_arc(global_position,target_position,fly_time)

	ok = await wait_for_combat_time(fly_time)
	if not ok or not _action_still_valid(serial):
		_finish_action(false)
		return
	if _held_coal > 0 and _train != null and is_instance_valid(_train) and bool(_train.call("is_waiting_for_coal")):
		_held_coal -= 1
		_broadcast_add_train_coal(1)
	_finish_action(true)


func _action_still_valid(serial:int) -> bool:
	return is_instance_valid(self) and health > 0 and serial == _action_serial


func _finish_action(_success:bool) -> void:
	if _current_mine != null and is_instance_valid(_current_mine) and _current_mine.has_method("release_claim"):
		_current_mine.call("release_claim",self)
	_current_mine = null
	_action_busy = false
	_mining_active = false
	_refueling_active = false
	_broadcast_conductor_visual(0)


func _broadcast_start_initial_train() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_start_initial_train.rpc()
	else:
		_rpc_start_initial_train()


func _broadcast_add_train_coal(amount:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_add_train_coal.rpc(amount)
	else:
		_rpc_add_train_coal(amount)


func _broadcast_conductor_visual(state_value:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_conductor_visual.rpc(state_value)
	else:
		_rpc_set_conductor_visual(state_value)


func _broadcast_mining_feedback(mine:Node,mine_position:Vector2,feedback_seed:int) -> void:
	var mine_name:String = ""
	if mine != null and is_instance_valid(mine):
		mine_name = str(mine.name)
	# 把落镐来源位置也同步出去。白线主方向必须来自“火车长 -> 矿点”，
	# 不能让远端客户端根据可能略有差异的本地位置重新猜方向。
	var strike_source_position:Vector2 = global_position
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_mining_feedback.rpc(mine_position,strike_source_position,mine_name,feedback_seed)
	else:
		_rpc_spawn_mining_feedback(mine_position,strike_source_position,mine_name,feedback_seed)


func _broadcast_refuel_coal_arc(start_position:Vector2,end_position:Vector2,duration:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_refuel_coal_arc.rpc(start_position,end_position,duration)
	else:
		_rpc_spawn_refuel_coal_arc(start_position,end_position,duration)


@rpc("authority","call_local","reliable")
func _rpc_start_initial_train() -> void:
	if _train != null and is_instance_valid(_train):
		_train.call("start_initial_run")


@rpc("authority","call_local","reliable")
func _rpc_launch_waiting_train() -> void:
	# 使用可跨端定位的火车长节点发 RPC；列车名含本地 instance_id，不能当 RPC 路径。
	if _train != null and is_instance_valid(_train):
		_train.call("launch_waiting_train")


@rpc("authority","call_local","reliable")
func _rpc_add_train_coal(amount:int) -> void:
	if _train != null and is_instance_valid(_train):
		_train.call("add_coal",amount)


@rpc("authority","call_local","reliable")
func _rpc_set_conductor_visual(state_value:int) -> void:
	match state_value:
		1:
			_set_character_texture(PICKAXE_TEXTURE)
		2:
			_set_character_texture(MINING_TEXTURE)
			_play_action_audio(MINING_AUDIO,mining_audio_volume_db)
		3:
			_set_character_texture(REFUEL_TEXTURE)
			_play_action_audio(REFUEL_AUDIO,refuel_audio_volume_db)
		_:
			_set_character_texture(NORMAL_TEXTURE)


func _set_character_texture(texture:Texture2D) -> void:
	if image is Sprite2D:
		(image as Sprite2D).texture = texture
	# 四张司机素材尺寸相同，但可见主体留白不同；只重拟合视觉，不改已稳定的碰撞框。
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _play_action_audio(stream:AudioStream,volume_db:float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "TrainConductorActionAudio"
	player.stream = stream
	player.bus = &"GameplayRecord"
	player.volume_db = volume_db
	player.max_distance = maxf(action_audio_max_distance,200.0)
	player.attenuation = 0.55
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


@rpc("authority","call_local","reliable")
func _rpc_spawn_mining_feedback(
	mine_position:Vector2,
	strike_source_position:Vector2,
	mine_name:String,
	feedback_seed:int
) -> void:
	_spawn_mining_white_lines(mine_position,strike_source_position,feedback_seed)
	_spawn_mining_white_ring(mine_position)
	_spawn_coal_arc(mine_position)
	var mine:Node = _find_mine_by_name(mine_name)
	if mine != null and is_instance_valid(mine) and mine.has_method("play_mining_bounce"):
		mine.call("play_mining_bounce",mine_position - strike_source_position)


@rpc("authority","call_local","reliable")
func _rpc_spawn_refuel_coal_arc(start_position:Vector2,end_position:Vector2,duration:float) -> void:
	_spawn_coal_arc_between(
		start_position,
		end_position,
		maxf(duration,0.10),
		maxf(refuel_coal_arc_height,0.0),
		maxf(refuel_coal_visual_size,2.0),
		122,
		"火车长_加煤飞行煤块"
	)


func _find_mine_by_name(mine_name:String) -> Node:
	if mine_name.is_empty() or get_tree() == null:
		return null
	for mine:Node in get_tree().get_nodes_in_group("TrainConductorMine"):
		if mine != null and is_instance_valid(mine) and str(mine.name) == mine_name:
			return mine
	return null


func _spawn_mining_white_lines(
	origin:Vector2,
	strike_source_position:Vector2,
	feedback_seed:int
) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return

	# V125：完全复用人物受击白线的“定向爆射”语义。
	# 落镐方向 = 火车长位置 -> 矿点；白线从矿点继续沿这个方向射出去，
	# 只在主方向附近做有限角度扩散。这样看起来就是矿点被镐击中后沿受力方向喷出白线，
	# 而不是围绕矿点画一圈放射线。
	var outward:Vector2 = origin - strike_source_position
	if outward.length_squared() <= 0.000001:
		outward = direction
	if outward.length_squared() <= 0.000001:
		outward = Vector2.RIGHT
	outward = outward.normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = feedback_seed
	var streaks:Array = []
	var count:int = clampi(mining_white_line_count,3,18)
	var spread:float = deg_to_rad(maxf(mining_white_line_spread_degrees,0.0))
	var min_distance:float = minf(mining_white_line_distance_min,mining_white_line_distance_max)
	var max_distance:float = maxf(mining_white_line_distance_min,mining_white_line_distance_max)
	var min_width:float = minf(mining_white_line_width_min,mining_white_line_width_max)
	var max_width:float = maxf(mining_white_line_width_min,mining_white_line_width_max)

	for _index:int in range(count):
		var angle_offset:float = rng.randf_range(-spread,spread)
		var streak_dir:Vector2 = outward.rotated(angle_offset).normalized()
		var distance:float = rng.randf_range(
			maxf(min_distance,8.0),
			maxf(max_distance,maxf(min_distance,8.0))
		)
		var length:float = distance * rng.randf_range(0.28,0.48)
		# 和人物受击一样保持细线；靠数量、方向收束和动画表现冲击，不靠粗线画扇形。
		var width:float = rng.randf_range(
			maxf(min_width,0.25),
			maxf(max_width,maxf(min_width,0.25))
		)
		var spawn_side:Vector2 = Vector2(-outward.y,outward.x)
		var spawn_offset:Vector2 = (
			outward * rng.randf_range(-2.0,2.5)
			+ spawn_side * rng.randf_range(-5.0,5.0)
		)
		streaks.append({
			"spawn_offset":spawn_offset,
			"direction":streak_dir,
			"distance":distance,
			"length":length,
			"width":width,
			"duration":maxf(mining_white_line_duration,0.08) * rng.randf_range(0.90,1.10),
			"delay":rng.randf_range(0.0,0.035),
			"grow_end":0.30,
			"fade_in_end":0.10,
			"fade_out_start":0.52,
			"color":Color.WHITE,
		})

	var effect:Node2D = TRAIN_HIT_BURST_EFFECT_SCRIPT.new()
	effect.call("setup",origin,streaks)
	parent.add_child(effect)
	# 煤矿在墙边，仍需要高于地图外遮罩；只改变绘制层级，不改变真实伤害/矿区判定。
	effect.z_as_relative = false
	effect.z_index = 122


func _spawn_mining_white_ring(origin:Vector2) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var root := Node2D.new()
	root.name = "火车长_挖矿震波"
	root.top_level = true
	root.global_position = origin
	root.z_as_relative = false
	root.z_index = 121
	root.scale = Vector2.ONE * clampf(mining_shockwave_start_scale,0.02,1.0)
	parent.add_child(root)

	var line := Line2D.new()
	line.name = "WhiteOutlineRing"
	line.width = maxf(mining_shockwave_line_width,0.5)
	line.default_color = Color(1.0,1.0,1.0,0.92)
	line.antialiased = true
	var radius:float = maxf(mining_shockwave_radius,1.0)
	var segments:int = 40
	for index:int in range(segments + 1):
		var angle:float = TAU * float(index) / float(segments)
		line.add_point(Vector2(cos(angle),sin(angle)) * radius)
	root.add_child(line)

	var lifetime:float = maxf(mining_shockwave_visual_time,0.08)
	var tween:Tween = root.create_tween().set_parallel(true)
	tween.tween_property(root,"scale",Vector2.ONE,lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(root,"modulate:a",0.0,lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(root.queue_free)


func _apply_mining_shockwave_damage(origin:Vector2) -> void:
	if not is_multiplayer_authority():
		return
	var radius:float = maxf(mining_shockwave_radius,1.0)
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,origin)
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,64)
	var damage_value:float = attack_damage(maxf(mining_shockwave_damage_multiplier,0.0))
	for hit:Dictionary in hits:
		var collider:Variant = hit.get("collider")
		if not collider is ball:
			continue
		var target:ball = collider as ball
		if not _is_valid_mining_target(target):
			continue
		var before_health:float = float(target.health)
		var before_block:float = float(target.block)
		var did_hit:bool = target.receive_spatial_damage(
			damage_value,
			{"point":origin,"source":self}
		)
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		if did_hit or health_loss > 0.0 or block_loss > 0.0:
			var push_direction:Vector2 = target.global_position - origin
			if push_direction.length_squared() <= 0.0001:
				push_direction = target.global_position - global_position
			if push_direction.length_squared() <= 0.0001:
				push_direction = Vector2.UP
			push_direction = push_direction.normalized()
			if mining_shockwave_knockback_distance > 0.0:
				target.apply_knockback(
					push_direction,
					mining_shockwave_knockback_distance,
					mining_shockwave_knockback_speed,
					0.08,
					0.0,
					{
						"source":self,
						"lock_control":false,
						"stop_on_character":false,
						"max_wall_bounces":0,
						"smooth_motion":true,
					}
				)


func _is_valid_mining_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and not Ignore_Team_Damage_Setting
		and Team != ""
		and target.Team == Team
	):
		return false
	return true


func _spawn_coal_arc(start_position:Vector2) -> void:
	_spawn_coal_arc_between(
		start_position,
		global_position,
		maxf(coal_fly_time,0.10),
		maxf(coal_arc_height,0.0),
		maxf(coal_visual_size,2.0),
		48,
		"火车长_飞行煤块"
	)


func _spawn_coal_arc_between(
	start_position:Vector2,
	end_position:Vector2,
	duration:float,
	arc_height:float,
	visual_size:float,
	z_value:int,
	node_name:String
) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var coal := Sprite2D.new()
	coal.name = node_name
	coal.texture = COAL_TEXTURE
	var tex_size:Vector2 = COAL_TEXTURE.get_size()
	var scale_value:float = maxf(visual_size,2.0) / maxf(maxf(tex_size.x,tex_size.y),1.0)
	coal.scale = Vector2.ONE * scale_value
	coal.top_level = true
	coal.global_position = start_position
	coal.z_as_relative = false
	coal.z_index = z_value
	parent.add_child(coal)

	var travel_time:float = maxf(duration,0.10)
	var move_tween:Tween = coal.create_tween().set_parallel(true)
	move_tween.tween_property(coal,"position:x",end_position.x,travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(coal,"rotation",coal.rotation + TAU * 1.75,travel_time).set_trans(Tween.TRANS_LINEAR)
	move_tween.tween_property(coal,"scale",coal.scale * 0.72,travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var arc_tween:Tween = coal.create_tween()
	arc_tween.tween_property(coal,"position:y",minf(start_position.y,end_position.y) - maxf(arc_height,0.0),travel_time * 0.50).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc_tween.tween_property(coal,"position:y",end_position.y,travel_time * 0.50).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	arc_tween.tween_callback(coal.queue_free)


func _exit_tree() -> void:
	if _train != null and is_instance_valid(_train):
		_train.queue_free()
	if get_tree() == null:
		return
	# _exit_tree 时 self 可能仍在 Ball 组，所以只检查“其它”火车长。
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node == self or node == null or not is_instance_valid(node):
			continue
		if node.has_method("is_train_conductor") and bool(node.call("is_train_conductor")):
			return
	for mine:Node in get_tree().get_nodes_in_group("TrainConductorMine"):
		if mine != null and is_instance_valid(mine):
			mine.queue_free()
