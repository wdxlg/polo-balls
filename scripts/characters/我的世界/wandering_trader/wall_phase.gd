extends RefCounted
## 流浪商人「入墙」geometry. A wall slot is a map tile whose tile data has a collision polygon
## (physics layer 1: the border/obstacle blocks) that touches a walkable (polygon-free) tile. Entering
## walks into the nearest slot's wall tile; exiting starts inside the safest slot's wall tile and
## steps out onto its floor tile. PortalMap islands are handled like the silverfish stone field.
## Maps without tile walls fall back to the visible arena rectangle edges.

static func current_map(world:Node) -> Node:
	if world == null: return null
	if world.has_method(&"_current_map_node"):
		var node:Variant = world.call(&"_current_map_node")
		if node is Node: return node
	var groups:Variant = world.get(&"map_group")
	var key:Variant = world.get(&"now_choose_map")
	if groups is Dictionary and (groups as Dictionary).has(key): return groups[key]
	return null

static func map_layers(map_node:Node) -> Array[TileMapLayer]:
	var layers:Array[TileMapLayer] = []
	if map_node == null or not is_instance_valid(map_node): return layers
	if map_node is TileMapLayer:
		layers.append(map_node as TileMapLayer)
		return layers
	if map_node.has_method(&"island_entries"):
		for entry:Variant in map_node.call(&"island_entries"):
			var layer:Variant = (entry as Dictionary).get("layer") if entry is Dictionary else null
			if layer is TileMapLayer and is_instance_valid(layer): layers.append(layer)
	if layers.is_empty():
		for child:Node in map_node.find_children("*","TileMapLayer",true,false):
			if (child as TileMapLayer).enabled: layers.append(child as TileMapLayer)
	return layers

static func _is_wall_cell(layer:TileMapLayer,cell:Vector2i) -> bool:
	var data:TileData = layer.get_cell_tile_data(cell)
	if data == null or layer.tile_set == null: return false
	for index:int in range(layer.tile_set.get_physics_layers_count()):
		if (layer.tile_set.get_physics_layer_collision_layer(index) & 1) != 0 and data.get_collision_polygons_count(index) > 0:
			return true
	return false

## Array of {wall:Vector2, floor:Vector2, face:Vector2, normal:Vector2 (wall->floor)} in world space.
## face = a point on the wall surface (the tile edge between wall and floor); the trader's sprite is
## clipped on that line while he walks in / out.
static func wall_slots(world:Node,fallback_rect:Rect2 = Rect2()) -> Array[Dictionary]:
	var slots:Array[Dictionary] = []
	for layer:TileMapLayer in map_layers(current_map(world)):
		# Maps keep TileMapLayer.collision_enabled off (World builds the bounce walls itself); the
		# wall tiles are still the cells whose tile data carries a layer-1 collision polygon.
		if layer.tile_set == null or not layer.enabled: continue
		var used:Dictionary = {}
		for cell:Vector2i in layer.get_used_cells(): used[cell] = _is_wall_cell(layer,cell)
		for cell:Vector2i in used.keys():
			if not bool(used[cell]): continue
			for offset:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var neighbour:Vector2i = cell + offset
				if used.has(neighbour) and not bool(used[neighbour]):
					var wall:Vector2 = layer.to_global(layer.map_to_local(cell))
					var floor_point:Vector2 = layer.to_global(layer.map_to_local(neighbour))
					slots.append({"wall":wall,"floor":floor_point,"face":wall.lerp(floor_point,0.5),"normal":wall.direction_to(floor_point)})
	if slots.is_empty() and fallback_rect.has_area():
		# Tile collision disabled (e.g. Map10x10): the arena boundary is the wall. Wall points sit
		# on the inner edge (World keeps units inside the rect), floors one step further in.
		var step:float = 16.0
		var rect:Rect2 = fallback_rect
		var x:float = rect.position.x + step*0.5
		while x < rect.end.x:
			slots.append({"wall":Vector2(x,rect.position.y + 1.0),"floor":Vector2(x,rect.position.y + 12.0),"face":Vector2(x,rect.position.y),"normal":Vector2.DOWN})
			slots.append({"wall":Vector2(x,rect.end.y - 1.0),"floor":Vector2(x,rect.end.y - 12.0),"face":Vector2(x,rect.end.y),"normal":Vector2.UP})
			x += step
		var y:float = rect.position.y + step*0.5
		while y < rect.end.y:
			slots.append({"wall":Vector2(rect.position.x + 1.0,y),"floor":Vector2(rect.position.x + 12.0,y),"face":Vector2(rect.position.x,y),"normal":Vector2.RIGHT})
			slots.append({"wall":Vector2(rect.end.x - 1.0,y),"floor":Vector2(rect.end.x - 12.0,y),"face":Vector2(rect.end.x,y),"normal":Vector2.LEFT})
			y += step
	return slots

static func nearest_slot(slots:Array[Dictionary],point:Vector2) -> Dictionary:
	var best:Dictionary = {}
	var best_distance:float = INF
	for slot:Dictionary in slots:
		var distance:float = point.distance_squared_to(slot.wall)
		if distance < best_distance:
			best_distance = distance
			best = slot
	return best

## "尽量安全": rank slots by the distance from their floor tile to the closest enemy (plus a small
## seeded jitter so repeated exits differ), then take the first one the resolver accepts.
## resolver.call(slot) -> Dictionary: the slot with a body-clear "floor" (e.g. pushed further out
## along "normal"), or {} when blocked. Without a clear slot the best-ranked raw slot is returned.
static func safest_slot(slots:Array[Dictionary],threats:Array[Vector2],resolver:Callable,rng:RandomNumberGenerator,jitter:float = 6.0,max_checks:int = 48) -> Dictionary:
	var ranked:Array = []
	for slot:Dictionary in slots:
		var nearest:float = 100000.0
		for threat:Vector2 in threats: nearest = minf(nearest,(slot.floor as Vector2).distance_to(threat))
		ranked.append([nearest + (rng.randf()*jitter if rng != null else 0.0),slot])
	ranked.sort_custom(func(a:Array,b:Array) -> bool: return float(a[0]) > float(b[0]))
	if ranked.is_empty(): return {}
	if not resolver.is_valid(): return ranked[0][1]
	for i:int in range(mini(ranked.size(),max_checks)):
		var resolved:Variant = resolver.call(ranked[i][1])
		if resolved is Dictionary and not (resolved as Dictionary).is_empty(): return resolved
	return ranked[0][1]

static func min_threat_distance(point:Vector2,threats:Array[Vector2]) -> float:
	var nearest:float = INF
	for threat:Vector2 in threats: nearest = minf(nearest,point.distance_to(threat))
	return nearest

static func face_point(slot:Dictionary) -> Vector2:
	if slot.has("face"): return slot.face
	return (slot.get("wall",Vector2.ZERO) as Vector2).lerp(slot.get("floor",Vector2.ZERO),0.5)
