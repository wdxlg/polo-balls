extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i in range(20): await process_frame
	var W:Script = load("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
	for key in world.map_group.keys():
		var m:Node = world.map_group[key]
		var info:Array = []
		for l in W.map_layers(m):
			var walls:int = 0
			for c in l.get_used_cells():
				if W._is_wall_cell(l,c): walls += 1
			info.append("%s coll=%s used=%d walls=%d" % [l.name,l.collision_enabled,l.get_used_cells().size(),walls])
		print("PROBE13 ",key," ",m.get_class()," ",info)
	quit(0)
