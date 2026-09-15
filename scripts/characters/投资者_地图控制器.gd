extends Node

const STOCK_BAR_SCRIPT = preload("res://scripts/characters/投资者_柱.gd")

var investor_ref:WeakRef
var investor_instance_id:int = 0

# 下面参数由投资者角色在创建控制器时复制进来。
var column_interval:float = 1.35
var grow_duration:float = 0.30
var scroll_duration:float = 0.24
var min_columns:int = 3
var max_columns:int = 10
var preferred_column_width_by_actor:float = 0.75
var bar_width_ratio_min:float = 0.62
var bar_width_ratio_max:float = 0.88
var map_inner_padding_ratio:float = 0.012
var minimum_open_space_ratio:float = 0.26
var actor_clearance_multiplier:float = 1.12

var green_height_fraction_min:float = 0.58
var green_height_fraction_max:float = 0.95
var red_height_fraction_min:float = 0.12
var red_height_fraction_max:float = 0.48

var green_damage_multiplier_at_low_bar:float = 3.4
var green_damage_multiplier_at_high_bar:float = 1.0
var red_damage_multiplier_at_low_bar:float = 9.2
var red_damage_multiplier_at_high_bar:float = 5.4

var green_color:Color = Color(0.15,0.78,0.28,0.88)
var red_color:Color = Color(0.95,0.18,0.18,0.88)

var _bars:Array[AnimatableBody2D] = []
var _map_rect:Rect2 = Rect2()
var _inner_rect:Rect2 = Rect2()
var _map_name:String = ""
var _column_count:int = 0
var _column_step:float = 1.0
var _created_columns:int = 0
var _running:bool = false
var _shutting_down:bool = false
var _bar_serial:int = 0


func _ready() -> void:
	if is_multiplayer_authority():
		call_deferred("_run_market")


func _process(_delta:float) -> void:
	# V43：菜月昴类时间回溯可能把已进入死亡的投资者恢复成存活状态。
	# 死亡时我们会先清柱并暂停控制器；如果同一实例又恢复健康，则重新启动行情。
	if not _shutting_down or not is_multiplayer_authority() or _running:
		return
	var investor:=_get_investor()
	if investor==null or investor.health<=0:
		return
	if investor.state_machine!=null and investor.state_machine.current_state==ball.State.Die:
		return
	_shutting_down=false
	call_deferred("_run_market")


func shutdown_market(broadcast_cleanup:bool=true) -> void:
	_shutting_down=true
	if broadcast_cleanup and is_multiplayer_authority():
		_cleanup_all_bars()
	else:
		_cleanup_all_bars_local()


func _exit_tree() -> void:
	# 控制器是投资者子节点，而柱子在 World 下；父节点离树时不能依赖协程尾部清理。
	_shutting_down=true
	_running=false
	_cleanup_all_bars_local()


func _run_market() -> void:
	if _running or _shutting_down:
		return
	_running = true

	await get_tree().physics_frame

	while not _shutting_down:
		var investor := _get_investor()
		if investor == null:
			break
		if investor.health <= 0:
			break
		if investor.state_machine and investor.state_machine.current_state == ball.State.Die:
			break

		# 行情属于持续战斗机制。布阵、暂停和特殊模式开场阶段不生成/滚动新行情。
		if not investor.is_combat_runtime_active():
			await get_tree().process_frame
			continue

		if _shutting_down:
			break

		if not _refresh_map_geometry_if_needed():
			if not (await investor.wait_for_combat_time(0.25)):
				break
			continue

		var spawn_x:float
		if _created_columns < _column_count:
			spawn_x = _inner_rect.position.x + _column_step * (float(_created_columns) + 0.5)
			_created_columns += 1
		else:
			await _scroll_all_left()
			_cleanup_bars_outside_left()
			spawn_x = _inner_rect.end.x - _column_step * 0.5

		if _get_investor() == null:
			break

		await _create_next_bar(spawn_x)
		if _shutting_down:
			break
		if not (await investor.wait_for_combat_time(maxf(column_interval,0.05))):
			break

	# 正常结束（投资者真正死亡/离场）和 shutdown 都必须清理。
	if is_inside_tree():
		if is_multiplayer_authority():
			_cleanup_all_bars()
		else:
			_cleanup_all_bars_local()
	_running=false

	# 若投资者只是被时间回溯从死亡状态救回，保留控制器，由 _process 重新启动。
	# 真正离场时父节点的 _exit_tree 会负责释放本控制器。


func _get_investor() -> ball:
	if investor_ref == null:
		return null
	var value = investor_ref.get_ref()
	if value == null or not is_instance_valid(value) or not (value is ball):
		return null
	return value as ball


func _refresh_map_geometry_if_needed() -> bool:
	var world = get_tree().current_scene
	if world == null:
		return false
	if not world.has_method("return_map_world_rect"):
		return false
	var current_map_name:String = str(world.now_choose_map)
	if not world.map_group.has(current_map_name):
		return false

	var map_node = world.map_group[current_map_name]
	if not map_node is TileMapLayer:
		return false

	var new_map_rect:Rect2 = world.return_map_world_rect(map_node)
	if new_map_rect.size.x <= 1.0 or new_map_rect.size.y <= 1.0:
		return false

	if current_map_name == _map_name and new_map_rect == _map_rect:
		return true

	# 地图真的换了才重建；普通比赛中这里通常只执行一次。
	_cleanup_all_bars()
	_map_name = current_map_name
	_map_rect = new_map_rect

	var padding:float = maxf(
		1.0,
		minf(_map_rect.size.x,_map_rect.size.y) * map_inner_padding_ratio
	)
	var inner_size:Vector2 = _map_rect.size - Vector2(padding * 2.0,padding * 2.0)
	inner_size.x = maxf(inner_size.x,1.0)
	inner_size.y = maxf(inner_size.y,1.0)
	_inner_rect = Rect2(_map_rect.position + Vector2(padding,padding),inner_size)

	var max_actor_width:float = _estimate_largest_actor_width()
	var preferred_step:float = maxf(max_actor_width * preferred_column_width_by_actor,4.0)
	_column_count = clampi(
		int(round(_inner_rect.size.x / preferred_step)),
		maxi(min_columns,1),
		maxi(max_columns,maxi(min_columns,1))
	)
	_column_step = _inner_rect.size.x / float(maxi(_column_count,1))
	_created_columns = 0
	return true


func _estimate_largest_actor_width() -> float:
	var max_width:float = 12.0
	for node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var b:ball = node as ball
		if b.Type != ball.Ball_Type.Ball:
			continue
		var shape_node:CollisionShape2D = b.collision_shape_2d
		if shape_node == null or shape_node.shape == null:
			continue

		var local_width:float = 12.0
		if shape_node.shape is RectangleShape2D:
			local_width = (shape_node.shape as RectangleShape2D).size.x
		elif shape_node.shape is CircleShape2D:
			local_width = (shape_node.shape as CircleShape2D).radius * 2.0
		elif shape_node.shape is CapsuleShape2D:
			local_width = (shape_node.shape as CapsuleShape2D).radius * 2.0

		var raw_scale:Vector2 = shape_node.global_transform.get_scale()
		var world_scale:Vector2 = Vector2(absf(raw_scale.x),absf(raw_scale.y))
		max_width = maxf(max_width,local_width * world_scale.x)
	return max_width


func _estimate_largest_actor_height() -> float:
	var max_height:float = 12.0
	for node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var b:ball = node as ball
		if b.Type != ball.Ball_Type.Ball:
			continue
		var shape_node:CollisionShape2D = b.collision_shape_2d
		if shape_node == null or shape_node.shape == null:
			continue

		var local_height:float = 12.0
		if shape_node.shape is RectangleShape2D:
			local_height = (shape_node.shape as RectangleShape2D).size.y
		elif shape_node.shape is CircleShape2D:
			local_height = (shape_node.shape as CircleShape2D).radius * 2.0
		elif shape_node.shape is CapsuleShape2D:
			local_height = (shape_node.shape as CapsuleShape2D).height

		var raw_scale:Vector2 = shape_node.global_transform.get_scale()
		var world_scale:Vector2 = Vector2(absf(raw_scale.x),absf(raw_scale.y))
		max_height = maxf(max_height,local_height * world_scale.y)
	return max_height


func _get_safe_bar_height_range() -> Vector2:
	var actor_height:float = _estimate_largest_actor_height()
	var minimum_open_space:float = maxf(
		_inner_rect.size.y * minimum_open_space_ratio,
		actor_height * actor_clearance_multiplier
	)

	# 无论地图多小，都尽量给角色留下至少一条可活动通道。
	var safe_max_height:float = maxf(_inner_rect.size.y - minimum_open_space,0.5)
	var minimum_bar_height:float = minf(
		maxf(_inner_rect.size.y * 0.06,0.5),
		safe_max_height
	)
	return Vector2(minimum_bar_height,safe_max_height)


func _create_next_bar(spawn_x:float) -> void:
	var investor := _get_investor()
	if investor == null:
		return

	var height_range:Vector2 = _get_safe_bar_height_range()
	var min_h:float = minf(height_range.x,height_range.y)
	var max_h:float = maxf(height_range.x,height_range.y)
	var is_green:bool = randf() < 0.5

	var frac_min:float
	var frac_max:float
	if is_green:
		frac_min = green_height_fraction_min
		frac_max = green_height_fraction_max
	else:
		frac_min = red_height_fraction_min
		frac_max = red_height_fraction_max

	var fraction:float = randf_range(minf(frac_min,frac_max),maxf(frac_min,frac_max))
	var height:float = lerpf(min_h,max_h,clampf(fraction,0.0,1.0))
	var normalized_height:float = 0.0
	if max_h > min_h + 0.001:
		normalized_height = clampf((height - min_h) / (max_h - min_h),0.0,1.0)

	var new_damage_multiplier:float
	var color:Color
	if is_green:
		# 绿色：柱越高，限制空间越大，投资者伤害越低。
		new_damage_multiplier = lerpf(green_damage_multiplier_at_low_bar,green_damage_multiplier_at_high_bar,normalized_height)
		color = green_color
	else:
		# 红色：柱越低，给敌人的空间越大，投资者伤害越高。
		new_damage_multiplier = lerpf(red_damage_multiplier_at_low_bar,red_damage_multiplier_at_high_bar,normalized_height)
		color = red_color

	if investor.has_method("set_market_damage_multiplier"):
		investor.call("set_market_damage_multiplier",new_damage_multiplier,is_green,normalized_height)
	else:
		# 旧脚本回退：不再直接改写 Damage，避免破坏整体攻击力语义。
		pass

	var width_ratio:float = randf_range(
		minf(bar_width_ratio_min,bar_width_ratio_max),
		maxf(bar_width_ratio_min,bar_width_ratio_max)
	)
	var width:float = maxf(_column_step * clampf(width_ratio,0.15,0.98),0.5)

	_bar_serial += 1
	var serial:int = _bar_serial
	var bar:AnimatableBody2D = _spawn_bar_local(serial,spawn_x,_inner_rect.end.y,width,height,color,false)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_bar.rpc(serial,spawn_x,_inner_rect.end.y,width,height,color)
	if bar != null:
		await bar.grow_from_bottom(maxf(grow_duration,0.0))


@rpc("authority","call_remote","reliable")
func _rpc_spawn_bar(serial:int,spawn_x:float,bottom_y:float,width:float,height:float,color:Color) -> void:
	_spawn_bar_local(serial,spawn_x,bottom_y,width,height,color,true)


func _spawn_bar_local(serial:int,spawn_x:float,bottom_y:float,width:float,height:float,color:Color,visual_only:bool) -> AnimatableBody2D:
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var bar = STOCK_BAR_SCRIPT.new()
	bar.name = "InvestorStockBar_%d" % serial
	bar.configure(width,height,color,visual_only)
	world.add_child(bar)
	bar.add_to_group("InvestorStockBar")
	bar.set_meta("investor_owner_id",investor_instance_id)
	bar.global_position = Vector2(spawn_x,bottom_y)
	_bars.append(bar)
	if visual_only:
		bar.grow_from_bottom(maxf(grow_duration,0.0))
	return bar


func _scroll_all_left() -> void:
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_rpc_scroll_bars.rpc(_column_step,scroll_duration)
	var live_bars:Array[AnimatableBody2D] = []
	for bar in _bars:
		if bar != null and is_instance_valid(bar):
			live_bars.append(bar)

	if live_bars.is_empty():
		return

	if scroll_duration <= 0.0:
		for bar in live_bars:
			bar.position.x -= _column_step
		return

	var tween := create_tween().bind_node(self)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)

	for bar in live_bars:
		tween.tween_property(
			bar,
			"position:x",
			bar.position.x - _column_step,
			maxf(scroll_duration,0.01)
		)

	await tween.finished


@rpc("authority","call_remote","reliable")
func _rpc_scroll_bars(step:float,duration:float) -> void:
	var live_bars:Array[AnimatableBody2D] = []
	for bar in _bars:
		if bar != null and is_instance_valid(bar):
			live_bars.append(bar)
	if live_bars.is_empty():
		return
	if duration <= 0.0:
		for bar in live_bars:
			bar.position.x -= step
		return
	var tween := create_tween().bind_node(self)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_parallel(true)
	for bar in live_bars:
		tween.tween_property(bar,"position:x",bar.position.x-step,maxf(duration,0.01)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _cleanup_bars_outside_left() -> void:
	var kept:Array[AnimatableBody2D] = []
	var left_limit:float = _inner_rect.position.x - _column_step * 0.55
	for bar in _bars:
		if bar == null or not is_instance_valid(bar):
			continue
		if bar.global_position.x < left_limit:
			bar.queue_free()
		else:
			kept.append(bar)
	_bars = kept
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_rpc_cleanup_bars_left.rpc(left_limit)


@rpc("authority","call_remote","reliable")
func _rpc_cleanup_bars_left(left_limit:float) -> void:
	var kept:Array[AnimatableBody2D] = []
	for bar in _bars:
		if bar == null or not is_instance_valid(bar):
			continue
		if bar.global_position.x < left_limit:
			bar.queue_free()
		else:
			kept.append(bar)
	_bars = kept


func _cleanup_all_bars() -> void:
	_cleanup_all_bars_local()
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_rpc_cleanup_all_bars.rpc()


@rpc("authority","call_remote","reliable")
func _rpc_cleanup_all_bars() -> void:
	_cleanup_all_bars_local()


func _cleanup_all_bars_local() -> void:
	var seen:Dictionary = {}
	for bar in _bars:
		if bar == null or not is_instance_valid(bar):
			continue
		var instance_id:int = bar.get_instance_id()
		seen[instance_id] = true
		if not bar.is_queued_for_deletion():
			bar.queue_free()
	_bars.clear()

	# V43：列表可能因为 Reset、RPC、死亡回溯的时序与实际 World 子节点短暂失步。
	# 再按 owner id 扫一次专用组，确保属于本投资者的孤儿长条也能被清掉。
	if get_tree() == null:
		return
	for node:Node in get_tree().get_nodes_in_group("InvestorStockBar"):
		if node == null or not is_instance_valid(node):
			continue
		if int(node.get_meta("investor_owner_id",-1)) != investor_instance_id:
			continue
		var instance_id:int = node.get_instance_id()
		if seen.has(instance_id):
			continue
		if not node.is_queued_for_deletion():
			node.queue_free()
