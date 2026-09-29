extends ball

const GO_STONE_SCRIPT := preload("res://scripts/characters/meme/时光围棋子.gd")
const GO_DIRS := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]

@export_category("围棋落子")
@export_range(0.5,5.0,0.1) var normal_place_interval:float = 2.0
@export_range(0.2,3.0,0.1) var high_dan_place_interval:float = 1.0
@export_range(0.05,1.0,0.05) var ke_jie_place_interval:float = 0.10
@export_range(12.0,60.0,1.0) var board_spacing:float = 26.0
@export_range(4.0,60.0,1.0) var board_margin:float = 18.0
@export_range(2.0,14.0,0.5) var stone_radius:float = 6.0
@export_range(20.0,240.0,5.0) var stone_fall_height:float = 105.0
@export_range(0.08,1.0,0.01) var stone_fall_duration:float = 0.30
@export_range(8.0,60.0,1.0) var landing_hit_radius:float = 27.0
@export_range(0.0,200.0,1.0) var landing_hit_damage:float = 25.0

@export_category("段位")
@export_range(0.1,60.0,0.1) var promotion_base_offset:float = 2.0
@export_range(1.0,60.0,0.5) var ke_jie_check_interval:float = 10.0
@export_range(0.0,1.0,0.001) var ke_jie_chance:float = 0.01
@export_range(0.0,1.0,0.01) var ke_jie_heal_ratio:float = 0.50
@export_range(0.0,200.0,1.0) var surround_damage_per_x:float = 25.0

var _board:Dictionary = {} # "x:y" -> 0黑 / 1白
var _stone_nodes:Dictionary = {} # "x:y" -> 本地视觉 Node2D
var _next_color:int = 0
var _place_left:float = 0.0

var _rank:int = 1
var _x_value:int = 1
var _promotion_left:float = 3.0
var _ke_jie_check_left:float = 10.0
var _is_ke_jie:bool = false
var _rank_label:Label = null

var _map_name:String = ""
var _map_rect:Rect2 = Rect2()
var _grid_cols:int = 0
var _grid_rows:int = 0
var _ko_forbidden_signature:String = ""


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	_place_left = maxf(normal_place_interval,0.1)
	_promotion_left = float(_x_value) + promotion_base_offset
	_ke_jie_check_left = maxf(ke_jie_check_interval,1.0)
	super._ready()
	_ensure_rank_label()
	_update_rank_label(false)


func tick_physics(state:State,delta:float) -> void:
	# 时光落子不锁行动；移动完全沿用 ball 的正常运动。
	super.tick_physics(state,delta)
	if not is_multiplayer_authority():
		return
	if state == State.Die or health <= 0:
		return

	_process_rank_progress(delta)
	_place_left -= delta
	if _place_left <= 0.0 and not is_player_controlled():
		var placed:bool = _attempt_place()
		_place_left = _current_place_interval() if placed else 0.25


func controlled_attack_action() -> void:
	# 左键：在鼠标所指的合法交叉点落子；保持段位、禁着与原落子间隔。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if _place_left > 0.0 or not has_player_control_aim():
		return
	var placed:bool = _attempt_place(player_control_aim_world_position(),true)
	_place_left = _current_place_interval() if placed else 0.25


func _process_rank_progress(delta:float) -> void:
	if _rank < 9:
		_promotion_left -= delta
		if _promotion_left <= 0.0:
			_rank += 1
			_x_value += 1
			_promotion_left = float(_x_value) + promotion_base_offset
			_sync_rank_state()
			if _rank >= 7:
				_place_left = minf(_place_left,_current_place_interval())
			if _rank >= 9:
				_ke_jie_check_left = maxf(ke_jie_check_interval,1.0)
		return

	if _is_ke_jie:
		return
	_ke_jie_check_left -= delta
	if _ke_jie_check_left > 0.0:
		return
	_ke_jie_check_left += maxf(ke_jie_check_interval,1.0)
	if randf() <= clampf(ke_jie_chance,0.0,1.0):
		_transform_to_ke_jie()


func _current_place_interval() -> float:
	if _is_ke_jie:
		return maxf(ke_jie_place_interval,0.05)
	if _rank >= 7:
		return maxf(high_dan_place_interval,0.2)
	return maxf(normal_place_interval,0.5)


func _transform_to_ke_jie() -> void:
	if _is_ke_jie:
		return
	_is_ke_jie = true
	var heal_amount:int = int(round(float(Max_health) * clampf(ke_jie_heal_ratio,0.0,1.0)))
	health = mini(Max_health,health + heal_amount)
	_place_left = minf(_place_left,_current_place_interval())
	_sync_rank_state()


func _sync_rank_state() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_rank_state.rpc(_rank,_x_value,_is_ke_jie)
	else:
		_rpc_set_rank_state(_rank,_x_value,_is_ke_jie)


@rpc("authority","call_local","reliable")
func _rpc_set_rank_state(rank_value:int,x_value:int,ke_jie_value:bool) -> void:
	_rank = clampi(rank_value,1,9)
	_x_value = maxi(x_value,1)
	_is_ke_jie = ke_jie_value
	_update_rank_label(true)


func _ensure_rank_label() -> void:
	if _rank_label != null and is_instance_valid(_rank_label):
		return
	_rank_label = Label.new()
	_rank_label.name = "GoRankLabel"
	_rank_label.position = Vector2(-95.0,98.0)
	_rank_label.size = Vector2(190.0,44.0)
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_label.z_index = 75
	_rank_label.add_theme_font_size_override("font_size",54)
	_rank_label.add_theme_constant_override("outline_size",8)
	_rank_label.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.95))
	add_child(_rank_label)


func _update_rank_label(animate:bool) -> void:
	_ensure_rank_label()
	if _rank_label == null:
		return
	if _is_ke_jie:
		_rank_label.text = tr("柯洁")
		_rank_label.modulate = Color(1.0,0.78,0.25,1.0)
	else:
		_rank_label.text = tr(_rank_key(_rank))
		_rank_label.modulate = Color(1.0,1.0,1.0,1.0)
	if animate:
		_rank_label.scale = Vector2(1.24,1.24)
		var tween := _rank_label.create_tween()
		tween.tween_property(_rank_label,"scale",Vector2.ONE,0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _rank_key(value:int) -> String:
	match clampi(value,1,9):
		1:return "初段"
		2:return "二段"
		3:return "三段"
		4:return "四段"
		5:return "五段"
		6:return "六段"
		7:return "七段"
		8:return "八段"
		_:return "九段"


func _attempt_place(aim_world_position:Vector2 = Vector2.ZERO,use_aim:bool = false) -> bool:
	if not _refresh_board_geometry():
		return false
	var move:Dictionary = {}
	if use_aim:
		if not _map_rect.has_point(aim_world_position):
			return false
		move = _simulate_move(_world_to_cell(aim_world_position),_next_color)
	else:
		move = _choose_random_legal_move(_next_color)
	if move.is_empty():
		return false

	var cell:Vector2i = move["cell"]
	var captured:Array = move.get("captures",[])
	var world_position:Vector2 = _cell_to_world(cell)
	# 简单劫：下一手不能直接恢复到本手之前的盘面。
	var before_signature:String = _board_signature(_board)
	if multiplayer.has_multiplayer_peer():
		_rpc_apply_move.rpc(cell,_next_color,captured,world_position)
	else:
		_rpc_apply_move(cell,_next_color,captured,world_position)
	_ko_forbidden_signature = before_signature
	_next_color = 1 - _next_color
	return true


func _refresh_board_geometry() -> bool:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return false
	var current_name:String = str(world.now_choose_map)
	if not world.map_group.has(current_name):
		return false
	var map_node = world.map_group[current_name]
	if not map_node is TileMapLayer:
		return false
	var rect:Rect2 = world.return_map_world_rect(map_node)
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return false

	if _map_name != "" and _map_name != current_name:
		_clear_board_synced()
	_map_name = current_name
	_map_rect = rect
	var usable_w:float = maxf(rect.size.x - board_margin * 2.0,1.0)
	var usable_h:float = maxf(rect.size.y - board_margin * 2.0,1.0)
	_grid_cols = maxi(int(floor(usable_w / maxf(board_spacing,8.0))) + 1,2)
	_grid_rows = maxi(int(floor(usable_h / maxf(board_spacing,8.0))) + 1,2)
	return true


func _choose_random_legal_move(color:int) -> Dictionary:
	var candidates:Array = []
	for y in range(_grid_rows):
		for x in range(_grid_cols):
			var cell := Vector2i(x,y)
			if not _board.has(_cell_key(cell)):
				candidates.append(cell)
	candidates.shuffle()
	for raw_cell in candidates:
		var cell:Vector2i = raw_cell
		var result:Dictionary = _simulate_move(cell,color)
		if not result.is_empty():
			return result
	return {}


func _simulate_move(cell:Vector2i,color:int) -> Dictionary:
	var key:String = _cell_key(cell)
	if _board.has(key):
		return {}
	var sim:Dictionary = _board.duplicate()
	sim[key] = color
	var opponent:int = 1 - color
	var captured:Array = []
	var captured_seen:Dictionary = {}
	for dir in GO_DIRS:
		var neighbor:Vector2i = cell + dir
		if not _in_bounds(neighbor):
			continue
		if int(sim.get(_cell_key(neighbor),-1)) != opponent:
			continue
		var group:Array = _collect_group(sim,neighbor,opponent)
		if _group_liberty_count(sim,group) > 0:
			continue
		for group_cell in group:
			var group_key:String = _cell_key(group_cell)
			if not captured_seen.has(group_key):
				captured_seen[group_key] = true
				captured.append(group_cell)
	for captured_cell in captured:
		sim.erase(_cell_key(captured_cell))

	var own_group:Array = _collect_group(sim,cell,color)
	if _group_liberty_count(sim,own_group) <= 0:
		# 围棋自杀手禁着；随机落子会自动换另一个合法交叉点。
		return {}
	if _ko_forbidden_signature != "" and _board_signature(sim) == _ko_forbidden_signature:
		return {}
	return {"cell":cell,"captures":captured}


func _collect_group(board_state:Dictionary,start:Vector2i,color:int) -> Array:
	var result:Array = []
	var stack:Array = [start]
	var visited:Dictionary = {}
	while not stack.is_empty():
		var cell:Vector2i = stack.pop_back()
		var key:String = _cell_key(cell)
		if visited.has(key):
			continue
		visited[key] = true
		if int(board_state.get(key,-1)) != color:
			continue
		result.append(cell)
		for dir in GO_DIRS:
			var next_cell:Vector2i = cell + dir
			if _in_bounds(next_cell) and not visited.has(_cell_key(next_cell)):
				stack.append(next_cell)
	return result


func _group_liberty_count(board_state:Dictionary,group:Array) -> int:
	var liberties:Dictionary = {}
	for raw_cell in group:
		var cell:Vector2i = raw_cell
		for dir in GO_DIRS:
			var next_cell:Vector2i = cell + dir
			if not _in_bounds(next_cell):
				continue
			var key:String = _cell_key(next_cell)
			if not board_state.has(key):
				liberties[key] = true
	return liberties.size()


@rpc("authority","call_local","reliable")
func _rpc_apply_move(cell:Vector2i,color:int,captured:Array,world_position:Vector2) -> void:
	var captured_visuals:Array = []
	for raw_cell in captured:
		var captured_cell:Vector2i = raw_cell
		var captured_key:String = _cell_key(captured_cell)
		_board.erase(captured_key)
		if _stone_nodes.has(captured_key):
			var captured_node = _stone_nodes[captured_key]
			_stone_nodes.erase(captured_key)
			if captured_node != null and is_instance_valid(captured_node):
				captured_visuals.append(captured_node)

	var key:String = _cell_key(cell)
	_board[key] = color
	var stone:Node2D = GO_STONE_SCRIPT.new()
	stone.name = "TimeGoStone_%d_%d_%d" % [color,cell.x,cell.y]
	stone.call("configure",cell,color,stone_radius,stone_fall_height,stone_fall_duration)
	get_tree().current_scene.add_child(stone)
	stone.global_position = world_position
	_stone_nodes[key] = stone

	var timer := get_tree().create_timer(maxf(stone_fall_duration,0.05))
	timer.timeout.connect(_resolve_move_landing.bind(cell,color,stone,captured_visuals))


func _resolve_move_landing(cell:Vector2i,color:int,stone:Node2D,captured_visuals:Array) -> void:
	# 被吃掉的旧棋子在新棋真正落地时自然“提走”。
	for node in captured_visuals:
		if node != null and is_instance_valid(node) and node.has_method("play_capture"):
			node.call("play_capture")

	if not is_multiplayer_authority() or health <= 0:
		return
	var key:String = _cell_key(cell)
	# 0.1秒落子阶段可能出现“新棋还在空中就被后一手提掉”；这种棋不再结算砸击/包围。
	if not _board.has(key) or int(_board[key]) != color:
		return
	if not _stone_nodes.has(key) or _stone_nodes[key] != stone or not is_instance_valid(stone):
		return
	_apply_landing_hit(stone.global_position)
	_process_surround_rules()


func _apply_landing_hit(position_value:Vector2) -> void:
	for node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_enemy(target):
			continue
		if target.global_position.distance_to(position_value) > maxf(landing_hit_radius,1.0):
			continue
		target.receive_spatial_damage(
			maxf(landing_hit_damage,0.0),
			{"point":position_value,"source":self},
			false
		)


func _process_surround_rules() -> void:
	var remove_cells:Dictionary = {}
	# 所有“被包围”判定都基于同一落子后的盘面，再统一提子，避免遍历顺序改变结果。
	for node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == self:
			continue
		if not _is_enemy(target):
			continue
		var territory:Dictionary = _territory_at_world_position(target.global_position)
		if territory.is_empty():
			continue
		var boundary:Array = territory.get("boundary",[])
		_add_random_boundary_stones(remove_cells,boundary,2)
		target.receive_spatial_damage(
			maxf(float(_x_value) * surround_damage_per_x,0.0),
			{"point":target.global_position,"source":self},
			false
		)

	var self_territory:Dictionary = _territory_at_world_position(global_position)
	if not self_territory.is_empty():
		_add_random_boundary_stones(remove_cells,self_territory.get("boundary",[]),1)

	if not remove_cells.is_empty():
		var cells:Array = remove_cells.values()
		_ko_forbidden_signature = ""
		if multiplayer.has_multiplayer_peer():
			_rpc_remove_cells.rpc(cells)
		else:
			_rpc_remove_cells(cells)


func _territory_at_world_position(position_value:Vector2) -> Dictionary:
	if _grid_cols <= 0 or _grid_rows <= 0:
		return {}
	if position_value.x < _map_rect.position.x or position_value.y < _map_rect.position.y or position_value.x > _map_rect.end.x or position_value.y > _map_rect.end.y:
		return {}
	var start:Vector2i = _world_to_cell(position_value)
	if not _in_bounds(start):
		return {}
	var ignored_key:String = _cell_key(start)
	var stack:Array = [start]
	var visited:Dictionary = {}
	var boundary:Dictionary = {}
	var boundary_colors:Dictionary = {}
	var touches_edge:bool = false

	while not stack.is_empty():
		var cell:Vector2i = stack.pop_back()
		var key:String = _cell_key(cell)
		if visited.has(key):
			continue
		visited[key] = true
		for dir in GO_DIRS:
			var next_cell:Vector2i = cell + dir
			if not _in_bounds(next_cell):
				touches_edge = true
				continue
			var next_key:String = _cell_key(next_cell)
			# 人物站立的格子视为“空点”，即使刚好有棋子砸在脚下，也仍能判断外圈是否把人物围住。
			if next_key != ignored_key and _board.has(next_key):
				boundary[next_key] = next_cell
				boundary_colors[int(_board[next_key])] = true
				continue
			if not visited.has(next_key):
				stack.append(next_cell)

	if touches_edge or boundary.is_empty() or boundary_colors.size() != 1:
		return {}
	return {"boundary":boundary.values(),"color":int(boundary_colors.keys()[0])}


func _add_random_boundary_stones(output:Dictionary,boundary:Array,count:int) -> void:
	if boundary.is_empty() or count <= 0:
		return
	var choices:Array = boundary.duplicate()
	choices.shuffle()
	for i in range(mini(count,choices.size())):
		var cell:Vector2i = choices[i]
		output[_cell_key(cell)] = cell


@rpc("authority","call_local","reliable")
func _rpc_remove_cells(cells:Array) -> void:
	for raw_cell in cells:
		var cell:Vector2i = raw_cell
		var key:String = _cell_key(cell)
		_board.erase(key)
		if not _stone_nodes.has(key):
			continue
		var node = _stone_nodes[key]
		_stone_nodes.erase(key)
		if node != null and is_instance_valid(node):
			if node.has_method("play_capture"):
				node.call("play_capture")
			else:
				node.queue_free()


func _clear_board_synced() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_clear_board.rpc()
	else:
		_rpc_clear_board()
	_ko_forbidden_signature = ""


@rpc("authority","call_local","reliable")
func _rpc_clear_board() -> void:
	_board.clear()
	for key in _stone_nodes.keys():
		var node = _stone_nodes[key]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_stone_nodes.clear()


func _cell_to_world(cell:Vector2i) -> Vector2:
	var usable_w:float = maxf(_map_rect.size.x - board_margin * 2.0,1.0)
	var usable_h:float = maxf(_map_rect.size.y - board_margin * 2.0,1.0)
	var step_x:float = usable_w / float(maxi(_grid_cols - 1,1))
	var step_y:float = usable_h / float(maxi(_grid_rows - 1,1))
	return Vector2(
		_map_rect.position.x + board_margin + float(cell.x) * step_x,
		_map_rect.position.y + board_margin + float(cell.y) * step_y
	)


func _world_to_cell(position_value:Vector2) -> Vector2i:
	var usable_w:float = maxf(_map_rect.size.x - board_margin * 2.0,1.0)
	var usable_h:float = maxf(_map_rect.size.y - board_margin * 2.0,1.0)
	var step_x:float = usable_w / float(maxi(_grid_cols - 1,1))
	var step_y:float = usable_h / float(maxi(_grid_rows - 1,1))
	return Vector2i(
		clampi(int(round((position_value.x - (_map_rect.position.x + board_margin)) / maxf(step_x,0.001))),0,_grid_cols - 1),
		clampi(int(round((position_value.y - (_map_rect.position.y + board_margin)) / maxf(step_y,0.001))),0,_grid_rows - 1)
	)


func _in_bounds(cell:Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_cols and cell.y < _grid_rows


func _cell_key(cell:Vector2i) -> String:
	return "%d:%d" % [cell.x,cell.y]


func _board_signature(board_state:Dictionary) -> String:
	var keys:Array = board_state.keys()
	keys.sort()
	var parts:PackedStringArray = PackedStringArray()
	for raw_key in keys:
		var key:String = str(raw_key)
		parts.append("%s=%d" % [key,int(board_state[key])])
	return "|".join(parts)


func _is_enemy(target:ball) -> bool:
	if target == null or target == self or not is_instance_valid(target):
		return false
	if not target.is_combat_targetable():
		return false
	if Team != "" and target.Team != "" and Team == target.Team:
		return false
	return true


func Die() -> void:
	if is_multiplayer_authority():
		_clear_board_synced()
	super()


func _exit_tree() -> void:
	# 远端也清本地视觉，防止角色被直接释放时残留棋子。
	for key in _stone_nodes.keys():
		var node = _stone_nodes[key]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_stone_nodes.clear()
	_board.clear()
