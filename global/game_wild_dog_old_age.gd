extends RefCounted
## 野生狗奶“老死”残骸结算（非 RPC 部分）
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node


func _init(game: Node) -> void:
	_game = game


const WILD_DOG_OLD_AGE_REMAINS_SCENE:PackedScene = preload("res://scenes/effects/野生狗奶老死残骸.tscn")

const WILD_DOG_OLD_AGE_DEADLINE_META:StringName = &"wild_dog_milk_old_age_death_deadline_msec"

const WILD_DOG_OLD_AGE_HEALTH_META:StringName = &"wild_dog_milk_old_age_death_health_before"

const WILD_DOG_OLD_AGE_AUDIO_PLAYED_META:StringName = &"wild_dog_milk_old_age_death_audio_played"

const WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD:float = 36.0

const WILD_DOG_OLD_AGE_MIN_SIZE_MULTIPLIER:float = 0.90

const WILD_DOG_OLD_AGE_REMAINS_CONTAINER_NAME:StringName = &"野生狗奶老死残骸容器"


func _play_wild_dog_old_age_death_audio(victim:Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	victim.set_meta(WILD_DOG_OLD_AGE_AUDIO_PLAYED_META,true)
	var unique_stream:Variant = victim.get("Unique_Death_Audio")
	if unique_stream is AudioStream and unique_stream != null and victim.has_method("play_unique_audio"):
		# ball.Character_Audio_Slot.Death == 5
		victim.call("play_unique_audio",5,true)
		return
	var dead_audio_name:String = str(victim.get("Dead_Audio"))
	if not dead_audio_name.is_empty():
		Audios.play_sfx(dead_audio_name,{},true)


func _is_wild_dog_old_age_death(victim:Node,killer:Node,health_before_lethal:float) -> bool:
	if victim == null or killer == null or not is_instance_valid(victim) or not is_instance_valid(killer):
		return false
	if not killer.is_in_group("WildDogMilkCharacter"):
		return false
	if not victim.has_meta(WILD_DOG_OLD_AGE_DEADLINE_META) or not victim.has_meta(WILD_DOG_OLD_AGE_HEALTH_META):
		return false
	var deadline_msec:int = int(victim.get_meta(WILD_DOG_OLD_AGE_DEADLINE_META,0))
	if deadline_msec <= 0 or Time.get_ticks_msec() > deadline_msec:
		return false
	var marked_health_before:float = float(victim.get_meta(WILD_DOG_OLD_AGE_HEALTH_META,-INF))
	return absf(marked_health_before - maxf(health_before_lethal,0.0)) <= 1.1


func _clear_wild_dog_old_age_marker(victim:Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if victim.has_meta(WILD_DOG_OLD_AGE_DEADLINE_META):
		victim.remove_meta(WILD_DOG_OLD_AGE_DEADLINE_META)
	if victim.has_meta(WILD_DOG_OLD_AGE_HEALTH_META):
		victim.remove_meta(WILD_DOG_OLD_AGE_HEALTH_META)


func _spawn_wild_dog_old_age_remains(victim:Node) -> void:
	if victim == null or not is_instance_valid(victim) or not (victim is Node2D):
		return
	var origin:Vector2 = (victim as Node2D).global_position
	var seed_value:int = Game.battle_rng_seed_or("global/game.gd:seed_value",int(Time.get_ticks_usec()) ^ int(victim.get_instance_id()))
	var victim_body_width:float = _resolve_character_body_collision_world_width(victim)
	var remains_size_multiplier:float = maxf(
		victim_body_width / maxf(WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD,0.001),
		WILD_DOG_OLD_AGE_MIN_SIZE_MULTIPLIER
	)
	if _game.multiplayer.has_multiplayer_peer():
		_game._rpc_spawn_wild_dog_old_age_remains.rpc(origin,seed_value,remains_size_multiplier)
	else:
		_game._rpc_spawn_wild_dog_old_age_remains(origin,seed_value,remains_size_multiplier)


func _resolve_character_body_collision_world_width(victim:Node) -> float:
	# V281：骨架实际尺寸只看人物“本体” CollisionShape2D 的横向世界宽度。
	# 用 Shape2D.get_rect() 的四个角经过 CollisionShape2D 全局变换后的 X 包围宽度，
	# 因此会自动包含角色根 scale / collision node scale / rotation 等真实变换。
	if victim == null or not is_instance_valid(victim):
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	var body_collision:CollisionShape2D = victim.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_collision == null or not is_instance_valid(body_collision) or body_collision.shape == null:
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	var local_rect:Rect2 = body_collision.shape.get_rect()
	if local_rect.size.x <= 0.001:
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	var local_corners:Array[Vector2] = [
		local_rect.position,
		Vector2(local_rect.end.x,local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x,local_rect.end.y)
	]
	var min_x:float = INF
	var max_x:float = -INF
	for local_point:Vector2 in local_corners:
		var world_point:Vector2 = body_collision.to_global(local_point)
		min_x = minf(min_x,world_point.x)
		max_x = maxf(max_x,world_point.x)
	var world_width:float = max_x - min_x
	if not is_finite(world_width) or world_width <= 0.001:
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	return world_width


func _ensure_wild_dog_old_age_remains_container(scene_root:Node) -> Node:
	# V309：World 根节点是 MultiplayerSpawner.spawn_path。老死残骸已经由本函数的 RPC 在各 peer
	# 使用同一 seed/size 手动创建，不能再作为 World 的直接子节点触发一次自动 Spawn。
	# 放进稳定的二级运行时容器后，残骸不再属于 spawn_path 的“直接子节点”；同时所有 add_child
	# 都使用 force_readable_name=true，避免同名节点被 Godot 改成 @StaticBody2D@xxxx 保留名称。
	if scene_root == null or not is_instance_valid(scene_root):
		return null
	var existing:Node = scene_root.get_node_or_null(NodePath(str(WILD_DOG_OLD_AGE_REMAINS_CONTAINER_NAME)))
	if existing != null and is_instance_valid(existing):
		return existing
	var container := Node2D.new()
	container.name = WILD_DOG_OLD_AGE_REMAINS_CONTAINER_NAME
	scene_root.add_child(container,true)
	return container
