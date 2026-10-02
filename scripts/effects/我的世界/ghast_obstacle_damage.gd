extends Node
## 世界级公共障碍破坏：0-100 累积进度；方块、静态障碍统一由 MCObstacleProperties 调参。
## collect_blast 在权威端收集一次；apply_updates 在每个 peer 执行（由技能 RPC）。
const PROFILE=preload("res://scripts/effects/我的世界/mc_obstacle_properties.gd")
const CRACKS=[preload("res://Images/Status/BlockDamage/destroy_stage_3.png"),preload("res://Images/Status/BlockDamage/destroy_stage_7.png")]
const CRACK_SHADER=preload("res://scripts/effects/我的世界/ghast_block_cracks.gdshader")
const FRAGMENTS=preload("res://scripts/effects/我的世界/item_fragments.gd")
const BLOCK_3D=preload("res://scripts/effects/我的世界/mc_block_3d.gd")
var records:Dictionary={}
static func ensure(context:Node) -> Node:
	var world:Node=context.get_tree().current_scene
	var manager:Node=world.get_node_or_null("GhastObstacleDamage")
	if manager==null:
		manager=load("res://scripts/effects/我的世界/ghast_obstacle_damage.gd").new()
		manager.name="GhastObstacleDamage"
		world.add_child(manager)
	return manager
func protected(node:Node) -> bool:
	while node!=null:
		if node.get_meta("map_safety_frame",false) or node.get_meta("mc_map_boundary",false) or node.get_meta("ghast_indestructible",false): return true
		if not PROFILE.can_break(node): return true
		node=node.get_parent()
	return false
func colliding(tile:TileData,tileset:TileSet) -> bool:
	if tile==null: return false
	for i:int in range(tileset.get_physics_layers_count()):
		if tileset.get_physics_layer_collision_layer(i)&1 and tile.get_collision_polygons_count(i)>0: return true
	return false
func interior(layer:TileMapLayer,cell:Vector2i) -> bool:
	# An occupied floor is preserved; outside edges/holes/portal shores are not mined.
	for x:int in range(-1,2):
		for y:int in range(-1,2):
			if layer.get_cell_source_id(cell+Vector2i(x,y))<0: return false
	return true
func floor_tile(layer:TileMapLayer,around:Vector2i) -> Array:
	for radius:int in range(1,10):
		for x:int in range(-radius,radius+1):
			for y:int in range(-radius,radius+1):
				if absi(x)!=radius and absi(y)!=radius: continue
				var cell:Vector2i=around+Vector2i(x,y)
				var data:TileData=layer.get_cell_tile_data(cell)
				if data!=null and not colliding(data,layer.tile_set):
					return [layer.get_cell_source_id(cell),layer.get_cell_atlas_coords(cell),layer.get_cell_alternative_tile(cell)]
	return []
func layers_in(node:Node,result:Array[TileMapLayer]) -> void:
	if node is TileMapLayer:
		if node.is_visible_in_tree() and node.collision_enabled and node.tile_set!=null: result.append(node)
	for child:Node in node.get_children():
		if child!=self: layers_in(child,result)
func collect_blast(context:Node2D,point:Vector2,radius:float) -> Array[Dictionary]:
	var updates:Array[Dictionary]=[]
	var world:Node=get_parent()
	var layers:Array[TileMapLayer]=[]
	# Maps only, not hidden inactive maps or tiles embedded in characters.
	if world.has_method("_current_map_node") and world._current_map_node()!=null: layers_in(world._current_map_node(),layers)
	else: layers_in(world,layers)
	for layer:TileMapLayer in layers:
		if protected(layer): continue
		var local_bounds:=Rect2(layer.to_local(point-Vector2.ONE*radius),Vector2.ZERO)
		for offset:Vector2 in [Vector2(radius,radius),Vector2(radius,-radius),Vector2(-radius,radius)]: local_bounds=local_bounds.expand(layer.to_local(point+offset))
		var first:Vector2i=layer.local_to_map(local_bounds.position)-Vector2i.ONE
		var last:Vector2i=layer.local_to_map(local_bounds.end)+Vector2i.ONE
		for x:int in range(first.x,last.x+1):
			for y:int in range(first.y,last.y+1):
				var cell:=Vector2i(x,y)
				if not colliding(layer.get_cell_tile_data(cell),layer.tile_set) or not interior(layer,cell) or not PROFILE.can_break(layer,cell): continue
				var local_rect:=Rect2(layer.map_to_local(cell)-Vector2(layer.tile_set.tile_size)*0.5,Vector2(layer.tile_set.tile_size))
				var near:Vector2=layer.to_global(layer.to_local(point).clamp(local_rect.position,local_rect.end))
				if point.distance_to(near)>radius: continue
				var floor_data:Array=floor_tile(layer,cell)
				if floor_data.is_empty(): continue # Never create a hole in the map's ground.
				var path:NodePath=world.get_path_to(layer)
				var key:String=str(path)+"/tile/"+str(cell)
				var count:int=hit_count(key,layer)+1
				updates.append({"key":key,"path":path,"tile":true,"cell":cell,"floor":floor_data,"hits":count,"progress":minf(100.0,damage_progress(key,layer)+PROFILE.progress_per_blast(layer,cell)),"rect":local_rect})
	var shape:=CircleShape2D.new()
	shape.radius=maxf(radius,0.1)
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=shape
	query.transform=Transform2D(0,point)
	# 静态障碍不应仅因被配置到非 1 号碰撞层就对爆炸隐身。
	query.collision_mask=0xFFFFFFFF
	query.collide_with_areas=false
	var excluded:Array[RID]=[]
	if context is CollisionObject2D: excluded.append(context.get_rid())
	query.exclude=excluded
	var seen:Dictionary={}
	for hit:Dictionary in context.get_world_2d().direct_space_state.intersect_shape(query,512):
		var node:Node=hit.collider
		if not node is StaticBody2D or protected(node) or node.is_queued_for_deletion(): continue
		var ancestor:Node=node.get_parent()
		var character_part:bool=false
		while ancestor!=null:
			if ancestor is ball: character_part=true; break
			ancestor=ancestor.get_parent()
		if character_part: continue
		if seen.has(node.get_instance_id()): continue
		seen[node.get_instance_id()]=true
		var rect:Rect2=body_rect(node)
		if not rect.has_area(): continue
		var path:NodePath=world.get_path_to(node)
		var key:String=str(path)+"/body"
		updates.append({"key":key,"path":path,"tile":false,"hits":hit_count(key,node)+1,"progress":minf(100.0,damage_progress(key,node)+PROFILE.progress_per_blast(node)),"rect":rect})
	# Data-backed floor obstacles have no collision body, so query them explicitly.
	for owner:Node in get_tree().get_nodes_in_group("MCNonCollidingObstacleOwner"):
		if not is_instance_valid(owner) or protected(owner) or owner.is_queued_for_deletion(): continue
		if not owner.has_method("collect_obstacle_blast"): continue
		for obstacle:Dictionary in owner.collect_obstacle_blast(point,radius):
			updates.append({"path":world.get_path_to(owner),"moss":true,"point":obstacle.point,"serial":obstacle.serial})
	return updates
func body_rect(body:StaticBody2D) -> Rect2:
	var result:=Rect2()
	for child:Node in body.get_children():
		if not child is CollisionShape2D or child.shape==null or child.disabled: continue
		var rect:Rect2=child.shape.get_rect()
		var transformed:Rect2=child.transform*rect
		result=transformed if not result.has_area() else result.merge(transformed)
	return result
func apply_updates(updates:Array) -> void:
	for update:Dictionary in updates:
		var node:Node=get_parent().get_node_or_null(update.path)
		if node==null or protected(node): continue
		if bool(update.get("moss",false)):
			if node.has_method("destroy_moss_obstacle"): node.destroy_moss_obstacle(update.point,int(update.serial))
			continue
		var key:String=update.key
		var record:Dictionary=records.get(key,{})
		if not record.is_empty() and (not is_instance_valid(record.node) or record.node!=node): record={}
		if int(record.get("hits",0))>=int(update.hits): continue
		var previous_hits:int=int(record.get("hits",0))
		if record.is_empty():
			record={"node":node,"tile":update.tile,"hits":0,"progress":0.0,"overlay":null}
			if update.tile:
				if not node is TileMapLayer or not interior(node,update.cell): continue
				record.cell=update.cell
				record.original=[node.get_cell_source_id(update.cell),node.get_cell_atlas_coords(update.cell),node.get_cell_alternative_tile(update.cell)]
			else:
				if not node is StaticBody2D: continue
				record.original=[node.collision_layer,node.collision_mask,node.visible,node.process_mode]
				record.hazard=node.is_in_group("AI_Hazard")
			records[key]=record
		record.hits=int(update.hits)
		# Older callers may still send hits=3 for an immediate shatter.
		var force_break:bool = int(update.hits)>=previous_hits+2 and not update.has("force_progress")
		var next_progress:float=float(update.get("progress",float(record.hits)*PROFILE.progress_per_blast(node,update.get("cell",null))))
		if force_break: next_progress=100.0
		if update.has("force_progress"): next_progress=float(update.force_progress)
		record.progress=clampf(maxf(float(record.progress),next_progress),0.0,100.0)
		if record.progress>=100.0:
			FRAGMENTS.spawn_obstacle(node,update if update.tile else {})
			if not update.tile and node.has_method("on_obstacle_destroyed"): node.on_obstacle_destroyed()
			if node.is_in_group("MinecraftSmithingTable"):
				get_parent().set_meta("mc_smithing_table_destroyed",true)
				node.remove_from_group("MinecraftSmithingTable")
			if is_instance_valid(record.overlay): record.overlay.queue_free()
			record.overlay=null
			if update.tile:
				var floor_data:Array=update.floor
				node.set_cell(update.cell,floor_data[0],floor_data[1],floor_data[2])
			else:
				node.hide()
				node.set_deferred("collision_layer",0)
				node.set_deferred("collision_mask",0)
				node.process_mode=Node.PROCESS_MODE_DISABLED
				if node.is_in_group("AI_Hazard"): node.remove_from_group("AI_Hazard")
				if node.is_in_group("BattleTransient"): node.queue_free()
			continue
		var crack_index:int=PROFILE.crack_index(node,float(record.progress))
		if crack_index<0: continue
		var block:Node2D=null if update.tile else BLOCK_3D.find_in(node)
		if block!=null:
			# 原版 3D 方块障碍：裂纹像原版一样贴在方块模型的每个面上，不再盖 2D 贴片。
			block.set_cracks(CRACKS[mini(crack_index,CRACKS.size()-1)])
			record.block=block
			continue
		if not is_instance_valid(record.overlay):
			var overlay:=Sprite2D.new()
			overlay.name="MCBlockCracks"
			overlay.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			overlay.z_index=1
			var material:=ShaderMaterial.new()
			material.shader=CRACK_SHADER
			if not update.tile:
				for child:Node in node.get_children():
					if child is CollisionShape2D and child.shape is CircleShape2D:
						material.set_shader_parameter("round_surface",true)
						break
			overlay.material=material
			node.add_child(overlay)
			record.overlay=overlay
		var overlay:Sprite2D=record.overlay
		overlay.texture=CRACKS[mini(crack_index,CRACKS.size()-1)]
		overlay.position=update.rect.get_center()
		overlay.scale=update.rect.size/16.0
@rpc("authority","call_local","reliable")
func reset_all() -> void:
	get_parent().remove_meta("mc_smithing_table_destroyed")
	for record:Dictionary in records.values():
		if is_instance_valid(record.overlay): record.overlay.queue_free()
		if is_instance_valid(record.get("block")): record.block.set_cracks(null)
		if not is_instance_valid(record.node): continue
		var node:Node=record.node
		if record.tile:
			node.set_cell(record.cell,record.original[0],record.original[1],record.original[2])
		else:
			node.collision_layer=record.original[0]
			node.collision_mask=record.original[1]
			node.visible=record.original[2]
			node.process_mode=record.original[3]
			if record.get("hazard",false): node.add_to_group("AI_Hazard")
	records.clear()

func hit_count(key:String,node:Node) -> int:
	var record:Dictionary=records.get(key,{})
	if record.is_empty() or not is_instance_valid(record.node) or record.node!=node: return 0
	return int(record.hits)

func damage_progress(key:String,node:Node) -> float:
	var record:Dictionary=records.get(key,{})
	if record.is_empty() or not is_instance_valid(record.node) or record.node!=node: return 0.0
	return clampf(float(record.get("progress",0.0)),0.0,100.0)
