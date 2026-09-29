extends Node

const TABLE_SCENE:PackedScene = preload("res://scenes/terrain/我的世界/锻造台.tscn")
const INGOT_SCENE:PackedScene = preload("res://scenes/effects/我的世界/下界合金锭.tscn")
const INGOT_COOLDOWN:float = 10.0

var _cooldown_left:float = INGOT_COOLDOWN
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "MinecraftNetheriteArenaManager"
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/我的世界/下界合金竞技场.gd:_rng.seed",int(Time.get_ticks_usec()) ^ get_instance_id())
	set_process(true)
	call_deferred("_ensure_table")


func _process(delta:float) -> void:
	if not _is_spawning_authority():
		return
	if not _has_active_diamond_sword():
		_cooldown_left = INGOT_COOLDOWN
		return
	_ensure_table()
	# 任意存活钻石剑一旦已经捡到下界合金锭（或已经完成升级），本轮不再刷新第二枚。
	# 这样锭被捡起 queue_free 后不会重新进入 10 秒刷新循环。
	if _has_claimed_or_upgraded_sword():
		_cooldown_left = INGOT_COOLDOWN
		return
	if _has_ingot_on_field():
		# 只要场上还有锭，刷新冷却就完全不走。
		_cooldown_left = INGOT_COOLDOWN
		return
	if not _combat_runtime_active():
		return
	_cooldown_left -= maxf(delta,0.0)
	if _cooldown_left <= 0.0:
		_spawn_ingot()
		_cooldown_left = INGOT_COOLDOWN


func _is_spawning_authority() -> bool:
	# 单机没有 multiplayer peer 时本机就是玩法 authority；联网时只让服务器刷新。
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _has_active_diamond_sword() -> bool:
	for node:Node in get_tree().get_nodes_in_group("MinecraftDiamondSword"):
		if node is ball and is_instance_valid(node) and (node as ball).health > 0:
			return true
	return false


func _has_claimed_or_upgraded_sword() -> bool:
	for node:Node in get_tree().get_nodes_in_group("MinecraftDiamondSword"):
		if not node is ball or not is_instance_valid(node) or (node as ball).health <= 0:
			continue
		if bool(node.get("has_netherite_ingot")) or bool(node.get("upgraded_to_netherite")):
			return true
	return false


func _combat_runtime_active() -> bool:
	for node:Node in get_tree().get_nodes_in_group("MinecraftDiamondSword"):
		if node is ball and is_instance_valid(node) and (node as ball).health > 0:
			return (node as ball).is_combat_runtime_active()
	return false


func _has_ingot_on_field() -> bool:
	for node:Node in get_tree().get_nodes_in_group("MinecraftNetheriteIngot"):
		if node != null and is_instance_valid(node) and not node.is_queued_for_deletion():
			return true
	return false


func _ensure_table() -> void:
	if not _is_spawning_authority() or get_tree() == null or get_tree().current_scene == null:
		return
	if get_tree().current_scene.get_meta("mc_smithing_table_destroyed",false): return
	var rect:Rect2 = _map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		# 地图数据还没准备好时不要拿 (0,0) 当“中间”。下一帧继续等真正地图范围。
		return
	var center:Vector2 = rect.get_center()
	for node:Node in get_tree().get_nodes_in_group("MinecraftSmithingTable"):
		if node is Node2D and is_instance_valid(node) and not node.is_queued_for_deletion():
			# 地图切换或旧版本曾把锻造台生在错误位置时，也会自动校正回当前地图正中心。
			(node as Node2D).global_position = center
			return
	var table:StaticBody2D = TABLE_SCENE.instantiate() as StaticBody2D
	if table == null:
		return
	get_tree().current_scene.add_child(table,true)
	table.global_position = center


func _spawn_ingot() -> void:
	if get_tree() == null or get_tree().current_scene == null or _has_ingot_on_field():
		return
	var rect:Rect2 = _map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var safe:Rect2 = rect.grow(-38.0)
	if safe.size.x <= 1.0 or safe.size.y <= 1.0:
		safe = rect
	var center:Vector2 = rect.get_center()
	var pos:Vector2 = center
	for _try:int in range(20):
		pos = Vector2(_rng.randf_range(safe.position.x,safe.end.x),_rng.randf_range(safe.position.y,safe.end.y))
		if pos.distance_to(center) >= 55.0:
			break
	var ingot:Area2D = INGOT_SCENE.instantiate() as Area2D
	if ingot == null:
		return
	get_tree().current_scene.add_child(ingot,true)
	ingot.global_position = pos


func _map_rect() -> Rect2:
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()

	# world.gd 的 map_group 实际是 Dictionary，键是 now_choose_map 的地图名。
	# 旧实现把它当 Array 用整数索引，因此永远走到 (0,0) 兜底，锻造台自然不在地图中心。
	var maps:Variant = world.get("map_group")
	var current_key:Variant = world.get("now_choose_map")
	var map_node:Variant = null
	if maps is Dictionary:
		var dict:Dictionary = maps as Dictionary
		if dict.has(current_key):
			map_node = dict[current_key]
	elif maps is Array:
		# 保留兼容：如果以后项目把 map_group 改回数组，仍可按整数索引读取。
		var index:int = int(current_key)
		if index >= 0 and index < (maps as Array).size():
			map_node = (maps as Array)[index]

	if map_node is TileMapLayer:
		var rect_value:Variant = world.call("return_map_world_rect",map_node as TileMapLayer)
		if typeof(rect_value) == TYPE_RECT2:
			return rect_value
	return Rect2()
