extends Node2D
const GEOMETRY = preload("res://classes/map_tile_geometry.gd")
const RENDERER = preload("res://scripts/effects/我的世界/mc_block_3d_renderer.gd")
const MESH = preload("res://scripts/characters/我的世界/bucket/fluid_mesh.gd")
const BLOCK = preload("res://scripts/characters/我的世界/bucket/fluid_block.gd")
const OXYGEN = preload("res://scripts/characters/我的世界/bucket/oxygen_display.gd")
const PARTICLES = preload("res://scripts/characters/我的世界/bucket/fluid_particles.gd")
const AUDIO = preload("res://scripts/characters/我的世界/bucket/bucket_audio.gd")
const SMOKE = preload("res://scripts/characters/我的世界/torch/torch_particles.gd")
const KNOCK = preload("res://scripts/effects/knockback_effect.gd")
const FIRE = preload("res://scripts/characters/我的世界/torch/torch_fire.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const ENCHANTS_PATH:String = "res://scripts/effects/我的世界/mc_enchantments.gd"
const SCRIPT_PATH:String = "res://scripts/characters/我的世界/bucket/fluid_field.gd"
const NODE_NAME:String = "MCFluidField"
const WATER:int = 0
const LAVA:int = 1
const STONE:int = 0
const OBSIDIAN:int = 1
const SOURCE_STRENGTH:Array[int] = [8,4]
const STEP_SECONDS:Array[float] = [0.25,1.5]
const DRAIN_STEP_SECONDS:float = 0.3
const LAVA_SECONDS:float = 10.0
const WATER_PUSH:float = 60.0
const LAVA_SLOW:float = 0.5
const LAVA_TICK:float = 0.5
const LAVA_DAMAGE_MULTIPLIER:float = 1.0
const LAVA_BURN_SECONDS:float = 4.0
const LAVA_BURN_MULTIPLIER:float = 0.3
const AIR_SECONDS:float = 10.0
const AIR_RECOVER_SECONDS:float = 3.0
const DROWN_TICK:float = 1.0
const DROWN_RATIO:float = 0.10
const BLOCK_SECONDS:Array[float] = [5.0,10.0]
const DIRS:Array[Vector2i] = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
const SOLID_CHECK_SECONDS:float = 0.5
const SEND_INTERVAL:float = 0.1
const AIR_SEND_INTERVAL:float = 0.1
const SLOW_KEY:StringName = &"mc_lava"
const FLUID_Z:int = -3
const WATER_ALPHA:float = 0.78
const AQUATIC_SCENES:Array[String] = ["溺尸","守卫者"]

var grid_size:Vector2 = Vector2.ONE * 16.0
var grid_origin:Vector2 = Vector2.ZERO
var floor_cells:Dictionary = {}
var levels:Array[Dictionary] = [{},{}]
var sources:Array[Dictionary] = [{},{}]
var blocks:Dictionary = {}
var drains:Array[Dictionary] = []
var air:Dictionary = {}
var clock:float = 0.0
var _target:Array[Dictionary] = [{},{}]
var _target_owner:Dictionary = {}
var _dirty:Array[bool] = [true,true]
var _step_left:Array[float] = [0.0,0.0]
var _drain_left:float = 0.0
var _solid:Dictionary = {}
var _solid_left:float = 0.0
var _grid_key:String = ""
var _grid_left:float = 0.0
var _send_left:float = 0.0
var _state_dirty:bool = false
var _air_send_left:float = 0.0
var _remote_air:Dictionary = {}
var _lava_wait:Dictionary = {}
var _renderers:Array = [null,null]
var _mesh_nodes:Array = [null,null]
var _materials:Array = [[null,null],[null,null]]
var _mesh_dirty:Array[bool] = [true,true]
var _anim_time:float = 0.0
var _oxygen:Node2D
var _particles:Node2D
var _fx_rng := RandomNumberGenerator.new()
var _ambient_left:Array[float] = [1.5,1.0]
var _bubble_left:float = 0.0
var _fizz_left:float = 0.0
var _sound_serial:int = 0


static func ensure(context:Node) -> Node2D:
	var world:Node = _world_of(context)
	if world == null: return null
	var existing:Node = world.get_node_or_null(NODE_NAME)
	if is_instance_valid(existing) and not existing.is_queued_for_deletion(): return existing as Node2D
	var field:Node2D = load(SCRIPT_PATH).new()
	field.name = NODE_NAME
	field.set_multiplayer_authority(world.get_multiplayer_authority())
	world.add_child(field)
	return field


static func find(context:Node) -> Node2D:
	var world:Node = _world_of(context)
	if world == null: return null
	var existing:Node = world.get_node_or_null(NODE_NAME)
	return existing as Node2D if is_instance_valid(existing) and not existing.is_queued_for_deletion() else null


static func _world_of(context:Node) -> Node:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var world:Node = context
	while is_instance_valid(world) and not world.has_method("_current_map_node"): world = world.get_parent()
	return world if is_instance_valid(world) else context.get_tree().current_scene


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MCFluidField")
	z_as_relative = false
	z_index = FLUID_Z
	_fx_rng.randomize()
	_oxygen = OXYGEN.new()
	_oxygen.field = self
	add_child(_oxygen)
	_particles = PARTICLES.new()
	add_child(_particles)
	_rebuild_grid()
	if not is_multiplayer_authority(): get_tree().create_timer(0.5,false).timeout.connect(_request_state)


func _exit_tree() -> void:
	for f:int in [WATER,LAVA]:
		if is_instance_valid(_renderers[f]): (_renderers[f] as Node).queue_free()
		_renderers[f] = null
		_mesh_nodes[f] = null
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball: KNOCK.release_pull(node,self)


func runtime_active() -> bool:
	if get_tree() == null or get_tree().paused or Game.now_stop_state or Engine.time_scale <= 0.000001: return false
	var world:Node = get_parent()
	return bool(world.call("is_combat_runtime_active")) if world != null and world.has_method("is_combat_runtime_active") else true


func cell_of(point:Vector2) -> Vector2i:
	return Vector2i(((point - grid_origin) / grid_size).floor())


func cell_center(cell:Vector2i) -> Vector2:
	return grid_origin + (Vector2(cell) + Vector2(0.5,0.5)) * grid_size


func cell_rect(cell:Vector2i) -> Rect2:
	return Rect2(grid_origin + Vector2(cell) * grid_size,grid_size)


func particles() -> Node2D:
	return _particles


func oxygen_display() -> Node2D:
	return _oxygen


func has_fluid(liquid:int,cell:Vector2i) -> bool:
	return levels[liquid].has(cell)


func fluid_at(point:Vector2) -> int:
	var cell:Vector2i = cell_of(point)
	if levels[WATER].has(cell): return WATER
	if levels[LAVA].has(cell): return LAVA
	return -1


func is_source(liquid:int,cell:Vector2i) -> bool:
	return sources[liquid].has(cell)


func fluid_height(liquid:int,cell:Vector2i) -> float:
	return float(levels[liquid].get(cell,0)) / float(SOURCE_STRENGTH[liquid]) * MESH.FULL_HEIGHT


func is_open_cell(cell:Vector2i) -> bool:
	return floor_cells.has(cell) and not blocks.has(cell) and not _solid.has(cell)


func passable(liquid:int,cell:Vector2i) -> bool:
	return is_open_cell(cell) and not levels[1 - liquid].has(cell)


func flow_vector(liquid:int,cell:Vector2i) -> Vector2:
	if not levels[liquid].has(cell): return Vector2.ZERO
	var height:float = fluid_height(liquid,cell)
	var result:Vector2 = Vector2.ZERO
	for d:Vector2i in DIRS:
		var other:Vector2i = cell + d
		if not levels[liquid].has(other): continue
		result += Vector2(d) * (height - fluid_height(liquid,other))
	return result.normalized() if result.length_squared() > 0.000001 else Vector2.ZERO


func _rebuild_grid() -> void:
	var world:Node = get_parent()
	var size:Vector2 = Vector2.ONE * 16.0
	var islands:Array = []
	if world != null and world.has_method("_current_map_node"):
		var map:Node = world.call("_current_map_node")
		if is_instance_valid(map):
			if world.has_method("map_visual_cell_size"): size = world.call("map_visual_cell_size",map)
			if world.has_method("map_islands"): islands = world.call("map_islands",map)
	size = size.max(Vector2.ONE)
	var regions:Array[Rect2] = []
	for island:Dictionary in islands:
		for region:Variant in island.get("regions",[]):
			if region is Rect2: regions.append(region)
	var key:String = var_to_str([size,regions])
	if key == _grid_key: return
	var first:bool = _grid_key.is_empty()
	_grid_key = key
	grid_size = size
	grid_origin = regions[0].position if not regions.is_empty() else Vector2.ZERO
	floor_cells.clear()
	for region:Rect2 in regions:
		var a:Vector2i = cell_of(region.position + Vector2.ONE * 0.01)
		var b:Vector2i = cell_of(region.end - Vector2.ONE * 0.01)
		for y:int in range(a.y,b.y + 1):
			for x:int in range(a.x,b.x + 1):
				var cell := Vector2i(x,y)
				if floor_cells.has(cell): continue
				var area:Array[Rect2] = [cell_rect(cell).grow(-0.01)]
				if GEOMETRY.subtract(area,regions).is_empty(): floor_cells[cell] = true
	if not first: clear_all()


func clear_all() -> void:
	for f:int in [WATER,LAVA]:
		levels[f] = {}
		sources[f] = {}
		_target[f] = {}
		_dirty[f] = true
		_mesh_dirty[f] = true
	_target_owner.clear()
	drains.clear()
	for node:Variant in blocks.values():
		if is_instance_valid(node): (node as Node).queue_free()
	blocks.clear()
	_solid.clear()
	_state_dirty = true


func _refresh_solid() -> void:
	var cells:Dictionary = {}
	for f:int in [WATER,LAVA]:
		for cell:Vector2i in levels[f]:
			cells[cell] = true
			for d:Vector2i in DIRS: cells[cell + d] = true
		for cell:Vector2i in sources[f]: cells[cell] = true
	var fresh:Dictionary = {}
	var space:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for cell:Vector2i in cells:
		if not floor_cells.has(cell) or blocks.has(cell): continue
		query.position = cell_center(cell)
		for hit:Dictionary in space.intersect_point(query,8):
			var collider:Object = hit.get("collider")
			if collider is StaticBody2D and not (collider as Node).is_in_group("MCFluidBlock"):
				fresh[cell] = true
				break
			if collider is TileMapLayer:
				fresh[cell] = true
				break
	if fresh != _solid:
		_solid = fresh
		_dirty[WATER] = true
		_dirty[LAVA] = true
		_mesh_dirty[WATER] = true
		_mesh_dirty[LAVA] = true


func _recompute_target(liquid:int) -> void:
	var strength:int = SOURCE_STRENGTH[liquid]
	var target:Dictionary = {}
	var owner:Dictionary = {}
	var queue:Array[Vector2i] = []
	for cell:Vector2i in sources[liquid]:
		if not passable(liquid,cell): continue
		target[cell] = strength
		owner[cell] = sources[liquid][cell].get("owner")
		queue.append(cell)
	var head:int = 0
	while head < queue.size():
		var cell:Vector2i = queue[head]
		head += 1
		var value:int = int(target[cell]) - 1
		if value <= 0: continue
		for d:Vector2i in DIRS:
			var other:Vector2i = cell + d
			if int(target.get(other,0)) >= value or not passable(liquid,other): continue
			target[other] = value
			owner[other] = owner[cell]
			queue.append(other)
	_target[liquid] = target
	if liquid == LAVA: _target_owner = owner
	_dirty[liquid] = false


func _ensure_targets() -> void:
	for f:int in [WATER,LAVA]:
		if _dirty[f]: _recompute_target(f)


func _drain_holds(cell:Vector2i) -> bool:
	for drain:Dictionary in drains:
		var dist:Dictionary = drain.dist
		if dist.has(cell) and int(dist[cell]) > int(drain.front): return true
	return false


func step_liquid(liquid:int) -> void:
	_ensure_targets()
	var current:Dictionary = levels[liquid]
	var candidates:Dictionary = {}
	for cell:Vector2i in current:
		candidates[cell] = true
		for d:Vector2i in DIRS: candidates[cell + d] = true
	for cell:Vector2i in sources[liquid]: candidates[cell] = true
	var strength:int = SOURCE_STRENGTH[liquid]
	var next:Dictionary = {}
	for cell:Vector2i in candidates:
		if not passable(liquid,cell): continue
		var have:int = int(current.get(cell,0))
		var target:int = int(_target[liquid].get(cell,0))
		var value:int = 0
		if sources[liquid].has(cell):
			value = strength
		elif target >= have:
			var grow:int = 0
			for d:Vector2i in DIRS:
				var other:Vector2i = cell + d
				if passable(liquid,other): grow = maxi(grow,int(current.get(other,0)) - 1)
			value = mini(target,maxi(have,grow))
		elif liquid == LAVA and _drain_holds(cell):
			value = have
		else:
			value = maxi(target,have - 1)
		if value > 0: next[cell] = value
	if next != current:
		levels[liquid] = next
		_changed(liquid)
	if liquid == WATER: _convert_infinite_sources()
	_interact()


func _convert_infinite_sources() -> void:
	var fresh:Array[Vector2i] = []
	for cell:Vector2i in levels[WATER]:
		if sources[WATER].has(cell): continue
		var count:int = 0
		for d:Vector2i in DIRS:
			if sources[WATER].has(cell + d): count += 1
		if count >= 2: fresh.append(cell)
	for cell:Vector2i in fresh:
		sources[WATER][cell] = {"owner":null,"team":"","until":-1.0}
		levels[WATER][cell] = SOURCE_STRENGTH[WATER]
	if not fresh.is_empty():
		_dirty[WATER] = true
		_changed(WATER)


func _interact() -> void:
	var convert:Array[Vector2i] = []
	for cell:Vector2i in levels[LAVA]:
		var touch:bool = levels[WATER].has(cell)
		if not touch:
			for d:Vector2i in DIRS:
				if levels[WATER].has(cell + d):
					touch = true
					break
		if touch: convert.append(cell)
	for cell:Vector2i in convert:
		if blocks.has(cell): continue
		place_block(cell,OBSIDIAN if sources[LAVA].has(cell) else STONE)


func _add_drain(origin:Vector2i) -> void:
	var dist:Dictionary = {origin:0}
	var queue:Array[Vector2i] = [origin]
	var head:int = 0
	var far:int = 0
	while head < queue.size():
		var cell:Vector2i = queue[head]
		head += 1
		for d:Vector2i in DIRS:
			var other:Vector2i = cell + d
			if dist.has(other) or not levels[LAVA].has(other): continue
			dist[other] = int(dist[cell]) + 1
			far = maxi(far,int(dist[other]))
			queue.append(other)
	var drain:Dictionary = {"origin":origin,"dist":dist,"front":-1,"far":far}
	drains.append(drain)
	_advance_drain(drain)


func _advance_drain(drain:Dictionary) -> void:
	_ensure_targets()
	drain.front = int(drain.front) + 1
	var dist:Dictionary = drain.dist
	var changed:bool = false
	for cell:Vector2i in dist:
		if int(dist[cell]) > int(drain.front) or not levels[LAVA].has(cell): continue
		var target:int = int(_target[LAVA].get(cell,0))
		if target >= int(levels[LAVA][cell]): continue
		if target <= 0: levels[LAVA].erase(cell)
		else: levels[LAVA][cell] = target
		changed = true
	if changed: _changed(LAVA)


func _step_drains() -> void:
	if drains.is_empty(): return
	for drain:Dictionary in drains.duplicate():
		_advance_drain(drain)
		if int(drain.front) >= int(drain.far): drains.erase(drain)


func _changed(liquid:int) -> void:
	_mesh_dirty[liquid] = true
	_state_dirty = true


func pick_place_cell(liquid:int,point:Vector2) -> Variant:
	if floor_cells.is_empty(): _rebuild_grid()
	var here:Vector2i = cell_of(point)
	var options:Array[Vector2i] = [here]
	var around:Array[Vector2i] = []
	for d:Vector2i in DIRS: around.append(here + d)
	around.sort_custom(func(a:Vector2i,b:Vector2i) -> bool: return cell_center(a).distance_squared_to(point) < cell_center(b).distance_squared_to(point))
	options.append_array(around)
	for cell:Vector2i in options:
		if not is_open_cell(cell) or levels[1 - liquid].has(cell) or sources[liquid].has(cell): continue
		return cell
	return null


func place_source(liquid:int,cell:Vector2i,source:Node) -> bool:
	if not is_multiplayer_authority() or not is_open_cell(cell): return false
	var point:Vector2 = cell_center(cell)
	if levels[1 - liquid].has(cell):
		if liquid == LAVA or sources[LAVA].has(cell):
			place_block(cell,OBSIDIAN)
			_emit_sound(AUDIO.KIND_EMPTY if liquid == WATER else AUDIO.KIND_EMPTY_LAVA,point)
			return true
		levels[LAVA].erase(cell)
		_dirty[LAVA] = true
		_changed(LAVA)
	var team:String = str(source.get("Team")) if is_instance_valid(source) and source.get("Team") != null else ""
	sources[liquid][cell] = {"owner":weakref(source) if is_instance_valid(source) else null,"team":team,"until":clock + LAVA_SECONDS if liquid == LAVA else -1.0}
	levels[liquid][cell] = SOURCE_STRENGTH[liquid]
	_dirty[liquid] = true
	_changed(liquid)
	_emit_sound(AUDIO.KIND_EMPTY if liquid == WATER else AUDIO.KIND_EMPTY_LAVA,point)
	_emit_place_fx(liquid,point)
	_interact()
	return true


func place_block(cell:Vector2i,kind:int) -> void:
	if not is_multiplayer_authority() or blocks.has(cell): return
	var drained:bool = sources[LAVA].has(cell)
	for f:int in [WATER,LAVA]:
		levels[f].erase(cell)
		sources[f].erase(cell)
		_dirty[f] = true
		_changed(f)
	_spawn_block(cell,kind,BLOCK_SECONDS[kind],0.0)
	if multiplayer.has_multiplayer_peer(): _receive_block.rpc(cell.x,cell.y,kind,BLOCK_SECONDS[kind])
	if drained: _add_drain(cell)
	_ensure_targets()
	if _fizz_left <= 0.0:
		_fizz_left = 0.12
		_emit_sound(AUDIO.KIND_FIZZ,cell_center(cell))
	_emit_fizz_fx(cell_center(cell))


func _spawn_block(cell:Vector2i,kind:int,seconds:float,start_age:float) -> Node:
	if blocks.has(cell) and is_instance_valid(blocks[cell]): return blocks[cell]
	var node:StaticBody2D = BLOCK.new()
	node.setup(self,cell,kind,seconds,cell_rect(cell),start_age)
	blocks[cell] = node
	get_parent().add_child(node)
	_dirty[WATER] = true
	_dirty[LAVA] = true
	_mesh_dirty[WATER] = true
	_mesh_dirty[LAVA] = true
	return node


@rpc("authority","call_remote","reliable")
func _receive_block(x:int,y:int,kind:int,seconds:float) -> void:
	_spawn_block(Vector2i(x,y),kind,seconds,0.0)


func block_removed(cell:Vector2i,node:Node) -> void:
	if blocks.get(cell) == node: blocks.erase(cell)
	_dirty[WATER] = true
	_dirty[LAVA] = true
	_mesh_dirty[WATER] = true
	_mesh_dirty[LAVA] = true


func remove_source(liquid:int,cell:Vector2i) -> void:
	if not sources[liquid].has(cell): return
	sources[liquid].erase(cell)
	_dirty[liquid] = true
	_state_dirty = true
	if liquid == LAVA: _add_drain(cell)


func owner_died(owner:Node) -> void:
	if not is_multiplayer_authority(): return
	for cell:Vector2i in sources[LAVA].keys():
		var ref:Variant = sources[LAVA][cell].get("owner")
		if ref is WeakRef and (ref as WeakRef).get_ref() == owner: remove_source(LAVA,cell)


func _expire_lava() -> void:
	for cell:Vector2i in sources[LAVA].keys():
		var entry:Dictionary = sources[LAVA][cell]
		var ref:Variant = entry.get("owner")
		var owner:Variant = (ref as WeakRef).get_ref() if ref is WeakRef else null
		var dead:bool = not is_instance_valid(owner) or float(owner.get("health")) <= 0.0
		if dead or (float(entry.until) >= 0.0 and clock >= float(entry.until)): remove_source(LAVA,cell)


func lava_owner(cell:Vector2i) -> ball:
	_ensure_targets()
	var ref:Variant = _target_owner.get(cell)
	if ref == null:
		var best:float = INF
		for source:Vector2i in sources[LAVA]:
			var d:float = Vector2(source - cell).length()
			if d < best:
				best = d
				ref = sources[LAVA][source].get("owner")
	var owner:Variant = (ref as WeakRef).get_ref() if ref is WeakRef else null
	return owner as ball if owner is ball and is_instance_valid(owner) else null


func immune_to_water(unit:Node) -> bool:
	if unit.is_in_group("MCWaterBucket"): return true
	var path:String = str(unit.get("scene_file_path"))
	for word:String in AQUATIC_SCENES:
		if path.contains(word): return true
	return false


func _oxygen_loss(unit:Node) -> float:
	var script:Script = load(ENCHANTS_PATH)
	if script == null or not script.has_method("resolve_event"): return 1.0
	var resolved:Dictionary = script.call("resolve_event",unit,"oxygen",{})
	return maxf(float(resolved.get("oxygen_loss_multiplier",1.0)),0.0)


func _units() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not (node is ball) or node.is_queued_for_deletion() or float(node.health) <= 0.0: continue
		result.append(node as ball)
	return result


func _apply_effects(delta:float) -> void:
	var seen:Dictionary = {}
	for unit:ball in _units():
		if not unit.is_multiplayer_authority(): continue
		var id:int = unit.get_instance_id()
		seen[id] = true
		var cell:Vector2i = cell_of(unit.global_position)
		var wet:bool = levels[WATER].has(cell) and not immune_to_water(unit)
		if wet:
			var flow:Vector2 = flow_vector(WATER,cell)
			if flow != Vector2.ZERO: KNOCK.set_pull(unit,self,flow * WATER_PUSH)
		_update_air(unit,wet,delta)
		if levels[LAVA].has(cell): _lava_contact(unit,cell,delta)
		else: _lava_wait.erase(id)
	for id:Variant in air.keys():
		if not seen.has(id): air.erase(id)


func _update_air(unit:ball,wet:bool,delta:float) -> void:
	var id:int = unit.get_instance_id()
	var entry:Dictionary = air.get(id,{})
	if entry.is_empty():
		if not wet: return
		entry = {"unit":weakref(unit),"air":AIR_SECONDS,"drown":DROWN_TICK,"wet":false}
		air[id] = entry
	if wet:
		entry.air = maxf(float(entry.air) - delta * _oxygen_loss(unit),0.0)
		if float(entry.air) <= 0.0:
			entry.drown = float(entry.drown) - delta
			if float(entry.drown) <= 0.0:
				entry.drown = float(entry.drown) + DROWN_TICK
				_drown(unit)
	else:
		entry.air = minf(float(entry.air) + delta * AIR_SECONDS / AIR_RECOVER_SECONDS,AIR_SECONDS)
		entry.drown = DROWN_TICK
	entry.wet = wet
	if not wet and float(entry.air) >= AIR_SECONDS: air.erase(id)


func _drown(unit:ball) -> void:
	var amount:float = float(unit.Max_health) * DROWN_RATIO
	if unit.receive_classified_spatial_damage(amount,{"point":unit.global_position,"source":self,"carrier":"status_tick"},&"drowning",true,true):
		_emit_sound(AUDIO.KIND_DROWN,unit.global_position)


func _lava_contact(unit:ball,cell:Vector2i,delta:float) -> void:
	var owner:ball = lava_owner(cell)
	if owner == null or owner.health <= 0 or owner.is_damage_output_disabled() or not U.enemy(owner,unit): return
	unit.set_motion_speed_factor(SLOW_KEY,self,LAVA_SLOW,0.25)
	var id:int = unit.get_instance_id()
	var wait:float = float(_lava_wait.get(id,0.0)) - delta
	if wait > 0.0:
		_lava_wait[id] = wait
		return
	_lava_wait[id] = wait + LAVA_TICK if wait > -LAVA_TICK else LAVA_TICK
	if unit.receive_fire_positional_damage(owner.attack_damage(LAVA_DAMAGE_MULTIPLIER),unit.global_position,false,owner,{"carrier":"area"}):
		FIRE.apply_burn(owner,unit,LAVA_BURN_SECONDS,owner.attack_damage(LAVA_BURN_MULTIPLIER))


func air_view() -> Dictionary:
	var result:Dictionary = {}
	if is_multiplayer_authority():
		for id:Variant in air.keys():
			var entry:Dictionary = air[id]
			var unit:Variant = (entry.unit as WeakRef).get_ref()
			if is_instance_valid(unit): result[id] = {"unit":unit,"ratio":float(entry.air) / AIR_SECONDS,"wet":bool(entry.wet)}
		return result
	for path:Variant in _remote_air.keys():
		var unit:Node = get_node_or_null(NodePath(str(path)))
		if unit == null: continue
		var data:Array = _remote_air[path]
		result[unit.get_instance_id()] = {"unit":unit,"ratio":float(data[0]),"wet":bool(data[1])}
	return result


func air_ratio(unit:Node) -> float:
	var entry:Dictionary = air.get(unit.get_instance_id(),{})
	return float(entry.get("air",AIR_SECONDS)) / AIR_SECONDS


func _physics_process(delta:float) -> void:
	_grid_left -= delta
	if _grid_left <= 0.0:
		_grid_left = 0.5
		_rebuild_grid()
	if not is_multiplayer_authority() or not runtime_active(): return
	clock += delta
	_fizz_left = maxf(_fizz_left - delta,0.0)
	_solid_left -= delta
	if _solid_left <= 0.0:
		_solid_left = SOLID_CHECK_SECONDS
		_refresh_solid()
	_expire_lava()
	for f:int in [WATER,LAVA]:
		_step_left[f] -= delta
		if _step_left[f] <= 0.0:
			_step_left[f] += STEP_SECONDS[f]
			if _step_left[f] <= 0.0: _step_left[f] = STEP_SECONDS[f]
			step_liquid(f)
	_drain_left -= delta
	if _drain_left <= 0.0:
		_drain_left = DRAIN_STEP_SECONDS
		_step_drains()
	_apply_effects(delta)
	_send_left -= delta
	if _send_left <= 0.0:
		_send_left = SEND_INTERVAL
		if _state_dirty:
			_state_dirty = false
			if multiplayer.has_multiplayer_peer(): _receive_state.rpc(_pack(WATER),_pack(LAVA))
	_air_send_left -= delta
	if _air_send_left <= 0.0:
		_air_send_left = AIR_SEND_INTERVAL
		if multiplayer.has_multiplayer_peer(): _receive_air.rpc(_pack_air())


func _pack(liquid:int) -> PackedInt32Array:
	var packed := PackedInt32Array()
	for cell:Vector2i in levels[liquid]:
		packed.append(cell.x)
		packed.append(cell.y)
		packed.append(int(levels[liquid][cell]) + (100 if sources[liquid].has(cell) else 0))
	return packed


func _unpack(liquid:int,packed:PackedInt32Array) -> void:
	var fresh:Dictionary = {}
	var fresh_sources:Dictionary = {}
	for i:int in range(0,packed.size() - 2,3):
		var cell := Vector2i(packed[i],packed[i + 1])
		var value:int = packed[i + 2]
		if value >= 100:
			fresh_sources[cell] = {"owner":null,"team":"","until":-1.0}
			value -= 100
		fresh[cell] = value
	levels[liquid] = fresh
	sources[liquid] = fresh_sources
	_mesh_dirty[liquid] = true


@rpc("authority","call_remote","reliable")
func _receive_state(water:PackedInt32Array,lava:PackedInt32Array) -> void:
	_unpack(WATER,water)
	_unpack(LAVA,lava)


func _pack_air() -> Dictionary:
	var packed:Dictionary = {}
	for id:Variant in air.keys():
		var entry:Dictionary = air[id]
		var unit:Variant = (entry.unit as WeakRef).get_ref()
		if is_instance_valid(unit): packed[str(get_path_to(unit))] = [float(entry.air) / AIR_SECONDS,bool(entry.wet)]
	return packed


@rpc("authority","call_remote","unreliable_ordered")
func _receive_air(packed:Dictionary) -> void:
	_remote_air = packed


func _request_state() -> void:
	if is_inside_tree() and multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_request_full.rpc_id(get_multiplayer_authority())


@rpc("any_peer","call_remote","reliable")
func _request_full() -> void:
	if not is_multiplayer_authority(): return
	var peer:int = multiplayer.get_remote_sender_id()
	_receive_state.rpc_id(peer,_pack(WATER),_pack(LAVA))
	for cell:Vector2i in blocks:
		var node:Variant = blocks[cell]
		if is_instance_valid(node): _receive_block.rpc_id(peer,cell.x,cell.y,int(node.kind),float(node.duration) - float(node.age))


func _emit_sound(kind:int,point:Vector2) -> void:
	_sound_serial += 1
	var index:int = _sound_serial % maxi(AUDIO.variant_count(kind),1)
	var pitch:float = 1.0
	if kind == AUDIO.KIND_FIZZ: pitch = 2.0 + float(_sound_serial % 5) * 0.16
	if multiplayer.has_multiplayer_peer(): _receive_sound.rpc(kind,index,point,pitch)
	AUDIO.play(self,kind,index,point,pitch)


@rpc("authority","call_remote","reliable")
func _receive_sound(kind:int,index:int,point:Vector2,pitch:float) -> void:
	AUDIO.play(self,kind,index,point,pitch)


func _emit_place_fx(liquid:int,point:Vector2) -> void:
	if multiplayer.has_multiplayer_peer(): _receive_place_fx.rpc(liquid,point)
	_receive_place_fx(liquid,point)


@rpc("authority","call_remote","reliable")
func _receive_place_fx(liquid:int,point:Vector2) -> void:
	if not is_instance_valid(_particles): return
	if liquid == WATER: _particles.splash(point,14,minf(grid_size.x,grid_size.y) * 0.4)
	else:
		for i:int in range(5): _particles.lava_pop(point + Vector2(_fx_rng.randf_range(-6.0,6.0),_fx_rng.randf_range(-4.0,4.0)))


func _emit_fizz_fx(point:Vector2) -> void:
	if multiplayer.has_multiplayer_peer(): _receive_fizz_fx.rpc(point)
	_receive_fizz_fx(point)


@rpc("authority","call_remote","reliable")
func _receive_fizz_fx(point:Vector2) -> void:
	var fx:Node2D = SMOKE.find_or_create(self)
	if fx == null: return
	var half:float = minf(grid_size.x,grid_size.y) * 0.4
	for i:int in range(8):
		fx.smoke(point + Vector2(_fx_rng.randf_range(-half,half),_fx_rng.randf_range(-half,half)),true,0.55)


func _process(delta:float) -> void:
	if runtime_active(): _anim_time += delta
	for f:int in [WATER,LAVA]:
		if _mesh_dirty[f]:
			_mesh_dirty[f] = false
			_rebuild_mesh(f)
		_apply_frames(f)
	if runtime_active(): _ambient(delta)


func _ensure_renderer(liquid:int) -> Node2D:
	if is_instance_valid(_renderers[liquid]): return _renderers[liquid]
	var world:Node = get_parent()
	if world == null: return null
	var renderer:Node2D = RENDERER.new()
	renderer.name = ("MCFluidWaterRenderer" if liquid == WATER else "MCFluidLavaRenderer")
	renderer.set_meta(RENDERER.USERS_META,0)
	world.add_child(renderer)
	renderer.configure_block_overlay(minf(grid_size.x,grid_size.y),RENDERER.GROUND)
	renderer.z_as_relative = false
	renderer.z_index = FLUID_Z
	renderer.shadow_picture.visible = false
	if liquid == WATER: renderer.picture.modulate.a = WATER_ALPHA
	renderer.set_active(false)
	_renderers[liquid] = renderer
	return renderer


func renderer(liquid:int) -> Node2D:
	return _renderers[liquid] if is_instance_valid(_renderers[liquid]) else null


func mesh_instance(liquid:int) -> MeshInstance3D:
	return _mesh_nodes[liquid] if is_instance_valid(_mesh_nodes[liquid]) else null


func _rebuild_mesh(liquid:int) -> void:
	if levels[liquid].is_empty():
		if is_instance_valid(_mesh_nodes[liquid]): (_mesh_nodes[liquid] as MeshInstance3D).mesh = null
		if is_instance_valid(_renderers[liquid]): _renderers[liquid].set_active(false)
		return
	var shared:Node2D = _ensure_renderer(liquid)
	if shared == null or not is_instance_valid(shared.get("viewport")): return
	if not is_instance_valid(_mesh_nodes[liquid]):
		var node := MeshInstance3D.new()
		node.name = "NativeFluid"
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shared.viewport.add_child(node)
		_mesh_nodes[liquid] = node
	var built:Dictionary = MESH.build(self,liquid)
	var node:MeshInstance3D = _mesh_nodes[liquid]
	node.mesh = built.mesh
	var surfaces:Array[int] = built.surfaces
	for index:int in range(surfaces.size()):
		var kind:int = surfaces[index]
		if _materials[liquid][kind] == null: _materials[liquid][kind] = MESH.new_material(liquid,kind)
		node.set_surface_override_material(index,_materials[liquid][kind])
	shared.set_active(true)
	if not shared.visible: shared.visible = true


func _apply_frames(liquid:int) -> void:
	for kind:int in [MESH.STILL,MESH.FLOW]:
		var material:Variant = _materials[liquid][kind]
		if material is ShaderMaterial: (material as ShaderMaterial).set_shader_parameter("frame",float(MESH.frame_at(liquid,kind,_anim_time)))


func _ambient(delta:float) -> void:
	for f:int in [WATER,LAVA]:
		if levels[f].is_empty(): continue
		_ambient_left[f] -= delta
		if _ambient_left[f] > 0.0: continue
		var keys:Array = levels[f].keys()
		var cell:Vector2i = keys[_fx_rng.randi_range(0,keys.size() - 1)]
		var point:Vector2 = cell_center(cell)
		if f == WATER:
			_ambient_left[f] = _fx_rng.randf_range(4.0,9.0)
			AUDIO.play(self,AUDIO.KIND_WATER,0,point,_fx_rng.randf_range(0.8,1.2))
		else:
			_ambient_left[f] = _fx_rng.randf_range(0.3,0.9)
			if is_instance_valid(_particles): _particles.lava_pop(point + Vector2(_fx_rng.randf_range(-grid_size.x,grid_size.x),_fx_rng.randf_range(-grid_size.y,grid_size.y)) * 0.35)
			if _fx_rng.randf() < 0.35: AUDIO.play(self,AUDIO.KIND_POP,0,point,_fx_rng.randf_range(0.9,1.15))
			elif _fx_rng.randf() < 0.12: AUDIO.play(self,AUDIO.KIND_LAVA,0,point,_fx_rng.randf_range(0.9,1.1))
	_bubble_left -= delta
	if _bubble_left <= 0.0 and is_instance_valid(_particles):
		_bubble_left = 0.18
		for data:Dictionary in air_view().values():
			if not bool(data.get("wet",false)): continue
			var unit:Node2D = data.get("unit") as Node2D
			if is_instance_valid(unit) and _fx_rng.randf() < 0.6: _particles.bubble(unit.global_position + Vector2(0.0,-8.0))
