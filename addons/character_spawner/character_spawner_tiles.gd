@tool
class_name CharacterSpawnerTiles
extends TileMapLayer
## 可绘制的人物生成图层。每个已绘制格子是一个生成点，不作为地形、墙体或传送门。
const SpawnEntry = preload("res://classes/character_spawn_entry.gd")
const BRUSH = preload("res://addons/character_spawner/spawn_brush.tres")

@export_group("地图与开关")
@export var spawning_enabled:bool = true
## 所属地图只由节点层级决定，不提供手动指定其它地图的属性。
## 开启：手动模式关闭工具栏后生成；特殊模式正式开战后生成。
@export var only_during_battle:bool = true
@export var show_spawn_markers:bool = true
@export var marker_color:Color = Color(0.30,0.94,0.70,0.65)

@export_group("角色表（新建 CharacterSpawnEntry，拖入人物场景）")
@export var character_table:Array[SpawnEntry] = []
## 留空为无队伍；填写 Team0、Team1 等现有队名，也可用 random 随机选择队伍。
@export var spawn_team:String = ""
@export_range(0.1,5.0,0.05) var character_scale:float = 1.0
@export var random_seed:int = 0

@export_group("生成节奏")
@export_range(0.05,3600.0,0.05,"or_greater") var spawn_interval:float = 3.0
@export_range(0.0,3600.0,0.1,"or_greater") var initial_delay:float = 0.0
@export var spawn_immediately:bool = true
@export_range(1,64,1) var spawn_count:int = 1
@export_enum("每个方块","图层轮流选择一个方块","图层随机选择一个方块") var cell_selection:int = 0
## 单物理帧实例化预算；大批量绘制会分帧生成，不会一次卡住主线程。
@export_range(1,64,1) var frame_spawn_budget:int = 4

@export_group("数量上限（0 表示不限制）")
## 仅统计本图层生成且仍存活的角色，死亡或删除后释放名额。
@export_range(0,5000,1) var max_alive:int = 32
@export_range(0,5000,1) var max_alive_per_cell:int = 4
## 累计生成上限。0 可以无限补充；非 0 达到后本轮不再生成。
@export_range(0,100000,1) var max_total:int = 0

@export_group("位置与重置")
@export var randomize_position:bool = false
@export_range(0.0,0.9,0.05) var position_jitter:float = 0.5
@export_range(0.0,256.0,1.0) var min_spawn_distance:float = 0.0
@export_range(1,16,1) var position_attempts:int = 6
@export var require_inside_map:bool = true
@export var reset_on_map_change:bool = true
@export var despawn_on_map_change:bool = true

var total_spawned:int = 0
var _world:Node
var _rng := RandomNumberGenerator.new()
var _alive:Dictionary = {}
var _alive_by_cell:Dictionary = {}
var _active:bool = false
var _was_selected:bool = false
var _time_left:float = 0.0
var _cursor:int = 0
var _wave:Array[Vector2i] = []
var _wave_index:int = 0
var _wave_repeat:int = 0
var _marker:Node2D
var _last_cells:Array[Vector2i] = []

class SpawnMarkers extends Node2D:
	var polygons:Array[PackedVector2Array] = []
	var tint:Color = Color(0.30,0.94,0.70,0.65)
	func _draw() -> void:
		for polygon:PackedVector2Array in polygons:
			draw_colored_polygon(polygon,Color(tint,0.10))
			var outline:PackedVector2Array = polygon.duplicate()
			outline.append(polygon[0])
			draw_polyline(outline,tint,1.0,true)
			var center:Vector2 = (polygon[0]+polygon[2])*0.5
			draw_line(center-Vector2(3,0),center+Vector2(3,0),tint,1.0)
			draw_line(center-Vector2(0,3),center+Vector2(0,3),tint,1.0)

func _ready() -> void:
	if tile_set == null: tile_set = BRUSH
	collision_enabled = false
	navigation_enabled = false
	occlusion_enabled = false
	if Engine.is_editor_hint():
		changed.connect(update_configuration_warnings)
		update_configuration_warnings()
		return
	visible = false
	add_to_group("MapCharacterSpawners")
	_rng.seed = random_seed if random_seed!=0 else int(Time.get_ticks_usec()) ^ int(get_instance_id())
	changed.connect(_invalidate_markers)

func is_character_spawn_layer() -> bool:
	return true

func _resolve_world() -> Node:
	if is_instance_valid(_world): return _world
	var ancestor:Node = get_parent()
	while ancestor != null:
		if ancestor.has_method("spawn_map_character"):
			_world = ancestor
			return _world
		ancestor = ancestor.get_parent()
	return null

func resolved_map_name() -> String:
	# 沿实际父节点链寻找所属地图；嵌套容器、移动到另一张地图也自动跟随。
	var world:Node = _resolve_world()
	if world == null: return ""
	var ancestor:Node = get_parent()
	while ancestor != null and ancestor != world:
		if world.map_group.get(str(ancestor.name)) == ancestor: return str(ancestor.name)
		ancestor = ancestor.get_parent()
	return ""

func is_selected_map() -> bool:
	var world:Node = _resolve_world()
	return world != null and not resolved_map_name().is_empty() and str(world.now_choose_map)==resolved_map_name()

func can_generate() -> bool:
	var world:Node = _resolve_world()
	if world == null or not spawning_enabled or not is_selected_map(): return false
	if not world.is_multiplayer_authority() or get_tree().paused or Engine.time_scale<=0.000001: return false
	var game:Node = get_tree().root.get_node_or_null("Game")
	if game == null or game.now_stop_state or world.random_character_draft.blocks_combat(): return false
	if only_during_battle:
		if world.is_toolbar_open(): return false
		if game.get_training_mode_type()!="manual" and not world.is_combat_runtime_active(): return false
	return true

func _physics_process(delta:float) -> void:
	if not Engine.is_editor_hint(): advance_spawning(delta)

## 独立时钟入口供回归测试使用；暂停/地图/权限检查仍然生效，无法绕过限制。
func advance_spawning(delta:float) -> int:
	var world:Node = _resolve_world()
	if world == null: return 0
	var selected:bool = is_selected_map()
	_update_markers(selected)
	if _was_selected and not selected and reset_on_map_change:
		reset_runtime(despawn_on_map_change)
	_was_selected = selected
	if not can_generate():
		_active = false
		_wave.clear()
		return 0
	if not _active:
		_active = true
		_time_left = maxf(initial_delay,0.0)+(0.0 if spawn_immediately else maxf(spawn_interval,0.05))
	_time_left -= maxf(delta,0.0)
	_prune_alive()
	if _wave.is_empty() and _time_left<=0.0:
		_time_left = maxf(spawn_interval,0.05)
		_prepare_wave()
	if _wave.is_empty(): return 0
	var generated:int = 0
	var attempts:int = 0
	while _wave_index<_wave.size() and attempts<clampi(frame_spawn_budget,1,64):
		if (max_total>0 and total_spawned>=max_total) or (max_alive>0 and _alive.size()>=max_alive):
			_wave.clear()
			break
		var cell:Vector2i = _wave[_wave_index]
		attempts += 1
		if get_cell_source_id(cell)>=0 and (max_alive_per_cell<=0 or int(_alive_by_cell.get(cell,0))<max_alive_per_cell):
			if _spawn_one(cell): generated += 1
		_wave_repeat += 1
		if _wave_repeat>=maxi(spawn_count,1):
			_wave_index += 1
			_wave_repeat = 0
	if _wave_index>=_wave.size(): _wave.clear()
	return generated

func _prepare_wave() -> void:
	var cells:Array[Vector2i] = get_used_cells()
	cells.sort_custom(func(a:Vector2i,b:Vector2i) -> bool: return a.y<b.y if a.y!=b.y else a.x<b.x)
	_wave.clear()
	_wave_index = 0
	_wave_repeat = 0
	if cells.is_empty(): return
	if cell_selection==2:
		_wave.append(cells[_rng.randi_range(0,cells.size()-1)])
	elif cell_selection==1:
		_wave.append(cells[_cursor%cells.size()])
	else:
		# 轮换起点，数量上限较低时也不会永远偏向第一格。
		for index:int in range(cells.size()): _wave.append(cells[(index+_cursor)%cells.size()])
	_cursor = (_cursor+1)%cells.size()

func _pick_scene() -> PackedScene:
	var total:float = 0.0
	for entry:SpawnEntry in character_table:
		if entry != null and entry.enabled and entry.character != null and is_finite(entry.weight) and entry.weight>0.0:
			total += entry.weight
	if total<=0.0: return null
	var value:float = _rng.randf()*total
	var last:PackedScene
	for entry:SpawnEntry in character_table:
		if entry == null or not entry.enabled or entry.character == null or not is_finite(entry.weight) or entry.weight<=0.0: continue
		last = entry.character
		value -= entry.weight
		if value<=0.0: return last
	return last

func _spawn_one(cell:Vector2i) -> bool:
	var scene:PackedScene = _pick_scene()
	if scene == null: return false
	var point:Vector2 = to_global(map_to_local(cell))
	var found:bool = false
	for attempt:int in range(clampi(position_attempts,1,16)):
		var local:Vector2 = map_to_local(cell)
		if randomize_position and tile_set!=null:
			local += Vector2(_rng.randf_range(-0.5,0.5),_rng.randf_range(-0.5,0.5))*Vector2(tile_set.tile_size)*clampf(position_jitter,0.0,0.9)
		point = to_global(local)
		if require_inside_map and not _world.map_contains_point(point,_world.current_map_island_rects()): continue
		var blocked:bool = false
		if min_spawn_distance>0.0:
			for unit:Node in _world.get_battle_units_fast():
				if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit is Node2D and unit.global_position.distance_to(point)<min_spawn_distance:
					blocked = true
					break
		if not blocked:
			found = true
			break
	if not found: return false
	var character:Node2D = _world.spawn_map_character(scene,spawn_team,point,character_scale)
	if not is_instance_valid(character): return false
	character.set_meta("map_spawn_source",get_path())
	character.set_meta("map_spawn_cell",cell)
	_alive[character.get_instance_id()] = {"node":weakref(character),"cell":cell}
	_alive_by_cell[cell] = int(_alive_by_cell.get(cell,0))+1
	total_spawned += 1
	return true

func _prune_alive() -> void:
	_alive_by_cell.clear()
	for id:Variant in _alive.keys():
		var record:Dictionary = _alive[id]
		var character:Node = (record.node as WeakRef).get_ref() as Node
		if not is_instance_valid(character) or character.is_queued_for_deletion() or float(character.get("health"))<=0:
			_alive.erase(id)
			continue
		_alive_by_cell[record.cell] = int(_alive_by_cell.get(record.cell,0))+1

func alive_count() -> int:
	_prune_alive()
	return _alive.size()

func reset_runtime(clear_spawned:bool = true) -> void:
	if clear_spawned:
		for record:Dictionary in _alive.values():
			var character:Node = (record.node as WeakRef).get_ref() as Node
			if is_instance_valid(character) and _world.is_multiplayer_authority(): character.queue_free()
		_alive.clear()
		_alive_by_cell.clear()
	total_spawned = 0
	_active = false
	_wave.clear()
	_cursor = 0
	_time_left = 0.0
	if random_seed!=0: _rng.seed = random_seed

func _invalidate_markers() -> void:
	_last_cells.clear()

func _update_markers(selected:bool) -> void:
	if not show_spawn_markers or not selected:
		if is_instance_valid(_marker): _marker.hide()
		return
	if not is_instance_valid(_marker):
		_marker = SpawnMarkers.new()
		_marker.name = "CharacterSpawnMarkers"
		_marker.z_index = 6
		_world.add_child(_marker)
	_marker.show()
	var cells:Array[Vector2i] = get_used_cells()
	if cells==_last_cells: return
	_last_cells = cells
	_marker.polygons.clear()
	_marker.tint = marker_color
	var half:Vector2 = Vector2(tile_set.tile_size)*0.5 if tile_set!=null else Vector2(8,8)
	for cell:Vector2i in cells:
		var center:Vector2 = map_to_local(cell)
		var points := PackedVector2Array()
		for offset:Vector2 in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
			points.append(_world.to_local(to_global(center+offset)))
		_marker.polygons.append(points)
	_marker.queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(_marker): _marker.queue_free()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_used_cells().is_empty(): warnings.append("请使用 TileMap 画笔绘制生成方块；空图层不会生成角色。")
	if character_table.is_empty(): warnings.append("角色表为空。请新增 CharacterSpawnEntry 并将角色 .tscn 拖入 Character。")
	return warnings
