extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(0.3).timeout
	print("PROBE maps=",world.map_group.keys()," now=",world.now_choose_map)
	for key in world.map_group.keys():
		var m:Node = world.map_group[key]
		if m is TileMapLayer:
			var layer:TileMapLayer = m
			var used:Array = layer.get_used_cells()
			var coll:int = 0
			var coll_cells:Array = []
			var ts:TileSet = layer.tile_set
			var pl:int = ts.get_physics_layers_count() if ts else -1
			for c in used:
				var td:TileData = layer.get_cell_tile_data(c)
				if td and pl > 0 and td.get_collision_polygons_count(0) > 0:
					coll += 1
					if coll_cells.size() < 6: coll_cells.append(c)
			print("PROBE map=",key," used=",used.size()," rect=",layer.get_used_rect()," tile=",ts.tile_size if ts else null," physics_layers=",pl," coll_cells=",coll," sample=",coll_cells," layer_bits=",(ts.get_physics_layer_collision_layer(0) if pl>0 else -1)," world_rect=",world.return_map_world_rect(layer), " visible=",layer.visible," enabled=",layer.enabled, " scale=",layer.global_scale)
		else:
			print("PROBE map=",key," class=",m.get_class())
	# static bodies in world
	var statics:Array = []
	for n in world.find_children("*","StaticBody2D",true,false):
		statics.append(str(n.get_path()).substr(0,90) + " L=" + str(n.collision_layer))
	print("PROBE statics=",statics.size()," ",statics.slice(0,12))
	var ball_scene:Node = (load("res://scenes/ball.tscn") as PackedScene).instantiate()
	print("PROBE ball layer=",ball_scene.collision_layer," mask=",ball_scene.collision_mask, " hurtbox=", ball_scene.get_node_or_null("Hurtbox"))
	for c in ball_scene.get_children():
		if c is CollisionObject2D: print("PROBE ball child ",c.name," ",c.get_class()," L=",c.collision_layer," M=",c.collision_mask)
	ball_scene.free()
	quit(0)
