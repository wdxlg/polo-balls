extends Node2D

# 蠹虫专属“被虫蚀的石砖背景”。
# 该节点直接挂在 World 下，是纯视觉层：只读取当前 TileMapLayer 的格子范围与坐标，不改变原地图墙体/碰撞。
# 逻辑状态只记录被触发过的格子；V147 用 8x8 渲染块缓存底图，50x50 地图约 49 个轻量 CanvasItem，而不是 2500 个逐格 Node。

const STONE_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/蠹虫/石砖.png")
const CRACKED_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/蠹虫/裂纹石砖.png")
const BREAK_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")
const STONE_RENDER_CHUNK_SCRIPT:Script = preload("res://scripts/effects/我的世界/蠹虫石砖渲染块.gd")

const STONE_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/蠹虫/石砖1.ogg"),
	preload("res://audio/characters/我的世界/蠹虫/石砖2.ogg"),
	preload("res://audio/characters/我的世界/蠹虫/石砖3.ogg"),
	preload("res://audio/characters/我的世界/蠹虫/石砖4.ogg"),
]

const SILVERFISH_SCENE_PATH:String = "res://scenes/characters/我的世界/蠹虫.tscn"
const FIELD_GROUP:StringName = &"MinecraftSilverfishStoneField"
const SILVERFISH_GROUP:StringName = &"MinecraftSilverfish"
const SOURCE_TILE_SIZE:Vector2i = Vector2i(16,16)
const MAX_ACTIVE_SILVERFISH:int = 10
const SHAKE_DURATION:float = 0.18
# World 根最终 Z=-2；项目自由血液使用 relative z=-2，因此血液最终约 Z=-4。
# 石砖必须在血液下面，同时仍盖住最终 Z=-5 的 Background。石砖与 Background 同为 -5，
# 但石砖场是运行时后加入的 World 子节点，同 Z 时按树顺序绘制，因此会盖在 Background 上。
const STONE_RENDER_Z:int = -5
# V147：石砖底图按块缓存绘制。单格变化只重画对应块，不再重画整张地图。
const STONE_RENDER_CHUNK_SIZE:int = 8

enum StoneState {
	INTACT,
	CRACKED,
	BROKEN,
}

var _world:Node = null
var _map_layer:TileMapLayer = null
# 石砖场所属的地图节点：普通 TileMapLayer，或包含多座岛的 PortalMap（此时 _map_layer 只是坐标基准岛）。
var _map_node:Node = null
# 实际有地板的格子（以 _map_layer 的格坐标表示）。非矩形地图 / 多岛传送门地图只在这些格子上铺石砖。
var _stone_cells:Dictionary = {}
var _used_rect:Rect2i = Rect2i()
var _tile_states:Dictionary = {}
var _transition_sprites:Dictionary = {}
var _owner_ids:Dictionary = {}
var _cleanup_generation:int = 0
var _pending_spawn_count:int = 0
var _render_chunks:Dictionary = {}
var _inner_shadow:Node2D
var _inner_shadow_update_pending:bool = false


func setup(world:Node,map_node:Node) -> void:
	if _map_layer != null and is_instance_valid(_map_layer):
		return
	_world = world
	_map_node = map_node
	_map_layer = _resolve_reference_layer(map_node)
	name = "蠹虫石砖场"
	# V82：石砖场仍直接挂在 World，避开隐藏 TileMapLayer。
	# 绝对 Z 改为 -5：与 Background 最终层级相同但运行时后加入，因此仍显示在背景之上；
	# 项目自由血液最终约 Z=-4，所以血液会稳定绘制在石砖之上；人物最终约 Z=-2，仍在最上。
	z_as_relative = false
	z_index = STONE_RENDER_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = true
	add_to_group(FIELD_GROUP)

	if _map_layer == null or not is_instance_valid(_map_layer) or _map_layer.tile_set == null:
		return

	_collect_stone_cells()
	if _used_rect.size.x <= 0 or _used_rect.size.y <= 0:
		return
	_rebuild_render_chunks()
	# 墙脚阴影由World统一向地图内部绘制；石砖场不再向外围木墙投影。
	# 此处只保留地图范围内的石砖缺口阴影，避免边界重复叠黑。
	_inner_shadow = load("res://scripts/effects/我的世界/石砖缺口阴影.gd").new()
	_inner_shadow.name = "StoneGapShadow"
	add_child(_inner_shadow)
	move_child(_inner_shadow,0)
	_inner_shadow.configure(_stone_footprint_rect(),_used_rect)
	_flush_inner_shadow()


func is_for_map(map_node:Node) -> bool:
	if _map_node == null or not is_instance_valid(_map_node):
		return false
	return _map_node == map_node or _map_layer == map_node


static func _resolve_reference_layer(map_node:Node) -> TileMapLayer:
	if map_node is TileMapLayer:
		return map_node as TileMapLayer
	if map_node is PortalMap:
		return (map_node as PortalMap).primary_island()
	return null


func _source_layers() -> Array[TileMapLayer]:
	var layers:Array[TileMapLayer] = []
	if _map_node is PortalMap:
		for entry:Dictionary in (_map_node as PortalMap).island_entries():
			var layer:TileMapLayer = entry.get("layer") as TileMapLayer
			if layer != null and is_instance_valid(layer) and layer.tile_set != null:
				layers.append(layer)
	elif _map_layer != null and is_instance_valid(_map_layer):
		layers.append(_map_layer)
	return layers


func _collect_stone_cells() -> void:
	# 把每座岛实际画过的格子换算到基准岛的格坐标；PortalMap 各岛一般同尺寸且按整格摆放。
	_stone_cells.clear()
	var first:bool = true
	var min_cell:Vector2i = Vector2i.ZERO
	var max_cell:Vector2i = Vector2i.ZERO
	for layer:TileMapLayer in _source_layers():
		for cell:Vector2i in layer.get_used_cells():
			var coord:Vector2i = cell
			if layer != _map_layer:
				coord = _map_layer.local_to_map(_map_layer.to_local(layer.to_global(layer.map_to_local(cell))))
			_stone_cells[coord] = true
			if first:
				min_cell = coord
				max_cell = coord
				first = false
			else:
				min_cell = min_cell.min(coord)
				max_cell = max_cell.max(coord)
	_used_rect = Rect2i() if first else Rect2i(min_cell,max_cell - min_cell + Vector2i.ONE)


func _stone_footprint_rect() -> Rect2:
	# 缺口阴影的贴图范围 = used_rect 在世界坐标下的外接矩形（按基准岛的变换换算）。
	if _map_node is TileMapLayer and _world != null and _world.has_method("return_map_world_rect"):
		return _world.call("return_map_world_rect",_map_layer)
	var tile_size:Vector2 = Vector2(_map_layer.tile_set.tile_size)
	var local_min:Vector2 = Vector2(_used_rect.position) * tile_size
	var local_max:Vector2 = Vector2(_used_rect.end) * tile_size
	var a:Vector2 = _map_layer.to_global(local_min)
	var b:Vector2 = _map_layer.to_global(local_max)
	return Rect2(a.min(b),(b - a).abs())


func has_stone_cell(coord:Vector2i) -> bool:
	return _stone_cells.has(coord)


func _coord_world_position(coord:Vector2i) -> Vector2:
	if _map_layer == null or not is_instance_valid(_map_layer):
		return global_position
	return _map_layer.to_global(_map_layer.map_to_local(coord))


func _coord_local_position(coord:Vector2i) -> Vector2:
	return to_local(_coord_world_position(coord))


func _draw() -> void:
	# V147：石砖底图已经交给 8x8 渲染块。父节点本身不再提交整张地图的绘制命令，
	# 否则任意一块砖 queue_redraw() 都会重新遍历整个 used_rect。
	pass


func _rebuild_render_chunks() -> void:
	for raw_chunk:Variant in _render_chunks.values():
		if raw_chunk is Node and is_instance_valid(raw_chunk):
			(raw_chunk as Node).queue_free()
	_render_chunks.clear()

	if (
		_map_layer == null
		or not is_instance_valid(_map_layer)
		or _map_layer.tile_set == null
		or _used_rect.size.x <= 0
		or _used_rect.size.y <= 0
	):
		return

	var chunk_size:int = maxi(STONE_RENDER_CHUNK_SIZE,1)
	var chunk_count_x:int = ceili(float(_used_rect.size.x) / float(chunk_size))
	var chunk_count_y:int = ceili(float(_used_rect.size.y) / float(chunk_size))

	for chunk_y:int in range(chunk_count_y):
		for chunk_x:int in range(chunk_count_x):
			var start:=Vector2i(
				_used_rect.position.x + chunk_x * chunk_size,
				_used_rect.position.y + chunk_y * chunk_size
			)
			var finish:=Vector2i(
				mini(start.x + chunk_size,_used_rect.end.x),
				mini(start.y + chunk_size,_used_rect.end.y)
			)
			var chunk_rect:=Rect2i(start,finish - start)
			var chunk:Node2D = STONE_RENDER_CHUNK_SCRIPT.new() as Node2D
			if chunk == null:
				continue
			chunk.name = "石砖渲染块_%d_%d" % [chunk_x,chunk_y]
			add_child(chunk)
			chunk.call("setup",self,_map_layer,chunk_rect,STONE_TEXTURE,CRACKED_TEXTURE,_stone_cells)
			_render_chunks[Vector2i(chunk_x,chunk_y)] = chunk


func _render_chunk_key_for_coord(coord:Vector2i) -> Vector2i:
	var local_coord:Vector2i = coord - _used_rect.position
	var chunk_size:int = maxi(STONE_RENDER_CHUNK_SIZE,1)
	return Vector2i(
		floori(float(local_coord.x) / float(chunk_size)),
		floori(float(local_coord.y) / float(chunk_size))
	)


func _queue_coord_redraw(coord:Vector2i) -> void:
	if not _used_rect.has_point(coord):
		return
	if is_instance_valid(_inner_shadow) and not _inner_shadow_update_pending:
		_inner_shadow_update_pending = true
		call_deferred("_flush_inner_shadow")
	var key:Vector2i = _render_chunk_key_for_coord(coord)
	var raw_chunk:Variant = _render_chunks.get(key,null)
	if raw_chunk is CanvasItem and is_instance_valid(raw_chunk):
		(raw_chunk as CanvasItem).queue_redraw()


func get_remaining_silverfish_slots() -> int:
	return maxi(MAX_ACTIVE_SILVERFISH - _count_active_silverfish() - _pending_spawn_count,0)

func _flush_inner_shadow() -> void:
	_inner_shadow_update_pending = false
	if not is_instance_valid(_inner_shadow):
		return
	# 没有地板的格子（环形走廊中央、岛与岛之间）本来就没有石砖，也要从遮罩里扣掉。
	var states:Dictionary = _tile_states.duplicate()
	for y:int in range(_used_rect.position.y,_used_rect.end.y):
		for x:int in range(_used_rect.position.x,_used_rect.end.x):
			var coord := Vector2i(x,y)
			if not _stone_cells.has(coord) and not states.has(coord):
				states[coord] = StoneState.BROKEN
	_inner_shadow.update_states(states)


func can_stone_react() -> bool:
	return get_remaining_silverfish_slots() > 0


func register_silverfish(instance_id_value:int) -> void:
	_owner_ids[instance_id_value] = true
	_cleanup_generation += 1


func unregister_silverfish(instance_id_value:int) -> void:
	_owner_ids.erase(instance_id_value)
	_cleanup_generation += 1
	if not _owner_ids.is_empty():
		return
	_cleanup_after_delay(_cleanup_generation)


func _cleanup_after_delay(generation:int) -> void:
	# World teardown can unregister its last insect after the field left the tree.
	if not is_inside_tree():
		return
	# 最后一只蠹虫消失后稍等一会再撤掉石砖层；若碎砖又生出新蠹虫，register 会取消本次清理。
	await get_tree().create_timer(2.2).timeout
	if not is_instance_valid(self):
		return
	if generation != _cleanup_generation or not _owner_ids.is_empty():
		return
	queue_free()


func trigger_near(
	world_position:Vector2,
	team:String,
	strong:bool,
	seed_value:int,
	can_spawn:bool = true,
	max_breaks_allowed:int = -1,
	source_name:String = ""
) -> void:
	if _map_layer == null or not is_instance_valid(_map_layer):
		return
	if _used_rect.size.x <= 0 or _used_rect.size.y <= 0:
		return

	# authority 会把触发当下剩余名额一起 RPC 给其它 peer。达到 10 只时整次事件直接停止：
	# 完整石砖不再裂，已有裂纹也不会继续碎。
	var remaining_slots:int = max_breaks_allowed
	if remaining_slots < 0:
		remaining_slots = get_remaining_silverfish_slots()
	if remaining_slots <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(abs(seed_value),1)

	var center_coord:Vector2i = _map_layer.local_to_map(_map_layer.to_local(world_position))
	var radius_cells:int = 5 if strong else 4
	var map_tile_size:Vector2 = Vector2(_map_layer.tile_set.tile_size) if _map_layer.tile_set != null else Vector2(SOURCE_TILE_SIZE)
	var radius_world:float = float(radius_cells) * maxf(map_tile_size.x,map_tile_size.y) * maxf(absf(global_scale.x),absf(global_scale.y))
	var candidates:Array[Vector2i] = []

	for y:int in range(center_coord.y - radius_cells,center_coord.y + radius_cells + 1):
		for x:int in range(center_coord.x - radius_cells,center_coord.x + radius_cells + 1):
			var coord := Vector2i(x,y)
			if not _is_reactive_coord(coord):
				continue
			var tile_world_position:Vector2 = _coord_world_position(coord)
			if tile_world_position.distance_to(world_position) <= radius_world:
				candidates.append(coord)

	_shuffle_coords(candidates,rng)

	var max_changes:int = 5 if strong else 3
	var base_chance:float = 0.46 if strong else 0.30
	var changed:int = 0
	var breaks_started:int = 0

	for coord:Vector2i in candidates:
		if changed >= max_changes:
			break
		var state:int = int(_tile_states.get(coord,StoneState.INTACT))
		if state == StoneState.BROKEN:
			continue

		var chance:float = minf(base_chance + (0.14 if state == StoneState.CRACKED else 0.0),0.90)
		if rng.randf() > chance:
			continue

		var sound_index:int = rng.randi_range(0,STONE_SOUNDS.size() - 1)
		var visual_seed:int = rng.randi()
		if state == StoneState.INTACT:
			_begin_crack(coord,sound_index,visual_seed)
		elif state == StoneState.CRACKED:
			# 当触发开始时只剩 N 个名额，本次最多允许 N 块裂砖进入完全碎裂，
			# 避免 9 只时同一帧多块砖一起先碎后发现只能生成 1 只。
			if breaks_started >= remaining_slots:
				continue
			_begin_break(coord,team,can_spawn,sound_index,visual_seed,source_name)
			breaks_started += 1
		changed += 1


func _is_reactive_coord(coord:Vector2i) -> bool:
	# V83：最外圈也是真实石砖，必须允许完整 -> 裂纹 -> 完全碎裂。
	# 出生安全不再靠“禁止边缘石砖响应”解决，而是在真正孵化时把出生点夹到内侧安全格。
	return _used_rect.has_point(coord) and _stone_cells.has(coord)


func _shuffle_coords(coords:Array[Vector2i],rng:RandomNumberGenerator) -> void:
	for i:int in range(coords.size() - 1,0,-1):
		var j:int = rng.randi_range(0,i)
		var temp:Vector2i = coords[i]
		coords[i] = coords[j]
		coords[j] = temp


func _begin_crack(coord:Vector2i,sound_index:int,visual_seed:int) -> void:
	# 状态必须立即写入，保证同一帧其它蠹虫反应看到的是最新裂纹状态。
	_tile_states[coord] = StoneState.CRACKED
	_queue_coord_redraw(coord)
	_queue_transition_visual({
		"kind": &"crack",
		"coord": coord,
		"sound_index": sound_index,
		"visual_seed": visual_seed,
	})


func _queue_transition_visual(request:Dictionary) -> void:
	# 震动、音效与烟雾在触发当帧开始；孵化仍等待原有 0.18 秒震动。
	_start_transition_visual(request)


func _start_transition_visual(request:Dictionary) -> void:
	var coord:Vector2i = request.get("coord",Vector2i.ZERO)
	var kind:StringName = request.get("kind",&"")
	var sound_index:int = int(request.get("sound_index",0))
	var visual_seed:int = int(request.get("visual_seed",1))
	_clear_old_transition_sprite(coord)

	var sprite:Sprite2D = _make_transition_sprite(coord,CRACKED_TEXTURE)
	_transition_sprites[coord] = sprite
	var event_world_position:Vector2 = _coord_world_position(coord)
	_play_stone_sound(event_world_position,sound_index)

	if kind == &"break":
		# V81：完全碎裂烟雾更大；孵化仍在对应震动结束后发生。
		_play_stone_smoke(event_world_position,0.30)
		_build_shake_tween(
			sprite,
			visual_seed,
			Callable(self,"_finish_break").bind(
				coord,
				sprite,
				str(request.get("team","")),
				bool(request.get("can_spawn",false)),
				visual_seed,
				str(request.get("source_name",""))
			)
		)
	else:
		_play_stone_smoke(event_world_position,0.22)
		_build_shake_tween(
			sprite,
			visual_seed,
			Callable(self,"_finish_crack").bind(coord,sprite)
		)


func _finish_crack(coord:Vector2i,sprite:Sprite2D) -> void:
	if not is_instance_valid(self):
		return
	if is_instance_valid(sprite):
		sprite.queue_free()
	if _transition_sprites.get(coord,null) == sprite:
		_transition_sprites.erase(coord)


func _begin_break(
	coord:Vector2i,
	team:String,
	can_spawn:bool,
	sound_index:int,
	visual_seed:int,
	source_name:String
) -> void:
	_tile_states[coord] = StoneState.BROKEN
	_queue_coord_redraw(coord)
	if can_spawn:
		# authority 仍在触发当帧预占孵化名额，不能因为视觉延迟而突破 10 只硬上限。
		_pending_spawn_count += 1
	_queue_transition_visual({
		"kind": &"break",
		"coord": coord,
		"team": team,
		"can_spawn": can_spawn,
		"sound_index": sound_index,
		"visual_seed": visual_seed,
		"source_name": source_name,
	})


func _finish_break(
	coord:Vector2i,
	sprite:Sprite2D,
	team:String,
	can_spawn:bool,
	spawn_seed:int,
	source_name:String
) -> void:
	if not is_instance_valid(self):
		return
	if is_instance_valid(sprite):
		sprite.queue_free()
	if _transition_sprites.get(coord,null) == sprite:
		_transition_sprites.erase(coord)
	if can_spawn:
		_spawn_silverfish_at(coord,team,spawn_seed,source_name)
		_pending_spawn_count = maxi(_pending_spawn_count - 1,0)


func _clear_old_transition_sprite(coord:Vector2i) -> void:
	var old:Variant = _transition_sprites.get(coord,null)
	if old is Sprite2D and is_instance_valid(old):
		(old as Sprite2D).queue_free()
	_transition_sprites.erase(coord)


func _make_transition_sprite(coord:Vector2i,texture:Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = _coord_local_position(coord)
	# 裂纹/震动临时砖也必须保持在血液 Z=-4 下面，不能因为相对父级 +1 跑到同层。
	sprite.z_as_relative = false
	sprite.z_index = STONE_RENDER_Z
	if _map_layer != null and _map_layer.tile_set != null and texture != null:
		var tile_size:Vector2 = Vector2(_map_layer.tile_set.tile_size)
		var texture_size:Vector2 = texture.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			sprite.scale = Vector2(tile_size.x / texture_size.x,tile_size.y / texture_size.y)
	add_child(sprite)
	return sprite


func _build_shake_tween(sprite:Sprite2D,seed_value:int,finished_callback:Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(abs(seed_value),1)
	var base_position:Vector2 = sprite.position
	var tween:Tween = sprite.create_tween()
	for _step:int in range(6):
		var offset := Vector2(rng.randf_range(-2.0,2.0),rng.randf_range(-2.0,2.0))
		tween.tween_property(sprite,"position",base_position + offset,SHAKE_DURATION / 7.0)
	tween.tween_property(sprite,"position",base_position,SHAKE_DURATION / 7.0)
	tween.tween_callback(finished_callback)


func _play_stone_smoke(world_position:Vector2,scale_value:float) -> void:
	var smoke := AnimatedSprite2D.new()
	smoke.name = "石砖碎裂烟雾"
	smoke.sprite_frames = BREAK_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 5
	smoke.scale = Vector2.ONE * scale_value
	add_child(smoke)
	smoke.global_position = world_position
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)
	smoke.play(&"死亡烟雾")


func _play_stone_sound(world_position:Vector2,sound_index:int) -> void:
	if STONE_SOUNDS.is_empty():
		return
	var index:int = clampi(sound_index,0,STONE_SOUNDS.size() - 1)
	var player := AudioStreamPlayer2D.new()
	player.stream = STONE_SOUNDS[index]
	player.max_distance = 900.0
	player.attenuation = 1.0
	player.volume_db = -1.0
	add_child(player)
	player.global_position = world_position
	player.finished.connect(Callable(player,"queue_free"),CONNECT_ONE_SHOT)
	player.play()


func _source_victory_side_key(source_ball:ball,resolved_team:String) -> String:
	if source_ball != null and is_instance_valid(source_ball):
		if source_ball.has_meta(&"battle_continuation_victory_side_key"):
			var inherited:String = str(source_ball.get_meta(&"battle_continuation_victory_side_key","")).strip_edges()
			if not inherited.is_empty():
				return inherited
		if source_ball.has_meta(&"victory_side_key"):
			var cached:String = str(source_ball.get_meta(&"victory_side_key","")).strip_edges()
			if not cached.is_empty():
				return cached
		var source_team:String = str(source_ball.Team).strip_edges()
		if not source_team.is_empty() and source_team != "Ball":
			return "team:" + source_team
		if source_ball.has_meta(&"battle_setup_id"):
			return "solo_setup:" + str(int(source_ball.get_meta(&"battle_setup_id")))
		return "solo_instance:" + str(source_ball.get_instance_id())
	var fallback_team:String = resolved_team.strip_edges()
	if not fallback_team.is_empty() and fallback_team != "Ball":
		return "team:" + fallback_team
	return ""


func _source_presentation_side_key(source_ball:ball,resolved_team:String) -> String:
	if source_ball != null and is_instance_valid(source_ball):
		if source_ball.has_meta(&"battle_continuation_presentation_side_key"):
			var inherited:String = str(source_ball.get_meta(&"battle_continuation_presentation_side_key","")).strip_edges()
			if not inherited.is_empty():
				return inherited
		var source_team:String = str(source_ball.Team).strip_edges()
		if not source_team.is_empty() and source_team != "Ball":
			return "team:" + source_team
		# 与 world.gd::return_ball_side_key() 的无 Team 主角色规则保持一致。
		return "solo:" + str(source_ball.get_instance_id())
	var fallback_team:String = resolved_team.strip_edges()
	if not fallback_team.is_empty() and fallback_team != "Ball":
		return "team:" + fallback_team
	return ""


func _spawn_silverfish_at(coord:Vector2i,team:String,seed_value:int,source_name:String) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if _count_active_silverfish() >= MAX_ACTIVE_SILVERFISH:
		return

	var resource:Resource = ResourceLoader.load(SILVERFISH_SCENE_PATH,"PackedScene")
	if not (resource is PackedScene):
		push_error("蠹虫石砖场：无法加载 " + SILVERFISH_SCENE_PATH)
		return
	var spawned:Node = (resource as PackedScene).instantiate()
	if not (spawned is ball):
		spawned.free()
		return
	var new_silverfish:ball = spawned as ball

	# 阵营继续使用 Team + forced_combat_team + Master/Master_name 三重保险。
	# V82 额外把“比赛阵营”和“顶部 VS 阵营”在生成前写成稳定 metadata：
	# 原始蠹虫先死亡/queue_free 后，孵化蠹虫仍代表同一方，不能让 VS 提前消失或误响胜利铃。
	var resolved_team:String = team.strip_edges()
	var source:Node = null
	var source_ball:ball = null
	if not source_name.is_empty():
		source = _world.get_node_or_null(NodePath(source_name))
	if source is ball and is_instance_valid(source):
		source_ball = source as ball
		new_silverfish.Master = source_ball
		new_silverfish.Master_name = str(source_ball.name)
		resolved_team = source_ball.Team.strip_edges()
	elif not source_name.is_empty():
		new_silverfish.Master_name = source_name
	if resolved_team.is_empty() or resolved_team == "Ball":
		resolved_team = team.strip_edges()
	new_silverfish.Team = resolved_team
	if not resolved_team.is_empty() and resolved_team != "Ball":
		new_silverfish.set_meta(&"forced_combat_team",resolved_team)

	var victory_side_key:String = _source_victory_side_key(source_ball,resolved_team)
	var presentation_side_key:String = _source_presentation_side_key(source_ball,resolved_team)
	if not victory_side_key.is_empty():
		new_silverfish.set_meta(&"battle_continuation_victory_side_key",victory_side_key)
		# 同时写入 world.gd 既有的缓存键，兼容原胜利统计回退逻辑。
		new_silverfish.set_meta(&"victory_side_key",victory_side_key)
	if not presentation_side_key.is_empty():
		new_silverfish.set_meta(&"battle_continuation_presentation_side_key",presentation_side_key)
	new_silverfish.set_meta(&"battle_continuation_display_name","蠹虫")

	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(abs(seed_value),1)
	new_silverfish.direction = Vector2.from_angle(rng.randf_range(0.0,TAU))
	new_silverfish.name = Game.return_random_name(new_silverfish)
	new_silverfish.set_meta("minecraft_silverfish_spawned_from_brick",true)

	# World 根受项目 MultiplayerSpawner 管理；关键身份全部在 add_child 前写入。
	_world.add_child(new_silverfish,true)
	new_silverfish.global_position = _safe_spawn_world_position(coord)
	# 本地再写一次，防止任意子类 ready 钩子改动阵营。远端仍由同步 Team + Master_name 兜底。
	new_silverfish.Team = resolved_team


func _safe_spawn_world_position(broken_coord:Vector2i) -> Vector2:
	# 最外圈现在允许正常碎裂，但很多地图把 used_rect 的最外圈本身当墙体。
	# 烟雾/声音/碎砖仍发生在原格；只有新蠹虫的实体出生点在边缘时向内夹 1 格，避免卡进墙。
	# 非矩形地图 / 多岛地图不能简单按 used_rect 夹取（可能夹到没有地板的格子），改为就近找一个四邻都有地板的内侧格。
	if _is_interior_cell(broken_coord):
		return _coord_world_position(broken_coord)
	for radius:int in range(1,4):
		var best:Vector2i = broken_coord
		var best_distance:int = 2147483647
		for dy:int in range(-radius,radius + 1):
			for dx:int in range(-radius,radius + 1):
				var candidate:Vector2i = broken_coord + Vector2i(dx,dy)
				if not _is_interior_cell(candidate):
					continue
				var distance:int = dx * dx + dy * dy
				if distance < best_distance:
					best_distance = distance
					best = candidate
		if best_distance != 2147483647:
			return _coord_world_position(best)
	return _coord_world_position(broken_coord)


func _is_interior_cell(coord:Vector2i) -> bool:
	if not _stone_cells.has(coord):
		return false
	for offset:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if not _stone_cells.has(coord + offset):
			return false
	return true


func _count_active_silverfish() -> int:
	var count:int = 0
	for node:Node in get_tree().get_nodes_in_group(SILVERFISH_GROUP):
		if not (node is ball):
			continue
		var candidate:ball = node as ball
		if candidate.health > 0:
			count += 1
	return count
