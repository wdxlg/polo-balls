extends Node2D

# 独立挂在 World 下，因此“呼叫确认后”即使原保安死亡，这个节点仍会继续倒计时并生成增援。
var Team:String = ""
var guard_scene:PackedScene = null
var arrival_delay:float = 1.8
var car_drive_time:float = 0.95
var max_team_count:int = 10
const HARD_MAX_TEAM_COUNT:int = 10
var spawn_map_margin:float = 24.0
var spawn_position:Vector2 = Vector2.ZERO
var disembark_distance:float = 24.0


# Confirmed arrivals survive their caller, but not reset or round retirement.
var _battle_spawn_ticket:int = 0
var _lifecycle_world:Node = null
func bind_battle_source(source:ball) -> void:
	_lifecycle_world = source.get_tree().current_scene
	_battle_spawn_ticket = _lifecycle_world.begin_battle_spawn(source,self)
func _exit_tree() -> void:
	if _battle_spawn_ticket > 0 and is_instance_valid(_lifecycle_world):
		_lifecycle_world.finish_battle_spawn(_battle_spawn_ticket)
	_battle_spawn_ticket = 0

func _ready() -> void:
	add_to_group("GuardReinforcementRequest")
	call_deferred("_wait_and_arrive")


func _wait_and_arrive() -> void:
	# arrival_delay 是“总部确认后车多久出现”，car_drive_time 是巡逻车真正开到呼叫点的时间。
	# 新保安在车抵达呼叫者当时位置的瞬间下车。
	await get_tree().create_timer(maxf(arrival_delay + car_drive_time,0.05)).timeout
	if not is_inside_tree() or guard_scene == null:
		queue_free()
		return

	# 请求本身已经占了一个“在路上”的名额；抵达时只检查活人是否被手动放置挤满。
	if _count_live_team_guards() >= mini(maxi(max_team_count,1),HARD_MAX_TEAM_COUNT):
		queue_free()
		return

	var guard:ball = guard_scene.instantiate() as ball
	if guard == null:
		queue_free()
		return
	if _battle_spawn_ticket > 0 and (not is_instance_valid(_lifecycle_world) or not _lifecycle_world.apply_battle_spawn_identity(guard,_battle_spawn_ticket)):
		guard.free()
		queue_free()
		return
	guard.set("spawn_initial_squad",false)
	# 增援必须继承已经确认的保安队伍（包括无队伍模式生成的隐藏小队 ID）。
	var reinforcement_team:String = Team
	guard.Team = reinforcement_team

	var stop_position:Vector2 = _clamp_point_to_map(spawn_position,spawn_map_margin)
	var exit_dir:Vector2 = _choose_disembark_direction(stop_position)
	var exit_position:Vector2 = _clamp_point_to_map(
		stop_position + exit_dir * maxf(disembark_distance,8.0),
		spawn_map_margin
	)

	# 下车时先出现在车身位置，再向车旁走一小段；巡逻车本身没有碰撞。
	guard.direction = exit_dir
	guard.name = Game.return_random_name(guard)
	get_tree().current_scene.add_child(guard,true)
	# 入树后再确认一次，避免任何初始化逻辑把增援恢复成 ball.tscn 的默认 Team。
	guard.Team = reinforcement_team
	guard.global_position = stop_position
	guard.modulate.a = 0.12

	var tween:Tween = guard.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(guard,"global_position",exit_position,0.24)
	tween.tween_property(guard,"modulate:a",1.0,0.18)

	queue_free()


func _choose_disembark_direction(stop_position:Vector2) -> Vector2:
	var rect:Rect2 = _get_map_rect()
	# 车从左右边缘横向驶入，因此让保安从车的上下侧下车，避免和车行进方向重叠。
	if rect.size.x > 1.0 and rect.size.y > 1.0:
		var up_space:float = stop_position.y - rect.position.y
		var down_space:float = rect.end.y - stop_position.y
		return Vector2.DOWN if down_space >= up_space else Vector2.UP
	return Vector2.DOWN


func _count_live_team_guards() -> int:
	var count:int = 0
	for node:Node in get_tree().get_nodes_in_group("SecurityGuard"):
		if not node is ball:
			continue
		var guard:ball = node as ball
		if guard.Team == Team and guard.health > 0:
			count += 1
	return count


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
