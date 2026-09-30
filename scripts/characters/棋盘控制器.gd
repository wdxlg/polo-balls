extends Node2D

const STONE_SCRIPT := preload("res://scripts/characters/棋子.gd")

var _players:Dictionary = {} # slot -> 棋手
var _occupied:Dictionary = {} # "x:y" -> 棋子
var _stones_by_owner:Dictionary = {} # owner instance id -> Array[StaticBody2D]
var _map_name:String = ""
var _board_spacing:float = 22.0
var _board_margin:float = 14.0


func _ready() -> void:
	add_to_group("__gomoku_board_controller")
	z_as_relative = false
	z_index = 0


func register_player(player:ball) -> int:
	_cleanup_players()
	for slot in [0,1]:
		if not _players.has(slot):
			_players[slot] = player
			if _players.size() == 1:
				_board_spacing = maxf(float(player.get("board_spacing")),8.0)
				_board_margin = maxf(float(player.get("board_margin")),4.0)
			return slot
	return -1


func unregister_player(player:ball) -> void:
	var slots_to_remove:Array[int] = []
	for slot in _players:
		if _players[slot] == player:
			slots_to_remove.append(int(slot))
	for slot in slots_to_remove:
		_players.erase(slot)
	_remove_owner_stones(player)
	_cleanup_players()
	if _players.is_empty():
		queue_free()


func request_place(player:ball,aim_world_position:Vector2 = Vector2.ZERO,use_aim:bool = false) -> bool:
	# 棋盘玩法只由 authority 选择格子；客户端只接收同一落子数据做视觉镜像。
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return false
	if player == null or not is_instance_valid(player) or player.health <= 0:
		return false
	var slot:int = _slot_for_player(player)
	if slot < 0:
		return false

	var map_info:Dictionary = _get_map_info()
	if map_info.is_empty():
		return false
	var current_name:String = str(map_info["name"])
	if _map_name != "" and _map_name != current_name:
		_clear_all_stones()
	_map_name = current_name

	var rect:Rect2 = map_info["rect"]
	if use_aim and not rect.has_point(aim_world_position):
		return false
	var free_cells:Array[Vector2i] = _return_free_cells(rect)
	if free_cells.is_empty():
		return false

	var chosen:Vector2i = free_cells.pick_random()
	if use_aim:
		var nearest:Vector2i = chosen
		var best_distance:float = INF
		for cell:Vector2i in free_cells:
			var distance:float = _cell_to_world(cell,rect).distance_squared_to(aim_world_position)
			if distance < best_distance:
				best_distance = distance
				nearest = cell
		# 鼠标所在格被占用时不可偷偷下到其他格。
		chosen = nearest
		if best_distance > (_board_spacing * _board_spacing * 0.5):
			return false
	var position:Vector2 = _cell_to_world(chosen,rect)
	var player_path:NodePath = player.get_path()
	_spawn_stone_local(player_path,chosen,slot,position)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_stone.rpc(player_path,chosen,slot,position)
	return true


@rpc("authority","call_remote","reliable")
func _rpc_spawn_stone(player_path:NodePath,cell_value:Vector2i,slot:int,position_value:Vector2) -> void:
	_spawn_stone_local(player_path,cell_value,slot,position_value)


func _spawn_stone_local(player_path:NodePath,chosen:Vector2i,slot:int,position:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var raw_player:Node = get_node_or_null(player_path)
	if raw_player == null and world != null:
		raw_player = world.get_node_or_null(player_path)
	if not raw_player is ball or not is_instance_valid(raw_player):
		return
	var player:ball = raw_player as ball
	var key:String = _cell_key(chosen)
	if _occupied.has(key):
		var existing:Variant = _occupied[key]
		if existing != null and is_instance_valid(existing):
			return

	var stone:StaticBody2D = STONE_SCRIPT.new()
	# 固定名来自 slot/cell，保证各 peer 的本地棋盘结构一致，不使用 instance_id/时间戳。
	stone.name = "ChessStone_%d_%d_%d" % [slot,chosen.x,chosen.y]
	stone.call(
		"configure",
		self,
		player,
		chosen,
		slot,
		float(player.get("stone_radius")),
		float(player.get("stone_touch_damage_multiplier")),
		float(player.get("stone_chain_bonus_damage_multiplier")),
		float(player.get("stone_fall_height")),
		float(player.get("stone_fall_duration")),
		float(player.get("stone_lifetime"))
	)
	world.add_child(stone)
	stone.global_position = position

	_occupied[key] = stone
	var owner_id:int = player.get_instance_id()
	if not _stones_by_owner.has(owner_id):
		_stones_by_owner[owner_id] = []
	var owner_stones:Array = _stones_by_owner[owner_id]
	owner_stones.append(stone)
	_stones_by_owner[owner_id] = owner_stones
	if is_multiplayer_authority() and player.has_method("play_chess_place_sfx"):
		player.call("play_chess_place_sfx",position)


# 棋子真正落地后才刷新连接、计算五连，避免棋子还在天上就触发结算。
func on_stone_landed(stone:StaticBody2D) -> void:
	if stone == null or not is_instance_valid(stone):
		return
	var cell:Vector2i = stone.get("cell")
	var slot:int = int(stone.get("color_slot"))
	if _stone_at(cell) != stone:
		return

	var best:Dictionary = _return_best_chain(cell,slot)
	var best_count:int = int(best.get("count",1))
	if best_count >= 5:
		var owner_ball = stone.get("stone_owner")
		if owner_ball != null and is_instance_valid(owner_ball) and owner_ball is ball:
			_trigger_five(owner_ball as ball,slot,best.get("stones",[]))
		return

	# 新棋连上旧棋时：连接到的棋子一起刷新寿命，并立即更新它们的连子等级。
	_refresh_connected_from_new_stone(cell,slot)
	_recalculate_all_chain_states()


func on_stone_expired(stone:StaticBody2D) -> void:
	if stone == null or not is_instance_valid(stone):
		return
	_remove_stone(stone,true)
	_recalculate_all_chain_states()


func on_stone_touched(stone:StaticBody2D,target:ball) -> void:
	# 远端棋子是视觉镜像；所有伤害只在 authority 结算，避免双扣血。
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if stone == null or not is_instance_valid(stone):
		return
	if target == null or not is_instance_valid(target):
		return
	var owner_ball = stone.get("stone_owner")
	if owner_ball == null or not is_instance_valid(owner_ball) or not (owner_ball is ball):
		return
	var owner_typed:ball = owner_ball as ball
	if not _is_enemy(owner_typed,target):
		return

	# 伤害读取棋子当前“连接状态”。新增/消失棋子都会刷新这个值。
	var chain_count:int = clampi(int(stone.get("chain_count")),1,5)
	var damage:float = owner_typed.attack_damage(float(stone.get("touch_damage_multiplier")) + float(stone.get("chain_bonus_damage_multiplier")) * float(chain_count - 1))
	if damage <= 0:
		return
	# 棋子是实体碰撞，不允许“圆形体积穿过人物”后从背面碰到破绽。
	# 普通目标仍按原圆形触碰结算；决斗者会使用 blocked_by_body 改成来源侧第一接触点。
	var touch_radius:float = maxf(float(stone.get("stone_radius")) + 1.2,2.0)
	target.receive_spatial_damage(
		damage,
		{
			"shape":"circle",
			"center":stone.global_position,
			"radius":touch_radius,
			"source":stone,
			"blocked_by_body":true,
			"source_position":stone.global_position,
		},
		false
	)
	var hit_audio:String = str(owner_typed.get("stone_hit_audio"))
	if hit_audio != "":
		Audios.play_sfx.rpc(hit_audio,{},true)


func _refresh_connected_from_new_stone(cell:Vector2i,slot:int) -> void:
	var touched:Dictionary = {}
	for axis in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,-1)]:
		var run:Array = _full_run(cell,slot,axis)
		if run.size() < 2:
			continue
		var level:int = mini(run.size(),5)
		for member in run:
			if member == null or not is_instance_valid(member):
				continue
			var id:int = member.get_instance_id()
			if touched.has(id):
				continue
			touched[id] = true
			member.call("set_chain_state",level,true)


func _recalculate_all_chain_states() -> void:
	for key in _occupied.keys():
		var stone = _occupied[key]
		if stone == null or not is_instance_valid(stone):
			continue
		var cell:Vector2i = stone.get("cell")
		var slot:int = int(stone.get("color_slot"))
		var best:Dictionary = _return_best_chain(cell,slot)
		stone.call("set_chain_state",clampi(int(best.get("count",1)),1,5),false)


func _trigger_five(player:ball,slot:int,stones) -> void:
	if player == null or not is_instance_valid(player):
		return
	if is_multiplayer_authority():
		var damage:float = player.attack_damage(float(player.get("five_link_damage_multiplier")))
		if damage > 0:
			for node in get_tree().get_nodes_in_group("Ball"):
				if node is ball:
					var target:ball = node as ball
					if _is_enemy(player,target):
						target.receive_spatial_damage(damage,{"shape":"all","source":player},false)
	_flash_map(slot,float(player.get("board_flash_duration")))
	if is_multiplayer_authority():
		var five_audio:String = str(player.get("five_link_audio"))
		if five_audio != "":
			if multiplayer.has_multiplayer_peer():
				Audios.play_sfx.rpc(five_audio,{},true)
			else:
				Audios.play_sfx(five_audio,{},true)

	# 五连棋消失；若一次桥接成超过5个，整条连续线都清掉，避免旧五连残留重复结算。
	var remove_list:Array = []
	for member in stones:
		if member != null and is_instance_valid(member):
			remove_list.append(member)
	call_deferred("_remove_stone_list",remove_list)


func _return_best_chain(cell:Vector2i,slot:int) -> Dictionary:
	var best_count:int = 1
	var best_stones:Array = []
	var center = _chain_stone_at(cell)
	if center != null:
		best_stones.append(center)
	for axis in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,-1)]:
		var stones:Array = _full_run(cell,slot,axis)
		if stones.size() > best_count:
			best_count = stones.size()
			best_stones = stones
	return {"count":mini(best_count,5),"stones":best_stones}


func _full_run(cell:Vector2i,slot:int,axis:Vector2i) -> Array:
	var result:Array = []
	var negative:Array = _collect_direction(cell,slot,-axis)
	negative.reverse()
	result.append_array(negative)
	var center = _chain_stone_at(cell)
	if center != null and int(center.get("color_slot")) == slot:
		result.append(center)
	result.append_array(_collect_direction(cell,slot,axis))
	return result


func _collect_direction(start:Vector2i,slot:int,step:Vector2i) -> Array:
	var result:Array = []
	var cursor:Vector2i = start + step
	# 棋盘不会很大，这里允许完整扫描连续线；伤害等级仍最多按5连计算。
	for _i in range(64):
		var stone = _chain_stone_at(cursor)
		if stone == null or not is_instance_valid(stone):
			break
		if int(stone.get("color_slot")) != slot:
			break
		result.append(stone)
		cursor += step
	return result


func _stone_at(cell:Vector2i):
	var key:String = _cell_key(cell)
	if not _occupied.has(key):
		return null
	var stone = _occupied[key]
	if stone == null or not is_instance_valid(stone):
		_occupied.erase(key)
		return null
	return stone


func _chain_stone_at(cell:Vector2i):
	var stone = _stone_at(cell)
	if stone == null or not is_instance_valid(stone):
		return null
	if stone.has_method("is_landed_stone") and not bool(stone.call("is_landed_stone")):
		return null
	return stone


func _return_free_cells(rect:Rect2) -> Array[Vector2i]:
	var cells:Array[Vector2i] = []
	var usable_w:float = maxf(rect.size.x - _board_margin * 2.0,1.0)
	var usable_h:float = maxf(rect.size.y - _board_margin * 2.0,1.0)
	var cols:int = maxi(int(floor(usable_w / _board_spacing)) + 1,2)
	var rows:int = maxi(int(floor(usable_h / _board_spacing)) + 1,2)
	for y in range(rows):
		for x in range(cols):
			var c := Vector2i(x,y)
			if not _occupied.has(_cell_key(c)):
				cells.append(c)
	return cells


func _cell_to_world(cell:Vector2i,rect:Rect2) -> Vector2:
	var usable_w:float = maxf(rect.size.x - _board_margin * 2.0,1.0)
	var usable_h:float = maxf(rect.size.y - _board_margin * 2.0,1.0)
	var cols:int = maxi(int(floor(usable_w / _board_spacing)) + 1,2)
	var rows:int = maxi(int(floor(usable_h / _board_spacing)) + 1,2)
	var step_x:float = usable_w / float(maxi(cols - 1,1))
	var step_y:float = usable_h / float(maxi(rows - 1,1))
	return Vector2(
		rect.position.x + _board_margin + float(cell.x) * step_x,
		rect.position.y + _board_margin + float(cell.y) * step_y
	)


func _cell_key(cell:Vector2i) -> String:
	return "%d:%d" % [cell.x,cell.y]


func _slot_for_player(player:ball) -> int:
	for slot in _players:
		if _players[slot] == player:
			return int(slot)
	return -1


func _is_enemy(source:ball,target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(source,target): return false # 皓宸复制品及其产物不把己方选为目标
	if source == null or target == null:
		return false
	if source == target or not target.is_combat_targetable():
		return false
	if source.Team != "" and target.Team != "" and source.Team == target.Team:
		return false
	return true


func _get_map_info() -> Dictionary:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return {}
	var map_name:String = str(world.now_choose_map)
	if not world.map_group.has(map_name):
		return {}
	var map_node = world.map_group[map_name]
	if not map_node is TileMapLayer:
		return {}
	var rect:Rect2 = world.return_map_world_rect(map_node)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return {}
	return {"name":map_name,"rect":rect}


func _flash_map(slot:int,duration:float) -> void:
	var info:Dictionary = _get_map_info()
	if info.is_empty():
		return
	var rect:Rect2 = info["rect"]
	var flash := Polygon2D.new()
	flash.name = "GomokuFlash_%d" % Time.get_ticks_usec()
	flash.z_as_relative = false
	flash.z_index = 500
	flash.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x,rect.position.y),
		rect.end,
		Vector2(rect.position.x,rect.end.y)
	])
	flash.color = Color(0.0,0.0,0.0,0.48) if slot == 0 else Color(1.0,1.0,1.0,0.58)
	get_tree().current_scene.add_child(flash)
	var tween:Tween = flash.create_tween()
	tween.tween_property(flash,"modulate:a",0.0,maxf(duration,0.05))
	tween.finished.connect(flash.queue_free)


func _remove_stone_list(stones:Array) -> void:
	for stone in stones:
		_remove_stone(stone,true)
	_recalculate_all_chain_states()


func _remove_stone(stone,animate:bool = true) -> void:
	if stone == null or not is_instance_valid(stone):
		return
	var cell_value:Vector2i = stone.get("cell")
	_occupied.erase(_cell_key(cell_value))
	for owner_id in _stones_by_owner.keys():
		var arr:Array = _stones_by_owner[owner_id]
		arr.erase(stone)
		_stones_by_owner[owner_id] = arr
	if animate and stone.has_method("play_disappear"):
		stone.call("play_disappear")
	else:
		stone.queue_free()


func _remove_owner_stones(player:ball) -> void:
	if player == null:
		return
	var owner_id:int = player.get_instance_id()
	if not _stones_by_owner.has(owner_id):
		return
	var owner_stones:Array = _stones_by_owner[owner_id]
	var stones:Array = owner_stones.duplicate()
	for stone in stones:
		_remove_stone(stone,true)
	_stones_by_owner.erase(owner_id)
	_recalculate_all_chain_states()


func _clear_all_stones() -> void:
	var stones:Array = []
	for key in _occupied:
		var stone = _occupied[key]
		if stone != null and is_instance_valid(stone):
			stones.append(stone)
	_occupied.clear()
	_stones_by_owner.clear()
	for stone in stones:
		stone.queue_free()


func _cleanup_players() -> void:
	var remove_slots:Array[int] = []
	for slot in _players:
		var player = _players[slot]
		if player == null or not is_instance_valid(player) or player.health <= 0:
			remove_slots.append(int(slot))
	for slot in remove_slots:
		_players.erase(slot)
