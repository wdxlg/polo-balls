extends Node2D
## One world controller; snow uses the existing sparse golem field, not a second damage system.
signal event_selected(event_id:String)
const CATALOG = preload("res://scripts/training/battle_conditions_catalog.gd")
const FIELD = preload("res://scripts/characters/我的世界/snow_golem/snow_field.gd")
const GEOMETRY = preload("res://classes/map_tile_geometry.gd")
const GOLEM:PackedScene = preload("res://scenes/characters/我的世界/雪傀儡.tscn")
const MAX_PATCHES:int = 1024
const MAX_CANDIDATES:int = 4096
const SNOW_INTERVAL:float = 0.45
var world:Node
var environment:String = "none"
var field:Node2D
var event_definitions:Array = CATALOG.EVENTS
var selected_event_count:int = 0
var last_event:String = ""
var snow_cold:float = 8.0
var freeze_duration:float = 1.4
var snow_tick_interval:float = 0.5
var snow_damage_multiplier:float = 1.0/3.0
var snow_attack:float = 9.0
var _profile_loaded:bool = false
var _rng:=RandomNumberGenerator.new()
var _event_rng:=RandomNumberGenerator.new()
var _seed:int = -1
var _map_key:String = ""
var _ground:Array[Rect2] = []
var _walls:Array[Rect2] = []
var _ground_candidates:Array[Dictionary] = []
var _wall_candidates:Array[Dictionary] = []
var _snow_left:float = SNOW_INTERVAL
var _event_seed:int = -1
var _layout_left:float = 0.0
var _generation:int = 0

func _init(owner_world:Node = null) -> void:
	world = owner_world
	name = "BattleConditions"

func _ready() -> void:
	set_multiplayer_authority(world.get_multiplayer_authority())
	Game.game_setting_changed.connect(_on_setting_changed)
	refresh_layout(true)

func attack_damage(multiplier:float = 1.0) -> float:
	return maxf(snow_attack,0.0)*maxf(multiplier,0.0)
func is_damage_output_disabled() -> bool: return environment!="snow"
func is_combat_runtime_active() -> bool:
	if get_tree()==null or get_tree().paused or Game.now_stop_state or Engine.time_scale<=0.000001: return false
	return bool(world.is_combat_runtime_active()) if world.has_method("is_combat_runtime_active") else true

func _load_profile() -> void:
	if _profile_loaded: return
	# Read configured defaults without entering the tree/spawning a hidden fighter.
	var defaults:Node = GOLEM.instantiate()
	snow_attack = float(defaults.Damage)
	for key:String in ["snow_cold","freeze_duration","snow_tick_interval","snow_damage_multiplier"]: set(key,defaults.get(key))
	defaults.free()
	_profile_loaded = true

func _weather_seed() -> int:
	return Game.derive_battle_random_seed("environment:snow",0) if Game.is_battle_random_active() else 1397636951

func refresh_layout(force:bool = false) -> void:
	if not is_instance_valid(world) or not world.has_method("_current_map_node"): return
	var choice:String = CATALOG.normalize_environment(Game.Game_Settings.get("Environment","none"))
	if choice=="none":
		environment = choice
		_generation += 1
		if is_instance_valid(field) and not field.is_queued_for_deletion(): field.clear_environment()
		_ground_candidates.clear()
		_wall_candidates.clear()
		return
	_load_profile()
	var previous:String = environment
	environment = choice
	var replaced:bool = not is_instance_valid(field) or field.is_queued_for_deletion()
	if replaced: field = FIELD.ensure(self,world)
	field.environment_source = self
	if not field._development_start_offsets.is_empty(): return # Same field moves existing snow with the maps.
	var map_node:Node = world._current_map_node()
	if not is_instance_valid(map_node): return
	var walls:Array[Rect2] = _wall_regions(map_node)
	if field.wall_view.visual_walls!=walls:
		field.wall_view.visual_walls = walls.duplicate()
		field.wall_view.queue_redraw()
	if not is_multiplayer_authority(): return # Only rendering follows local theme; clients never generate gameplay.
	var ground:Array[Rect2] = world.map_island_rects(map_node)
	var key:String = str(world.now_choose_map)
	var seed_value:int = _weather_seed()
	var restart:bool = force or replaced or previous!=choice or key!=_map_key or seed_value!=_seed
	if restart:
		_generation += 1
		field.clear_environment()
		_seed = seed_value
		_map_key = key
		_rng.seed = _seed
		_snow_left = SNOW_INTERVAL
	if restart or ground!=_ground or walls!=_walls:
		_ground = ground.duplicate()
		_walls = walls.duplicate()
		field.reconcile_environment(_ground,_walls)
		_rebuild_candidates()
	if restart: _seed_initial.call_deferred(_generation)

func _wall_regions(map_node:Node) -> Array[Rect2]:
	if world._is_grass_map_background():
		field.wall_view.z_index = 0 # Tile walls already render beneath the original snow field.
		return world._map_shape_walls(map_node)
	var result:Array[Rect2] = []
	# Blue maps have thin black frames, not Minecraft's full-width block walls.
	# Reuse the actual rendered segments, including door/portal gaps, instead of
	# painting decorative snow over invisible wall tiles or sealed doorways.
	var border:Node2D = world.map_border_segment_root
	if not is_instance_valid(border): return result
	field.wall_view.z_index = border.z_index-field.z_index+1
	for child:Node in border.get_children():
		if not child is Line2D or child.is_queued_for_deletion(): continue
		var line:Line2D = child
		if line.points.size()!=2: continue
		var a:Vector2 = line.to_global(line.points[0])
		var end:Vector2 = line.to_global(line.points[1])
		var width:float = maxf(line.width,0.0)
		if absf(a.y-end.y)<0.01: result.append(Rect2(minf(a.x,end.x),a.y-width*0.5,absf(a.x-end.x),width))
		elif absf(a.x-end.x)<0.01: result.append(Rect2(a.x-width*0.5,minf(a.y,end.y),width,absf(a.y-end.y)))
	return result

func _rebuild_candidates() -> void:
	_ground_candidates.clear()
	_wall_candidates.clear()
	var candidates:Dictionary = {}
	# Geometry coverage, not the union's outer rectangle: holes/portal gaps stay empty.
	var total_area:float = 0.0
	for rect:Rect2 in _ground: total_area += rect.get_area()
	var stride:int = maxi(1,int(ceil(sqrt(total_area/(FIELD.CELL*FIELD.CELL*MAX_CANDIDATES)))))
	for rect:Rect2 in _ground:
		var low:=Vector2i((rect.position/FIELD.CELL-Vector2.ONE*0.5).ceil())
		var high:=Vector2i((rect.end/FIELD.CELL+Vector2.ONE*0.5).floor())
		for y:int in range(low.y,high.y+1,stride):
			for x:int in range(low.x,high.x+1,stride):
				var cell:=Vector2i(x,y)
				if candidates.has(cell): continue
				var footprint:=Rect2(FIELD.point_at(cell)-Vector2.ONE*FIELD.CELL*0.5,Vector2.ONE*FIELD.CELL)
				if not GEOMETRY.subtract([footprint],_ground).is_empty(): continue
				var touches_wall:bool = false
				for wall:Rect2 in _walls:
					if footprint.intersects(wall):
						touches_wall = true
						break
				if touches_wall: continue
				candidates[cell] = {"cell":cell,"decorative":false,"rects":[footprint]}
	for record:Dictionary in candidates.values():
		if not field.environment_patches.has(record.cell): _ground_candidates.append(record)
	var wall_cells:Dictionary = {}
	for rect:Rect2 in _walls:
		var low:=Vector2i((rect.position/FIELD.CELL-Vector2.ONE*0.5).floor())
		var high:=Vector2i((rect.end/FIELD.CELL+Vector2.ONE*0.5).ceil())
		for y:int in range(low.y,high.y+1):
			for x:int in range(low.x,high.x+1):
				var cell:=Vector2i(x,y)
				if candidates.has(cell): continue
				var footprint:=Rect2(FIELD.point_at(cell)-Vector2.ONE*FIELD.CELL*0.5,Vector2.ONE*FIELD.CELL)
				var clipped:Rect2 = footprint.intersection(rect)
				if clipped.size.x<1.0 or clipped.size.y<1.0: continue
				if not wall_cells.has(cell): wall_cells[cell] = {"cell":cell,"decorative":true,"rects":[]}
				wall_cells[cell].rects.append(clipped)
	for record:Dictionary in wall_cells.values():
		if not field.environment_patches.has(record.cell): _wall_candidates.append(record)
	_shuffle(_ground_candidates)
	_shuffle(_wall_candidates)

func _shuffle(values:Array) -> void:
	for i:int in range(values.size()-1,0,-1):
		var j:int = _rng.randi_range(0,i)
		var saved:Variant = values[i]
		values[i] = values[j]
		values[j] = saved

func _seed_initial(generation:int) -> void:
	await get_tree().physics_frame # Let map collision transforms settle, even during setup.
	if generation!=_generation or environment!="snow" or not is_multiplayer_authority() or not is_instance_valid(field): return
	for i:int in range(8): _spawn_from(_ground_candidates)
	for i:int in range(4): _spawn_from(_wall_candidates)

func _spawn_from(candidates:Array[Dictionary]) -> bool:
	if not is_instance_valid(field) or field.is_queued_for_deletion() or field.environment_patches.size()>=MAX_PATCHES: return false
	var attempts:int = 0
	while not candidates.is_empty() and attempts<32:
		attempts += 1
		var record:Dictionary = candidates.pop_back()
		if field.environment_patches.has(record.cell): continue
		if not bool(record.decorative) and not field.can_place(null,record.cell,false): continue
		return field.add_environment_patch(self,record)
	return false

func draw_selected_event() -> String:
	if not is_multiplayer_authority() or not is_combat_runtime_active(): return ""
	var current_seed:int = Game.derive_battle_random_seed("training:events",0) if Game.is_battle_random_active() else 1163284052
	if current_seed!=_event_seed:
		_event_seed = current_seed
		_event_rng.seed = current_seed
	var id:String = CATALOG.pick_event(Game.Game_Settings,_event_rng,event_definitions)
	if not id.is_empty():
		last_event = id
		selected_event_count += 1
		event_selected.emit(id) # Future event implementations connect here; no placeholder effects.
	return id

func advance(delta:float) -> void:
	if not is_finite(delta) or delta<=0.0 or not is_combat_runtime_active() or not is_multiplayer_authority(): return
	if environment=="snow" and is_instance_valid(field) and not field.is_queued_for_deletion():
		_snow_left -= delta
		var guard:int = 0
		while _snow_left<=0.0 and guard<16:
			_snow_left += SNOW_INTERVAL
			guard += 1
			if _rng.randf()<0.25:
				if not _spawn_from(_wall_candidates): _spawn_from(_ground_candidates)
			elif not _spawn_from(_ground_candidates): _spawn_from(_wall_candidates)

func _physics_process(delta:float) -> void:
	_layout_left -= delta
	if _layout_left<=0.0:
		_layout_left = 0.5
		refresh_layout()
	advance(delta)

func _on_setting_changed(key:String,_value:Variant) -> void:
	if key=="Environment": refresh_layout(true)
