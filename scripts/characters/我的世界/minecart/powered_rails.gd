extends Node2D
## Canonical grid occupancy: ONE rail cell, ONE power flag and ONE draw per coordinate.
const TILES:Texture2D = preload("res://Images/characters/我的世界/矿车/rail_grid_tiles.png")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const CELL:float = 24.0
const GROUND_Z:int = -4 # Above floor (-5), below World bodies/projectiles (-2 and up).
const BODY_Z:int = 5
const CONNECT_RADIUS:float = 26.0
const ENTRY_RADIUS:float = 20.0
const EXIT_RADIUS:float = 29.0
const MAX_NODES:int = 8192
const MAX_EDGES:int = 16384
var nodes:Dictionary = {} # Each node IS a unique occupied block cell.
var rails:Array[Dictionary] = [] # Unique links between cardinal-neighbor cells.
var serial:int = 0
var revision:int = 0
var _node_serial:int = 0
var _edge_serial:int = 0
var _cell_ids:Dictionary = {}
var _edges:Dictionary = {}
var _edge_pairs:Dictionary = {}
var _adjacency:Dictionary = {}
var _previews:Dictionary = {}
var _render_cells:Dictionary = {}
var last_draw_cell_count:int = 0
var _loops:Dictionary = {}
var _last_build_effect:int = 0
var _development_node_lanes:Dictionary = {}
var _development_start_offsets:Dictionary = {}
var _development_current_offsets:Dictionary = {}
var _development_draw_offsets:Dictionary = {}

func development_begin_merge(lane_at:Callable,start_offsets:Dictionary) -> void:
	# This is one world-origin graph for both teams, not a Node2D per lane.
	_development_start_offsets = start_offsets.duplicate(true)
	_development_current_offsets = start_offsets.duplicate(true)
	_development_node_lanes.clear()
	_development_draw_offsets.clear()
	for id:Variant in nodes:
		_development_node_lanes[id] = str(lane_at.call(nodes[id].point))
	# A charging cart's proposal is not permanent track and its owner can be
	# stopped/repositioned at the transition; never retain a stale preview.
	if not _previews.is_empty():
		_previews.clear()
		_refresh_render_cells()

func _development_change(lane:String) -> Vector2:
	return (_development_current_offsets.get(lane,Vector2.ZERO) as Vector2)-(_development_start_offsets.get(lane,Vector2.ZERO) as Vector2)

func development_preview_merge(_start_offsets:Dictionary,lanes:Dictionary) -> void:
	for lane:String in _development_start_offsets:
		if lanes.has(lane): _development_current_offsets[lane] = (lanes[lane] as Dictionary).get("offset",Vector2.ZERO)
	_development_draw_offsets.clear()
	for id:Variant in _development_node_lanes:
		if nodes.has(id): _development_draw_offsets[nodes[id].cell] = _development_change(str(_development_node_lanes[id]))
	queue_redraw()

func development_finish_merge() -> void:
	if _development_start_offsets.is_empty(): return
	var old_nodes:Dictionary = nodes
	var old_links:Array[Dictionary] = rails
	var remapped:Dictionary = {}
	nodes = {}; rails = []
	_cell_ids.clear(); _edges.clear(); _edge_pairs.clear(); _adjacency.clear()
	for id:Variant in old_nodes:
		var n:Dictionary = old_nodes[id]
		var change:Vector2 = _development_change(str(_development_node_lanes.get(id,"")))
		var cell:Vector2i = world_to_cell(n.point+change)
		var existing:int = int(_cell_ids.get(cell,0))
		if existing != 0:
			# Both maps can lay a rail on the same final cell. Coalesce it rather
			# than leaving two IDs and an invalid world-grid lookup.
			remapped[id] = existing
			nodes[existing].powered = bool(nodes[existing].powered) or bool(n.powered)
			continue
		remapped[id] = id
		n.cell = cell
		n.point = cell_to_world(cell)
		n.mask = 0
		nodes[id] = n
		_cell_ids[cell] = id
		_adjacency[id] = []
	var occupied:Dictionary = {}
	for old:Dictionary in old_links:
		var a:int = int(remapped.get(old.a,0))
		var b:int = int(remapped.get(old.b,0))
		if a == 0 or b == 0 or a == b: continue
		var difference:Vector2i = nodes[b].cell-nodes[a].cell
		if absi(difference.x)+absi(difference.y) != 1: continue
		var pair:Vector2i = Vector2i(mini(a,b),maxi(a,b))
		if _edge_pairs.has(pair):
			var existing:int = int(_edge_pairs[pair])
			if not bool(old.get("transfer",false)): _edges[existing].transfer = false
			continue
		var e:Dictionary = old.duplicate()
		e.a = a; e.b = b
		var link:int = int(e.id)
		rails.append(e); _edges[link] = e; _edge_pairs[pair] = link
		_adjacency[a].append(link); _adjacency[b].append(link)
	# At a coalesced junction only two branches can form a physical rail;
	# other traversable links are the existing virtual side-entry type.
	for e:Dictionary in rails:
		if bool(e.get("transfer",false)): continue
		var a:int = int(e.a); var b:int = int(e.b)
		if int(occupied.get(a,0)) >= 2 or int(occupied.get(b,0)) >= 2:
			e.transfer = true
			continue
		occupied[a] = int(occupied.get(a,0))+1
		occupied[b] = int(occupied.get(b,0))+1
		var direction:Vector2i = nodes[b].cell-nodes[a].cell
		nodes[a].mask = int(nodes[a].mask)|_bit(direction)
		nodes[b].mask = int(nodes[b].mask)|_bit(-direction)
	_development_node_lanes.clear()
	_development_start_offsets.clear()
	_development_current_offsets.clear()
	_development_draw_offsets.clear()
	if is_multiplayer_authority(): _publish() # Full canonical graph, including overlapping cells.
	else:
		_refresh_ports()
		revision += 1
		_refresh_render_cells()
func _ready() -> void:
	z_as_relative = false
	z_index = GROUND_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not is_multiplayer_authority():
		multiplayer.peer_connected.connect(_on_peer_connected)
		call_deferred("_request_state")
func world_to_cell(point:Vector2) -> Vector2i:
	return Vector2i(roundi(point.x/CELL),roundi(point.y/CELL))
func cell_to_world(cell:Vector2i) -> Vector2: return Vector2(cell)*CELL
func cell_at(point:Vector2) -> Dictionary:
	var id:int = int(_cell_ids.get(world_to_cell(point),0))
	return nodes.get(id,{})
func node_point(id:int) -> Vector2: return nodes[id].point if nodes.has(id) else Vector2.INF
func edge(id:int) -> Dictionary: return _edges.get(id,{})
func neighbors(id:int) -> Array: return _adjacency.get(id,[]).duplicate()
func other_end(id:int,node:int) -> int:
	var e:Dictionary = edge(id)
	if e.is_empty(): return 0
	return int(e.b) if int(e.a) == node else int(e.a) if int(e.b) == node else 0
func living_carts() -> Array[Node2D]:
	var result:Array[Node2D] = []
	for unit:Node in get_tree().get_nodes_in_group("MCMinecart"):
		if is_instance_valid(unit) and unit.health > 0 and not unit.is_queued_for_deletion(): result.append(unit)
	return result
func tick_rails(_delta:float,_carts:Array[Node2D]) -> void: pass # No TTL/owner-death cleanup.
func find_port(point:Vector2,radius_value:float = CONNECT_RADIUS,exclude_id:int = 0) -> int:
	var center:Vector2i = world_to_cell(point)
	var reach:int = int(ceil(radius_value/CELL))+1
	var best:int = 0
	var distance:float = radius_value*radius_value
	for x:int in range(-reach,reach+1):
		for y:int in range(-reach,reach+1):
			var id:int = int(_cell_ids.get(center+Vector2i(x,y),0))
			if id == 0 or id == exclude_id or not nodes[id].port: continue
			var d:float = point.distance_squared_to(nodes[id].point)
			if d <= distance: distance = d; best = id
	return best
func _clearance(cart:Node2D,from:Vector2,to:Vector2) -> float:
	if from.distance_squared_to(to) < 0.001: return 1.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = cart.collision_shape_2d.shape
	query.transform = cart.collision_shape_2d.global_transform
	query.transform.origin += from-cart.global_position
	query.motion = to-from
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = [cart.get_rid()]
	var cast:PackedFloat32Array = get_world_2d().direct_space_state.cast_motion(query)
	return float(cast[0]) if cast.size() > 0 else 0.0
func _cell_clear(point:Vector2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE*(CELL-0.2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0,point)
	query.collision_mask = 1
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
func legal_path(points:PackedVector2Array) -> bool:
	if points.size() < 2 or points.size() > 3: return false
	var total:float = 0.0
	for i:int in range(points.size()):
		if not points[i].is_finite() or points[i].distance_to(cell_to_world(world_to_cell(points[i]))) > 0.01: return false
		if i > 0:
			var delta:Vector2 = points[i]-points[i-1]
			if (absf(delta.x)>0.01 and absf(delta.y)>0.01) or delta.length() < CELL-0.01: return false
			total += delta.length()
	if total > 650.0: return false
	if points.size() == 3 and absf(points[0].direction_to(points[1]).dot(points[1].direction_to(points[2]))) > 0.001: return false
	return true
func _path_cells(points:PackedVector2Array) -> Array[Vector2i]:
	var result:Array[Vector2i] = []
	if not legal_path(points): return result
	result.append(world_to_cell(points[0]))
	for i:int in range(points.size()-1):
		var a:Vector2i = world_to_cell(points[i])
		var b:Vector2i = world_to_cell(points[i+1])
		var direction:Vector2i = Vector2i(signi(b.x-a.x),signi(b.y-a.y))
		var count:int = absi(b.x-a.x)+absi(b.y-a.y)
		for j:int in range(1,count+1): result.append(a+direction*j)
	return result
func _compressed(cells:Array[Vector2i]) -> PackedVector2Array:
	var result:PackedVector2Array = PackedVector2Array()
	if cells.size() < 2: return result
	result.append(cell_to_world(cells[0]))
	for i:int in range(1,cells.size()-1):
		if cells[i]-cells[i-1] != cells[i+1]-cells[i]: result.append(cell_to_world(cells[i]))
	result.append(cell_to_world(cells[-1]))
	return result
func prepare_path(cart:Node2D,raw:PackedVector2Array) -> PackedVector2Array:
	if not is_instance_valid(cart) or not cart._can_rush() or raw.size()<2 or raw.size()>3: return PackedVector2Array()
	for point:Vector2 in raw:
		if not point.is_finite(): return PackedVector2Array()
	if raw.size() == 3 and absf(raw[0].direction_to(raw[1]).dot(raw[1].direction_to(raw[2]))) > 0.001: return PackedVector2Array()
	# Snap to the grid, never pull a planned endpoint sideways onto an unrelated port.
	var a:Vector2i = world_to_cell(raw[0])
	var b:Vector2i = world_to_cell(raw[-1])
	var axis:Vector2 = raw[0].direction_to(raw[1])
	var points:PackedVector2Array = PackedVector2Array([cell_to_world(a)])
	if a.x != b.x and a.y != b.y:
		var corner:Vector2i = Vector2i(b.x,a.y) if absf(axis.x)>=absf(axis.y) else Vector2i(a.x,b.y)
		points.append(cell_to_world(corner))
	points.append(cell_to_world(b))
	if not legal_path(points) or not _cell_clear(points[0]) or _clearance(cart,cart.global_position,points[0]) < 0.999: return PackedVector2Array()
	var safe:Array[Vector2i] = []
	for cell:Vector2i in _path_cells(points):
		var point:Vector2 = cell_to_world(cell)
		if not _cell_clear(point): break
		if not safe.is_empty() and _clearance(cart,cell_to_world(safe[-1]),point) < 0.999: break
		safe.append(cell)
	var clipped:PackedVector2Array = _compressed(safe)
	return clipped if legal_path(clipped) else PackedVector2Array()
func _bit(delta:Vector2i) -> int:
	if delta.x > 0: return 1
	if delta.y > 0: return 2
	if delta.x < 0: return 4
	return 8
func _plan_cells(points:PackedVector2Array) -> Dictionary:
	var path:Array[Vector2i] = _path_cells(points)
	var result:Dictionary = {}
	for i:int in range(path.size()):
		var mask:int = 0
		if i > 0: mask |= _bit(path[i-1]-path[i])
		if i+1 < path.size(): mask |= _bit(path[i+1]-path[i])
		var fraction:float = float(i)/maxf(float(path.size()-1),1.0)
		result[path[i]] = {"mask":mask,"powered":fraction>=0.4 and fraction<=0.6,"port":i==0 or i==path.size()-1,"alpha":0.48}
	return result
func _node(cell:Vector2i,powered:bool,is_port:bool) -> int:
	var id:int = int(_cell_ids.get(cell,0))
	if id == 0:
		_node_serial += 1; id = _node_serial
		_cell_ids[cell] = id
		nodes[id] = {"id":id,"cell":cell,"point":cell_to_world(cell),"powered":false,"port":false,"mask":0}
		_adjacency[id] = []
	# Monotone merge: ordinary construction can never downgrade a powered cell.
	nodes[id].powered = bool(nodes[id].powered) or powered
	nodes[id].port = bool(nodes[id].port) or is_port
	return id
func physical_neighbors(id:int) -> Array:
	return neighbors(id).filter(func(link:Variant) -> bool: return not bool(_edges[int(link)].get("transfer",false)))
func _faces(id:int,delta:Vector2i) -> bool:
	var physical:Array = physical_neighbors(id)
	if physical.size() == 1:
		return nodes[id].cell-nodes[other_end(int(physical[0]),id)].cell == delta
	if physical.is_empty(): return (int(nodes[id].get("draw_mask",5))&_bit(delta)) != 0
	return false
func _connect(a:int,b:int,transfer:bool = false) -> int:
	var key:Vector2i = Vector2i(mini(a,b),maxi(a,b))
	if _edge_pairs.has(key):
		var existing:int = int(_edge_pairs[key])
		if not transfer and bool(_edges[existing].get("transfer",false)) and physical_neighbors(a).size()<2 and physical_neighbors(b).size()<2:
			_edges[existing].transfer = false
			nodes[a].mask = int(nodes[a].mask)|_bit(nodes[b].cell-nodes[a].cell)
			nodes[b].mask = int(nodes[b].mask)|_bit(nodes[a].cell-nodes[b].cell)
		return existing
	# One physical rail has at most two ends: never overwrite an old straight/elbow with a crossing.
	if not transfer and (physical_neighbors(a).size() >= 2 or physical_neighbors(b).size() >= 2): return 0
	if rails.size() >= MAX_EDGES: return 0
	_edge_serial += 1
	var e:Dictionary = {"id":_edge_serial,"a":a,"b":b,"length":CELL,"transfer":transfer}
	rails.append(e); _edges[_edge_serial] = e; _edge_pairs[key] = _edge_serial
	_adjacency[a].append(_edge_serial); _adjacency[b].append(_edge_serial)
	if not transfer:
		nodes[a].mask = int(nodes[a].mask)|_bit(nodes[b].cell-nodes[a].cell)
		nodes[b].mask = int(nodes[b].mask)|_bit(nodes[a].cell-nodes[b].cell)
	return _edge_serial
func _rail_shape(mask:int) -> int:
	# Extending a straight endpoint does not destroy its existing rail tile.
	if mask in [1,4,5]: return 5
	if mask in [2,8,10]: return 10
	return mask
func commit_path(cart:Node2D,points:PackedVector2Array) -> Dictionary:
	if not is_multiplayer_authority() or not is_instance_valid(cart) or not cart._can_rush() or not legal_path(points): return {}
	var path:Array[Vector2i] = _path_cells(points)
	var new_cells:int = 0
	var new_edges:int = 0
	for i:int in range(path.size()):
		if not _cell_ids.has(path[i]): new_cells += 1
		if i>0:
			var a:int = int(_cell_ids.get(path[i-1],0)); var b:int = int(_cell_ids.get(path[i],0))
			if a==0 or b==0 or not _edge_pairs.has(Vector2i(mini(a,b),maxi(a,b))): new_edges += 1
		if not _cell_clear(cell_to_world(path[i])): return {}
		if i>0 and _clearance(cart,cell_to_world(path[i-1]),cell_to_world(path[i])) < 0.999: return {}
	if nodes.size()+new_cells > MAX_NODES or rails.size()+new_edges > MAX_EDGES: return {}
	var plan:Dictionary = _plan_cells(points)
	var broken:Array = []
	var placed:Array[Vector2] = []
	# Capture committed old artwork BEFORE mask and powered flags are overwritten.
	# Preview tiles, untouched neighbors and identical re-placement are not destruction.
	for coord:Vector2i in path:
		var old:Dictionary = cell_at(cell_to_world(coord))
		if old.is_empty():
			placed.append(cell_to_world(coord))
			continue
		var old_mask:int = int(old.mask) if int(old.mask)!=0 else int(old.get("draw_mask",5))
		var changed:bool = _rail_shape(old_mask) != _rail_shape(int(plan[coord].mask))
		if changed:
			broken.append({"point":old.point,"mask":old_mask,"powered":bool(old.powered)})
		if changed or (bool(plan[coord].powered) and not bool(old.powered)):
			placed.append(cell_to_world(coord))
	var ids:Array[int] = []
	var links:Array[int] = []
	var covered:Dictionary = {}
	for cell:Vector2i in path:
		var id:int = _node(cell,bool(plan[cell].powered),bool(plan[cell].port))
		nodes[id].draw_mask = int(plan[cell].mask)
		ids.append(id)
		covered[id] = true
	var desired:Dictionary = {}
	for i:int in range(ids.size()-1):
		desired[Vector2i(mini(ids[i],ids[i+1]),maxi(ids[i],ids[i+1]))] = true
	# New construction owns the shape of EVERY covered cell, including occupied cells.
	# Cut old rails at the replacement by demoting their exits to side-entry links.
	# Keep edge IDs stable: a cart already approaching the replaced cell can enter its new rail.
	for e:Dictionary in rails:
		if not covered.has(int(e.a)) and not covered.has(int(e.b)): continue
		var key:Vector2i = Vector2i(mini(int(e.a),int(e.b)),maxi(int(e.a),int(e.b)))
		e.transfer = not desired.has(key)
	for n:Dictionary in nodes.values(): n.mask = 0
	for e:Dictionary in rails:
		if bool(e.get("transfer",false)): continue
		nodes[e.a].mask = int(nodes[e.a].mask)|_bit(nodes[e.b].cell-nodes[e.a].cell)
		nodes[e.b].mask = int(nodes[e.b].mask)|_bit(nodes[e.a].cell-nodes[e.b].cell)
	for i:int in range(ids.size()-1):
		var link:int = _connect(ids[i],ids[i+1])
		if link != 0: links.append(link)
	# Either endpoint can face the other: covers bends regardless of construction order.
	# Side entry into an existing straight/elbow is a traversal link, NOT a second drawn rail.
	for id:int in ids:
		for delta:Vector2i in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
			var adjacent:int = int(_cell_ids.get(nodes[id].cell+delta,0))
			if adjacent == 0: continue
			var both_ends:bool = physical_neighbors(id).size()<2 and physical_neighbors(adjacent).size()<2
			# Adjacent ends also form U/corner connections when neither faces the other yet.
			if not both_ends and not _faces(id,delta) and not _faces(adjacent,-delta): continue
			var transfer:bool = physical_neighbors(id).size()>=2 or physical_neighbors(adjacent).size()>=2
			_connect(id,adjacent,transfer)
	for id:Variant in nodes:
		nodes[id].port = physical_neighbors(id).size() <= 1 and not neighbors(id).is_empty()
	serial += 1
	_publish()
	if not placed.is_empty():
		var sound_point:Vector2 = Vector2.ZERO
		for point:Vector2 in placed: sound_point += point
		sound_point /= float(placed.size())
		if multiplayer.has_multiplayer_peer(): _construction_effect.rpc(serial,sound_point,broken)
		_construction_effect(serial,sound_point,broken)
	return {"id":serial,"nodes":ids,"edges":links,"points":points.duplicate(),"cells":path}
@rpc("authority","call_remote","reliable")
func _construction_effect(event_id:int,point:Vector2,broken:Array) -> void:
	if event_id <= _last_build_effect: return
	_last_build_effect = event_id
	# Once per real committed batch; network snapshots never replay historical sounds.
	AUDIO.play(self,"block.metal.place",point,-10.0,false,false,true)
	if broken.is_empty(): return
	var break_point:Vector2 = Vector2.ZERO
	for old:Dictionary in broken:
		break_point += old.point
		_shatter_rail(old)
	AUDIO.play(self,"block.metal.break",break_point/float(broken.size()),-8.0,false,false,true)
func _shatter_rail(old:Dictionary) -> void:
	# The old rail cell is a BLOCK: crop its own atlas pixels and land nearby, not item-death flight.
	var texture := AtlasTexture.new()
	texture.atlas = TILES
	texture.region = Rect2((int(old.mask)&15)*16,16 if bool(old.powered) else 0,16,16)
	texture.filter_clip = true
	var source := Sprite2D.new()
	source.texture = texture
	source.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(source)
	source.global_position = old.point
	source.global_scale = Vector2.ONE*(CELL/16.0)
	var effect:Node2D = FRAGMENTS.spawn_obstacle(source)
	effect.add_to_group("MCRailBreakFragments")
	effect.set_meta("rail_point",old.point)
	effect.set_meta("rail_mask",int(old.mask))
	effect.set_meta("rail_powered",bool(old.powered))
	source.free() # A sampling sprite only; never leave an old full tile over the new rail.
func is_powered_at(_edge_id:int,point:Vector2) -> bool:
	var cell:Dictionary = cell_at(point)
	return not cell.is_empty() and bool(cell.powered)
func is_elbow(id:int) -> bool:
	return nodes.has(id) and int(nodes[id].mask) in [3,6,9,12]
func choose_edge(node:int,visited:Dictionary,goal:Vector2,heading:Vector2 = Vector2.ZERO) -> int:
	var best:int = 0; var score:float = INF
	var best_priority:int = 2
	for raw:Variant in _adjacency.get(node,[]):
		var id:int = int(raw)
		if visited.has(id): continue
		var end:Vector2 = node_point(other_end(id,node))
		# Finish the current rail first; only use side-entry links at its exit.
		var value:float = end.distance_to(goal)-node_point(node).direction_to(end).dot(heading)*4.0
		var priority:int = 1 if bool(_edges[id].get("transfer",false)) else 0
		if priority < best_priority or (priority == best_priority and value < score):
			score = value; best = id; best_priority = priority
	return best
func entry_edge(node:int,motion:Vector2,position:Vector2) -> int:
	if not nodes.has(node) or not bool(nodes[node].port) or motion.length_squared()<0.000001: return 0
	var heading:Vector2 = motion.normalized()
	var offset:Vector2 = position-node_point(node)
	var candidates:Array = physical_neighbors(node)
	if candidates.is_empty(): candidates = neighbors(node)
	var best:int = 0
	var alignment:float = 0.90 # About 26 degrees of tolerance; perpendicular/diagonal crossings fail.
	for link:Variant in candidates:
		var inward:Vector2 = node_point(node).direction_to(node_point(other_end(int(link),node)))
		var dot:float = heading.dot(inward)
		if dot<alignment: continue
		# Approach from OUTSIDE the endpoint, within the rail's width, not from its inner side.
		if offset.dot(inward)>2.0 or absf(offset.cross(inward))>CELL*0.35: continue
		alignment = dot
		best = int(link)
	return best
func nearby_port(cart:Node2D,from:Vector2,to:Vector2) -> int:
	if not is_multiplayer_authority() or not is_instance_valid(cart) or not cart._can_rush(): return 0
	var motion:Vector2 = to-from if from.distance_squared_to(to)>0.000001 else cart.entry_motion()
	var center:Vector2i = world_to_cell(to)
	var best:int = 0
	var distance:float = ENTRY_RADIUS*ENTRY_RADIUS
	for x:int in range(-2,3):
		for y:int in range(-2,3):
			var id:int = int(_cell_ids.get(center+Vector2i(x,y),0))
			if entry_edge(id,motion,to)==0: continue
			var d:float = to.distance_squared_to(node_point(id))
			if d>distance or U.segment_distance(node_point(id),from,to)>ENTRY_RADIUS: continue
			if _clearance(cart,to,node_point(id))<0.999: continue
			best = id; distance = d
	return best
func set_preview(owner_id:int,points:PackedVector2Array) -> void:
	if points.size() < 2: clear_preview(owner_id); return
	if _previews.has(owner_id) and _previews[owner_id].points == points: return
	_previews.erase(owner_id) # Latest changed preview draws after older proposals.
	_previews[owner_id] = {"points":points.duplicate(),"cells":_plan_cells(points)}
	_refresh_render_cells()
func clear_preview(owner_id:int) -> void:
	if _previews.erase(owner_id): _refresh_render_cells()
func _refresh_render_cells() -> void:
	_render_cells.clear()
	for n:Dictionary in nodes.values():
		_render_cells[n.cell] = {"mask":int(n.mask) if int(n.mask)!=0 else int(n.get("draw_mask",5)),"powered":bool(n.powered),"alpha":1.0}
	for preview:Dictionary in _previews.values():
		for coord:Vector2i in preview.cells:
			var proposed:Dictionary = preview.cells[coord].duplicate()
			# New shape wins, but a powered committed/earlier cell cannot be downgraded.
			proposed.powered = bool(proposed.powered) or bool(_render_cells.get(coord,{}).get("powered",false))
			_render_cells[coord] = proposed
	queue_redraw()
func render_cells() -> Dictionary: return _render_cells.duplicate(true)
func clear_tracks() -> void:
	if not is_multiplayer_authority(): return
	for cart:Node2D in living_carts(): cart.end_rush()
	nodes.clear(); rails.clear(); _cell_ids.clear(); _edges.clear(); _edge_pairs.clear(); _adjacency.clear(); _previews.clear()
	_publish()
func network_state() -> Dictionary: return {"schema":2,"nodes":nodes.values().duplicate(true),"edges":rails.duplicate(true),"serial":serial}
func _publish() -> void:
	_refresh_ports()
	revision += 1
	_refresh_render_cells()
	if multiplayer.has_multiplayer_peer(): _receive_state.rpc(revision,network_state())
@rpc("authority","call_remote","reliable")
func _receive_state(version:int,data:Dictionary) -> void:
	if version < revision or int(data.get("schema",0)) != 2: return
	var incoming:Variant = data.get("nodes",[])
	var links:Variant = data.get("edges",[])
	if not incoming is Array or not links is Array or incoming.size()>MAX_NODES or links.size()>MAX_EDGES: return
	var next_nodes:Dictionary = {}; var next_cells:Dictionary = {}; var next_adj:Dictionary = {}
	for value:Variant in incoming:
		if not value is Dictionary or not value.get("point") is Vector2 or not (value.point as Vector2).is_finite(): return
		var id:int = int(value.get("id",0))
		var coord:Vector2i = world_to_cell(value.point)
		if id<=0 or next_nodes.has(id) or next_cells.has(coord) or value.point.distance_to(cell_to_world(coord))>0.01: return
		next_nodes[id] = {"id":id,"cell":coord,"point":cell_to_world(coord),"port":bool(value.get("port",false)),"powered":bool(value.get("powered",false)),"draw_mask":int(value.get("draw_mask",5)),"mask":0}
		next_cells[coord] = id; next_adj[id] = []
	var next_edges:Dictionary = {}; var next_pairs:Dictionary = {}; var next_rails:Array[Dictionary] = []
	for value:Variant in links:
		if not value is Dictionary: return
		var id:int = int(value.get("id",0)); var a:int = int(value.get("a",0)); var b:int = int(value.get("b",0))
		var key:Vector2i = Vector2i(mini(a,b),maxi(a,b))
		if id<=0 or next_edges.has(id) or next_pairs.has(key) or not next_nodes.has(a) or not next_nodes.has(b): return
		var delta:Vector2i = next_nodes[b].cell-next_nodes[a].cell
		if absi(delta.x)+absi(delta.y) != 1: return
		var transfer:bool = bool(value.get("transfer",false))
		var e:Dictionary = {"id":id,"a":a,"b":b,"length":CELL,"transfer":transfer}
		next_edges[id] = e; next_pairs[key] = id; next_rails.append(e)
		next_adj[a].append(id); next_adj[b].append(id)
		if not transfer:
			next_nodes[a].mask = int(next_nodes[a].mask)|_bit(delta)
			next_nodes[b].mask = int(next_nodes[b].mask)|_bit(-delta)
	for n:Dictionary in next_nodes.values():
		if int(n.mask) in [7,11,13,14,15]: return
	nodes=next_nodes; _cell_ids=next_cells; rails=next_rails; _edges=next_edges; _edge_pairs=next_pairs; _adjacency=next_adj
	revision=version; serial=int(data.get("serial",serial))
	_refresh_ports()
	_refresh_render_cells()
func _on_peer_connected(id:int) -> void:
	if id == get_multiplayer_authority(): _request_state()
func _request_state() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(get_multiplayer_authority()): _send_state.rpc_id(get_multiplayer_authority())
@rpc("any_peer","call_remote","reliable")
func _send_state() -> void:
	if is_multiplayer_authority(): _receive_state.rpc_id(multiplayer.get_remote_sender_id(),revision,network_state())
func _draw() -> void:
	last_draw_cell_count = 0
	for coord:Vector2i in _render_cells:
		var cell:Dictionary = _render_cells[coord]
		var mask:int = int(cell.mask)&15
		if mask == 0: continue
		var position:Vector2 = to_local(cell_to_world(coord)+(_development_draw_offsets.get(coord,Vector2.ZERO) as Vector2))
		var region:Rect2 = Rect2(mask*16,16 if cell.powered else 0,16,16)
		draw_texture_rect_region(TILES,Rect2(position-Vector2.ONE*CELL*0.5,Vector2.ONE*CELL),region,Color(1,1,1,float(cell.alpha)))
		last_draw_cell_count += 1

func loop_nodes(id:int) -> Array: return _loops.get(id,[])
func _refresh_ports() -> void:
	_loops.clear()
	var seen:Dictionary = {}
	for id:Variant in nodes:
		nodes[id].port = physical_neighbors(id).size() <= 1 and not neighbors(id).is_empty()
	for start:Variant in nodes:
		if seen.has(start): continue
		var component:Array = [start]
		seen[start] = true
		var closed:bool = true
		var cursor:int = 0
		while cursor < component.size():
			var id:int = int(component[cursor]); cursor += 1
			var links:Array = physical_neighbors(id)
			closed = closed and links.size() == 2
			for link:Variant in links:
				var next:int = other_end(int(link),id)
				if not seen.has(next): seen[next] = true; component.append(next)
		if not closed or component.size()<4: continue
		for id:Variant in component:
			_loops[id] = component
			if is_elbow(int(id)): nodes[id].port = true
