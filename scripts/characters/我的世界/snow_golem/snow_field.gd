extends Node2D
## A single battle-scoped sparse grid: no Area2D or timer per snow tile.
const CELL:float = 16.0 # Fallback only; live snow follows the actual map block size/origin.
const LEGACY_ENV_CELL:float = 24.0
const GEOMETRY = preload("res://classes/map_tile_geometry.gd")
# Melt seconds: retain one full block, then briefly fade at the same footprint.
@export_range(0.1,120.0,0.1) var full_snow_lifetime:float = 8.0
@export_range(0.01,5.0,0.01) var snow_fade_duration:float = 0.30
const SNOW:Texture2D = preload("res://Images/effects/我的世界/雪环境/snow.png")
const COLD = preload("res://scripts/characters/我的世界/snow_golem/cold.gd")
const RULES = preload("res://scripts/characters/我的世界/snow_golem/rules.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const AUDIO = preload("res://scripts/characters/我的世界/snow_golem/audio.gd")
var patches:Dictionary = {} # Map-block key -> one full footprint, owner and fade deadline.
# Independent ownership/lifetime: removing weather never erases a golem's trail.
# Ground weather uses the same contact, damage, cold, audio and cooldown below.
var environment_patches:Dictionary = {}
# Both layers use the same block geometry and lifetime. Exact rectangles remain
# authoritative across development movement and local visual-theme changes.
var _environment_ground_index:Dictionary = {}
var _trail_ground_index:Dictionary = {}
var _indices_dirty:bool = true
var grid_size:Vector2 = Vector2.ONE*CELL
var grid_origin:Vector2 = Vector2.ZERO
var grid_revision:int = 0
var _grid_base:Vector2i = Vector2i.ZERO
var _grid_ground:Array[Rect2] = []
var _grid_refresh_left:float = 0.0
var _melt_clock:float = 0.0
var _melt_rate:float = 1.0
var _dirty_environment:Dictionary = {}
var _environment_bucket_size:float = CELL
var _environment_path_step:float = CELL*0.4
var environment_source:Node
var wall_view:Node2D
var _development_environment_starts:Dictionary = {}
var _development_environment_offsets:Dictionary = {}
var _clock:float = 0.0
var _next_melt:float = INF
var _ground_left:float = 0.0
var _sync_left:float = 0.0
var _damage_until:Dictionary = {}
var _positions:Dictionary = {}
var _dirty_cells:Dictionary = {}
var _development_patch_lanes:Dictionary = {}
var _development_start_offsets:Dictionary = {}
var _development_current_offsets:Dictionary = {}
var _development_draw_offsets:Dictionary = {}

func _development_lane(entry:Dictionary,point:Vector2,lane_at:Callable,prefer_source:bool) -> String:
	var ref:Variant = entry.get("source")
	var actor:Variant = ref.get_ref() if ref is WeakRef else null
	if prefer_source and is_instance_valid(actor) and actor.has_meta("development_lane_key"):
		return str(actor.get_meta("development_lane_key"))
	return str(lane_at.call(point))

func development_begin_merge(lane_at:Callable,start_offsets:Dictionary,prefer_source:bool = true) -> void:
	# One shared manager holds both teams' snow. Bind each tile to its original
	# lane BEFORE the two maps overlap; moving this Node2D is wrong.
	_development_start_offsets = start_offsets.duplicate(true)
	_development_current_offsets = start_offsets.duplicate(true)
	_development_patch_lanes.clear()
	_development_draw_offsets.clear()
	_development_environment_starts.clear()
	_development_environment_offsets.clear()
	for cell:Vector2i in environment_patches:
		_development_environment_starts[cell] = {"lane":str(lane_at.call(environment_tile(environment_patches[cell]).get_center())),"record":environment_patches[cell].duplicate(true)}
	for cell:Vector2i in patches:
		_development_patch_lanes[cell] = _development_lane(patches[cell],patch_tile(patches[cell],cell).get_center(),lane_at,prefer_source)

func _development_change(lane:String) -> Vector2:
	return (_development_current_offsets.get(lane,Vector2.ZERO) as Vector2)-(_development_start_offsets.get(lane,Vector2.ZERO) as Vector2)

func development_preview_merge(_start_offsets:Dictionary,lanes:Dictionary) -> void:
	_development_draw_offsets.clear()
	for lane:String in _development_start_offsets:
		if lanes.has(lane): _development_current_offsets[lane] = (lanes[lane] as Dictionary).get("offset",Vector2.ZERO)
	for cell:Vector2i in _development_patch_lanes:
		_development_draw_offsets[cell] = _development_change(str(_development_patch_lanes[cell]))
	for cell:Vector2i in _development_environment_starts:
		_development_environment_offsets[cell] = _development_change(str(_development_environment_starts[cell].lane))
	queue_redraw()
	if is_instance_valid(wall_view): wall_view.request_update()

func development_finish_merge() -> void:
	if _development_start_offsets.is_empty(): return
	var translated:Dictionary = {}
	for cell:Vector2i in patches:
		var change:Vector2 = _development_change(str(_development_patch_lanes.get(cell,"")))
		var patch:Dictionary = patches[cell]
		var tile:Rect2 = patch_tile(patch,cell)
		tile.position += change
		var destination:=Vector2i((tile.get_center()/tile.size).floor())
		patch.cell = destination
		patch.tile = tile
		patch.rects = [tile]
		var existing:Dictionary = translated.get(destination,{})
		# Identical locations from two teams coalesce into one canonical tile;
		# a full or longer-lived patch wins, never a duplicate grid key.
		if existing.is_empty() or int(patch.level)>int(existing.level) or (int(patch.level)==int(existing.level) and float(patch.get("expires_at",0.0))>float(existing.get("expires_at",0.0))):
			translated[destination] = patch
	patches = translated
	var weather:Dictionary = {}
	for cell:Vector2i in environment_patches:
		var change:Vector2 = _development_environment_offsets.get(cell,Vector2.ZERO)
		var record:Dictionary = environment_patches[cell].duplicate(true)
		var tile:Rect2 = environment_tile(record)
		tile.position += change
		var destination:=Vector2i((tile.get_center()/tile.size).floor())
		record.cell = destination
		record.tile = tile
		for index:int in range(record.rects.size()): record.rects[index] = Rect2(record.rects[index].position+change,record.rects[index].size)
		var existing:Dictionary = weather.get(destination,{})
		if existing.is_empty() or (bool(existing.decorative) and not bool(record.decorative)) or (bool(existing.decorative)==bool(record.decorative) and float(record.get("expires_at",0))>float(existing.get("expires_at",0))): weather[destination] = record
	environment_patches = weather
	_rebuild_environment_index()
	_development_environment_starts.clear()
	_development_environment_offsets.clear()
	# Position history from the separated maps must not sweep across the arena.
	_positions.clear()
	_dirty_cells.clear()
	_reschedule_melt()
	_development_start_offsets.clear()
	_development_current_offsets.clear()
	_development_patch_lanes.clear()
	_development_draw_offsets.clear()
	queue_redraw()
	if is_instance_valid(wall_view): wall_view.request_update()
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_field_state.rpc(_cell_snapshot(patches.keys()),[],true)
		_environment_state.rpc(_environment_payload(environment_patches.values()),true)

static func ensure(context:Node,world_override:Node = null) -> Node2D:
	var world:Node = world_override
	if not is_instance_valid(world):
		world = context
		while is_instance_valid(world) and not world.has_method("_current_map_node"): world = world.get_parent()
		if not is_instance_valid(world): world = context.get_tree().current_scene
	var existing:Node = world.get_node_or_null("MCSnowField")
	if is_instance_valid(existing):
		if not existing.is_queued_for_deletion(): return existing as Node2D
		# Reset/rematch may create the next battle before queued deletion is flushed.
		# Retire the old name so the replacement keeps its stable lookup/RPC path.
		existing.name = "RetiredMCSnowField_"+str(existing.get_instance_id())
	var field:Node2D = load("res://scenes/effects/我的世界/雪傀儡雪地.tscn").instantiate()
	field.name = "MCSnowField"
	field.set_multiplayer_authority(world.get_multiplayer_authority())
	world.add_child(field)
	return field

static func cell_at(point:Vector2) -> Vector2i: return Vector2i((point/CELL).floor())
static func point_at(cell:Vector2i) -> Vector2: return (Vector2(cell)+Vector2.ONE*0.5)*CELL

func refresh_grid(force:bool = false) -> void:
	if not _development_start_offsets.is_empty(): return
	if not force and _grid_refresh_left>0.0: return
	_grid_refresh_left = 0.25
	var world:Node = get_parent()
	var size:Vector2 = Vector2.ONE*CELL
	var ground:Array[Rect2] = []
	if world.has_method("_current_map_node"):
		var map:Node = world._current_map_node()
		if is_instance_valid(map):
			if world.has_method("map_visual_cell_size"): size = world.map_visual_cell_size(map)
			if world.has_method("map_island_rects"): ground.assign(world.map_island_rects(map))
			elif world.has_method("return_map_world_rect"): ground.append(world.return_map_world_rect(map))
	size = size.max(Vector2(0.01,0.01))
	var origin:Vector2 = ground[0].position if not ground.is_empty() else Vector2.ZERO
	if size==grid_size and origin==grid_origin and ground==_grid_ground: return
	grid_size = size
	grid_origin = origin
	_grid_base = Vector2i(((origin+size*0.5)/size).floor())
	_grid_ground = ground
	grid_revision += 1
	_indices_dirty = true
	# No stale trail remains over a removed island; development movement owns its
	# own translation and deliberately bypasses this refresh until merge completes.
	if is_multiplayer_authority() and not ground.is_empty():
		for key:Vector2i in patches.keys():
			var area:Array[Rect2] = [patch_tile(patches[key],key)]
			if not GEOMETRY.subtract(area,ground).is_empty():
				patches.erase(key)
				_dirty_cells[key] = true
	queue_redraw()

func snow_cell_at(point:Vector2) -> Vector2i:
	refresh_grid()
	return Vector2i(((point-grid_origin)/grid_size).floor())+_grid_base

func snow_point_at(cell:Vector2i) -> Vector2:
	refresh_grid()
	return grid_origin+(Vector2(cell-_grid_base)+Vector2.ONE*0.5)*grid_size

func snow_tile_at(cell:Vector2i) -> Rect2:
	return Rect2(snow_point_at(cell)-grid_size*0.5,grid_size)

static func patch_tile(record:Dictionary,cell:Vector2i) -> Rect2:
	var value:Variant = record.get("tile")
	if value is Rect2 and value.has_area(): return value
	return Rect2(point_at(cell)-Vector2.ONE*CELL*0.5,Vector2.ONE*CELL)

func snow_alpha(record:Dictionary) -> float:
	var left:float = float(record.get("expires_at",_melt_clock+full_snow_lifetime))-_melt_clock
	return clampf(1.0+minf(left,0.0)/maxf(float(record.get("fade_duration",snow_fade_duration)),0.01),0.0,1.0)

func _snow_damaging(record:Dictionary) -> bool:
	return float(record.get("expires_at",INF))>_melt_clock

func _remaining_damage_time(record:Dictionary) -> float:
	return maxf(0.0,float(record.get("expires_at",_melt_clock+full_snow_lifetime))-_melt_clock)/maxf(_melt_rate,0.001)

func _refresh_melt_rate() -> void:
	if not is_multiplayer_authority(): return
	var rate:float = 0.5 if str(Game.Game_Settings.get("Environment","none"))=="snow" else 1.0
	if is_equal_approx(rate,_melt_rate): return
	_melt_rate = rate
	if multiplayer.has_multiplayer_peer(): _melt_rate_state.rpc(_melt_rate)

@rpc("authority","call_remote","reliable")
func _melt_rate_state(rate:float) -> void:
	_melt_rate = 0.5 if rate<0.75 else 1.0

func _on_snow_setting_changed(key:String,_value:Variant) -> void:
	if key=="Environment": _refresh_melt_rate()

static func environment_tile(record:Dictionary) -> Rect2:
	var value:Variant = record.get("tile")
	if value is Rect2 and value.has_area() and value.position.is_finite() and value.size.is_finite(): return value
	# Legacy snapshots/test fixtures retain their original 24-unit geometry.
	return Rect2(Vector2(record.get("cell",Vector2i.ZERO))*LEGACY_ENV_CELL-Vector2.ONE*LEGACY_ENV_CELL*0.5,Vector2.ONE*LEGACY_ENV_CELL)

func _environment_bucket(point:Vector2) -> Vector2i:
	return Vector2i((point/_environment_bucket_size).floor())

func _rebuild_environment_index() -> void:
	_environment_ground_index.clear()
	_trail_ground_index.clear()
	_environment_bucket_size = CELL
	_environment_path_step = CELL*0.4
	for layer:Dictionary in [patches,environment_patches]:
		for cell:Vector2i in layer:
			var record:Dictionary = layer[cell]
			if bool(record.get("decorative",false)): continue
			for rect:Rect2 in _ground_rects(record,cell):
				_environment_bucket_size = maxf(_environment_bucket_size,maxf(rect.size.x,rect.size.y))
				_environment_path_step = minf(_environment_path_step,minf(rect.size.x,rect.size.y)*0.4)
	_environment_path_step = maxf(0.1,_environment_path_step)
	for layer_index:int in range(2):
		var layer:Dictionary = patches if layer_index==0 else environment_patches
		var index:Dictionary = _trail_ground_index if layer_index==0 else _environment_ground_index
		for cell:Vector2i in layer:
			var record:Dictionary = layer[cell]
			if bool(record.get("decorative",false)): continue
			for rect:Rect2 in _ground_rects(record,cell):
				var low:Vector2i = _environment_bucket(rect.position)
				var high:Vector2i = _environment_bucket(rect.end)
				for y:int in range(low.y,high.y+1):
					for x:int in range(low.x,high.x+1):
						var bucket:=Vector2i(x,y)
						if not index.has(bucket): index[bucket] = []
						if not cell in index[bucket]: index[bucket].append(cell)
	_indices_dirty = false

func _ground_rects(record:Dictionary,cell:Vector2i) -> Array[Rect2]:
	var result:Array[Rect2] = []
	for value:Variant in record.get("rects",[patch_tile(record,cell)]):
		if value is Rect2 and value.has_area(): result.append(value)
	return result

func _ground_at(point:Vector2,layer:Dictionary,index:Dictionary) -> Dictionary:
	if _indices_dirty: _rebuild_environment_index()
	for cell:Vector2i in index.get(_environment_bucket(point),[]):
		if not layer.has(cell): continue
		var record:Dictionary = layer[cell]
		if not _snow_damaging(record): continue
		for rect:Rect2 in _ground_rects(record,cell):
			if rect.has_point(point): return record
	return {}

func _environment_at(point:Vector2) -> Dictionary:
	return _ground_at(point,environment_patches,_environment_ground_index)

func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("AI_Hazard")
	# World defaults to z=-2; floor is -4/-5 and normal bodies/shots are -2.
	# Keep ground RELATIVE below its world, not absolute above ordinary actors.
	z_as_relative = true
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wall_view = load("res://scripts/training/snow_wall_view.gd").new()
	wall_view.field = self
	add_child(wall_view)
	refresh_grid(true)
	_refresh_melt_rate()
	Game.game_setting_changed.connect(_on_snow_setting_changed)
	if not is_multiplayer_authority(): call_deferred("_request_state")

func runtime_active() -> bool:
	if get_tree() == null or get_tree().paused or Game.now_stop_state or Engine.time_scale <= 0.000001: return false
	var world:Node = get_parent()
	return bool(world.call("is_combat_runtime_active")) if world.has_method("is_combat_runtime_active") else true

func can_place(source:Node2D,cell:Vector2i,check_outer_bounds:bool = true) -> bool:
	var tile:Rect2 = snow_tile_at(cell)
	if check_outer_bounds and not _grid_ground.is_empty():
		var area:Array[Rect2] = [tile]
		if not GEOMETRY.subtract(area,_grid_ground).is_empty(): return false
	return _can_place_rect(source,tile)

func can_place_environment(record:Dictionary) -> bool:
	return _can_place_rect(null,environment_tile(record))

func _can_place_rect(source:Node2D,rect:Rect2) -> bool:
	var point:Vector2 = rect.get_center()
	var shape := RectangleShape2D.new()
	shape.size = (rect.size-Vector2.ONE).max(Vector2(0.01,0.01))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 1
	query.collide_with_areas = false
	if not get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return not is_instance_valid(source) or U.line_clear(source,source.global_position,point)

func add_environment_patch(source:Node,record:Dictionary) -> bool:
	if not is_multiplayer_authority() or not is_instance_valid(source): return false
	if not record.get("cell") is Vector2i or environment_patches.size()>=1024: return false
	environment_source = source
	_environment_state([record],false)
	if multiplayer.has_multiplayer_peer(): _environment_state.rpc(_environment_payload([environment_patches[record.cell]]),false)
	return true

func clear_environment() -> void:
	if environment_patches.is_empty(): return
	_environment_state([],true)
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _environment_state.rpc([],true)

func reconcile_environment(ground:Array[Rect2],walls:Array[Rect2]) -> void:
	if not is_multiplayer_authority(): return
	var changes:Array[Dictionary] = []
	for cell:Vector2i in environment_patches:
		var record:Dictionary = environment_patches[cell]
		var footprint:Rect2 = environment_tile(record)
		if bool(record.decorative):
			var pieces:Array[Rect2] = []
			for wall:Rect2 in walls:
				var piece:Rect2 = footprint.intersection(wall)
				if piece.size.x>=1.0 and piece.size.y>=1.0: pieces.append(piece)
			if pieces.is_empty(): changes.append({"cell":cell,"removed":true})
			elif pieces!=record.rects:
				var update:Dictionary = record.duplicate()
				update.rects = pieces
				changes.append(update)
		elif not GEOMETRY.subtract([footprint],ground).is_empty(): changes.append({"cell":cell,"removed":true})
	if not changes.is_empty():
		_environment_state(changes,false)
		if multiplayer.has_multiplayer_peer(): _environment_state.rpc(_environment_payload(changes),false)

func _remove_environment_cell(cell:Vector2i) -> void:
	if not environment_patches.has(cell): return
	var update:Array = [{"cell":cell,"removed":true}]
	_environment_state(update,false)
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _environment_state.rpc(update,false)

@rpc("authority","call_remote","reliable")
func _environment_state(records:Array,full:bool) -> void:
	if full:
		environment_patches.clear()
		_development_environment_starts.clear()
		_development_environment_offsets.clear()
	for raw:Variant in records:
		if not raw is Dictionary: continue
		var item:Dictionary = raw
		if not item.get("cell") is Vector2i: continue
		var cell:Vector2i = item.cell
		if bool(item.get("removed",false)):
			environment_patches.erase(cell)
			continue
		var rects:Array[Rect2] = []
		for rect:Variant in item.get("rects",[]):
			if rect is Rect2 and rect.has_area(): rects.append(rect)
		if rects.is_empty(): continue
		var expiry:float = float(item.get("expires_at",_melt_clock+full_snow_lifetime))
		if item.has("remaining"): expiry = _melt_clock+float(item.remaining)
		environment_patches[cell] = {"cell":cell,"decorative":bool(item.get("decorative",false)),"tile":environment_tile(item),"rects":rects,"expires_at":expiry,"fade_duration":maxf(float(item.get("fade_duration",snow_fade_duration)),0.01)}
	_indices_dirty = true
	_reschedule_melt()
	queue_redraw()
	if is_instance_valid(wall_view): wall_view.request_update()

func _environment_payload(records:Array) -> Array:
	var result:Array = []
	for item:Dictionary in records:
		var data:Dictionary = item.duplicate(true)
		if not bool(data.get("removed",false)):
			data["remaining"] = float(data.get("expires_at",_melt_clock+full_snow_lifetime))-_melt_clock
			data["fade_duration"] = float(data.get("fade_duration",snow_fade_duration))
			data.erase("expires_at")
		result.append(data)
	return result

func _same_side(source:ball,entry:Dictionary) -> bool:
	return str(entry.family) == str(source.get_meta("mc_snow_family","")) or (not source.Team.is_empty() and source.Team == str(entry.team))

func deposit(source:ball,cell:Vector2i,_retired_half_size:bool = false) -> bool:
	if not is_multiplayer_authority() or not runtime_active() or not is_instance_valid(source) or source.health<=0: return false
	if source.dizziness or source.is_damage_output_disabled() or not can_place(source,cell): return false
	var tile:Rect2 = snow_tile_at(cell)
	if patches.has(cell):
		var old:Dictionary = patches[cell]
		if not _same_side(source,old): return false
		# Actual revisits refresh; stationary actors still deposit only once.
		old.level = 2
		old.cell = cell
		old.tile = tile
		old.rects = [tile]
		_stamp_lifetime(old)
	else:
		patches[cell] = {"cell":cell,"tile":tile,"rects":[tile],"level":2,"source":weakref(source),"family":str(source.get_meta("mc_snow_family","")),"team":source.Team}
		_stamp_lifetime(patches[cell])
	_dirty_cells[cell] = true
	_indices_dirty = true
	queue_redraw()
	return true

func _stamp_lifetime(patch:Dictionary) -> void:
	patch["expires_at"] = _melt_clock+maxf(full_snow_lifetime,0.1)
	patch["fade_duration"] = maxf(snow_fade_duration,0.01)
	_next_melt = minf(_next_melt,float(patch.expires_at))

func _reschedule_melt() -> void:
	_next_melt = INF
	for layer:Dictionary in [patches,environment_patches]:
		for patch:Dictionary in layer.values(): _next_melt = minf(_next_melt,float(patch.get("expires_at",_melt_clock)))

func _melt_patches() -> void:
	if _melt_clock<_next_melt: return
	_next_melt = INF
	var changed:bool = false
	var wall_changed:bool = false
	for layer_index:int in range(2):
		var layer:Dictionary = patches if layer_index==0 else environment_patches
		for cell:Vector2i in layer.keys():
			var patch:Dictionary = layer[cell]
			if not patch.has("expires_at"): _stamp_lifetime(patch)
			var deadline:float = float(patch.expires_at)
			if _melt_clock>=deadline:
				changed = true
				wall_changed = wall_changed or bool(patch.get("decorative",false))
				if _melt_clock>=deadline+float(patch.get("fade_duration",snow_fade_duration)):
					layer.erase(cell)
					_indices_dirty = true
					if is_multiplayer_authority():
						if layer_index==0: _dirty_cells[cell] = true
						else: _dirty_environment[cell] = true
			if layer.has(cell): _next_melt = minf(_next_melt,deadline)
	if changed: queue_redraw()
	if wall_changed and is_instance_valid(wall_view): wall_view.request_update()

func _source(entry:Dictionary) -> ball:
	var ref:WeakRef = entry.get("source")
	var unit:Variant = ref.get_ref() if ref != null else null
	if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.health > 0: return unit as ball
	# Replicas resolve the actual living owner from its family ID; this is no
	# longer a descendant-maintenance path and never crosses physics worlds.
	for candidate:Node in get_tree().get_nodes_in_group("MCSnowGolem"):
		if not candidate.is_queued_for_deletion() and candidate.health>0 and candidate.get_world_2d()==get_world_2d() and str(candidate.get_meta("mc_snow_family",""))==str(entry.family): return candidate as ball
	return null

func _patch_on_path(source_position:Vector2,target:ball) -> Dictionary:
	var destination:Vector2 = ball.body_point(target,global_position)
	if source_position.distance_to(destination)>LEGACY_ENV_CELL*8.0: source_position = destination
	if _indices_dirty: _rebuild_environment_index()
	var steps:int = clampi(int(ceil(source_position.distance_to(destination)/_environment_path_step)),1,128)
	for index:int in range(steps+1):
		var sample:Vector2 = source_position.lerp(destination,float(index)/float(steps))
		var trail:Dictionary = _ground_at(sample,patches,_trail_ground_index)
		if not trail.is_empty():
			var owner_unit:ball = _source(trail)
			var point:Vector2 = patch_tile(trail,trail.get("cell",snow_cell_at(sample))).get_center()
			if RULES.enemy(owner_unit,target) and U.line_clear(self,point,destination): return {"source":owner_unit,"point":point}
		var weather:Dictionary = _environment_at(sample)
		if not weather.is_empty() and is_instance_valid(environment_source):
			var point:Vector2 = environment_tile(weather).get_center()
			if U.line_clear(self,point,destination): return {"source":environment_source,"point":point}
	return {}

func check_ground() -> void:
	if not runtime_active() or not is_multiplayer_authority(): return
	var live_ids:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or node.is_queued_for_deletion() or not node.is_combat_targetable(): continue
		var target:ball = node as ball
		if target.get_world_2d()!=get_world_2d() or target.is_cold_immune(): continue
		var id:int = target.get_instance_id()
		live_ids[id] = true
		var previous:Vector2 = _positions.get(id,target.global_position)
		_positions[id] = target.global_position
		if _clock < float(_damage_until.get(id,-1.0)): continue
		var contact:Dictionary = _patch_on_path(previous,target)
		if contact.is_empty(): continue
		var source:Node = contact.source
		if not source.is_combat_runtime_active() or source.is_damage_output_disabled(): continue
		_damage_until[id] = _clock+maxf(source.snow_tick_interval,0.1)
		# Health is integer-valued in this project. Quantize once before subtraction
		# so 6 * 0.33333334 cannot accidentally remove three HP via truncation.
		var outgoing:float = source.attack_damage(source.snow_damage_multiplier)
		var damage:float = maxf(1.0,roundf(outgoing)) if outgoing > 0.0 else 0.0
		var before:float = maxf(float(target.health),0.0)
		var point:Vector2 = ball.body_point(target,global_position)
		var accepted:bool = target.receive_cold_positional_damage(damage,contact.point,false,source)
		var remaining:float = maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0
		var actual:float = maxf(before-remaining,0.0)
		if actual > 0.0: emit_impact(actual,point,false)
		if accepted and is_instance_valid(target) and target.health > 0:
			if target.can_receive_cold_status(): COLD.ensure(target).add_cold(source.snow_cold,source.freeze_duration,source)
	for id:Variant in _positions.keys():
		if not live_ids.has(id):
			_positions.erase(id)
			_damage_until.erase(id)

func advance(delta:float) -> void:
	if not runtime_active() or not is_finite(delta) or delta<=0.0: return
	_clock += delta
	_refresh_melt_rate()
	_melt_clock += delta*_melt_rate
	# Fading snow is visual only; damage cadence stays on the unscaled combat clock.
	_melt_patches()
	if not is_multiplayer_authority(): return
	_ground_left -= delta
	if _ground_left <= 0.0:
		_ground_left = 0.1
		check_ground()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = 0.15
		_send_changes()

func _physics_process(delta:float) -> void:
	advance(delta)

func _process(delta:float) -> void:
	_grid_refresh_left -= delta
	refresh_grid()
	var paused:bool = not runtime_active()
	for player:Node in get_tree().get_nodes_in_group("MCSnowSound"):
		if is_instance_valid(player): player.stream_paused = paused

func _draw() -> void:
	for cell:Vector2i in environment_patches:
		var record:Dictionary = environment_patches[cell]
		if bool(record.decorative): continue
		var offset:Vector2 = _development_environment_offsets.get(cell,Vector2.ZERO)
		for rect:Rect2 in record.rects:
			draw_texture_rect(SNOW,Rect2(rect.position+offset,rect.size),false,Color(1,1,1,snow_alpha(record)))
	for cell:Vector2i in patches:
		var patch:Dictionary = patches[cell]
		var tile:Rect2 = patch_tile(patch,cell)
		tile.position += _development_draw_offsets.get(cell,Vector2.ZERO) as Vector2
		draw_texture_rect(SNOW,tile,false,Color(1,1,1,snow_alpha(patch)))

func emit_sound(event:String,point:Vector2,volume:float) -> void:
	if multiplayer.has_multiplayer_peer(): _sound.rpc(event,point,volume)
	_sound(event,point,volume)
@rpc("authority","call_remote","reliable")
func _sound(event:String,point:Vector2,volume:float) -> void: AUDIO.play(self,event,point,volume)

func emit_phase(phase:String,point:Vector2) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.get_peers().size() > 0: _phase_sound.rpc(phase,point)
	_phase_sound(phase,point)
@rpc("authority","call_remote","reliable")
func _phase_sound(phase:String,point:Vector2) -> void:
	AUDIO.play_phase(self,phase,point)

func emit_impact(actual:float,point:Vector2,include_snow:bool = true) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.get_peers().size() > 0: _impact_sound.rpc(actual,point,include_snow)
	_impact_sound(actual,point,include_snow)
@rpc("authority","call_remote","reliable")
func _impact_sound(actual:float,point:Vector2,include_snow:bool) -> void:
	AUDIO.play_impact(self,actual,point,include_snow)

func sync_cold(target:ball,value:float,frozen:float,total:float = 0.0) -> void:
	if multiplayer.has_multiplayer_peer(): _cold_state.rpc(get_parent().get_path_to(target),value,frozen,total)
@rpc("authority","call_remote","reliable")
func _cold_state(path:NodePath,value:float,frozen:float,total:float = 0.0) -> void:
	var target:Node = get_parent().get_node_or_null(path)
	if target is ball and target.health > 0: COLD.ensure(target).accept_state(value,frozen,total)

func _cell_snapshot(cells:Array) -> Array:
	var result:Array = []
	for cell:Vector2i in cells:
		if patches.has(cell):
			var patch:Dictionary = patches[cell]
			result.append({"cell":cell,"tile":patch_tile(patch,cell),"level":2,"family":patch.family,"team":patch.team,"remaining":float(patch.get("expires_at",_melt_clock+full_snow_lifetime))-_melt_clock,"fade_duration":float(patch.get("fade_duration",snow_fade_duration))})
		else: result.append({"cell":cell,"level":0})
	return result

func _send_changes() -> void:
	if multiplayer.has_multiplayer_peer():
		if not _dirty_cells.is_empty(): _field_state.rpc(_cell_snapshot(_dirty_cells.keys()),[],false)
		if not _dirty_environment.is_empty():
			var updates:Array = []
			for cell:Vector2i in _dirty_environment:
				updates.append(environment_patches[cell] if environment_patches.has(cell) else {"cell":cell,"removed":true})
			_environment_state.rpc(_environment_payload(updates),false)
	_dirty_cells.clear()
	_dirty_environment.clear()

@rpc("authority","call_remote","reliable")
func _field_state(cells:Array,_retired_heads:Array,full:bool) -> void:
	if full: patches.clear()
	for item:Dictionary in cells:
		if int(item.level)<=0: patches.erase(item.cell)
		else:
			var patch:Dictionary = item.duplicate()
			patch["level"] = 2
			patch["tile"] = patch_tile(item,item.cell)
			patch["rects"] = [patch.tile]
			# Signed remaining melt time retains a partly completed fade on late join.
			patch["expires_at"] = _melt_clock+float(item.get("remaining",full_snow_lifetime))
			patch["fade_duration"] = maxf(float(item.get("fade_duration",snow_fade_duration)),0.01)
			patches[item.cell] = patch
	_indices_dirty = true
	_reschedule_melt()
	queue_redraw()

func _request_state() -> void:
	if multiplayer.has_multiplayer_peer(): _request_field.rpc_id(get_multiplayer_authority())
@rpc("any_peer","call_remote","reliable")
func _request_field() -> void:
	if not is_multiplayer_authority(): return
	var peer:int = multiplayer.get_remote_sender_id()
	_refresh_melt_rate()
	_melt_rate_state.rpc_id(peer,_melt_rate)
	_field_state.rpc_id(peer,_cell_snapshot(patches.keys()),[],true)
	_environment_state.rpc_id(peer,_environment_payload(environment_patches.values()),true)
	for cold:Node in get_tree().get_nodes_in_group("MCSnowCold"):
		if is_instance_valid(cold.target) and get_parent().is_ancestor_of(cold.target): _cold_state.rpc_id(peer,get_parent().get_path_to(cold.target),cold.amount,cold.frozen_left,cold.freeze_total)

func _hazard_rect(source:Node,rect:Rect2,receiver:ball,duration:float = 1.0) -> Dictionary:
	if not is_instance_valid(source) or source.is_damage_output_disabled() or not source.is_combat_runtime_active() or duration<=0.0: return {}
	var damage:float = float(source.attack_damage(source.snow_damage_multiplier))
	if damage<=0.0: return {}
	damage = maxf(1.0,roundf(damage))
	if is_instance_valid(receiver): damage *= receiver.get_cold_effect_ratio()
	return {"shape":"rect","position":rect.get_center(),"half_extents":rect.size*0.5,"rotation":0.0,"damage":damage,"danger_in":0.0,"danger_duration":duration,"control":float(source.snow_cold)/COLD.LIMIT,"kind":"cold_snow","source":source}

func get_ai_hazard_info(receiver:ball = null) -> Dictionary:
	if not runtime_active(): return {}
	if is_instance_valid(receiver) and (receiver.is_cold_immune() or receiver.get_world_2d()!=get_world_2d()): return {}
	var parts:Array[Dictionary] = []
	var ordinary:Dictionary = {}
	if _indices_dirty: _rebuild_environment_index()
	for cell:Vector2i in patches:
		if not _snow_damaging(patches[cell]): continue
		var golem:ball = _source(patches[cell])
		if not is_instance_valid(golem) or (receiver!=null and not RULES.enemy(golem,receiver)): continue
		var rect:Rect2 = patch_tile(patches[cell],cell)
		# Match contact priority even when the eligible trail source currently cannot damage.
		ordinary[cell] = rect
		var part:Dictionary = _hazard_rect(golem,rect,receiver,_remaining_damage_time(patches[cell]))
		if not part.is_empty(): parts.append(part)
	for record:Dictionary in environment_patches.values():
		if bool(record.decorative) or not _snow_damaging(record): continue
		for rect:Rect2 in record.rects:
			# One shared contact cooldown: don't draw overlapping hazards as two hits.
			var cuts:Array[Rect2] = []
			var low:Vector2i = _environment_bucket(rect.position)
			var high:Vector2i = _environment_bucket(rect.end)
			for y:int in range(low.y,high.y+1):
				for x:int in range(low.x,high.x+1):
					for key:Vector2i in _trail_ground_index.get(Vector2i(x,y),[]):
						if ordinary.has(key) and not ordinary[key] in cuts: cuts.append(ordinary[key])
			var area:Array[Rect2] = [rect]
			for piece:Rect2 in GEOMETRY.subtract(area,cuts):
				var part:Dictionary = _hazard_rect(environment_source,piece,receiver,_remaining_damage_time(record))
				if not part.is_empty(): parts.append(part)
	return {} if parts.is_empty() else {"shape":"compound","parts":parts,"damage":1.0,"source":self}

func get_debug_hazard_info() -> Dictionary:
	return get_ai_hazard_info(null)
